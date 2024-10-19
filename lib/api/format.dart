import 'dart:io';
import 'dart:math';

import 'package:mime/mime.dart';
import 'package:toxic/extensions/iterable.dart';

enum MediaType {
  image,
  video,
  audio,
  document,
  archive,
}

class MediaFormat {
  static const Set<MediaFormat> kImageFormats = {
    MediaFormat.jpeg(),
    MediaFormat.png(),
    MediaFormat.webp(),
    MediaFormat.gif(),
    MediaFormat.rgba(),
  };

  static const Set<MediaFormat> kVideoFormats = {};

  static const Set<MediaFormat> kAudioFormats = {};

  static const Set<MediaFormat> kDocumentFormats = {};

  static const Set<MediaFormat> kArchiveFormats = {};

  static const Set<MediaFormat> kAllFormats = {
    ...kImageFormats,
    ...kVideoFormats,
    ...kAudioFormats,
    ...kDocumentFormats,
    ...kArchiveFormats,
  };

  static const Set<MediaFormat> kSupportedImageMagickLoaderFormats = {
    MediaFormat.jpeg(),
    MediaFormat.png(),
    MediaFormat.webp(),
    MediaFormat.gif(),
    MediaFormat.rgba(),
  };

  static const Set<MediaFormat> kSupportedDartImageLoaderFormats = {
    MediaFormat.jpeg(),
    MediaFormat.png(),
    MediaFormat.gif(),
    MediaFormat.webp(),
    MediaFormat.psd(),
    MediaFormat.exr(),
    MediaFormat.pnm(),
    MediaFormat.bmp(),
    MediaFormat.tiff(),
    MediaFormat.tga(),
    MediaFormat.pvr(),
    MediaFormat.ico(),
  };

  final MediaType type;
  final Set<String> extensions;
  final String mimeType;
  final bool known;

  const MediaFormat({
    required this.type,
    required this.extensions,
    required this.mimeType,
    this.known = true,
  });

  const MediaFormat.jpeg()
      : type = MediaType.image,
        extensions = const {"jpg", "jpeg"},
        mimeType = "image/jpeg",
        known = true;

  const MediaFormat.png()
      : type = MediaType.image,
        extensions = const {"png"},
        mimeType = "image/png",
        known = true;

  const MediaFormat.webp()
      : type = MediaType.image,
        extensions = const {"webp"},
        mimeType = "image/webp",
        known = true;

  const MediaFormat.gif()
      : type = MediaType.image,
        extensions = const {"gif"},
        mimeType = "image/gif",
        known = true;

  const MediaFormat.rgba()
      : type = MediaType.image,
        extensions = const {"rgba"},
        mimeType = "image/rgba",
        known = true;

  const MediaFormat.psd()
      : type = MediaType.image,
        extensions = const {"psd"},
        mimeType = "image/vnd.adobe.photoshop",
        known = true;

  const MediaFormat.exr()
      : type = MediaType.image,
        extensions = const {"exr"},
        mimeType = "image/x-exr",
        known = true;

  const MediaFormat.pnm()
      : type = MediaType.image,
        extensions = const {"pnm", "pbm", "pgm", "ppm"},
        mimeType = "image/x-portable-anymap",
        known = true;

  const MediaFormat.bmp()
      : type = MediaType.image,
        extensions = const {"bmp"},
        mimeType = "image/bmp",
        known = true;

  const MediaFormat.tiff()
      : type = MediaType.image,
        extensions = const {"tiff"},
        mimeType = "image/tiff",
        known = true;

  const MediaFormat.tga()
      : type = MediaType.image,
        extensions = const {"tga"},
        mimeType = "image/x-tga",
        known = true;

  const MediaFormat.pvr()
      : type = MediaType.image,
        extensions = const {"pvr"},
        mimeType = "image/x-pvr",
        known = true;

  const MediaFormat.ico()
      : type = MediaType.image,
        extensions = const {"ico"},
        mimeType = "image/x-icon",
        known = true;

  const MediaFormat.unknownImage()
      : type = MediaType.image,
        extensions = const {"image"},
        mimeType = "image/unknown",
        known = false;

  const MediaFormat.unknown()
      : type = MediaType.image,
        extensions = const {"file"},
        mimeType = "application/octet-stream",
        known = false;

  static MediaFormat fromExtensionOrType(String t) =>
      kAllFormats
          .select((i) => i.extensions.any((x) => x == t.toLowerCase())) ??
      MediaFormat.unknown();

  static Future<MediaFormat> getFormat(File file,
      {bool trustExtension = false}) async {
    MediaFormat? format = kAllFormats
        .select((i) => i.extensions.any((x) => file.path.endsWith(x)));

    int length = await file.length();
    if (format == null || !trustExtension) {
      RandomAccessFile raf = await file.open();
      List<int> headerBytes =
          await raf.read(min(defaultMagicNumbersMaxLength, length));
      raf.close();
      String? mimeType = lookupMimeType(file.path, headerBytes: headerBytes);

      if (mimeType != null) {
        format = kAllFormats.select((i) => i.mimeType == mimeType);
      }
    }

    return format ?? MediaFormat.unknown();
  }

  @override
  String toString() => mimeType;
}
