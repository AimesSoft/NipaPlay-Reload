import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:nipa_harness/nipa_harness.dart';

/// Use the already loaded Classic runtime; never create a second session.
abstract final class NativeBandwidth {
  static DynamicLibrary? _library() {
    final process = DynamicLibrary.process();
    if (process.providesSymbol('nipaplay_download_limits')) return process;
    final name = Platform.isWindows
        ? 'rust_lib_nipaplay.dll'
        : 'librust_lib_nipaplay.so';
    if (Platform.isAndroid) return DynamicLibrary.open(name);
    final path =
        '${File(Platform.resolvedExecutable).parent.path}/${Platform.isLinux ? 'lib/' : ''}$name';
    if (!Platform.isWindows && !Platform.isLinux || !File(path).existsSync()) {
      return null;
    }
    return DynamicLibrary.open(path);
  }

  static JsonMap call(JsonMap input) {
    final library = _library();
    if (library == null ||
        !library.providesSymbol('nipaplay_download_limits')) {
      return {
        'supported': false,
        'applied': false,
        'reason': 'native_bridge_not_available'
      };
    }
    final call = library.lookupFunction<
        Int32 Function(Int64, Int64, Pointer<Uint32>),
        int Function(int, int, Pointer<Uint32>)>('nipaplay_download_limits');
    final actual = calloc<Uint32>(2);
    try {
      final result = call(input['downloadBytesPerSecond'] as int? ?? -1,
          input['uploadBytesPerSecond'] as int? ?? -1, actual);
      if (result < 0) {
        throw const Failure(
            FailureCode.unavailable, 'Native bandwidth control failed.');
      }
      return {
        'supported': true,
        'sessionInitialized': result == 1,
        'applied': result == 1 && input.isNotEmpty,
        'reason': result == 0 ? 'session_not_initialized' : null,
        'actual': result == 1
            ? {
                'downloadBytesPerSecond': actual[0],
                'uploadBytesPerSecond': actual[1]
              }
            : null
      };
    } finally {
      calloc.free(actual);
    }
  }
}
