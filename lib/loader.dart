import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:image_magick_ffi/image_magick_ffi.dart';
import 'package:thumbhash/thumbhash.dart';
import 'package:toxic/extensions/num.dart';

String _prefix = "package:multimedia/libraries";

class ImageDestination {
  final File file;
  final int maxDimension;
  final int quality;

  ImageDestination(this.file, {this.maxDimension = 1024, this.quality = 85});

  static ImageDestination test(int dim, int q) =>
      ImageDestination(File("test_${dim}_$q.webp"),
          maxDimension: dim, quality: q);
}

class ImageGoal {
  final File file;
  final int maxDimension;
  final int maxBytes;

  ImageGoal(this.file, this.maxDimension, this.maxBytes);
}

class MediaMagic {
  static (int, int) forceScaleImage(int w, int h, int maxDim) =>
      w > h ? (maxDim, (maxDim * h) ~/ w) : ((maxDim * w) ~/ h, maxDim);

  static (int, int) imageScale(int w, int h, int maxDim) => max(w, h) <= maxDim
      ? (w, h)
      : w > h
          ? (maxDim, (maxDim * h) ~/ w)
          : ((maxDim * w) ~/ h, maxDim);

  static Future<String> getThumbhash(File input,
      {int maxDim = 100,
      PixelInterpolateMethod pim =
          PixelInterpolateMethod.BilinearInterpolatePixel}) async {
    MagickWand wand = MagickWand.newMagickWand();
    await wand.magickReadImage(input.path);
    wand.magickSetImageFormat("RGBA");
    wand.magickSetImageInterpolateMethod(pim);
    (int, int) inSize =
        (wand.magickGetImageWidth(), wand.magickGetImageHeight());
    (int, int) outSize = imageScale(inSize.$1, inSize.$2, maxDim);
    await wand.magickScaleImage(columns: outSize.$1, rows: outSize.$2);
    File t = File("${input.path.split(Platform.pathSeparator).last}.rgba");
    await wand.magickWriteImage(t.path);
    String s = base64
        .encode(rgbaToThumbHash(outSize.$1, outSize.$2, await t.readAsBytes()));
    await t.delete();
    await wand.destroyMagickWand();
    return s;
  }

  static Future<String> findOptimal(
    File input,
    List<ImageGoal> goals, {
    int maxAttempts = 10,
  }) async {
    Future<String> snipeThumbhash(MagickWand wand) async {
      (int, int) imgs =
          (wand.magickGetImageWidth(), wand.magickGetImageHeight());
      (int, int) outSize = forceScaleImage(imgs.$1, imgs.$2, 100);
      await wand.magickScaleImage(columns: outSize.$1, rows: outSize.$2);
      File t = File("${input.path.split(Platform.pathSeparator).last}.rgba");
      await wand.magickWriteImage(t.path);
      String s = base64.encode(
          rgbaToThumbHash(outSize.$1, outSize.$2, await t.readAsBytes()));
      await t.delete();
      return s;
    }

    goals.sort((a, b) => b.maxDimension.compareTo(a.maxDimension));
    MagickWand wand = MagickWand.newMagickWand();
    await wand.magickReadImage(input.path);
    wand.magickSetImageInterpolateMethod(
        PixelInterpolateMethod.BilinearInterpolatePixel);
    (int, int) inSize =
        (wand.magickGetImageWidth(), wand.magickGetImageHeight());
    String? th;

    if (goals.first.maxDimension <= 100 || min(inSize.$1, inSize.$2) <= 100) {
      th = await snipeThumbhash(wand);
      inSize = (wand.magickGetImageWidth(), wand.magickGetImageHeight());
    }

    for (ImageGoal goal in goals) {
      if (th == null && goal.maxDimension <= 100 ||
          min(inSize.$1, inSize.$2) <= 100) {
        th = await snipeThumbhash(wand);
        inSize = (wand.magickGetImageWidth(), wand.magickGetImageHeight());
      }

      (int, int) outSize = imageScale(inSize.$1, inSize.$2, goal.maxDimension);
      await wand.magickScaleImage(columns: outSize.$1, rows: outSize.$2);
      inSize = outSize;
      wand.magickSetImageCompression(CompressionType.WebPCompression);
      wand.magickSetImageFormat("webp");

      int comp = 100;
      int att = maxAttempts;
      double mult = 5;

      wand.magickSetImageCompressionQuality(comp);
      while (att-- > 0) {
        await wand.magickWriteImage(goal.file.path);
        print(
            "Attempt Left $att: ${comp}% is ${goal.file.lengthSync().readableFileSize()} of ${goal.maxBytes.readableFileSize()}");

        if (goal.file.lengthSync() <= goal.maxBytes) {
          if (comp >= 95) {
            break;
          }

          comp = min(100, (comp * mult).round());
        } else {
          comp ~/= mult;
        }

        wand.magickSetImageCompressionQuality(comp);

        mult = sqrt(mult);

        if (mult < 1.05) {
          break;
        }
      }
      await wand.magickWriteImage(goal.file.path);

      print(
          "Optimal Compression for ${goal.file.path} is $comp% (${((goal.file.lengthSync() / goal.maxBytes * 100)).toStringAsFixed(2)}% of target ${goal.maxBytes.readableFileSize()})");
    }

    if (th == null) {
      th = await snipeThumbhash(wand);
      inSize = (wand.magickGetImageWidth(), wand.magickGetImageHeight());
    }

    await wand.destroyMagickWand();
    return th;
  }

