import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:path/path.dart' as p;

class NativeLibrary {
  static DynamicLibrary? _dylib;
  static const String _libName = 'nipaplay_native';

  static DynamicLibrary get instance {
    return _dylib ??= _open();
  }

  static DynamicLibrary _open() {
    // iOS: 静态链接，直接使用 process
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }

    // Android: 系统 dlopen 搜索路径
    if (Platform.isAndroid) {
      return DynamicLibrary.open('lib$_libName.so');
    }

    // Windows: 在 exe 同目录查找
    if (Platform.isWindows) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      return DynamicLibrary.open(p.join(exeDir, '$_libName.dll'));
    }

    // macOS: 在 Frameworks 目录查找，然后 fallback
    if (Platform.isMacOS) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final candidates = [
        p.normalize(p.join(exeDir, '..', 'Frameworks', '$_libName.framework', _libName)),
        p.normalize(p.join(exeDir, '..', 'Frameworks', 'lib$_libName.dylib')),
      ];
      for (final path in candidates) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {}
      }
      // fallback: 系统搜索路径
      return DynamicLibrary.open('lib$_libName.dylib');
    }

    // Linux: 在 lib/ 子目录查找，然后 fallback
    if (Platform.isLinux) {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final candidates = [
        p.join(exeDir, 'lib', 'lib$_libName.so'),
        p.join(exeDir, 'lib$_libName.so'),
      ];
      for (final path in candidates) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {}
      }
      return DynamicLibrary.open('lib$_libName.so');
    }

    throw UnsupportedError('Unsupported platform for cpp_native');
  }
}
