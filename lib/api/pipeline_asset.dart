import 'dart:io';

import 'package:multimedia/api/format.dart';
import 'package:multimedia/magick/cli/converter.dart';
import 'package:multimedia/magick/image_magick.dart';

class ImagePipelineAsset {
  final MediaFormat format;
  final File src;
  final ImageProperties properties;
  final MagickWand wand;

  ImagePipelineAsset(
      {required this.src,
      required this.format,
      required this.properties,
      required this.wand});
}
