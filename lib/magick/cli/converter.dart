import 'dart:convert';
import 'dart:io';

import 'package:multimedia/api/format.dart';

enum WebPCompressionMethod {
  l0, // 0
  l1, // 1
  l2, // 2
  l3, // 3
  l4, // 4
  l5, // 5
  l6, // 6
}

class ImageProperties {
  final MediaFormat format;
  final int width;
  final int height;
  final String colorSpace;
  double get aspectRatio => width / height;

  ImageProperties({
    this.format = const MediaFormat.unknownImage(),
    this.width = -1,
    this.height = -1,
    this.colorSpace = "sRGB",
  });

  ImageProperties resize(int newWidth, int newHeight) {
    return ImageProperties(
      format: format,
      width: newWidth,
      height: newHeight,
      colorSpace: colorSpace,
    );
  }

  // Example:
  // rose.jpg JPEG 70x46 70x46+0+0 8-bit sRGB 2.36KB 0.000u 0:00.000
  ImageProperties.fromMagickOutput(String s)
      : format = MediaFormat.fromExtensionOrType(s.split(" ")[1]),
        width = int.parse(s.split(" ")[2].split("x")[0]),
        height = int.parse(s.split(" ")[2].split("x")[1]),
        colorSpace = s.split(" ")[5];

  @override
  String toString() => "$format ${width}x$height $colorSpace";
}

class MagickCLI {
  static Future<ImageProperties> identify(File file) async {
    Process p = await Process.start("magick", ["identify", file.path]);
    // get the output of the command
    Stream<String> s =
        p.stdout.transform(utf8.decoder).transform(LineSplitter());
    p.stderr.pipe(stderr);
    int exitCode = await p.exitCode;
    ImageProperties props =
        ImageProperties.fromMagickOutput((await s.toList()).first);
    print("Magick exit code: $exitCode");

    if (exitCode != 0) {
      throw Exception("ImageMagick command failed with exit code $exitCode");
    }

    return props;
  }

  static Future<void> convertToWebp(File input, File output,
      {
      /// Maximum size of the output image in bytes.
      /// This is a target size, the actual size may vary
      /// depending on the webp library used this may not work. (doesnt seem to work on windows)
      int? maxBytes,

      /// Maximum dimension of the output image maintaining aspect ratio.
      /// Will only shrink the image, not enlarge it.
      int? maxDim,

      /// true or false defaults to false
      bool? lossless,

      /// 0 to 100
      int? quality,

      /// 0 to 3 for how many progressive segments to use
      int? progressivePartitions,

      /// 0 to 100 defaults to 100
      int? alphaQuality,

      /// 0 (fast) to 6 (best) defaults to 4
      int? compressiveStrength,

      /// true or false
      bool? alphaCompression}) async {
    Process p = await Process.start("magick", [
      input.path,
      if (maxDim != null) ...["-resize", "${maxDim}x$maxDim>"],
      if (maxBytes != null) ...["-define", "webp:target-size=$maxBytes"],
      if (lossless != null) ...["-define", "webp:lossless=$lossless"],
      if (compressiveStrength != null) ...[
        "-define",
        "webp:method=$compressiveStrength"
      ],
      if (progressivePartitions != null) ...[
        "-define",
        "webp:partitions=$progressivePartitions"
      ],
      if (alphaCompression != null) ...[
        "-define",
        "webp:alpha-compression=${alphaCompression ? 1 : 0}"
      ],
      if (alphaQuality != null) ...[
        "-define",
        "webp:alpha-quality=$alphaQuality"
      ],
      if (quality != null) ...["-quality", quality.toString()],
      "-format",
      "webp",
      output.path
    ]);
    p.stdout.pipe(stdout);
    p.stderr.pipe(stderr);
    int exitCode = await p.exitCode;
    print("Magick exit code: $exitCode");

    if (exitCode != 0) {
      throw Exception("ImageMagick command failed with exit code $exitCode");
    }
  }

  static Future<void> convert(File input, File output,
      {String? outputFormat, int? quality, int? maxDim}) async {
    Process p = await Process.start("magick", [
      input.path,
      if (quality != null) ...[
        "-quality",
        quality.toString(),
      ],
      if (maxDim != null) ...["-resize", "$maxDim>x$maxDim>"],
      if (outputFormat != null) ...[
        "-format",
        outputFormat,
      ],
      output.path
    ]);

    p.stdout.pipe(stdout);
    p.stderr.pipe(stderr);
    int exitCode = await p.exitCode;
    print("Magick exit code: $exitCode");

    if (exitCode != 0) {
      throw Exception("ImageMagick command failed with exit code $exitCode");
    }
  }
}
