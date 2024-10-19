library multimedia;

import 'dart:io';

import 'package:multimedia/api/format.dart';

export 'loader.dart';
export 'magick/image_magick.dart';
export 'pipeline.dart';

void main() async {
  print((await MediaFormat.getFormat(File("test.jpeg"))));
}
