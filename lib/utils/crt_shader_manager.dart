import 'dart:io' if (dart.library.io) 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// CRT 预设强度。
///
/// 根据性能开销提供多档位选择。
enum CrtProfile {
  off,
  lite,
  standard,
  high,
}

/// CRT 着色器资源管理器。
///
/// 负责将打包在 assets/shaders/crt/ 下的 shader 复制到运行时可访问
/// 的本地目录，并返回可供 libmpv 读取的绝对路径列表。
class CrtShaderManager {
  static const String _assetRoot = 'assets/shaders/crt';
  static const List<String> _shaderFiles = <String>[
    'crt_lite.glsl',
    'crt_standard.glsl',
    'crt_high.glsl',
  ];

  static const Map<CrtProfile, List<String>> _profileShaderOrder = {
    CrtProfile.off: <String>[],
    CrtProfile.lite: <String>[
      'crt_lite.glsl',
    ],
    CrtProfile.standard: <String>[
      'crt_standard.glsl',
    ],
    CrtProfile.high: <String>[
      'crt_high.glsl',
    ],
  };

  static Map<String, String>? _cachedShaderPaths;

  static Future<List<String>> getShaderPathsForProfile(
    CrtProfile profile,
  ) async {
    if (profile == CrtProfile.off || kIsWeb) {
      return const <String>[];
    }

    final Map<String, String> shaderMap = await _ensureShaderCache();
    if (shaderMap.isEmpty) {
      return const <String>[];
    }

    final List<String> orderedFiles =
        _profileShaderOrder[profile] ?? const <String>[];
    return orderedFiles
        .map((fileName) => shaderMap[fileName])
        .whereType<String>()
        .toList(growable: false);
  }

  static Future<Map<String, String>> _ensureShaderCache() async {
    if (_cachedShaderPaths != null) {
      return _cachedShaderPaths!;
    }

    if (kIsWeb) {
      _cachedShaderPaths = const <String, String>{};
      return _cachedShaderPaths!;
    }

    final Directory targetDir = await _resolveShaderDirectory();
    final Map<String, String> shaderMap = <String, String>{};

    for (final String fileName in _shaderFiles) {
      final String assetPath = '$_assetRoot/$fileName';
      final File outputFile = File(p.join(targetDir.path, fileName));

      try {
        final ByteData byteData = await rootBundle.load(assetPath);
        await outputFile.parent.create(recursive: true);

        final Uint8List bytes = byteData.buffer.asUint8List();
        try {
          final bool shouldRewrite = !await outputFile.exists() ||
              (await outputFile.length()) != bytes.length;
          if (shouldRewrite) {
            await outputFile.writeAsBytes(bytes, flush: true);
          }
        } catch (_) {
          await outputFile.writeAsBytes(bytes, flush: true);
        }

        shaderMap[fileName] = outputFile.path;
      } catch (e) {
        debugPrint('[CrtShaderManager] 无法提取着色器 $assetPath: $e');
      }
    }

    _cachedShaderPaths = shaderMap;
    return _cachedShaderPaths!;
  }

  static Future<Directory> _resolveShaderDirectory() async {
    Directory baseDirectory;

    if (Platform.isAndroid || Platform.isIOS) {
      baseDirectory = await getApplicationSupportDirectory();
    } else if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      baseDirectory = await getApplicationSupportDirectory();
    } else {
      baseDirectory = await getTemporaryDirectory();
    }

    final Directory shaderDir =
        Directory(p.join(baseDirectory.path, 'crt_shaders'));
    if (!await shaderDir.exists()) {
      await shaderDir.create(recursive: true);
    }

    return shaderDir;
  }
}
