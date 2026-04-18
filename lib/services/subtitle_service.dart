import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/utils/subtitle_parser.dart';
import 'package:nipaplay/utils/subtitle_file_utils.dart';
import 'package:nipaplay/utils/subtitle_language_utils.dart';

class SubtitleService {
  static final SubtitleService _instance = SubtitleService._internal();
  factory SubtitleService() => _instance;
  SubtitleService._internal();

  // 外部字幕信息缓存
  final Map<String, List<Map<String, dynamic>>> _externalSubtitlesCache = {};

  /// 获取视频文件的唯一标识
  String _getVideoHashKey(String videoPath) {
    if (kIsWeb) return p.basename(videoPath);

    final file = File(videoPath);
    if (file.existsSync()) {
      final size = file.lengthSync();
      final name = p.basename(videoPath);
      return '$name-$size';
    }
    return sha1.convert(utf8.encode(videoPath)).toString();
  }

  /// 加载指定视频的外部字幕列表
  Future<List<Map<String, dynamic>>> loadExternalSubtitles(
      String videoPath) async {
    if (kIsWeb) return [];

    final videoHashKey = _getVideoHashKey(videoPath);

    // 先检查缓存
    if (_externalSubtitlesCache.containsKey(videoHashKey)) {
      return _externalSubtitlesCache[videoHashKey]!;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final subtitlesJson = prefs.getString('external_subtitles_$videoHashKey');

      if (subtitlesJson != null) {
        final List<dynamic> decoded = json.decode(subtitlesJson);
        final subtitles =
            decoded.map((item) => Map<String, dynamic>.from(item)).toList();

        // 验证文件是否还存在
        final validSubtitles = <Map<String, dynamic>>[];
        for (final subtitle in subtitles) {
          final path = subtitle['path'] as String;
          if (File(path).existsSync()) {
            validSubtitles.add(subtitle);
          }
        }

        // 更新缓存
        _externalSubtitlesCache[videoHashKey] = validSubtitles;

        // 如果有文件被移除，更新存储
        if (validSubtitles.length != subtitles.length) {
          await _saveExternalSubtitles(videoPath, validSubtitles);
        }

        return validSubtitles;
      }
    } catch (e) {
      debugPrint('加载外部字幕失败: $e');
    }

    return [];
  }

