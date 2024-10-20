import 'dart:io';

abstract class Transformer {
  Future<void> transform(File input, File output);
}
