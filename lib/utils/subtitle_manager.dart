import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'subtitle_parser.dart';
import '../../player_abstraction/player_abstraction.dart';

/// 字幕管理器类，负责处理与字幕相关的所有功能
class SubtitleManager extends ChangeNotifier {
  Player _player;
  String? _currentVideoPath;
  String? _currentExternalSubtitlePath;
  final Map<String, Map<String, dynamic>> _subtitleTrackInfo = {};
  final Map<String, List<dynamic>> _subtitleCache = {};

  // 视频-字幕路径映射的持久化存储键
  static const String _videoSubtitleMapKey = 'video_subtitle_map';

  // 外部字幕自动加载回调
  Function(String path, String fileName)? onExternalSubtitleAutoLoaded;

  // 构造函数
  SubtitleManager({required Player player}) : _player = player;

  // 更新播放器实例
  void updatePlayer(Player newPlayer) {
    _player = newPlayer;
    debugPrint('SubtitleManager: 播放器实例已更新');
  }

  // Getters
  Map<String, Map<String, dynamic>> get subtitleTrackInfo => _subtitleTrackInfo;
  String? get currentExternalSubtitlePath => _currentExternalSubtitlePath;

  // 设置播放器实例
  void setPlayer(Player player) {
    _player = player;
  }

  // 设置当前视频路径
  void setCurrentVideoPath(String? path) {
    _currentVideoPath = path;
  }

  // 更新字幕轨道信息
  void updateSubtitleTrackInfo(String key, Map<String, dynamic> info) {
    _subtitleTrackInfo[key] = info;
    notifyListeners();
  }

  // 清除字幕轨道信息
  void clearSubtitleTrackInfo() {
    _subtitleTrackInfo.clear();
    notifyListeners();
  }

  // 获取当前活跃的外部字幕文件路径
  String? getActiveExternalSubtitlePath() {
    if (_player.activeSubtitleTracks.isEmpty) {
      return null;
    }

    // 检查是否是外部字幕
    final activeTrack = _player.activeSubtitleTracks.first;
    // 查找外部字幕信息
    if (_subtitleTrackInfo.containsKey('external_subtitle') &&
        _subtitleTrackInfo['external_subtitle']?['isActive'] == true) {
      // 返回外部字幕文件路径
      return _subtitleTrackInfo['external_subtitle']?['path'];
    }

    // 特殊处理：当轨道索引为0，可能是外部字幕
    if (activeTrack == 0 && _currentExternalSubtitlePath != null) {
      return _currentExternalSubtitlePath;
    }

    return null;
  }

  // 获取已缓存的字幕内容
  List<dynamic>? getCachedSubtitle(String path) {
    return _subtitleCache[path];
  }

