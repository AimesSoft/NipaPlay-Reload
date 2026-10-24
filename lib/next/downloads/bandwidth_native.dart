import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:nipa_harness/nipa_harness.dart';

/// Use the already loaded Classic runtime; never create a second session.
abstract final class NativeBandwidth {
  static bool _resolved = false;
  static DynamicLibrary? _resolvedLibrary;
  static int Function(int, int, Pointer<Uint32>)? _limits;
  static Pointer<Uint32>? _actual;

  static DynamicLibrary? _library() {
    if (_resolved) return _resolvedLibrary;
    _resolved = true;
    final process = DynamicLibrary.process();
    if (process.providesSymbol('nipaplay_download_limits')) {
      return _resolvedLibrary = process;
    }
    final name = Platform.isWindows
        ? 'rust_lib_nipaplay.dll'
        : 'librust_lib_nipaplay.so';
    if (Platform.isAndroid) return _resolvedLibrary = DynamicLibrary.open(name);
    final path =
        '${File(Platform.resolvedExecutable).parent.path}/${Platform.isLinux ? 'lib/' : ''}$name';
    if (!Platform.isWindows && !Platform.isLinux || !File(path).existsSync()) {
      return null;
    }
    return _resolvedLibrary = DynamicLibrary.open(path);
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
    // The symbol and two-word readback buffer belong to this isolate for the
    // process lifetime; resource probes must not resolve or allocate per tick.
    final call = _limits ??= library.lookupFunction<
        Int32 Function(Int64, Int64, Pointer<Uint32>),
        int Function(int, int, Pointer<Uint32>)>('nipaplay_download_limits');
    final actual = _actual ??= calloc<Uint32>(2);
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
  }
}
