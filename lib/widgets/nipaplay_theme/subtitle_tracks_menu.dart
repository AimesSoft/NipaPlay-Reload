import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'base_settings_menu.dart';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'blur_button.dart';
import 'package:file_selector/file_selector.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:flutter/foundation.dart';

class SubtitleTracksMenu extends StatefulWidget {
  final VoidCallback onClose;

  const SubtitleTracksMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<SubtitleTracksMenu> createState() => _SubtitleTracksMenuState();
}

class _SubtitleTracksMenuState extends State<SubtitleTracksMenu> {
  // 存储外部字幕信息的列表
  List<Map<String, dynamic>> _externalSubtitles = [];
  bool _isLoading = false;
  VideoPlayerState? _videoPlayerState; // Add this member variable
  
  @override
  void initState() {
    super.initState();
    _loadExternalSubtitles();
    
    // 设置自动加载字幕的回调
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return; // Add mounted check
      _videoPlayerState = Provider.of<VideoPlayerState>(context, listen: false); // Assign here
      _videoPlayerState!.onExternalSubtitleAutoLoaded = _handleAutoLoadedSubtitle;
      
      // 检查当前是否有激活的外部字幕
      _checkCurrentExternalSubtitle(_videoPlayerState!);
    });
  }
  
  @override
  void dispose() {
    // 清除回调
    // Use the stored _videoPlayerState to clear the callback
    _videoPlayerState?.onExternalSubtitleAutoLoaded = null;
    super.dispose();
  }
  
  // 从SharedPreferences加载已保存的外部字幕信息
  Future<void> _loadExternalSubtitles() async {
    if (kIsWeb) {
      setState(() => _isLoading = false);
      return;
    }
    if (!mounted) return; // Add mounted check
    setState(() => _isLoading = true);
    
    try {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      if (videoState.currentVideoPath == null) {
        if (mounted) setState(() => _isLoading = false); // Add mounted check
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final videoHashKey = _getVideoHashKey(videoState.currentVideoPath!);
      final subtitlesJson = prefs.getString('external_subtitles_$videoHashKey');
      
      if (subtitlesJson != null) {
        final List<dynamic> decoded = json.decode(subtitlesJson);
        _externalSubtitles = decoded.map((item) => Map<String, dynamic>.from(item)).toList();
        
        // 自动加载上次使用的外部字幕
        final lastActiveIndex = prefs.getInt('last_active_subtitle_$videoHashKey');
        if (lastActiveIndex != null && lastActiveIndex >= 0) {
          if (lastActiveIndex < _externalSubtitles.length) {
            final subtitleInfo = _externalSubtitles[lastActiveIndex];
            final path = subtitleInfo['path'] as String;
            if (File(path).existsSync()) {
              // 延迟加载，避免初始化冲突
              Future.delayed(const Duration(milliseconds: 500), () {
                if (!mounted) return; // Add mounted check
                _applyExternalSubtitle(path, lastActiveIndex);
              });
            }
          }
        }
      }
    } catch (e) {
      // print('加载外部字幕失败: $e');
      debugPrint('加载外部字幕失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false); // Add mounted check
    }
  }
  
  // 计算视频文件的唯一标识
  String _getVideoHashKey(String videoPath) {
    if (kIsWeb) return p.basename(videoPath);
    // 使用文件路径和大小作为标识
    final file = File(videoPath);
    if (file.existsSync()) {
      final size = file.lengthSync();
      final name = p.basename(videoPath);
      return '$name-$size';
    }
    return p.basename(videoPath);
  }
  
  // 保存外部字幕信息到SharedPreferences
  Future<void> _saveExternalSubtitles(BuildContext context) async {
    if (kIsWeb) return;
    try {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      if (videoState.currentVideoPath == null) return;
      
      final prefs = await SharedPreferences.getInstance();
      final videoHashKey = _getVideoHashKey(videoState.currentVideoPath!);
      
      await prefs.setString(
        'external_subtitles_$videoHashKey', 
        json.encode(_externalSubtitles)
      );
      
      // 获取当前激活的字幕索引
      final activeTrackIndex = _getActiveExternalSubtitleIndex();
      if (activeTrackIndex >= 0) {
        await prefs.setInt('last_active_subtitle_$videoHashKey', activeTrackIndex);
      }
    } catch (e) {
      // print('保存外部字幕失败: $e');
      debugPrint('保存外部字幕失败: $e');
    }
  }
  
  // 获取当前激活的外部字幕索引
  int _getActiveExternalSubtitleIndex() {
    // 检查哪个外部字幕是激活的
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    
    // 如果没有激活的字幕轨道，返回-1
    if (videoState.player.activeSubtitleTracks.isEmpty) {
      return -1;
    }
    
    // 检查当前激活的字幕是否是外部字幕
    for (int i = 0; i < _externalSubtitles.length; i++) {
      // 如果当前有激活的字幕轨道，并且是索引0（外部字幕总是索引0）
      if (videoState.player.activeSubtitleTracks.contains(0)) {
        final currentPath = _externalSubtitles[i]['path'];
        // 检查这个字幕是否已经被加载
        if (_externalSubtitles[i]['isActive'] == true) {
          return i;
        }
      }
    }
    
    return -1;
  }
  
  // 加载外部字幕文件
  Future<void> _loadExternalSubtitle(BuildContext context) async {
    if (kIsWeb) {
      BlurSnackBar.show(context, 'Web平台不支持加载本地字幕文件');
      return;
    }
    try {
      setState(() => _isLoading = true);
      
      // 使用FilePickerService选择字幕文件
      final filePickerService = FilePickerService();
      final filePath = await filePickerService.pickSubtitleFile();

      if (filePath == null) {
        setState(() => _isLoading = false);
        return;
      }
      
      final fileName = p.basename(filePath);
      
      // 检查是否是有效的字幕文件
      if (!filePath.toLowerCase().endsWith('.srt') && 
          !filePath.toLowerCase().endsWith('.ass') && 
          !filePath.toLowerCase().endsWith('.ssa') &&
          !filePath.toLowerCase().endsWith('.sub')) {
        if (context.mounted) {
          BlurSnackBar.show(context, '不支持的字幕格式，请选择 .srt, .ass, .ssa 或 .sub 文件');
          setState(() => _isLoading = false);
        }
        return;
      }
      
      // 检查是否已经添加过相同路径的字幕
      final existingIndex = _externalSubtitles.indexWhere((s) => s['path'] == filePath);
      if (existingIndex >= 0) {
        // 已存在，直接应用这个字幕
        _applyExternalSubtitle(filePath, existingIndex);
        if (context.mounted) {
          BlurSnackBar.show(context, '已切换到字幕: $fileName');
        }
        setState(() => _isLoading = false);
        return;
      }

      // 创建新的字幕信息
      final subtitleInfo = {
        'path': filePath,
        'name': fileName,
        'type': p.extension(filePath).toLowerCase().substring(1),
        'addTime': DateTime.now().millisecondsSinceEpoch,
        'isActive': false
      };
      
      // 添加到列表
      setState(() {
        _externalSubtitles.add(subtitleInfo);
        _isLoading = false;
      });
      
      // 应用这个字幕
      _applyExternalSubtitle(filePath, _externalSubtitles.length - 1);
      
      // 保存字幕列表
      if (context.mounted) {
        await _saveExternalSubtitles(context);
        BlurSnackBar.show(context, '已加载字幕文件: $fileName');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (context.mounted) {
        BlurSnackBar.show(context, '加载字幕文件失败: $e');
      }
    }
  }
  
  // 应用外部字幕
  void _applyExternalSubtitle(String filePath, int index) {
    try {
      if (!mounted) return; // Add mounted check
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      
      // 将所有字幕设为非激活
      for (var subtitle in _externalSubtitles) {
        subtitle['isActive'] = false;
      }
      
      // 设置当前字幕为激活
      if (index >= 0 && index < _externalSubtitles.length) {
        _externalSubtitles[index]['isActive'] = true;
      }
      
      // 使用强制设置外部字幕的方法，确保它会被标记为手动设置，优先于内嵌字幕
      videoState.forceSetExternalSubtitle(filePath);
      
      if (mounted) setState(() {}); // Add mounted check
    } catch (e) {
      // print('应用外部字幕失败: $e');
      debugPrint('应用外部字幕失败: $e');
    }
  }
  
  // 切换到内嵌字幕
  Future<void> _switchToEmbeddedSubtitle(BuildContext context, int trackIndex) async {
    try {
      if (!mounted) return; // Add mounted check
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      
      // 禁用外部字幕 (如果之前有外部字幕激活)
      // This ensures that if an external subtitle was active, turning on an embedded one
      // correctly signals that the external one is no longer the primary.
      // The player adapter and subtitle manager should handle the state changes.
      videoState.setExternalSubtitle(""); // Clears external subtitle path in manager
      
      // 将所有外部字幕设为非激活 (UI state for external subtitles list)
      for (var subtitle in _externalSubtitles) {
        subtitle['isActive'] = false;
      }
      
      // 如果指定了轨道索引，切换到该内嵌字幕
      if (trackIndex >= 0) {
        // 核心：告诉播放器切换到指定的内嵌字幕轨道索引
        // Note: `activeSubtitleTracks` in `MediaKitPlayerAdapter` expects an index
        // that corresponds to its `_mediaInfo.subtitle` list.
        videoState.player.activeSubtitleTracks = [trackIndex];
        debugPrint('_SubtitleTracksMenu: Switched to embedded subtitle, player instructed with mediaInfo index: $trackIndex');

        // 不需要在此处手动更新SubtitleManager的title/language或调用updateDanmakuTrackInfo。
        // MediaKitPlayerAdapter监听到播放器轨道变化后，会更新其_mediaInfo，
        // 进而触发SubtitleManager通过Player实例的mediaInfo更新其_subtitleTrackInfo。
        // UI应该响应SubtitleManager通过ChangeNotifier发出的更新。

      } else {
        // 关闭字幕 (trackIndex is -1 or invalid)
        videoState.player.activeSubtitleTracks = []; // Tell player to use "no" subtitle
        debugPrint('_SubtitleTracksMenu: Turned off subtitles, player instructed.');
        
        // 清除所有字幕轨道信息 (这部分可能需要审视，是否真的需要清除所有"Danmaku"信息)
        // videoState.clearDanmakuTrackInfo(); // Commenting out for now, as it might be too broad.
        
        // 明确清除外部字幕的手动设置标记 (这应该由SubtitleManager内部逻辑处理)
        // videoState.updateDanmakuTrackInfo('external_subtitle', {
        //   'isActive': false,
        //   'isManualSet': false
        // });
      }
      
      if (mounted) setState(() {}); // UI update for external list, and potentially for embedded list selection state
      
      // 保存设置 (主要是保存外部字幕列表的状态，例如哪个是激活的)
      if (context.mounted) { // Re-check mounted as it's an async gap
        await _saveExternalSubtitles(context);
      }
      
      // 通知字幕轨道变化 (This might be redundant if player events drive everything)
      // videoState.onSubtitleTrackChanged(); // Commenting out for now
    } catch (e) {
      // print('切换到内嵌字幕失败: $e');
      debugPrint('_SubtitleTracksMenu: Error switching to embedded subtitle: $e');
    }
  }
  
  // 获取字幕轨道的语言名称
  String _getLanguageName(String language) {
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
      r'chi|chs|zh|中文|简体|繁体|chi.*?simplified|chinese': '中文',
      r'eng|en|英文|english': '英文',
      r'jpn|ja|日文|japanese': '日语',
      r'kor|ko|韩文|korean': '韩语',
      r'fra|fr|法文|french': '法语',
      r'ger|de|德文|german': '德语',
      r'spa|es|西班牙文|spanish': '西班牙语',
      r'ita|it|意大利文|italian': '意大利语',
      r'rus|ru|俄文|russian': '俄语',
    };

    // 首先检查语言代码映射
    final mappedLanguage = languageCodes[language.toLowerCase()];
    if (mappedLanguage != null) {
      return mappedLanguage;
    }

    // 然后检查语言标识符
    for (final entry in languagePatterns.entries) {
      final pattern = RegExp(entry.key, caseSensitive: false);
      if (pattern.hasMatch(language.toLowerCase())) {
        return entry.value;
      }
    }

    return language;
  }
  
  // 删除外部字幕
  Future<void> _removeExternalSubtitle(BuildContext context, int index) async {
    if (index < 0 || index >= _externalSubtitles.length) return;
    
    final subtitleInfo = _externalSubtitles[index];
    final fileName = subtitleInfo['name'];
    
    // 如果当前字幕是激活的，先切换回内嵌字幕
    if (subtitleInfo['isActive'] == true) {
      await _switchToEmbeddedSubtitle(context, -1);
    }
    
    // 从列表中移除
    setState(() {
      _externalSubtitles.removeAt(index);
    });
    
    // 保存更新后的列表
    if (context.mounted) {
      await _saveExternalSubtitles(context);
      BlurSnackBar.show(context, '已移除字幕: $fileName');
    }
  }

  // 处理自动加载的字幕
  void _handleAutoLoadedSubtitle(String path, String fileName) {
    // 检查是否已经添加过相同路径的字幕
    final existingIndex = _externalSubtitles.indexWhere((s) => s['path'] == path);
    if (existingIndex >= 0) {
      // 已存在，直接更新激活状态
      if (!mounted) return; // Add mounted check
      setState(() {
        for (var subtitle in _externalSubtitles) {
          subtitle['isActive'] = false;
        }
        _externalSubtitles[existingIndex]['isActive'] = true;
      });
      return;
    }

    // 创建新的字幕信息
    final subtitleInfo = {
      'path': path,
      'name': fileName,
      'type': p.extension(path).toLowerCase().substring(1),
      'addTime': DateTime.now().millisecondsSinceEpoch,
      'isActive': true
    };
    
    // 添加到列表并更新UI
    if (!mounted) return; // Add mounted check
    setState(() {
      // 将所有字幕设为非激活
      for (var subtitle in _externalSubtitles) {
        subtitle['isActive'] = false;
      }
      _externalSubtitles.add(subtitleInfo);
    });
    
    // 保存字幕列表
    if (context.mounted) { // Re-check mounted as it's an async gap
      _saveExternalSubtitles(context);
    }
  }
  
  // 检查当前是否有激活的外部字幕
  void _checkCurrentExternalSubtitle(VideoPlayerState videoState) {
    // 获取当前外部字幕路径
    final currentPath = videoState.getActiveExternalSubtitlePath();
    if (currentPath == null || currentPath.isEmpty) return;
    
    // 检查是否已经在列表中
    final existingIndex = _externalSubtitles.indexWhere((s) => s['path'] == currentPath);
    if (existingIndex >= 0) {
      // 已存在，直接更新激活状态
      setState(() {
        for (var subtitle in _externalSubtitles) {
          subtitle['isActive'] = false;
        }
        _externalSubtitles[existingIndex]['isActive'] = true;
      });
      return;
    }
    
    // 不在列表中，添加到列表
    final fileName = currentPath.split('/').last;
    final subtitleInfo = {
      'path': currentPath,
      'name': fileName,
      'type': p.extension(currentPath).toLowerCase().substring(1),
      'addTime': DateTime.now().millisecondsSinceEpoch,
      'isActive': true
    };
    
    setState(() {
      _externalSubtitles.add(subtitleInfo);
    });
    
    // 保存字幕列表
    if (context.mounted) {
      _saveExternalSubtitles(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        // Access SubtitleManager through VideoPlayerState
        final subtitleManager = videoState.subtitleManager;
        
        // `videoState.player.mediaInfo.subtitle` contains the raw PlayerSubtitleStreamInfo list from the adapter.
        // We iterate this list to get the number of tracks and their original indices.
        final embeddedSubtitleTracksFromPlayer = videoState.player.mediaInfo.subtitle;
        final hasEmbeddedSubtitles = embeddedSubtitleTracksFromPlayer != null && 
                                    embeddedSubtitleTracksFromPlayer.isNotEmpty;
        // For debugging: Print all known tracks in SubtitleManager
        // subtitleManager.subtitleTrackInfo.forEach((key, value) {
        //   debugPrint('_SubtitleTracksMenu: SubtitleManager track cache for key "$key": title="${value['title']}", lang="${value['language']}"');
        // });
        
        return BaseSettingsMenu(
          title: '字幕轨道',
          onClose: widget.onClose,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 添加加载本地字幕文件的按钮
              if (!kIsWeb) ...[
                _isLoading 
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    )
                  : BlurButton(
                      icon: Icons.add_circle_outline,
                      text: "加载本地字幕文件",
                      onTap: () => _loadExternalSubtitle(context),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      margin: const EdgeInsets.symmetric(horizontal: 0),
                      expandHorizontally: true,
                      borderRadius: BorderRadius.zero,
                    ),
                const SizedBox(height: 16),
              ],
              
              // 外部字幕列表
              if (_externalSubtitles.isNotEmpty) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 16, bottom: 8),
                    child: Text(
                      '外部字幕',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                ..._externalSubtitles.asMap().entries.map((entry) {
                  final index = entry.key;
                  final subtitle = entry.value;
                  final isActive = subtitle['isActive'] == true;
                  final fileName = subtitle['name'] as String;
                  final fileType = subtitle['type'] as String;
                  
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (isActive) {
                          _switchToEmbeddedSubtitle(context, -1);
                          BlurSnackBar.show(context, '已关闭字幕');
                        } else {
                          final filePath = subtitle['path'] as String;
                          _applyExternalSubtitle(filePath, index);
                          BlurSnackBar.show(context, '已切换到字幕: $fileName');
                          _saveExternalSubtitles(context);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.white.withOpacity(0.1) : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.white.withOpacity(0.5),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isActive ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fileName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '类型: ${fileType.toUpperCase()}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.white, size: 18),
                              onPressed: () => _removeExternalSubtitle(context, index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              //tooltip: '移除',
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],
              
              // 内嵌字幕列表
              if (hasEmbeddedSubtitles) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 16, bottom: 8),
                    child: Text(
                      '内嵌字幕',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // Use embeddedSubtitleTracksFromPlayer for iteration count and original index
                ...embeddedSubtitleTracksFromPlayer.asMap().entries.map((entry) {
                  final index = entry.key; // This is the original index from player.mediaInfo.subtitle
                  // final track = entry.value; // This is PlayerSubtitleStreamInfo, we don't need to parse it here.
                  
                  // Determine if this track is active.
                  // Active state is based on player's active tracks and no external subtitle being active.
                  final bool hasActiveExternal = _externalSubtitles.any((s) => s['isActive'] == true);
                  final isActive = !hasActiveExternal && videoState.player.activeSubtitleTracks.contains(index);
                  
                  // --- Get Title and Language from SubtitleManager ---
                  // The key in subtitleManager.subtitleTrackInfo should match how SubtitleManager stores it.
                  // SubtitleManager.updateEmbeddedSubtitleTrack uses 'embedded_subtitle_$trackIndex'
                  final String managerTrackKey = 'embedded_subtitle_$index';
                  final Map<String, dynamic>? trackDataFromManager = subtitleManager.subtitleTrackInfo[managerTrackKey];
                  
                  String title = '轨道 ${index + 1}'; // Fallback title
                  String language = '未知';    // Fallback language

                  if (trackDataFromManager != null) {
                    title = trackDataFromManager['title'] as String? ?? title;
                    language = trackDataFromManager['language'] as String? ?? language;
                    // debugPrint('_SubtitleTracksMenu: For embedded track index $index (key: $managerTrackKey): Using title="$title", language="$language" FROM SubtitleManager.');
                  } else {
                    // This case means SubtitleManager doesn't have info for this track index yet, or an issue with keys.
                    // This can happen if SubtitleManager hasn't processed updates from the adapter yet.
                    // The UI should reactively update when SubtitleManager notifies its listeners.
                    // debugPrint('_SubtitleTracksMenu: For embedded track index $index (key: $managerTrackKey): No data in SubtitleManager. Using fallbacks: title="$title", language="$language".');
                  }
                  // --- End Get Title and Language ---
                  
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (isActive) {
                          // 关闭字幕
                          videoState.player.activeSubtitleTracks = [];
                          BlurSnackBar.show(context, '已关闭字幕');
                        } else {
                          // 先确保禁用外部字幕
                          _switchToEmbeddedSubtitle(context, index);
                          BlurSnackBar.show(context, '已切换到字幕: $title');
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.white.withOpacity(0.5),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isActive ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title, // Display title from SubtitleManager (or fallback)
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    '语言: $language', // Display language from SubtitleManager (or fallback)
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
              
              // 没有字幕的情况
              if (!hasEmbeddedSubtitles && _externalSubtitles.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    '当前视频没有可用的字幕轨道。\n您可以通过"加载本地字幕文件"按钮添加外部字幕。',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
} 