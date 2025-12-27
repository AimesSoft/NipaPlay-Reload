import 'dart:ffi';
import 'dart:io';

import 'nipaplay_smb2_bindings_generated.dart';

const String _libName = 'nipaplay_smb2';

/// The dynamic library in which the symbols for [NipaplaySmb2Bindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final NipaplaySmb2Bindings _bindings = NipaplaySmb2Bindings(_dylib);

NipaplaySmb2Bindings get nipaplaySmb2Bindings => _bindings;
