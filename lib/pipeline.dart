import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:image_magick_ffi/image_magick_ffi.dart';
import 'package:precision_stopwatch/precision_stopwatch.dart';
import 'package:thumbhash/thumbhash.dart';
import 'package:toxic/extensions/double.dart';
import 'package:toxic/extensions/num.dart';

int _pmax = -1 >>> 1;

abstract class IPipelineJob {
  /// Higher priority jobs run first before lower priority jobs.
  int get priority;

  Future<void> transform(MediaPipeline pipeline);

  IPipelineJob then(IPipelineJob next) => MediaPipelineJob(
        [this, next],
      );

  int get count => 1;
}

/// A job that runs a single transformation using a shared MagickWand.
abstract class MagickPipelineJob extends IPipelineJob {
  final String wandKey;

  MagickPipelineJob({this.wandKey = "wand"});

  Future<void> wandTransform(MediaPipeline pipeline, MagickWand wand);

  @override
  Future<void> transform(MediaPipeline pipeline) =>
      wandTransform(pipeline, pipeline.memory[wandKey]);
}

/// A job that runs an entire sub-pipeline of jobs.
class MediaPipelineJob extends IPipelineJob {
  final List<IPipelineJob> jobs;

  MediaPipelineJob(this.jobs);

  @override
  int get priority => jobs.fold(0, (int acc, job) => max(acc, job.priority));

  @override
  int get count => jobs.fold(0, (int acc, job) => acc + job.count);

  @override
  Future<void> transform(MediaPipeline pipeline) {
    jobs.sort((a, b) => b.priority - a.priority);
    Future<void> work = Future.value();

    int completed = 0;
    int ind = pipeline.memory["ind"];
    pipeline.memory["ind"] = ind + 1;

    for (IPipelineJob job in jobs) {
      work = work.then((_) async {
        PrecisionStopwatch psw = PrecisionStopwatch.start();
        await job.transform(pipeline);
        double ms = psw.getMilliseconds();
        completed++;
        pipeline.memory["completed"] = completed;
        print(
            "${"  " * ind}#$job in ${ms.format()} (${pipeline.memory["completed"]} of ${pipeline.memory["total"]})");
      });
    }

    pipeline.memory["ind"] = ind - 1;

    return work;
  }
}

class MagickImageLoaderJob extends IPipelineJob {
  final File image;
  final String wandKey;

  MagickImageLoaderJob(this.image, {this.wandKey = "wand"});

  @override
  int get priority => _pmax;

  @override
  Future<void> transform(MediaPipeline pipeline) async {
    MagickWand wand = MagickWand.newMagickWand();
    await wand.magickReadImage(image.path);
    pipeline.memory["$wandKey.src"] = image;
    pipeline.memory[wandKey] = wand;
  }
}

class ImageThumbHashJob extends MagickPipelineJob {
  final Function(String s) onThumbHash;
  final int forceDim;

  ImageThumbHashJob(
      {super.wandKey = "wand", this.forceDim = 64, required this.onThumbHash});

  @override
  int get priority => forceDim;

  @override
  Future<void> wandTransform(MediaPipeline pipeline, MagickWand wand) async {
    File src = pipeline.memory["$wandKey.src"];
    File srcRgba = File("${src.path.split(Platform.pathSeparator).last}.rgba");
    wand.magickSetImageInterpolateMethod(
        PixelInterpolateMethod.NearestInterpolatePixel);
    wand.magickSetImageFormat("RGBA");
    (int, int) inSize =
        (wand.magickGetImageWidth(), wand.magickGetImageHeight());
    (int, int) outSize = _forceScaleImage(inSize.$1, inSize.$2, forceDim);
    await wand.magickScaleImage(columns: outSize.$1, rows: outSize.$2);
    await wand.magickWriteImage(srcRgba.path);
    pipeline.memory["$wandKey.thumbhash"] = base64.encode(
        rgbaToThumbHash(outSize.$1, outSize.$2, await srcRgba.readAsBytes()));
    await srcRgba.delete();
    onThumbHash(pipeline.memory["$wandKey.thumbhash"]);
  }
}

class ImageScaleWebPJob extends MagickPipelineJob {
  final int maxDimension;
  final int quality;
  final PixelInterpolateMethod interpolateMethod;
  final File output;

  ImageScaleWebPJob({
    super.wandKey = "wand",
    this.maxDimension = 1024,
    this.quality = 100,
    this.interpolateMethod = PixelInterpolateMethod.BilinearInterpolatePixel,
    required this.output,
  });

  @override
  int get priority => maxDimension;