  // 保存视频与字幕路径的映射
  Future<void> saveVideoSubtitleMapping(
      String videoPath, String subtitlePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappingJson = prefs.getString(_videoSubtitleMapKey) ?? '{}';
      final Map<String, dynamic> mappingMap =
          Map<String, dynamic>.from(json.decode(mappingJson));
      mappingMap[videoPath] = subtitlePath;
      await prefs.setString(_videoSubtitleMapKey, json.encode(mappingMap));
      debugPrint(
          'SubtitleManager: 保存视频字幕映射 - 视频: $videoPath, 字幕: $subtitlePath');
    } catch (e) {
      debugPrint('SubtitleManager: 保存视频字幕映射失败: $e');
    }
  }

  // 获取视频对应的字幕路径
  Future<String?> getVideoSubtitlePath(String videoPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappingJson = prefs.getString(_videoSubtitleMapKey) ?? '{}';
      final Map<String, dynamic> mappingMap =
          Map<String, dynamic>.from(json.decode(mappingJson));
      final subtitlePath = mappingMap[videoPath] as String?;
      debugPrint(
          'SubtitleManager: 获取视频对应的字幕路径 - 视频: $videoPath, 字幕: $subtitlePath');

      // 检查字幕文件是否仍然存在
      if (subtitlePath != null && subtitlePath.isNotEmpty) {
        final subtitleFile = File(subtitlePath);
        if (!subtitleFile.existsSync()) {
          debugPrint('SubtitleManager: 记录的字幕文件不存在: $subtitlePath');
          return null;
        }
      }

      return subtitlePath;
    } catch (e) {
      debugPrint('SubtitleManager: 获取视频字幕映射失败: $e');
      return null;
    }
  }

  // 获取当前显示的字幕文本
  String getCurrentSubtitleText() {
    try {
      // 如果没有播放器或没有激活的字幕轨道
      if (_player.activeSubtitleTracks.isEmpty) {
        debugPrint('SubtitleManager: getCurrentSubtitleText - 没有激活的字幕轨道');
        return '';
      }

      // 检查是否是外部字幕
      String? externalSubtitlePath = _currentExternalSubtitlePath;
      if (externalSubtitlePath == null || externalSubtitlePath.isEmpty) {
        // 再次尝试从subtitleTrackInfo中获取
        if (subtitleTrackInfo.containsKey('external_subtitle') &&
            subtitleTrackInfo['external_subtitle']?['isActive'] == true) {
          externalSubtitlePath =
              subtitleTrackInfo['external_subtitle']?['path'] as String?;
        }
      }

      // 输出详细调试信息
      debugPrint(
          'SubtitleManager: getCurrentSubtitleText - 外部字幕路径: $externalSubtitlePath');
      debugPrint(
          'SubtitleManager: getCurrentSubtitleText - 激活轨道: ${_player.activeSubtitleTracks}');

      // 如果是外部字幕
      if (externalSubtitlePath != null && externalSubtitlePath.isNotEmpty) {
        final fileName = externalSubtitlePath.split('/').last;
        return "正在使用外部字幕文件 - $fileName";
      }

      // 如果是内嵌字幕
      final activeTrack = _player.activeSubtitleTracks.first;
      return "正在播放内嵌字幕轨道 $activeTrack";
    } catch (e) {
      debugPrint('SubtitleManager: 获取当前字幕内容失败: $e');
      return '';
    }
  }

  // 异步预加载字幕文件
  Future<void> preloadSubtitleFile(String path) async {
    // 如果已经缓存过，不重复加载
    if (_subtitleCache.containsKey(path)) {
      return;
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        // 检查文件扩展名，只处理.ass和.srt文件
        final extension = p.extension(path).toLowerCase();
        if (extension == '.ass' || extension == '.srt') {
          // 解析字幕文件
          final entries = await SubtitleParser.parseAssFile(path);
          _subtitleCache[path] = entries;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('预加载字幕文件失败: $e');
    }
  }

  // 当字幕轨道改变时调用
  void onSubtitleTrackChanged() {
    final subtitlePath = getActiveExternalSubtitlePath();
    if (subtitlePath != null) {
      preloadSubtitleFile(subtitlePath);
    }
  }

  // 设置当前外部字幕路径
  void setCurrentExternalSubtitlePath(String? path) {
    _currentExternalSubtitlePath = path;
    debugPrint('SubtitleManager: 设置当前外部字幕路径: $path');
  }

  // 设置外部字幕并更新路径
  void setExternalSubtitle(String path, {bool isManualSetting = false}) {
    try {
      // NEW: Check if player supports external subtitles
      if (!_player.supportsExternalSubtitles) {
        debugPrint('SubtitleManager: 当前播放器内核不支持加载外部字幕');
        // TODO: Call your blur_snackbar here
        // For example: globals.showBlurSnackbar('当前播放器内核不支持加载外部字幕');
        // As a placeholder, I'll just print. Replace with your actual snackbar call.
        print(
            "USER_INFO: blur_snackbar should be called here: '当前播放器内核不支持加载外部字幕'");
        return;
      }

      debugPrint('SubtitleManager: 设置外部字幕: $path, 手动设置: $isManualSetting');

      // 如果字幕文件存在
      if (path.isNotEmpty && File(path).existsSync()) {
        // 设置外部字幕文件
        _player.setMedia(path, MediaType.subtitle);

        // 更新字幕轨道
        _player.activeSubtitleTracks = [0];

        // 更新内部路径，如果是手动设置的，特别标记以避免被内嵌字幕覆盖
        _currentExternalSubtitlePath = path;

        // 更新轨道信息
        updateSubtitleTrackInfo('external_subtitle', {
          'path': path,
          'title': path.split('/').last,
          'isActive': true,
          'isManualSet': isManualSetting, // 添加是否手动设置的标记
        });

        // 预加载字幕文件
        preloadSubtitleFile(path);

        // 如果是手动设置的或者是视频首次使用外部字幕，保存映射关系
        if (isManualSetting && _currentVideoPath != null) {
          saveVideoSubtitleMapping(_currentVideoPath!, path);
        }

        debugPrint('SubtitleManager: 外部字幕设置成功');
      } else if (path.isEmpty) {
        // 清除外部字幕
        _player.setMedia("", MediaType.subtitle);
        _currentExternalSubtitlePath = null;

        // 更新轨道信息，明确清除所有相关标记
        if (_subtitleTrackInfo.containsKey('external_subtitle')) {
          updateSubtitleTrackInfo('external_subtitle', {
            'isActive': false,
            'isManualSet': false, // 明确清除手动设置标记
            'path': null
          });
        }

        debugPrint('SubtitleManager: 外部字幕已清除');
      } else {
        debugPrint('SubtitleManager: 字幕文件不存在: $path');
      }

      // 通知字幕轨道变化
      onSubtitleTrackChanged();
      notifyListeners();
    } catch (e) {
      debugPrint('设置外部字幕失败: $e');
    }
  }

  // 强制设置外部字幕（手动操作）
  void forceSetExternalSubtitle(String path) {
    // 调用setExternalSubtitle，并标记为手动设置
    setExternalSubtitle(path, isManualSetting: true);
  }

  // 自动检测并加载同名字幕文件
  Future<void> autoDetectAndLoadSubtitle(String videoPath) async {
    try {
      debugPrint('SubtitleManager: 自动检测字幕文件...');

      // 首先检查是否有保存的字幕路径
      String? savedSubtitlePath = await getVideoSubtitlePath(videoPath);
      if (savedSubtitlePath != null && savedSubtitlePath.isNotEmpty) {
        debugPrint('SubtitleManager: 找到保存的字幕映射: $savedSubtitlePath');

        // 检查字幕文件是否存在
        final subtitleFile = File(savedSubtitlePath);
        if (subtitleFile.existsSync()) {
          debugPrint('SubtitleManager: 加载上次使用的外部字幕: $savedSubtitlePath');

          // 等待一段时间确保播放器准备好
          await Future.delayed(const Duration(milliseconds: 500));

          // 设置外部字幕（标记为手动设置，因为这是用户曾经手动选择过的）
          setExternalSubtitle(savedSubtitlePath, isManualSetting: true);

          // 设置完成后强制刷新状态
          await Future.delayed(const Duration(milliseconds: 300));

          // 触发自动加载字幕回调
          if (onExternalSubtitleAutoLoaded != null) {
            final fileName = savedSubtitlePath.split('/').last;
            onExternalSubtitleAutoLoaded!(savedSubtitlePath, fileName);
          }

          return;
        } else {
          debugPrint('SubtitleManager: 保存的字幕文件不存在，尝试寻找新的字幕文件');
        }
      }

      // 检查视频是否有内嵌字幕
      bool hasEmbeddedSubtitles = _player.mediaInfo.subtitle != null &&
          _player.mediaInfo.subtitle!.isNotEmpty;

      // 检查是否已激活内嵌字幕轨道
      bool hasActiveEmbeddedTrack = false;
      if (_player.activeSubtitleTracks.isNotEmpty) {
        // 排除轨道0（外部字幕轨道）
        hasActiveEmbeddedTrack =
            _player.activeSubtitleTracks.any((track) => track > 0);
      }

      // 如果以前手动设置过外部字幕，则始终尝试加载
      bool wasManuallySet = false;
      if (_subtitleTrackInfo.containsKey('external_subtitle')) {
        wasManuallySet =
            _subtitleTrackInfo['external_subtitle']?['isManualSet'] == true;
      }

      // 如果是第一次检查，并且有内嵌字幕，跳过自动加载
      // 注意：现在我们已经检查了保存的字幕路径，所以只有在未找到保存记录的情况下才会跳过
      if (hasEmbeddedSubtitles &&
          !wasManuallySet &&
          savedSubtitlePath == null) {
        debugPrint('SubtitleManager: 检测到内嵌字幕且无手动设置记录，跳过自动加载外部字幕');
        return;
      }

      // 检查视频文件是否存在
      final videoFile = File(videoPath);
      if (!videoFile.existsSync()) {
        debugPrint('SubtitleManager: 视频文件不存在，无法检测字幕');
        return;
      }

      // 以下是正常的字幕检测和加载过程

      // 获取视频文件目录和文件名（不含扩展名）
      final videoDir = videoFile.parent.path;
      final videoName = videoPath.split('/').last.split('.').first;

      // 从视频文件名中提取数字（可能的集数）
      final videoNumberMatch = RegExp(r'(\d+)').allMatches(videoName).toList();
      List<String> videoNumbers = [];
      if (videoNumberMatch.isNotEmpty) {
        videoNumbers =
            videoNumberMatch.map((match) => match.group(0)!).toList();
        debugPrint('SubtitleManager: 从视频文件名中提取的数字: $videoNumbers');
      }

      // 提取最可能是集数的数字
      String? episodeNumber;
      if (videoNumbers.isNotEmpty) {
        // 尝试找到两位数的数字作为集数
        for (final num in videoNumbers) {
          if (num.length == 2 && int.parse(num) > 0) {
            episodeNumber = num;
            break;
          }
        }

        // 如果没找到两位数，使用最后一个数字
        episodeNumber ??= videoNumbers.last;

        debugPrint('SubtitleManager: 提取的可能集数: $episodeNumber');
      }

      // 常见字幕文件扩展名按优先级排序
      final subtitleExts = ['.ass', '.srt', '.ssa', '.sub'];

      // 搜索可能的字幕文件
      for (final ext in subtitleExts) {
        final potentialPath = '$videoDir/$videoName$ext';
        debugPrint('SubtitleManager: 尝试检测字幕文件: $potentialPath');
        final subtitleFile = File(potentialPath);
        if (subtitleFile.existsSync()) {
          debugPrint('SubtitleManager: 找到匹配的字幕文件: $potentialPath');

          // 等待一段时间确保播放器准备好
          await Future.delayed(const Duration(milliseconds: 500));

          // 设置外部字幕（不标记为手动设置，因为是自动检测的）
          setExternalSubtitle(potentialPath, isManualSetting: false);

          // 保存这个自动找到的字幕路径，下次可以直接使用
          saveVideoSubtitleMapping(videoPath, potentialPath);

          // 设置完成后强制刷新状态
          await Future.delayed(const Duration(milliseconds: 300));

          // 触发自动加载字幕回调
          if (onExternalSubtitleAutoLoaded != null) {
            final fileName = potentialPath.split('/').last;
            onExternalSubtitleAutoLoaded!(potentialPath, fileName);
          }

          return;
        }
      }

      // 如果没有找到完全匹配的，尝试查找目录中可能匹配的字幕文件
      final videoDirectory = Directory(videoDir);
      if (videoDirectory.existsSync()) {
        try {
          final files = videoDirectory.listSync();

          // 收集所有字幕文件
          List<File> subtitleFiles = [];
          for (final file in files) {
            if (file is File) {
              final ext = p.extension(file.path).toLowerCase();
              if (subtitleExts.contains(ext)) {
                subtitleFiles.add(file);
              }
            }
          }

          if (subtitleFiles.isEmpty) {
            debugPrint('SubtitleManager: 目录中没有找到任何字幕文件');
            return;
          }

          // 如果视频文件名中有数字（可能的集数），尝试基于数字匹配
          if (videoNumbers.isNotEmpty) {
            // 评分系统：根据字幕文件名中包含的视频文件名中的数字数量，给每个字幕文件打分
            Map<File, int> fileScores = {};

            for (final subtitleFile in subtitleFiles) {
              final subtitleName =
                  subtitleFile.path.split('/').last.split('.').first;
              final subtitleNumberMatch =
                  RegExp(r'(\d+)').allMatches(subtitleName).toList();
              List<String> subtitleNumbers = [];

              if (subtitleNumberMatch.isNotEmpty) {
                subtitleNumbers = subtitleNumberMatch
                    .map((match) => match.group(0)!)
                    .toList();
                debugPrint(
                    'SubtitleManager: 字幕文件 ${subtitleFile.path} 中的数字: $subtitleNumbers');

                // 提取可能的字幕集数
                String? subtitleEpisode;
                for (final num in subtitleNumbers) {
                  if (num.length == 2 && int.parse(num) > 0) {
                    subtitleEpisode = num;
                    break;
                  }
                }

                // 如果没找到两位数，使用最后一个数字
                if (subtitleEpisode == null && subtitleNumbers.isNotEmpty) {
                  subtitleEpisode = subtitleNumbers.last;
                }

                debugPrint('SubtitleManager: 字幕可能集数: $subtitleEpisode');

                // 计算匹配分数
                int score = 0;

                // 如果能提取出视频和字幕的集数，精确匹配集数
                if (episodeNumber != null && subtitleEpisode != null) {
                  // 完全匹配集数 - 最高优先级
                  if (episodeNumber == subtitleEpisode) {
                    score += 10; // 给予极高的分数
                    debugPrint(
                        'SubtitleManager: 集数完全匹配! 视频: $episodeNumber, 字幕: $subtitleEpisode');
                  } else {
                    // 检查部分匹配 (例如"01"和"1"，"02"和"2")
                    final vidEpNum = int.tryParse(episodeNumber) ?? -1;
                    final subEpNum = int.tryParse(subtitleEpisode) ?? -1;

                    if (vidEpNum == subEpNum && vidEpNum > 0) {
                      score += 8; // 数值匹配但格式不同
                      debugPrint(
                          'SubtitleManager: 集数数值匹配! 视频: $episodeNumber, 字幕: $subtitleEpisode');
                    } else {
                      // 不匹配 - 给予负分以防止误匹配
                      score -= 5;
                      debugPrint(
                          'SubtitleManager: 集数不匹配! 视频: $episodeNumber, 字幕: $subtitleEpisode');
                    }
                  }
                } else {
                  // 退回到原来的匹配逻辑
                  for (final videoNum in videoNumbers) {
                    if (subtitleNumbers.contains(videoNum)) {
                      score++;
                    }
                  }
                }

                // 如果最后一个数字相同（可能是集数），增加权重
                if (videoNumbers.isNotEmpty &&
                    subtitleNumbers.isNotEmpty &&
                    videoNumbers.last == subtitleNumbers.last) {
                  score += 3;
                }

                fileScores[subtitleFile] = score;
              } else {
                // 没有数字的字幕文件得分为0
                fileScores[subtitleFile] = 0;
              }
            }

            // 按匹配分数排序字幕文件
            subtitleFiles.sort(
                (a, b) => (fileScores[b] ?? 0).compareTo(fileScores[a] ?? 0));

            // 获取最高分
            final highestScore = subtitleFiles.isNotEmpty
                ? (fileScores[subtitleFiles.first] ?? 0)
                : 0;
            debugPrint('SubtitleManager: 最高匹配分数: $highestScore');

            // 只有得分大于0且不是负分的字幕文件才会被使用
            if (subtitleFiles.isNotEmpty && highestScore > 0) {
              final bestMatchFile = subtitleFiles.first;
              debugPrint(
                  'SubtitleManager: 找到最佳匹配的字幕文件: ${bestMatchFile.path} (分数: $highestScore)');

              // 等待一段时间确保播放器准备好
              await Future.delayed(const Duration(milliseconds: 500));

              // 设置外部字幕（不标记为手动设置，因为是自动检测的）
              setExternalSubtitle(bestMatchFile.path, isManualSetting: false);

              // 保存这个自动找到的字幕路径，下次可以直接使用
              saveVideoSubtitleMapping(videoPath, bestMatchFile.path);

              // 设置完成后强制刷新状态
              await Future.delayed(const Duration(milliseconds: 300));

              // 触发自动加载字幕回调
              if (onExternalSubtitleAutoLoaded != null) {
                final fileName = bestMatchFile.path.split('/').last;
                onExternalSubtitleAutoLoaded!(bestMatchFile.path, fileName);
              }

              return;
            } else {
              debugPrint('SubtitleManager: 没有找到高质量匹配的字幕文件，最高分: $highestScore');
            }
          }

          // 如果没有找到基于数字匹配的，或者视频文件名中没有数字，退回到原来的逻辑：选择第一个字幕文件
          if (subtitleFiles.isNotEmpty) {
            final file = subtitleFiles.first;
            debugPrint(
                'SubtitleManager: 没有找到基于数字匹配的字幕，使用第一个可用字幕: ${file.path}');

            // 等待一段时间确保播放器准备好
            await Future.delayed(const Duration(milliseconds: 500));

            // 设置外部字幕（不标记为手动设置，因为是自动检测的）
            setExternalSubtitle(file.path, isManualSetting: false);

            // 保存这个自动找到的字幕路径，下次可以直接使用
            saveVideoSubtitleMapping(videoPath, file.path);

            // 设置完成后强制刷新状态
            await Future.delayed(const Duration(milliseconds: 300));

            // 触发自动加载字幕回调
            if (onExternalSubtitleAutoLoaded != null) {
              final fileName = file.path.split('/').last;
              onExternalSubtitleAutoLoaded!(file.path, fileName);
            }

            return;
          }
        } catch (e) {
          debugPrint('SubtitleManager: 目录搜索错误: $e');
        }
      }

      debugPrint('SubtitleManager: 未找到匹配的字幕文件');
    } catch (e) {
      debugPrint('SubtitleManager: 自动检测字幕文件失败: $e');
    }
  }

  // 获取语言名称
  String getLanguageName(String language) {
    debugPrint(
        'SubtitleManager: getLanguageName - Called with input: "$language"');
    // 语言代码映射
    final Map<String, String> languageCodes = {
      'chi': '中文',
      'eng': '英文',
      'jpn': '日语',
      'kor': '韩语',
      'fra': '法语',
      'deu': '德语',
      'spa': '西班牙语',
      'ita': '意大利语',
      'rus': '俄语',
    };

    // 常见的语言标识符
    final Map<String, String> languagePatterns = {
      r'simplified|简体|chs|imp|zh-hans|zh-cn|zh-sg|sc$|scjp': '简体中文',
      r'traditional|繁体|cht|rad|zh-hant|zh-tw|zh-hk|tc$|tcjp': '繁体中文',
      r'chi|zho|chinese|中文': '中文', // General Chinese as a fallback
      r'eng|en|英文|english': '英文',
      r'jpn|ja|日文|japanese': '日语',
      r'kor|ko|韩文|korean': '韩语',
      r'fra|fr|法文|french': '法语',
      r'ger|de|德文|german': '德语',
      r'spa|es|西班牙文|spanish': '西班牙语',
      r'ita|it|意大利文|italian': '意大利语',
      r'rus|ru|俄文|russian': '俄语',
      r'ind|in|印尼文|indonesian': '印尼语',
    };

    // 首先检查语言代码映射
    final mappedLanguage = languageCodes[language.toLowerCase()];
    if (mappedLanguage != null) {
      debugPrint(
          'SubtitleManager: getLanguageName - Matched languageCodes for "$language": $mappedLanguage');
      return mappedLanguage;
    }

    // 然后检查语言标识符
    for (final entry in languagePatterns.entries) {
      final pattern = RegExp(entry.key, caseSensitive: false);
      if (pattern.hasMatch(language.toLowerCase())) {
        debugPrint(
            'SubtitleManager: getLanguageName - Matched languagePatterns for "$language" (pattern: "${entry.key}"): ${entry.value}');
        return entry.value;
      }
    }
    debugPrint(
        'SubtitleManager: getLanguageName - No match for "$language", returning original.');
    return language;
  }

  // 更新指定的字幕轨道信息
  void updateEmbeddedSubtitleTrack(int trackIndex) {
    if (_player.mediaInfo.subtitle == null ||
        trackIndex >= _player.mediaInfo.subtitle!.length) {
      return;
    }

    final playerSubInfo = _player.mediaInfo.subtitle![trackIndex];
    debugPrint(
        'SubtitleManager: updateEmbeddedSubtitleTrack - Called for trackIndex: $trackIndex');
    debugPrint(
        '  - playerSubInfo.title (from Adapter): "${playerSubInfo.title}"');
    debugPrint(
        '  - playerSubInfo.language (from Adapter): "${playerSubInfo.language}"');
    debugPrint(
        '  - playerSubInfo.metadata (from Adapter): ${playerSubInfo.metadata}');

    String originalTitleFromAdapter = playerSubInfo.title ?? '';
    String originalLanguageCodeFromAdapter = playerSubInfo.language ?? '';
    debugPrint(
        '  - Initial originalTitleFromAdapter: "$originalTitleFromAdapter"');
    debugPrint(
        '  - Initial originalLanguageCodeFromAdapter: "$originalLanguageCodeFromAdapter"');

    String displayTitle = originalTitleFromAdapter;
    String determinedLanguage = "未知";
    debugPrint(
        '  - Initial displayTitle: "$displayTitle", determinedLanguage: "$determinedLanguage"');

    // 1. Try to determine language using the language code from adapter first
    if (originalLanguageCodeFromAdapter.isNotEmpty) {
      determinedLanguage = getLanguageName(originalLanguageCodeFromAdapter);
      debugPrint(
          '  - After step 1 (from lang code): determinedLanguage: "$determinedLanguage"');
    }

    // 2. If language code didn't yield a good name (or was empty), try with the title from adapter
    if (determinedLanguage == "未知" ||
        determinedLanguage == originalLanguageCodeFromAdapter) {
      String langFromTitle = getLanguageName(originalTitleFromAdapter);
      debugPrint(
          '  - Step 2 (from title "$originalTitleFromAdapter"): langFromTitle: "$langFromTitle"');
      if (langFromTitle != originalTitleFromAdapter) {
        determinedLanguage = langFromTitle;
      }
      debugPrint('  - After step 2: determinedLanguage: "$determinedLanguage"');
    }

    // 3. Determine final display title based on the determinedLanguage
    if (determinedLanguage != "未知" &&
        determinedLanguage != originalTitleFromAdapter &&
        determinedLanguage != originalLanguageCodeFromAdapter) {
      displayTitle = determinedLanguage;
      if (originalTitleFromAdapter.isNotEmpty &&
          originalTitleFromAdapter.toLowerCase() != 'n/a' &&
          originalTitleFromAdapter != displayTitle &&
          !displayTitle.contains(originalTitleFromAdapter) &&
          getLanguageName(originalTitleFromAdapter) != displayTitle) {
        displayTitle += " ($originalTitleFromAdapter)";
      }
    } else if (originalTitleFromAdapter.isNotEmpty &&
        originalTitleFromAdapter.toLowerCase() != 'n/a') {
      String langFromOrigTitle = getLanguageName(originalTitleFromAdapter);
      if (langFromOrigTitle != originalTitleFromAdapter) {
        displayTitle = langFromOrigTitle;
        determinedLanguage = langFromOrigTitle;
      } else {
        displayTitle = originalTitleFromAdapter;
        if (determinedLanguage == "未知") {
          determinedLanguage = originalTitleFromAdapter;
        }
      }
    } else {
      displayTitle = "轨道 ${trackIndex + 1}";
      if (determinedLanguage == "未知") determinedLanguage = displayTitle;
    }
    debugPrint(
        '  - After step 3 (display title construction): displayTitle: "$displayTitle", determinedLanguage: "$determinedLanguage"');

    // Ensure determinedLanguage itself is a "final" friendly name
    String finalDeterminedLanguage = getLanguageName(determinedLanguage);
    if (finalDeterminedLanguage != determinedLanguage) {
      determinedLanguage = finalDeterminedLanguage;
    }
    debugPrint(
        '  - After final determinedLanguage refinement: determinedLanguage: "$determinedLanguage"');

    // If displayTitle is generic but determinedLanguage is more specific, use determinedLanguage for displayTitle
    if ((displayTitle == "未知" ||
            displayTitle.startsWith("轨道 ") ||
            displayTitle.isEmpty) &&
        determinedLanguage != "未知" &&
        !determinedLanguage.startsWith("轨道 ") &&
        determinedLanguage.isNotEmpty) {
      displayTitle = determinedLanguage;
    }
    // If displayTitle ended up being empty (e.g. original title was empty and no language match), use a fallback for title
    if (displayTitle.isEmpty) {
      displayTitle = "轨道 ${trackIndex + 1}";
    }
    // If determinedLanguage ended up empty, and display title is not generic, use display title for language
    if (determinedLanguage.isEmpty &&
        displayTitle.isNotEmpty &&
        !displayTitle.startsWith("轨道 ")) {
      determinedLanguage = displayTitle;
    } else if (determinedLanguage.isEmpty) {
      // If still empty, use fallback for language
      determinedLanguage = "未知";
    }
    debugPrint(
        '  - After displayTitle/determinedLanguage final fallbacks: displayTitle: "$displayTitle", determinedLanguage: "$determinedLanguage"');

    debugPrint(
        'SubtitleManager: updateEmbeddedSubtitleTrack - FINAL values before updateSubtitleTrackInfo for trackIndex $trackIndex:');
    debugPrint('  - FINAL title for UI: "$displayTitle"');
    debugPrint('  - FINAL language for UI: "$determinedLanguage"');

    updateSubtitleTrackInfo('embedded_subtitle_$trackIndex', {
      'index': trackIndex,
      'title': displayTitle,
      'language': determinedLanguage,
      'isActive': _player.activeSubtitleTracks.contains(trackIndex),
      'original_media_kit_title':
          playerSubInfo.metadata['title'] ?? originalTitleFromAdapter,
      'original_media_kit_lang_code':
          playerSubInfo.metadata['language'] ?? originalLanguageCodeFromAdapter
    });

    // 清除外部字幕信息的激活状态
    if (_player.activeSubtitleTracks.contains(trackIndex) &&
        _subtitleTrackInfo.containsKey('external_subtitle')) {
      updateSubtitleTrackInfo('external_subtitle', {'isActive': false});
    }
  }

  // 更新所有字幕轨道信息
  void updateAllSubtitleTracksInfo() {
    if (_player.mediaInfo.subtitle == null) {
      return;
    }

    // 清除之前的内嵌字幕轨道信息
    for (final key in List.from(_subtitleTrackInfo.keys)) {
      if (key.startsWith('embedded_subtitle_')) {
        _subtitleTrackInfo.remove(key);
      }
    }

    // 更新所有内嵌字幕轨道信息
    for (var i = 0; i < _player.mediaInfo.subtitle!.length; i++) {
      updateEmbeddedSubtitleTrack(i);
    }

    // 在更新完成后检查当前激活的字幕轨道并确保相应的信息被更新
    if (_player.activeSubtitleTracks.isNotEmpty) {
      final activeIndex = _player.activeSubtitleTracks.first;
      if (activeIndex > 0 &&
          activeIndex <= _player.mediaInfo.subtitle!.length) {
        // 激活的是内嵌字幕轨道
        updateSubtitleTrackInfo('embedded_subtitle', {
          'index': activeIndex - 1, // MDK 字幕轨道从 1 开始，而我们的索引从 0 开始
          'title': _player.mediaInfo.subtitle![activeIndex - 1].toString(),
          'isActive': true,
        });

        // 通知字幕轨道变化
        onSubtitleTrackChanged();
      }
    }

    notifyListeners();
  }
}