  /// 保存外部字幕列表
  Future<void> _saveExternalSubtitles(
      String videoPath, List<Map<String, dynamic>> subtitles) async {
    if (kIsWeb) return;

    try {
      final videoHashKey = _getVideoHashKey(videoPath);
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
          'external_subtitles_$videoHashKey', json.encode(subtitles));

      // 更新缓存
      _externalSubtitlesCache[videoHashKey] = subtitles;
    } catch (e) {
      debugPrint('保存外部字幕失败: $e');
    }
  }

  /// 保存最后激活的字幕索引
  Future<void> saveLastActiveSubtitleIndex(String videoPath, int index) async {
    if (kIsWeb) return;

    try {
      final videoHashKey = _getVideoHashKey(videoPath);
      final prefs = await SharedPreferences.getInstance();

      if (index >= 0) {
        await prefs.setInt('last_active_subtitle_$videoHashKey', index);
      } else {
        await prefs.remove('last_active_subtitle_$videoHashKey');
      }
    } catch (e) {
      debugPrint('保存最后激活字幕索引失败: $e');
    }
  }

  /// 获取最后激活的字幕索引
  Future<int?> getLastActiveSubtitleIndex(String videoPath) async {
    if (kIsWeb) return null;

    try {
      final videoHashKey = _getVideoHashKey(videoPath);
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('last_active_subtitle_$videoHashKey');
    } catch (e) {
      debugPrint('获取最后激活字幕索引失败: $e');
      return null;
    }
  }

  /// 选择并加载外部字幕文件
  Future<Map<String, dynamic>?> pickAndLoadSubtitleFile() async {
    if (kIsWeb) {
      throw UnsupportedError('Web平台不支持加载本地字幕文件');
    }

    try {
      final filePickerService = FilePickerService();
      final filePath = await filePickerService.pickSubtitleFile();

      if (filePath == null) return null;

      final fileName = p.basename(filePath);

      // 检查文件格式
      final extension = p.extension(filePath).toLowerCase();

      if (!supportedSubtitleExtensions.contains(extension)) {
        throw UnsupportedError('不支持的字幕格式，请选择 .srt, .ass, .ssa, .sub 或 .sup 文件');
      }

      // 检查文件是否存在
      if (!File(filePath).existsSync()) {
        throw FileSystemException('字幕文件不存在', filePath);
      }

      // 创建字幕信息
      return {
        'path': filePath,
        'name': fileName,
        'type': extension.substring(1),
        'addTime': DateTime.now().millisecondsSinceEpoch,
        'isActive': false
      };
    } catch (e) {
      debugPrint('选择字幕文件失败: $e');
      rethrow;
    }
  }

  /// 添加外部字幕
  Future<bool> addExternalSubtitle(
      String videoPath, Map<String, dynamic> subtitleInfo) async {
    try {
      final subtitles = await loadExternalSubtitles(videoPath);

      // 检查是否已经存在相同路径的字幕
      final existingIndex =
          subtitles.indexWhere((s) => s['path'] == subtitleInfo['path']);
      if (existingIndex >= 0) {
        // 已存在，更新信息
        subtitles[existingIndex] = subtitleInfo;
      } else {
        // 新增字幕
        subtitles.add(subtitleInfo);
      }

      await _saveExternalSubtitles(videoPath, subtitles);
      return true;
    } catch (e) {
      debugPrint('添加外部字幕失败: $e');
      return false;
    }
  }

  /// 批量添加外部字幕，并可指定当前激活的字幕路径
  Future<bool> addExternalSubtitles(
    String videoPath,
    List<Map<String, dynamic>> subtitleInfos, {
    String? activePath,
  }) async {
    try {
      final subtitles = await loadExternalSubtitles(videoPath);

      if (activePath != null) {
        for (final subtitle in subtitles) {
          subtitle['isActive'] = false;
        }
      }

      for (final subtitleInfo in subtitleInfos) {
        final normalizedInfo = Map<String, dynamic>.from(subtitleInfo);
        if (activePath != null) {
          normalizedInfo['isActive'] = normalizedInfo['path'] == activePath;
        }

        final existingIndex =
            subtitles.indexWhere((s) => s['path'] == normalizedInfo['path']);
        if (existingIndex >= 0) {
          subtitles[existingIndex] = {
            ...subtitles[existingIndex],
            ...normalizedInfo,
          };
        } else {
          subtitles.add(normalizedInfo);
        }
      }

      await _saveExternalSubtitles(videoPath, subtitles);

      if (activePath != null) {
        final activeIndex =
            subtitles.indexWhere((s) => s['path'] == activePath);
        await saveLastActiveSubtitleIndex(videoPath, activeIndex);
      }

      return true;
    } catch (e) {
      debugPrint('批量添加外部字幕失败: $e');
      return false;
    }
  }

  /// 移除外部字幕
  Future<bool> removeExternalSubtitle(String videoPath, int index) async {
    try {
      final subtitles = await loadExternalSubtitles(videoPath);

      if (index >= 0 && index < subtitles.length) {
        subtitles.removeAt(index);
        await _saveExternalSubtitles(videoPath, subtitles);
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('移除外部字幕失败: $e');
      return false;
    }
  }

  /// 设置外部字幕激活状态
  Future<bool> setExternalSubtitleActive(
      String videoPath, int index, bool isActive) async {
    try {
      final subtitles = await loadExternalSubtitles(videoPath);

      // 先将所有字幕设为非激活
      for (var subtitle in subtitles) {
        subtitle['isActive'] = false;
      }

      // 设置指定字幕为激活状态
      if (index >= 0 && index < subtitles.length) {
        subtitles[index]['isActive'] = isActive;
      }

      await _saveExternalSubtitles(videoPath, subtitles);

      if (isActive && index >= 0) {
        await saveLastActiveSubtitleIndex(videoPath, index);
      }

      return true;
    } catch (e) {
      debugPrint('设置外部字幕激活状态失败: $e');
      return false;
    }
  }

  /// 查找视频对应的默认字幕文件
  String? findDefaultSubtitleFile(String videoPath) {
    if (kIsWeb) return null;

    try {
      final videoFile = File(videoPath);
      if (!videoFile.existsSync()) return null;

      final videoDir = videoFile.parent.path;
      final videoName = p.basenameWithoutExtension(videoPath);

      final subtitleExts = subtitleExtensionMatchScore.keys;

      // 尝试查找同名字幕文件
      for (final ext in subtitleExts) {
        final potentialPath = p.join(videoDir, '$videoName$ext');
        if (File(potentialPath).existsSync()) {
          return potentialPath;
        }
      }

      return null;
    } catch (e) {
      debugPrint('查找默认字幕文件失败: $e');
      return null;
    }
  }

  /// 解析字幕文件
  Future<List<SubtitleEntry>> parseSubtitleFile(String subtitlePath) async {
    try {
      if (!File(subtitlePath).existsSync()) {
        throw FileSystemException('字幕文件不存在', subtitlePath);
      }
      final extension = p.extension(subtitlePath).toLowerCase();
      if (extension == '.sup') {
        throw UnsupportedError('图像字幕(.sup)暂不支持预览');
      }

      return await SubtitleParser.parseAssFile(subtitlePath);
    } catch (e) {
      debugPrint('解析字幕文件失败: $e');
      rethrow;
    }
  }

  /// 获取语言友好名称
  String getLanguageName(String language) {
    return getSubtitleLanguageName(language);
  }

  /// 清除指定视频的字幕缓存
  void clearCache(String videoPath) {
    final videoHashKey = _getVideoHashKey(videoPath);
    _externalSubtitlesCache.remove(videoHashKey);
  }

  /// 清除所有缓存
  void clearAllCache() {
    _externalSubtitlesCache.clear();
  }
}
