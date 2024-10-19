import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:multimedia/api/format.dart';
import 'package:multimedia/api/pipeline_asset.dart';
import 'package:multimedia/magick/cli/converter.dart';
import 'package:multimedia/magick/image_magick.dart';

abstract class AbstractImageLoader {
  const AbstractImageLoader();

  Future<ImagePipelineAsset> load(File file);
}

class ImageLoader extends AbstractImageLoader {
  @override
  Future<ImagePipelineAsset> load(File file) async {
    MediaFormat format = await MediaFormat.getFormat(file);
    if (format.known && format.type == MediaType.image) {
      if (MediaFormat.kSupportedImageMagickLoaderFormats.contains(format)) {
        return await MagickImageLoader().load(file);
      } else {
        return DartImageCompatPNGLoader().load(file);
      }
    } else if (format.known) {
      throw Exception(
          "Incorrect media-type: ${format.type}. ${format.mimeType}. Not an image!");
    } else {
      throw Exception("Unknown file type.");
    }
  }
}

class DartImageCompatPNGLoader extends AbstractImageLoader {
  const DartImageCompatPNGLoader();

  @override
  Future<ImagePipelineAsset> load(File file) async {
    File png =
        File("${file.path}compatpng${Random().nextInt(100000) + 100000}");
    List<dynamic> r = await Future.wait([
      (img.Command()
            ..decodeImageFile(file.path)
            ..encodePng(level: 6)
            ..writeToFile(png.path))
          .executeThread()
          .then((_) async {
        MagickWand wand = MagickWand.newMagickWand();
        await wand.magickReadImage(png.path);
        await png.delete();
        return wand;
      }),
      MagickCLI.identify(file)
    ]);
    ImageProperties properties = r[1] as ImageProperties;

    return ImagePipelineAsset(
        src: file,
        format: properties.format,
        properties: properties,
        wand: r[0]);
  }
}

class MagickImageLoader extends AbstractImageLoader {
  const MagickImageLoader();

  @override
  Future<ImagePipelineAsset> load(File file) async {
    MagickWand wand = MagickWand.newMagickWand();
    List<dynamic> r = await Future.wait(
        [wand.magickReadImage(file.path), MagickCLI.identify(file)]);
    ImageProperties properties = r[1] as ImageProperties;

    return ImagePipelineAsset(
        src: file,
        format: properties.format,
        properties: properties,
        wand: wand);
  }
}