  @override
  Future<void> wandTransform(MediaPipeline pipeline, MagickWand wand) {
    (int, int) inSize =
        (wand.magickGetImageWidth(), wand.magickGetImageHeight());
    (int, int) outSize = _imageScale(inSize.$1, inSize.$2, maxDimension);
    wand.magickSetInterpolateMethod(interpolateMethod);
    wand.magickSetImageInterpolateMethod(interpolateMethod);
    wand.magickSetImageCompression(CompressionType.WebPCompression);
    wand.magickSetImageFormat("webp");
    wand.magickSetImageCompressionQuality(quality);
    return wand.magickScaleImage(columns: outSize.$1, rows: outSize.$2);
  }
}

class ImageOptimizerWebPJob extends MagickPipelineJob {
  final int maxDimension;
  final int maxBytes;
  final int maxAttempts;
  final int plentifulSpaceQualityThreshold;
  final int initialQuality;
  final double stepMultiplierCutoff;
  final double initialStepMultiplier;
  final File output;
  final PixelInterpolateMethod interpolateMethod;

  ImageOptimizerWebPJob({
    super.wandKey = "wand",
    this.initialStepMultiplier = 10,
    this.initialQuality = 75,
    this.stepMultiplierCutoff = 1.05,
    this.maxDimension = 1024,
    this.maxBytes = 1024 * 1024,
    this.maxAttempts = 15,
    this.plentifulSpaceQualityThreshold = 95,
    required this.output,
    this.interpolateMethod = PixelInterpolateMethod.BilinearInterpolatePixel,
  });

  @override
  int get priority => maxDimension;

  @override
  Future<void> wandTransform(MediaPipeline pipeline, MagickWand wand) async {
    (int, int) inSize =
        (wand.magickGetImageWidth(), wand.magickGetImageHeight());
    (int, int) outSize = _imageScale(inSize.$1, inSize.$2, maxDimension);
    wand.magickSetInterpolateMethod(interpolateMethod);
    wand.magickSetImageInterpolateMethod(interpolateMethod);
    wand.magickSetImageCompression(CompressionType.WebPCompression);
    wand.magickSetImageFormat("webp");
    int quality = initialQuality;
    int att = maxAttempts;
    double stepMultiplier = initialStepMultiplier;
    wand.magickSetImageCompressionQuality(quality);
    await wand.magickScaleImage(columns: outSize.$1, rows: outSize.$2);
    inSize = outSize;
    int tooBig = 101;
    int tooSmall = 0;

    while (att-- > 0) {
      await wand.magickWriteImage(output.path);
      print(
          "Attempt Left $att: $quality% is ${output.lengthSync().readableFileSize()} of ${maxBytes.readableFileSize()}");

      int oq = quality;
      if (output.lengthSync() <= maxBytes) {
        if (quality >= plentifulSpaceQualityThreshold) {
          print("Quality is plentiful at $quality%");
          break;
        }
        tooSmall = quality;
        quality = max(min(tooBig - 1, (quality * stepMultiplier)), tooSmall + 1)
            .round();
      } else {
        tooBig = quality;
        quality ~/= stepMultiplier;
      }

      if (quality == oq) {
        print("Same Quality result... stopping at $quality%");
        break;
      }

      wand.magickSetImageCompressionQuality(quality);
      stepMultiplier = pow(stepMultiplier, 0.69).toDouble();
      if (stepMultiplier < stepMultiplierCutoff) {
        print("We're getting nowhere, stopping at $quality%");
        break;
      }
    }
    await wand.magickWriteImage(output.path);

    print(
        "Optimal Compression for ${output.path} is $quality% (${((output.lengthSync() / maxBytes * 100)).toStringAsFixed(2)}% of target ${maxBytes.readableFileSize()})");
  }
}

(int, int) _forceScaleImage(int w, int h, int maxDim) =>
    w > h ? (maxDim, (maxDim * h) ~/ w) : ((maxDim * w) ~/ h, maxDim);

(int, int) _imageScale(int w, int h, int maxDim) => max(w, h) <= maxDim
    ? (w, h)
    : w > h
        ? (maxDim, (maxDim * h) ~/ w)
        : ((maxDim * w) ~/ h, maxDim);

class MediaPipeline extends MediaPipelineJob {
  Map<String, dynamic> memory = {};

  MediaPipeline(super.jobs);

  Future<void> push() async {
    memory["completed"] = 0;
    memory["ind"] = 0;
    memory["total"] = count;
    PrecisionStopwatch psw = PrecisionStopwatch.start();
    print("Starting pipeline with ${memory["total"]} jobs");
    await transform(this);
    print("Pipeline completed in ${psw.getMilliseconds()}ms");
  }
}