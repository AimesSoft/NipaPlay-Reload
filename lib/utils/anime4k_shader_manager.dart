import 'dart:io' if (dart.library.io) 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Anime4K 预设强度。
///
/// 提供从完全关闭到更激进的多档位配置，便于在设置中进行调节。
enum Anime4KProfile {
  off,
  lite,
  standard,
  high,
}

/// Anime4K 着色器资源管理器。
///
/// 负责将打包在 assets/shaders/anime4k/ 下的 shader 复制到运行时可访问
/// 的本地目录，并返回可供 libmpv 读取的绝对路径列表。
class Anime4KShaderManager {
  static const String _assetRoot = 'assets/shaders/anime4k';
  static const List<String> _shaderFiles = <String>[
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_Soft_M.glsl',
    'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
  ];

  static const Map<Anime4KProfile, List<String>> _profileShaderOrder = {
    Anime4KProfile.off: <String>[],
    Anime4KProfile.lite: <String>[
      'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
    ],
    Anime4KProfile.standard: <String>[
      'Anime4K_Restore_CNN_Soft_M.glsl',
      'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
    ],
    Anime4KProfile.high: <String>[
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_Soft_M.glsl',
      'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
    ],
  };

  static Map<String, String>? _cachedShaderPaths;

  /// 将 Anime4K 着色器复制到本地缓存目录并返回路径。
  ///
  /// 如果当前运行在 Web 平台，直接返回空列表。
  static Future<List<String>> prepareShaders() async {
    final Map<String, String> shaderMap = await _ensureShaderCache();
    if (shaderMap.isEmpty) {
      return const <String>[];
    }
    return _shaderFiles
        .map((fileName) => shaderMap[fileName])
        .whereType<String>()
        .toList(growable: false);
  }

  /// 获取指定 Anime4K 配置所需的着色器绝对路径（按执行顺序）。
  static Future<List<String>> getShaderPathsForProfile(
    Anime4KProfile profile,
  ) async {
    if (profile == Anime4KProfile.off || kIsWeb) {
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

  /// 按照 mpv 的语法构造 glsl-shaders 属性字符串。
  static String buildMpvShaderList(List<String> shaderPaths) {
    if (shaderPaths.isEmpty || kIsWeb) {
      return '';
    }

    // mpv 在 Windows 上使用分号分隔，在类 Unix 平台使用冒号分隔。
    final String separator = Platform.isWindows ? ';' : ':';
    return shaderPaths.join(separator);
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
        debugPrint('[Anime4KShaderManager] 无法提取着色器 $assetPath: $e');
      }
    }

    _cachedShaderPaths = shaderMap;
    return _cachedShaderPaths!;
  }

  /// Anime4K 着色器写入的目标目录。
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
        Directory(p.join(baseDirectory.path, 'anime4k_shaders'));
    if (!await shaderDir.exists()) {
      await shaderDir.create(recursive: true);
    }

    return shaderDir;
  }
}
