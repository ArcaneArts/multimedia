import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:multimedia/magick/cli/converter.dart';
import 'package:multimedia/multimedia.dart';
import 'package:toxic/extensions/iterable.dart';
import 'package:uuid/uuid.dart';

String _prefix = "package:multimedia/libraries";
String _prefixAssets = "package:multimedia/assets";
bool _initialized = false;
bool multimediaFFIMode = true;

List<ImageFormatSupport> _pureDartSupportedFormats = [
  ImageFormatSupport("bmp", true, true),
  ImageFormatSupport("gif", true, true),
  ImageFormatSupport("jpg", true, true),
  ImageFormatSupport("png", true, true),
  ImageFormatSupport("tiff", true, true),
  ImageFormatSupport("ico", true, true),
  ImageFormatSupport("webp", true, false),
  ImageFormatSupport("psd", true, false),
];

List<ImageFormatSupport> _magickSupportedFormats = [];

List<ImageFormatSupport> _magickTests = [
  ImageFormatSupport("jpg", true, true),
  ImageFormatSupport("png", true, true),
  ImageFormatSupport("webp", true, true),
  ImageFormatSupport("psd", true, true),
  ImageFormatSupport("bmp", true, true),
  ImageFormatSupport("tiff", true, true),
  ImageFormatSupport("gif", true, true),
  ImageFormatSupport("ico", true, true),
];

void main() async {
  await MagickCLI.convertToWebp(File("1.gif"), File("x.webp"),
      quality: 95,
      compressiveStrength: 6,
      alphaQuality: 1,
      alphaCompression: false);
}

Future<void> _testSupportedFormats() async {
  Set<String> successfulReads = {};
  Set<String> successfulWrites = {};

  for (ImageFormatSupport a in _magickTests) {
    for (ImageFormatSupport b in _magickTests) {
      if (await _testConversion(a.format, b.format)) {
        successfulReads.add(a.format);
        successfulWrites.add(b.format);
      }
    }
  }

  for (ImageFormatSupport a in _pureDartSupportedFormats) {
    _magickSupportedFormats.add(ImageFormatSupport(
        a.format,
        successfulReads.contains(a.format),
        successfulWrites.contains(a.format)));
  }

  for (ImageFormatSupport a in _magickTests) {
    File("testConversionIn${a.format}").deleteSync();
  }

  print("----------- Image Format Support -----------");
  for (ImageFormatSupport a in _pureDartSupportedFormats) {
    ImageFormatSupport m = _magickSupportedFormats
            .select((element) => element.format == a.format) ??
        ImageFormatSupport(a.format, false, false);
    String r = m.read
        ? "NATIVE"
        : a.read
            ? "BACKUP"
            : "FAILED";
    String w = m.write
        ? "NATIVE"
        : a.write
            ? "BACKUP"
            : "FAILED";
    if (r == w) {
      print("Format: ${a.format} RW: $r");
    } else {
      print("Format: ${a.format} R: $r W: $w");
    }
  }
  print("--------------------------------------------");
}

bool isFormatReadSupportedMagick(String format) =>
    _magickSupportedFormats
        .select((element) => element.format == format)
        ?.read ??
    false;

bool isFormatWriteSupportedMagick(String format) =>
    _magickSupportedFormats
        .select((element) => element.format == format)
        ?.write ??
    false;

bool isFormatReadSupportedBackup(String format) =>
    _pureDartSupportedFormats
        .select((element) => element.format == format)
        ?.read ??
    false;

bool isFormatWriteSupportedBackup(String format) =>
    _pureDartSupportedFormats
        .select((element) => element.format == format)
        ?.write ??
    false;

Future<bool> _testConversion(String inFormat, String outFormat) async {
  String id = Uuid().v4().replaceAll("-", "");
  File testIn = File("testConversionIn$inFormat");
  File testOut = File("testConversionOut$outFormat$id");
  if (!testIn.existsSync()) {
    File src = File.fromUri(Isolate.resolvePackageUriSync(
        Uri.parse("$_prefixAssets/rgbw.$inFormat"))!);
    testIn.writeAsBytesSync(src.readAsBytesSync());
  }

  if (testOut.existsSync()) testOut.deleteSync();

  MagickWand wand = MagickWand.newMagickWand();
  await wand.magickReadImage(testIn.path);
  wand.magickSetFormat(outFormat);
  wand.magickSetImageFormat(outFormat);
  await wand.magickWriteImage(testOut.path);
  bool success = testOut.existsSync();
  await wand.destroyMagickWand();
  if (testOut.existsSync()) testOut.deleteSync();
  return success;
}

class ImageFormatSupport {
  final String format;
  final bool read;
  final bool write;

  ImageFormatSupport(this.format, this.read, this.write);
}

Future<void> initMultimedia({bool ffi = true, bool initMagick = true}) async {
  if (_initialized) {
    return;
  }

  _initialized = true;

  if (!ffi) {
    multimediaFFIMode = false;
    return;
  }

  try {
    _load("image_magick_ffi");

    if (initMagick) {
      initializeImageMagick();
    }

    await _testSupportedFormats();
  } catch (e, es) {
    print("Failed to initialize ImageMagick: $e");
    print(es);
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
    return _loadAny([
      '${Directory.current.absolute.path}/lib$libName.so',
      '/usr/local/lib/lib$libName.so',
      '/usr/lib/lib$libName.so',
      'lib$libName.so',
    ]);
  }
  if (Platform.isWindows) {
    _install('$libName.dll');
    print("Loading Library $libName.dll");
    return DynamicLibrary.open('$libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}

DynamicLibrary _loadAny(List<String> opts) {
  for (String i in opts) {
    try {
      return DynamicLibrary.open(i);
    } catch (e) {
      print("Failed to load $i: $e");
    }
  }

  throw Exception("Failed to load any of the libraries: $opts");
}
