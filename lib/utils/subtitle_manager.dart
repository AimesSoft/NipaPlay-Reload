import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'subtitle_parser.dart';
import 'storage_service.dart';
import '../../player_abstraction/player_abstraction.dart';
import 'package:nipaplay/services/remote_subtitle_service.dart';
import 'package:nipaplay/utils/subtitle_file_utils.dart';
import 'package:nipaplay/utils/subtitle_language_utils.dart';

/// 字幕管理器类，负责处理与字幕相关的所有功能
class SubtitleManager extends ChangeNotifier {
  static const Duration _mdkSubtitleRetryInterval = Duration(
    milliseconds: 80,
  );
  static const int _mdkVisibilityRetryAttempts = 6;
  static const int _mdkTrackActivationRetryAttempts = 10;
  static const Duration _autoLoadPlayerReadyDelay = Duration(
    milliseconds: 500,
  );
  static const Duration _autoLoadStateSettleDelay = Duration(
    milliseconds: 300,
  );
  static const int _subtitlePreviewMaxChars = 80;

  Player _player;
  String? _currentVideoPath;
  String? _currentExternalSubtitlePath;
  final Map<String, Map<String, dynamic>> _subtitleTrackInfo = {};
  final Map<String, List<dynamic>> _subtitleCache = {};
  int _subtitleLoadToken = 0;

  // 视频-字幕路径映射的持久化存储键
  static const String _videoSubtitleMapKey = 'video_subtitle_map';

  // 外部字幕自动加载回调
  Function(String path, String fileName)? onExternalSubtitleAutoLoaded;
  void Function(String message)? onUserNotification;

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
    // 检查是否是外部字幕
    final externalInfo = _subtitleTrackInfo['external_subtitle'];
    if (externalInfo is Map<String, dynamic> &&
        externalInfo['isActive'] == true) {
      final path = externalInfo['path'];
      if (path is String && path.isNotEmpty) {
        return path;
      }
    }

