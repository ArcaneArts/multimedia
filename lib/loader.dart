import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:multimedia/magick/image_magick.dart';

String _prefix = "package:multimedia/libraries";
bool _initialized = false;

void initMultimedia() {
  if (_initialized) {
    return;
  }

  _initialized = true;

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
    _install('${Directory.current.absolute.path}/lib$libName.so');
    print("Loading Library lib$libName.so");
    return DynamicLibrary.open(
        '${Directory.current.absolute.path}/lib$libName.so');
  }
  if (Platform.isWindows) {
    _install('$libName.dll');
    print("Loading Library $libName.dll");
    return DynamicLibrary.open('$libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}
