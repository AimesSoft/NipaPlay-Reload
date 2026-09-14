import 'dart:ffi';
import 'dart:io';
import 'package:path/path.dart' as p;

typedef _NativeVsync = Uint8 Function(Uint64, Uint64);
typedef _Vsync = int Function(int, int);

class Next2NativeVsync {
  static final _Vsync? _signal = _load();

  static _Vsync? _load() {
    if (!Platform.isWindows) return null;
    try {
      // Same absolute library path used by RustLib and the texture plugin.
      final library = DynamicLibrary.open(p.join(
          p.dirname(Platform.resolvedExecutable), 'rust_lib_nipaplay.dll'));
      return library.lookupFunction<_NativeVsync, _Vsync>('next2_engine_vsync');
    } catch (_) {
      // Older binaries remain usable through the scene-submission path.
      return null;
    }
  }

  static bool signal(int handle, int elapsedUs) =>
      _signal?.call(handle, elapsedUs) == 1;
}