    // 回退：使用当前记录的外部字幕路径
    if (_currentExternalSubtitlePath != null &&
        _currentExternalSubtitlePath!.isNotEmpty) {
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
    String videoPath,
    String subtitlePath,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappingJson = prefs.getString(_videoSubtitleMapKey) ?? '{}';
      final Map<String, dynamic> mappingMap = Map<String, dynamic>.from(
        json.decode(mappingJson),
      );
      mappingMap[videoPath] = subtitlePath;
      await prefs.setString(_videoSubtitleMapKey, json.encode(mappingMap));
      debugPrint(
        'SubtitleManager: 保存视频字幕映射 - 视频: $videoPath, 字幕: $subtitlePath',
      );
    } catch (e) {
      debugPrint('SubtitleManager: 保存视频字幕映射失败: $e');
    }
  }

  // 获取视频对应的字幕路径
  Future<String?> getVideoSubtitlePath(String videoPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappingJson = prefs.getString(_videoSubtitleMapKey) ?? '{}';
      final Map<String, dynamic> mappingMap = Map<String, dynamic>.from(
        json.decode(mappingJson),
      );
      final subtitlePath = mappingMap[videoPath] as String?;
      debugPrint(
        'SubtitleManager: 获取视频对应的字幕路径 - 视频: $videoPath, 字幕: $subtitlePath',
      );

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
      // 检查是否是外部字幕（外部字幕在 media_kit 内核下可能不会体现在 activeSubtitleTracks 中）
      String? externalSubtitlePath = getActiveExternalSubtitlePath();

      // 输出详细调试信息
      debugPrint(
        'SubtitleManager: getCurrentSubtitleText - 外部字幕路径: $externalSubtitlePath',
      );
      debugPrint(
        'SubtitleManager: getCurrentSubtitleText - 激活轨道: ${_player.activeSubtitleTracks}',
      );

      // 如果是外部字幕
      if (externalSubtitlePath != null && externalSubtitlePath.isNotEmpty) {
        final fileName = p.basename(externalSubtitlePath);
        return "正在使用外部字幕文件 - $fileName";
      }

      // 如果没有外部字幕且没有激活的字幕轨道
      if (_player.activeSubtitleTracks.isEmpty) {
        debugPrint('SubtitleManager: getCurrentSubtitleText - 没有激活的字幕轨道');
        return '';
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
        // 仅对文本字幕进行预解析，图像字幕(.sup)直接交给播放器
        final extension = p.extension(path).toLowerCase();
        if (extension == '.ass' ||
            extension == '.srt' ||
            extension == '.ssa' ||
            extension == '.sub') {
          final result = await SubtitleParser.parseSubtitleFile(
            path,
            allowUnknownFormat: true,
          );
          _subtitleCache[path] = result.entries;
          notifyListeners();
        } else if (extension == '.sup') {
          debugPrint('SubtitleManager: 检测到sup字幕，跳过文本解析');
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

  String _getVideoHashKey(String videoPath) {
    final file = File(videoPath);
    if (file.existsSync()) {
      final size = file.lengthSync();
      final name = p.basename(videoPath);
      return '$name-$size';
    }
    return sha1.convert(utf8.encode(videoPath)).toString();
  }

  Future<void> _persistExternalSubtitleSelection({
    required String videoPath,
    required String subtitlePath,
    required bool isActive,
  }) async {
    try {
      if (subtitlePath.isEmpty) return;
      if (!File(subtitlePath).existsSync()) return;

      final prefs = await SharedPreferences.getInstance();
      final videoHashKey = _getVideoHashKey(videoPath);
      final subtitlesKey = 'external_subtitles_$videoHashKey';

      final existingJson = prefs.getString(subtitlesKey);
      final List<Map<String, dynamic>> subtitles = [];
      if (existingJson != null && existingJson.isNotEmpty) {
        try {
          final decoded = json.decode(existingJson);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                subtitles.add(Map<String, dynamic>.from(item));
              }
            }
          }
        } catch (_) {
          // 忽略解析错误，回退为空列表
        }
      }

      // 移除同路径条目，并把当前字幕置顶（方便选择）
      subtitles.removeWhere((s) => s['path'] == subtitlePath);

      // 将所有字幕设为非激活
      for (final s in subtitles) {
        s['isActive'] = false;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      subtitles.insert(0, <String, dynamic>{
        'path': subtitlePath,
        'name': p.basename(subtitlePath),
        'type': p.extension(subtitlePath).toLowerCase().replaceFirst('.', ''),
        'addTime': now,
        'isActive': isActive,
      });

      await prefs.setString(subtitlesKey, json.encode(subtitles));

      final lastActiveKey = 'last_active_subtitle_$videoHashKey';
      if (isActive) {
        await prefs.setInt(lastActiveKey, 0);
      } else {
        await prefs.remove(lastActiveKey);
      }
    } catch (e) {
      debugPrint('SubtitleManager: 持久化外部字幕选择失败: $e');
    }
  }

  // 清空外部字幕状态，同时通知播放器关闭外挂轨道
  void _clearExternalSubtitleState({bool resetManualFlag = true}) {
    try {
      if (_player.supportsExternalSubtitles) {
        _player.setMedia("", MediaType.subtitle);
      }
    } catch (e) {
      debugPrint('SubtitleManager: 清除播放器外部字幕失败: $e');
    }

    try {
      if (_player.activeSubtitleTracks.isNotEmpty) {
        _player.activeSubtitleTracks = [];
      }
    } catch (e) {
      debugPrint('SubtitleManager: 重置字幕轨道选择失败: $e');
    }

    _currentExternalSubtitlePath = null;

    final existing = _subtitleTrackInfo['external_subtitle'];
    if (existing is Map<String, dynamic>) {
      final updated = Map<String, dynamic>.from(existing);
      updated['isActive'] = false;
      updated['path'] = null;
      if (resetManualFlag) {
        updated['isManualSet'] = false;
      }
      _subtitleTrackInfo['external_subtitle'] = updated;
    }
  }

  /// 对外暴露的清理接口，供播放器切集或重置时调用
  void clearExternalSubtitle({bool notifyListenersToo = true}) {
    _clearExternalSubtitleState();
    if (notifyListenersToo) {
      onSubtitleTrackChanged();
      notifyListeners();
    }
    debugPrint('SubtitleManager: 外部字幕状态已重置');
  }

  // 设置外部字幕并更新路径
  void setExternalSubtitle(String path, {bool isManualSetting = false}) {
    try {
      final loadToken = ++_subtitleLoadToken;
      final previousSubtitleTrackSignatures =
          _isMdkKernel() ? _snapshotCurrentSubtitleTrackSignatures() : null;
      // NEW: Check if player supports external subtitles
      if (!_player.supportsExternalSubtitles && path.isNotEmpty) {
        debugPrint('SubtitleManager: 当前播放器内核不支持加载外部字幕');
        onUserNotification?.call('当前播放器内核不支持加载外部字幕');
        return;
      }

      debugPrint('SubtitleManager: 设置外部字幕: $path, 手动设置: $isManualSetting');

      // 如果字幕文件存在
      if (path.isNotEmpty && File(path).existsSync()) {
        final shouldRenderInApp = _shouldRenderExternalSubtitleInApp(path);
        final shouldFixEncoding = _shouldFixExternalSubtitleEncoding();
        if (shouldRenderInApp) {
          _activateAppRenderedExternalSubtitle(path);
        } else if (!shouldFixEncoding) {
          // 设置外部字幕文件
          _loadExternalSubtitleIntoPlayer(
            path,
            loadToken,
            previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
          );
        } else {
          // 对 MDK / Media Kit 预处理字幕编码，避免 UTF-16 直接喂给内核导致崩溃
          unawaited(
            _loadExternalSubtitleWithEncodingFix(
              path,
              loadToken,
              previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
            ),
          );
        }

        // 更新内部路径，如果是手动设置的，特别标记以避免被内嵌字幕覆盖
        _currentExternalSubtitlePath = path;

        // 更新轨道信息
        updateSubtitleTrackInfo('external_subtitle', {
          'path': path,
          'title': p.basename(path),
          'isActive': true,
          'isManualSet': isManualSetting, // 添加是否手动设置的标记
        });

        // 预加载字幕文件
        preloadSubtitleFile(path);

        // 如果是手动设置的或者是视频首次使用外部字幕，保存映射关系
        if (isManualSetting && _currentVideoPath != null) {
          saveVideoSubtitleMapping(_currentVideoPath!, path);
        }

        if (_currentVideoPath != null && _currentVideoPath!.isNotEmpty) {
          unawaited(
            _persistExternalSubtitleSelection(
              videoPath: _currentVideoPath!,
              subtitlePath: path,
              isActive: true,
            ),
          );
        }

        debugPrint('SubtitleManager: 外部字幕设置成功');
      } else if (path.isEmpty) {
        _clearExternalSubtitleState();
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

  bool _isMdkKernel() => _player.getPlayerKernelName() == 'MDK';
  bool _isMediaKitKernel() => _player.getPlayerKernelName() == 'Media Kit';
  bool _shouldFixExternalSubtitleEncoding() =>
      !kIsWeb && (_isMdkKernel() || _isMediaKitKernel());
  bool _shouldRenderExternalSubtitleInApp(String path) {
    if (kIsWeb || !_isMdkKernel() || !Platform.isWindows) {
      return false;
    }

    final extension = p.extension(path).toLowerCase();
    return extension == '.ass' || extension == '.ssa' || extension == '.srt';
  }

  void _activateAppRenderedExternalSubtitle(String path) {
    try {
      _player.setMedia("", MediaType.subtitle);
    } catch (e) {
      debugPrint('SubtitleManager: 清理播放器外挂字幕失败: $e');
    }

    try {
      _player.activeSubtitleTracks = [];
    } catch (e) {
      debugPrint('SubtitleManager: 清理播放器字幕轨失败: $e');
    }

    unawaited(preloadSubtitleFile(path));
    debugPrint('SubtitleManager: 使用应用内叠层渲染外挂字幕: $path');
  }

  bool shouldRenderCurrentExternalSubtitleInApp() {
    final path = getActiveExternalSubtitlePath();
    if (path == null || path.isEmpty) {
      return false;
    }

    return _shouldRenderExternalSubtitleInApp(path);
  }

  String getCurrentExternalSubtitleTextAt(int positionMs) {
    final path = getActiveExternalSubtitlePath();
    if (path == null ||
        path.isEmpty ||
        !_shouldRenderExternalSubtitleInApp(path)) {
      return '';
    }

    final cachedEntries = _subtitleCache[path];
    if (cachedEntries == null || cachedEntries.isEmpty) {
      unawaited(preloadSubtitleFile(path));
      return '';
    }

    final activeContents = <String>[];
    for (final entry in cachedEntries) {
      if (entry is! SubtitleEntry) {
        continue;
      }
      if (positionMs < entry.startTimeMs || positionMs > entry.endTimeMs) {
        continue;
      }

      final content = entry.content.trim();
      if (content.isEmpty || activeContents.contains(content)) {
        continue;
      }
      activeContents.add(content);
    }

    final text = activeContents.join('\n');
    return text;
  }

  List<String> _snapshotCurrentSubtitleTrackSignatures() {
    final tracks = _player.mediaInfo.subtitle;
    if (tracks == null || tracks.isEmpty) {
      return const [];
    }

    return tracks.map(_buildSubtitleTrackSignature).toList();
  }

  String _buildSubtitleTrackSignature(PlayerSubtitleStreamInfo track) {
    final raw = track.rawRepresentation.trim();
    if (raw.isNotEmpty) {
      return raw;
    }

    final title = track.title?.trim() ?? '';
    final language = track.language?.trim() ?? '';
    return '$title|$language';
  }

  void _loadExternalSubtitleIntoPlayer(
    String path,
    int loadToken, {
    List<String>? previousSubtitleTrackSignatures,
  }) {
    if (_isMdkKernel()) {
      try {
        _player.setProperty('subtitle', '1');
        _player.activeSubtitleTracks = [];
      } catch (e) {
        debugPrint('SubtitleManager: MDK 清理旧字幕轨失败: $e');
      }
    }

    _player.setMedia(path, MediaType.subtitle);

    if (_isMdkKernel()) {
      unawaited(
        _ensureMdkExternalSubtitleVisible(
          subtitlePath: path,
          loadToken: loadToken,
        ),
      );
      unawaited(
        _activateMdkExternalSubtitleTrack(
          subtitlePath: path,
          loadToken: loadToken,
          previousSubtitleTrackSignatures:
              previousSubtitleTrackSignatures ?? const [],
        ),
      );
    }
  }

  Future<void> _ensureMdkExternalSubtitleVisible({
    required String subtitlePath,
    required int loadToken,
  }) async {
    if (!_isMdkKernel()) return;

    for (var attempt = 0; attempt < _mdkVisibilityRetryAttempts; attempt++) {
      await Future.delayed(_mdkSubtitleRetryInterval);

      if (loadToken != _subtitleLoadToken) return;
      if (_currentExternalSubtitlePath != subtitlePath) return;

      try {
        _player.setProperty('subtitle', '1');
        _player.activeSubtitleTracks = [0];
        debugPrint(
          'SubtitleManager: MDK 已请求显示外挂字幕，attempt=$attempt active=${_player.activeSubtitleTracks}',
        );
      } catch (e) {
        debugPrint('SubtitleManager: MDK 请求显示外挂字幕失败: $e');
      }
    }
  }

  Future<void> _activateMdkExternalSubtitleTrack({
    required String subtitlePath,
    required int loadToken,
    required List<String> previousSubtitleTrackSignatures,
  }) async {
    if (!_isMdkKernel()) return;

    final subtitleName = p.basenameWithoutExtension(subtitlePath).toLowerCase();
    final previousTrackSet = previousSubtitleTrackSignatures.toSet();

    for (var attempt = 0;
        attempt < _mdkTrackActivationRetryAttempts;
        attempt++) {
      await Future.delayed(_mdkSubtitleRetryInterval);

      if (loadToken != _subtitleLoadToken) return;
      if (_currentExternalSubtitlePath != subtitlePath) return;

      final currentTracks = _player.mediaInfo.subtitle;
      if (currentTracks == null || currentTracks.isEmpty) {
        continue;
      }

      int? targetIndex;
      for (var i = 0; i < currentTracks.length; i++) {
        final signature = _buildSubtitleTrackSignature(currentTracks[i]);
        if (!previousTrackSet.contains(signature)) {
          targetIndex = i;
          break;
        }
      }

      if (targetIndex == null) {
        final matchedIndex = currentTracks.indexWhere((track) {
          final title = track.title?.toLowerCase() ?? '';
          final raw = track.rawRepresentation.toLowerCase();
          return title.contains(subtitleName) || raw.contains(subtitleName);
        });
        if (matchedIndex >= 0) {
          targetIndex = matchedIndex;
        }
      }

      if (targetIndex == null &&
          currentTracks.length > previousSubtitleTrackSignatures.length) {
        targetIndex = currentTracks.length - 1;
      }

      if (targetIndex == null && currentTracks.length == 1) {
        targetIndex = 0;
      }

      if (targetIndex == null) {
        continue;
      }

      try {
        _player.setProperty('subtitle', '1');
        _player.activeSubtitleTracks = [targetIndex];
        debugPrint(
          'SubtitleManager: MDK 外部字幕轨已激活，索引: $targetIndex, 字幕: $subtitlePath',
        );
        return;
      } catch (e) {
        debugPrint('SubtitleManager: MDK 激活外部字幕轨失败: $e');
      }
    }

    debugPrint('SubtitleManager: MDK 外部字幕轨激活超时: $subtitlePath');
  }

  Future<void> _loadExternalSubtitleWithEncodingFix(
    String sourcePath,
    int loadToken, {
    List<String>? previousSubtitleTrackSignatures,
  }) async {
    try {
      if (kIsWeb) return;

      final extension = p.extension(sourcePath).toLowerCase();
      if (extension == '.sup') {
        if (loadToken != _subtitleLoadToken) return;
        if (_currentExternalSubtitlePath != sourcePath) return;
        _loadExternalSubtitleIntoPlayer(
          sourcePath,
          loadToken,
          previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
        );
        return;
      }

      final decoded = await SubtitleParser.decodeSubtitleFile(
        sourcePath,
        allowUnknownFormat: true,
      );
      if (decoded == null) {
        if (extension == '.sub') {
          final idxPath = p.setExtension(sourcePath, '.idx');
          final idxFile = File(idxPath);
          if (await idxFile.exists()) {
            if (loadToken != _subtitleLoadToken) return;
            if (_currentExternalSubtitlePath != sourcePath) return;
            _loadExternalSubtitleIntoPlayer(
              idxPath,
              loadToken,
              previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
            );
            debugPrint('SubtitleManager: 检测到VobSub，改用IDX加载字幕: $idxPath');
          }
        }
        // 解码失败，回退直接加载原文件（避免完全无字幕）
        if (loadToken != _subtitleLoadToken) return;
        if (_currentExternalSubtitlePath != sourcePath) return;
        _loadExternalSubtitleIntoPlayer(
          sourcePath,
          loadToken,
          previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
        );
        return;
      }

      final encoding = decoded.encoding.toLowerCase();
      final preview = _extractSubtitlePreview(decoded.text);
      final format = SubtitleParser.detectFormat(decoded.text, sourcePath);
      debugPrint(
        'SubtitleManager: 检测到字幕编码: ${decoded.encoding}, 格式: $format, 预览: $preview',
      );
      if (encoding.startsWith('utf-8')) {
        if (loadToken != _subtitleLoadToken) return;
        if (_currentExternalSubtitlePath != sourcePath) return;
        _loadExternalSubtitleIntoPlayer(
          sourcePath,
          loadToken,
          previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
        );
        return;
      }

      final file = File(sourcePath);
      if (!await file.exists()) return;
      final stat = await file.stat();
      if (stat.size <= 0) return;

      final cacheDir = await _getSubtitleCacheDirectory();
      const cacheVersion = 'v2';
      final cacheKey =
          '$cacheVersion|$sourcePath|${stat.modified.millisecondsSinceEpoch}|${stat.size}|${decoded.encoding}';
      final hash = sha1.convert(utf8.encode(cacheKey)).toString();
      final targetExtension = _resolveSubtitleExtension(format, extension);
      final targetPath = p.join(cacheDir.path, '$hash$targetExtension');

      final targetFile = File(targetPath);
      if (!await targetFile.exists()) {
        await targetFile.writeAsString(decoded.text, encoding: utf8);
      }

      if (loadToken != _subtitleLoadToken) return;
      if (_currentExternalSubtitlePath != sourcePath) return;

      _loadExternalSubtitleIntoPlayer(
        targetPath,
        loadToken,
        previousSubtitleTrackSignatures: previousSubtitleTrackSignatures,
      );
      debugPrint('SubtitleManager: 已转换字幕编码并重新加载: $targetPath');
    } catch (e) {
      debugPrint('SubtitleManager: 转换字幕编码失败: $e');
    }
  }

  Future<Directory> _getSubtitleCacheDirectory() async {
    final baseDir = await StorageService.getAppStorageDirectory();
    final cacheDir = Directory(p.join(baseDir.path, 'subtitle_transcoded'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  String _resolveSubtitleExtension(
    SubtitleFormat format,
    String originalExtension,
  ) {
    if (format == SubtitleFormat.ass) return '.ass';
    if (format == SubtitleFormat.srt) return '.srt';
    if (format == SubtitleFormat.subViewer) return '.sub';
    if (format == SubtitleFormat.microdvd) return '.sub';
    if (originalExtension.isNotEmpty) return originalExtension;
    return '.sub';
  }

  String _extractSubtitlePreview(String text) {
    final lines = LineSplitter.split(text);
    String? firstNonEmpty;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      firstNonEmpty ??= trimmed;
      if (_containsCjk(trimmed)) {
        return _trimPreview(trimmed);
      }
    }

    if (firstNonEmpty == null) return '';
    return _trimPreview(firstNonEmpty);
  }

  bool _containsCjk(String text) {
    for (final rune in text.runes) {
      if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0xF900 && rune <= 0xFAFF) ||
          (rune >= 0x3040 && rune <= 0x30FF) ||
          (rune >= 0xAC00 && rune <= 0xD7AF)) {
        return true;
      }
    }
    return false;
  }

  String _trimPreview(String text) {
    final cleaned = text.replaceAll('\n', ' ').trim();
    if (cleaned.length <= _subtitlePreviewMaxChars) return cleaned;
    return '${cleaned.substring(0, _subtitlePreviewMaxChars)}...';
  }

  // 强制设置外部字幕（手动操作）
  void forceSetExternalSubtitle(String path) {
    // 调用setExternalSubtitle，并标记为手动设置
    setExternalSubtitle(path, isManualSetting: true);
  }

  File? _pickBestLocalSubtitleFile({
    required List<File> subtitleFiles,
    required String videoName,
    required List<String> videoNumbers,
    String? episodeNumber,
  }) {
    if (subtitleFiles.isEmpty) {
      return null;
    }

    final scoredCandidates = subtitleFiles.map((file) {
      final subtitleName = p.basenameWithoutExtension(file.path);
      final extension = p.extension(file.path).toLowerCase();
      final score = computeLocalSubtitleMatchScore(
        videoName: videoName,
        subtitleName: subtitleName,
        extension: extension,
        videoNumbers: videoNumbers,
        episodeNumber: episodeNumber,
      );
      return (file: file, score: score);
    }).toList()
      ..sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) {
          return scoreCompare;
        }
        return a.file.path.compareTo(b.file.path);
      });

    for (final candidate in scoredCandidates) {
      debugPrint(
        'SubtitleManager: 本地字幕候选 ${candidate.file.path} 得分: ${candidate.score}',
      );
    }

    final bestCandidate = scoredCandidates.first;
    if (bestCandidate.score >= minReliableLocalSubtitleMatchScore ||
        (subtitleFiles.length == 1 && bestCandidate.score >= 0)) {
      return bestCandidate.file;
    }

    return null;
  }

  // 自动检测并加载同名字幕文件
  Future<void> autoDetectAndLoadSubtitle(String videoPath) async {
    if (kIsWeb) {
      debugPrint('SubtitleManager: Web平台跳过自动检测字幕文件');
      return;
    }
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
          await Future.delayed(_autoLoadPlayerReadyDelay);

          // 设置外部字幕（标记为手动设置，因为这是用户曾经手动选择过的）
          setExternalSubtitle(savedSubtitlePath, isManualSetting: true);

          // 设置完成后强制刷新状态
          await Future.delayed(_autoLoadStateSettleDelay);

          // 触发自动加载字幕回调
          if (onExternalSubtitleAutoLoaded != null) {
            final fileName = p.basename(savedSubtitlePath);
            onExternalSubtitleAutoLoaded!(savedSubtitlePath, fileName);
          }

          return;
        } else {
          debugPrint('SubtitleManager: 保存的字幕文件不存在，尝试寻找新的字幕文件');
        }
      }

      // 远程媒体库字幕（含弹弹play远程流）
      if (!kIsWeb &&
          RemoteSubtitleService.instance.isPotentialRemoteVideoPath(
            videoPath,
          )) {
        try {
          final candidates = await RemoteSubtitleService.instance
              .listCandidatesForVideo(videoPath);
          if (candidates.isNotEmpty) {
            final resolvedMatchPath = RemoteSubtitleService.instance
                .resolveVideoPathForMatching(videoPath);
            final matchPath =
                resolvedMatchPath.isNotEmpty ? resolvedMatchPath : videoPath;
            final selected = _pickRemoteSubtitleCandidate(
              candidates,
              matchPath,
            );
            final cachedPath = await RemoteSubtitleService.instance
                .ensureSubtitleCached(selected);

            // 等待一段时间确保播放器准备好
            await Future.delayed(_autoLoadPlayerReadyDelay);

            // 设置外部字幕（不标记为手动设置，因为是自动检测的）
            setExternalSubtitle(cachedPath, isManualSetting: false);

            // 保存这个自动找到的字幕路径，下次可以直接使用
            saveVideoSubtitleMapping(videoPath, cachedPath);

            // 设置完成后强制刷新状态
            await Future.delayed(_autoLoadStateSettleDelay);

            // 触发自动加载字幕回调
            if (onExternalSubtitleAutoLoaded != null) {
              onExternalSubtitleAutoLoaded!(cachedPath, selected.name);
            }

            return;
          } else {
            debugPrint('SubtitleManager: 远程目录未找到字幕文件');
          }
        } catch (e) {
          debugPrint('SubtitleManager: 远程字幕检测失败: $e');
        }

        final streamUri = Uri.tryParse(videoPath);
        final scheme = streamUri?.scheme.toLowerCase();
        if (scheme == 'http' || scheme == 'https') {
          debugPrint('SubtitleManager: 远程流字幕检测结束，跳过本地文件系统检测');
          return;
        }
      }

      // 需求：即使存在内嵌字幕，也应优先尝试自动加载外挂字幕。

      // 检查视频文件是否存在
      final videoFile = File(videoPath);
      if (!videoFile.existsSync()) {
        debugPrint('SubtitleManager: 视频文件不存在，无法检测字幕');
        return;
      }

      // 以下是正常的字幕检测和加载过程

      // 获取视频文件目录和文件名（不含扩展名）
      final videoDir = videoFile.parent.path;
      final videoName = p.basenameWithoutExtension(videoPath);

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
        episodeNumber = pickLikelyEpisodeNumber(videoNumbers);
        debugPrint('SubtitleManager: 提取的可能集数: $episodeNumber');
      }

      // 常见字幕文件扩展名按优先级排序
      final subtitleExts = subtitleExtensionMatchScore.keys.toList();

      // 搜索可能的字幕文件
      for (final ext in subtitleExts) {
        final potentialPath = p.join(videoDir, '$videoName$ext');
        debugPrint('SubtitleManager: 尝试检测字幕文件: $potentialPath');
        final subtitleFile = File(potentialPath);
        if (subtitleFile.existsSync()) {
          debugPrint('SubtitleManager: 找到匹配的字幕文件: $potentialPath');

          // 等待一段时间确保播放器准备好
          await Future.delayed(_autoLoadPlayerReadyDelay);

          // 设置外部字幕（不标记为手动设置，因为是自动检测的）
          setExternalSubtitle(potentialPath, isManualSetting: false);

          // 保存这个自动找到的字幕路径，下次可以直接使用
          saveVideoSubtitleMapping(videoPath, potentialPath);

          // 设置完成后强制刷新状态
          await Future.delayed(_autoLoadStateSettleDelay);

          // 触发自动加载字幕回调
          if (onExternalSubtitleAutoLoaded != null) {
            final fileName = p.basename(potentialPath);
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

          final bestMatchFile = _pickBestLocalSubtitleFile(
            subtitleFiles: subtitleFiles,
            videoName: videoName,
            videoNumbers: videoNumbers,
            episodeNumber: episodeNumber,
          );

          if (bestMatchFile != null) {
            debugPrint('SubtitleManager: 找到最佳匹配的字幕文件: ${bestMatchFile.path}');

            // 等待一段时间确保播放器准备好
            await Future.delayed(_autoLoadPlayerReadyDelay);

            // 设置外部字幕（不标记为手动设置，因为是自动检测的）
            setExternalSubtitle(bestMatchFile.path, isManualSetting: false);

            // 保存这个自动找到的字幕路径，下次可以直接使用
            saveVideoSubtitleMapping(videoPath, bestMatchFile.path);

            // 设置完成后强制刷新状态
            await Future.delayed(_autoLoadStateSettleDelay);

            // 触发自动加载字幕回调
            if (onExternalSubtitleAutoLoaded != null) {
              final fileName = p.basename(bestMatchFile.path);
              onExternalSubtitleAutoLoaded!(bestMatchFile.path, fileName);
            }

            return;
          }

          debugPrint('SubtitleManager: 没有找到足够可靠的本地字幕匹配结果');
        } catch (e) {
          debugPrint('SubtitleManager: 目录搜索错误: $e');
        }
      }

      debugPrint('SubtitleManager: 未找到匹配的字幕文件');
    } catch (e) {
      debugPrint('SubtitleManager: 自动检测字幕文件失败: $e');
    }
  }

  RemoteSubtitleCandidate _pickRemoteSubtitleCandidate(
    List<RemoteSubtitleCandidate> candidates,
    String videoPath,
  ) {
    String? baseName;
    try {
      final uri = Uri.tryParse(videoPath);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        baseName = p.basenameWithoutExtension(uri.pathSegments.last);
      }
    } catch (_) {}

    int scoreCandidate(RemoteSubtitleCandidate candidate) {
      final ext = candidate.extension.toLowerCase();
      int score = switch (ext) {
        '.ass' => 40,
        '.ssa' => 35,
        '.srt' => 30,
        '.sub' => 20,
        '.sup' => 10,
        _ => 0,
      };

      if (baseName != null && baseName.isNotEmpty) {
        final lowerName = candidate.name.toLowerCase();
        if (lowerName.contains(baseName.toLowerCase())) {
          score += 15;
        }
      }

      if (candidate is SharedRemoteSubtitleCandidate &&
          candidate.isLikelyMatch) {
        score += 25;
      }
      return score;
    }

    final sorted = List<RemoteSubtitleCandidate>.from(candidates)
      ..sort((a, b) {
        final scoreCompare = scoreCandidate(b).compareTo(scoreCandidate(a));
        if (scoreCompare != 0) return scoreCompare;
        return a.name.compareTo(b.name);
      });

    return sorted.first;
  }

  // 获取语言名称
  String getLanguageName(String language) {
    final mapped = getSubtitleLanguageName(language);
    debugPrint('SubtitleManager: getLanguageName "$language" -> "$mapped"');
    return mapped;
  }

  // 更新指定的字幕轨道信息
  void updateEmbeddedSubtitleTrack(int trackIndex) {
    if (_player.mediaInfo.subtitle == null ||
        trackIndex >= _player.mediaInfo.subtitle!.length) {
      return;
    }

    final playerSubInfo = _player.mediaInfo.subtitle![trackIndex];
    debugPrint(
      'SubtitleManager: updateEmbeddedSubtitleTrack - Called for trackIndex: $trackIndex',
    );
    debugPrint(
      '  - playerSubInfo.title (from Adapter): "${playerSubInfo.title}"',
    );
    debugPrint(
      '  - playerSubInfo.language (from Adapter): "${playerSubInfo.language}"',
    );
    debugPrint(
      '  - playerSubInfo.metadata (from Adapter): ${playerSubInfo.metadata}',
    );

    String originalTitleFromAdapter = playerSubInfo.title ?? '';
    String originalLanguageCodeFromAdapter = playerSubInfo.language ?? '';
    debugPrint(
      '  - Initial originalTitleFromAdapter: "$originalTitleFromAdapter"',
    );
    debugPrint(
      '  - Initial originalLanguageCodeFromAdapter: "$originalLanguageCodeFromAdapter"',
    );

    String displayTitle = originalTitleFromAdapter;
    String determinedLanguage = "未知";
    debugPrint(
      '  - Initial displayTitle: "$displayTitle", determinedLanguage: "$determinedLanguage"',
    );

    // 1. Try to determine language using the language code from adapter first
    if (originalLanguageCodeFromAdapter.isNotEmpty) {
      determinedLanguage = getLanguageName(originalLanguageCodeFromAdapter);
      debugPrint(
        '  - After step 1 (from lang code): determinedLanguage: "$determinedLanguage"',
      );
    }

    // 2. If language code didn't yield a good name (or was empty), try with the title from adapter
    if (determinedLanguage == "未知" ||
        determinedLanguage == originalLanguageCodeFromAdapter) {
      String langFromTitle = getLanguageName(originalTitleFromAdapter);
      debugPrint(
        '  - Step 2 (from title "$originalTitleFromAdapter"): langFromTitle: "$langFromTitle"',
      );
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
      '  - After step 3 (display title construction): displayTitle: "$displayTitle", determinedLanguage: "$determinedLanguage"',
    );

    // Ensure determinedLanguage itself is a "final" friendly name
    String finalDeterminedLanguage = getLanguageName(determinedLanguage);
    if (finalDeterminedLanguage != determinedLanguage) {
      determinedLanguage = finalDeterminedLanguage;
    }
    debugPrint(
      '  - After final determinedLanguage refinement: determinedLanguage: "$determinedLanguage"',
    );

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
      '  - After displayTitle/determinedLanguage final fallbacks: displayTitle: "$displayTitle", determinedLanguage: "$determinedLanguage"',
    );

    debugPrint(
      'SubtitleManager: updateEmbeddedSubtitleTrack - FINAL values before updateSubtitleTrackInfo for trackIndex $trackIndex:',
    );
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
          playerSubInfo.metadata['language'] ?? originalLanguageCodeFromAdapter,
    });

    // 清除外部字幕信息的激活状态
    if (_currentExternalSubtitlePath == null &&
        _player.activeSubtitleTracks.contains(trackIndex) &&
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
    if (_player.activeSubtitleTracks.isNotEmpty &&
        _currentExternalSubtitlePath == null) {
      final activeIndex = _player.activeSubtitleTracks.first;
      if (activeIndex >= 0 &&
          activeIndex < _player.mediaInfo.subtitle!.length) {
        // 激活的是内嵌字幕轨道
        updateSubtitleTrackInfo('embedded_subtitle', {
          'index': activeIndex,
          'title': _player.mediaInfo.subtitle![activeIndex].toString(),
          'isActive': true,
        });

        // 通知字幕轨道变化
        onSubtitleTrackChanged();
      }
    }

    notifyListeners();
  }
}