  static Future<void> processImages(File input, List<ImageDestination> d,
      {PixelInterpolateMethod pim =
          PixelInterpolateMethod.BilinearInterpolatePixel}) async {
    d.sort((a, b) => b.maxDimension.compareTo(a.maxDimension));
    MagickWand wand = MagickWand.newMagickWand();
    await wand.magickReadImage(input.path);
    wand.magickSetImageInterpolateMethod(pim);
    (int, int) inSize =
        (wand.magickGetImageWidth(), wand.magickGetImageHeight());

    for (ImageDestination dest in d) {
      (int, int) outSize = imageScale(inSize.$1, inSize.$2, dest.maxDimension);

      if (inSize.$1 != outSize.$1 || inSize.$2 != outSize.$2) {
        await wand.magickScaleImage(columns: outSize.$1, rows: outSize.$2);
        inSize = outSize;
      }

      wand.magickSetImageCompression(CompressionType.WebPCompression);
      wand.magickSetImageFormat("webp");
      wand.magickSetImageCompressionQuality(dest.quality);
      await wand.magickWriteImage(dest.file.path);
    }

    await wand.destroyMagickWand();
  }
}

void initMultimedia() {
  try {
    _load("image_magick_ffi");
    initializeImageMagick();
  } catch (e) {
    print("Failed to initialize ImageMagick: $e");
  }
}

void _install(String n) {
  File f = File(n);
  if (f.existsSync()) {
    return;
  }

  File o =
      File.fromUri(Isolate.resolvePackageUriSync(Uri.parse("$_prefix/$n"))!);
  print(o.path);

  if (!o.existsSync()) {
    throw Exception("Library not found: $n");
  }

  print("Installing $n...");
  f.writeAsBytesSync(o.readAsBytesSync());
}

DynamicLibrary _load(String libName) {
  if (Platform.isMacOS || Platform.isIOS) {
    _install('$libName.framework/$libName');
    print("Loading Library $libName.framework/$libName");
    return DynamicLibrary.open('$libName.framework/$libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    _install('lib$libName.so');
    print("Loading Library lib$libName.so");
    return DynamicLibrary.open('lib$libName.so');
  }
  if (Platform.isWindows) {
    _install('$libName.dll');
    print("Loading Library $libName.dll");
    return DynamicLibrary.open('$libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}
