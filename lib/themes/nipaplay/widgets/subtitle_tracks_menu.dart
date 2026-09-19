import 'package:flutter/material.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/player_event_log.dart';
import 'package:provider/provider.dart';
import 'base_settings_menu.dart';
import 'player_menu_theme.dart';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'blur_button.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/remote_subtitle_service.dart';
import 'package:nipaplay/utils/subtitle_file_utils.dart';
import 'package:nipaplay/utils/subtitle_language_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/services/emby_player_menu_selection.dart';

class SubtitleTracksMenu extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<bool>? onHoverChanged;

  const SubtitleTracksMenu({
    super.key,
    required this.onClose,
    this.onHoverChanged,
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
      _videoPlayerState =
          Provider.of<VideoPlayerState>(context, listen: false); // Assign here
      _videoPlayerState!.onExternalSubtitleAutoLoaded =
          _handleAutoLoadedSubtitle;

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
        _externalSubtitles =
            decoded.map((item) => Map<String, dynamic>.from(item)).toList();
        // 清理旧缓存残留：hash 文件名时代保存的路径（95042d....srt 等）
        // 文件已不存在，过滤掉避免轨道列表出现不明字幕。
        final staleCount = _externalSubtitles.length;
        _externalSubtitles.removeWhere((s) {
          final path = s['path'] as String?;
          return path == null ||
              path.isEmpty ||
              !File(path).existsSync();
        });
        if (_externalSubtitles.length != staleCount) {
          await _saveExternalSubtitles(videoState.currentVideoPath ?? '');
        }
      }

      // 合并当前已激活的外部字幕：自动加载挂载的不在持久化列表里，
      // 不合并的话轨道列表看不到自动加载的 ass/srt（"没自动加载到字幕轨道"）。
      for (final path in videoState.activeExternalSubtitlePaths) {
        if (_externalSubtitles.any((s) => s['path'] == path)) continue;
        _externalSubtitles.add(<String, dynamic>{
          'path': path,
          'name': p.basename(path),
          'type': p.extension(path).replaceAll('.', ''),
          'addTime': DateTime.now().millisecondsSinceEpoch,
          'isActive': true,
        });
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
    return sha1.convert(utf8.encode(videoPath)).toString();
  }

  // 保存外部字幕信息到SharedPreferences。
  // videoPath 由调用方显式传入：iPad 大屏模式下菜单面板可能已随弹窗页面
  // 路由卸载，挂载流程的持久化不能依赖 Provider.of(context)（否则面板
  // 卸载时保存被跳过，字幕轨道列表读到空——"挂载成功但列表空"的根因）。
  Future<void> _saveExternalSubtitles(String videoPath) async {
    if (kIsWeb || videoPath.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final videoHashKey = _getVideoHashKey(videoPath);

      await prefs.setString(
          'external_subtitles_$videoHashKey', json.encode(_externalSubtitles));

      // 直写 prefs 绕过了 SubtitleService 的内存缓存，失效它保证
      // Cupertino 面板下次读取到最新列表（避免陈旧列表/按索引删错）。
      SubtitleService().clearCache(videoPath);

      // 获取当前激活的字幕索引
      final activeTrackIndex = _getActiveExternalSubtitleIndex();
      if (activeTrackIndex >= 0) {
        await prefs.setInt(
            'last_active_subtitle_$videoHashKey', activeTrackIndex);
      }
    } catch (e) {
      debugPrint('保存外部字幕失败: $e');
    }
  }

  // 获取当前激活的外部字幕索引
  int _getActiveExternalSubtitleIndex() {
    return _externalSubtitles.indexWhere((s) => s['isActive'] == true);
  }

  // 加载外部字幕文件
  Future<void> _loadExternalSubtitle(BuildContext context) async {
    if (kIsWeb) {
      BlurSnackBar.show(context, 'Web平台不支持加载本地字幕文件');
      return;
    }
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    try {
      if (mounted) {
        setState(() => _isLoading = true);
      }

      // 使用FilePickerService选择字幕文件
      final filePickerService = FilePickerService();
      final filePath = await filePickerService.pickSubtitleFile();

      if (filePath == null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final fileName = p.basename(filePath);

      // 检查是否是有效的字幕文件
      final extension = p.extension(filePath).toLowerCase();
      if (!supportedSubtitleExtensions.contains(extension)) {
        if (context.mounted) {
          BlurSnackBar.show(
              context, '不支持的字幕格式，请选择 .srt, .ass, .ssa, .sub 或 .sup 文件');
          setState(() => _isLoading = false);
        }
        return;
      }

      // 检查是否已经添加过相同路径的字幕
      final existingIndex =
          _externalSubtitles.indexWhere((s) => s['path'] == filePath);
      if (existingIndex >= 0) {
        // 已存在，直接应用这个字幕
        _applyExternalSubtitle(videoState, filePath, existingIndex);
        if (mounted && context.mounted) {
          BlurSnackBar.show(context, '已切换到字幕: $fileName');
        }
        if (mounted) {
          setState(() => _isLoading = false);
        }
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
      _externalSubtitles.add(subtitleInfo);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      // 应用这个字幕
      _applyExternalSubtitle(
        videoState,
        filePath,
        _externalSubtitles.length - 1,
      );

      // 保存字幕列表
      await _saveExternalSubtitles(videoState.currentVideoPath ?? '');
      if (mounted && context.mounted) {
        BlurSnackBar.show(context, '已加载字幕文件: $fileName');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      if (mounted && context.mounted) {
        BlurSnackBar.show(context, '加载字幕文件失败: $e');
      }
    }
  }

  Future<void> _loadRemoteSubtitle(BuildContext context) async {
    if (kIsWeb) {
      BlurSnackBar.show(context, 'Web平台不支持加载远程字幕');
      return;
    }

    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    final videoPath = videoState.currentVideoPath;
    if (videoPath == null || videoPath.isEmpty) {
      BlurSnackBar.show(context, '没有正在播放的视频文件');
      return;
    }

    try {
      if (mounted) setState(() => _isLoading = true);

      final candidates = await RemoteSubtitleService.instance
          .listCandidatesForVideo(videoPath);
      if (mounted) setState(() => _isLoading = false);

      if (candidates.isEmpty) {
        if (context.mounted) {
          BlurSnackBar.show(context, '当前远程目录未找到字幕文件');
        }
        return;
      }

      // 多选远程字幕（支持一次挂载多个 SRT）
      final checked = <RemoteSubtitleCandidate>{};
      final selected = await BlurDialog.show<List<RemoteSubtitleCandidate>>(
        context: context,
        title: '选择远程字幕（可多选）',
        contentWidget: StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(dialogContext).size.height * 0.6,
                maxWidth: 520,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final candidate = candidates[index];
                        return CheckboxListTile(
                          value: checked.contains(candidate),
                          title: Text(candidate.name),
                          subtitle: Text(candidate.sourceLabel),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (bool? value) {
                            setDialogState(() {
                              if (value == true) {
                                checked.add(candidate);
                              } else {
                                checked.remove(candidate);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      HoverScaleTextButton(
                        child: const Text('取消'),
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(null),
                      ),
                      const SizedBox(width: 8),
                      HoverScaleTextButton(
                        child: const Text('挂载选中'),
                        onPressed: () {
                          final list = checked.toList();
                          Navigator.of(dialogContext)
                              .pop(list.isEmpty ? null : list);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );

      if (selected == null || selected.isEmpty) {
        debugPrint('[SubtitleMenu] selected empty');
        logPlayerEvent(
          'Subtitle',
          '远程字幕挂载取消：未选择任何字幕（selected=${selected?.length ?? 'null'}）',
          level: 'WARN',
        );
        return;
      }

      logPlayerEvent(
        'Subtitle',
        '远程字幕挂载开始: 已选 ${selected.length} 个 '
        '(${selected.map((c) => c.name).join(', ')})',
      );

      // 注意：iPad 大屏模式下选择弹窗是全屏页面路由，弹窗关闭时菜单面板
      // 可能已被卸载。挂载流程必须继续执行到底（只操作 videoState 与持久化），
      // 所有 UI 操作（setState/SnackBar）按 mounted 逐点保护。
      if (mounted) setState(() => _isLoading = true);
      var loadedCount = 0;
      var lastIndex = -1;
      for (final candidate in selected) {
        final cachedPath = await RemoteSubtitleService.instance
            .ensureSubtitleCached(candidate);
        final existingIndex =
            _externalSubtitles.indexWhere((s) => s['path'] == cachedPath);
        if (existingIndex >= 0) {
          // 列表已存在（可能由自动检测加入但未真正挂载/或曾被删除标记）：
          // 重新挂载到播放器，而不是跳过——否则「挂载选中」看起来无效果
          lastIndex = existingIndex;
          loadedCount++;
          await _remountExternalSubtitle(videoState, existingIndex);
          continue;
        }
        final subtitleInfo = <String, dynamic>{
          'path': cachedPath,
          'name': candidate.name,
          'type': candidate.extension.substring(1),
          'addTime': DateTime.now().millisecondsSinceEpoch,
          'isActive': false,
          'remoteSource': candidate.sourceLabel,
          if (candidate is WebDavRemoteSubtitleCandidate) ...{
            'remoteType': 'webdav',
            'remoteConn': candidate.connection.name,
            'remotePath': candidate.remotePath,
          },
          if (candidate is SmbRemoteSubtitleCandidate) ...{
            'remoteType': 'smb',
            'remoteConn': candidate.connection.name,
            'remotePath': candidate.smbPath,
          },
        };
        _externalSubtitles.add(subtitleInfo);
        if (mounted) setState(() {});
        lastIndex = _externalSubtitles.length - 1;
        loadedCount++;
      }
      // 多挂：本次选中的全部叠加激活（ASS/SRT 同等对待，逐条进栈），
      // 不再对 ASS 单独 forceSet（那会清空整个叠层栈，导致先挂的字幕消失）
      for (final candidate in selected) {
        final cached = await RemoteSubtitleService.instance
            .ensureSubtitleCached(candidate);
        await videoState.addExternalSubtitleToStack(cached,
            displayName: candidate.name);
        final idx =
            _externalSubtitles.indexWhere((s) => s['path'] == cached);
        if (idx >= 0) _externalSubtitles[idx]['isActive'] = true;
      }
      if (mounted) setState(() {});
      logPlayerEvent(
        'Subtitle',
        '远程字幕挂载完成: $loadedCount 个，已应用叠层/内核轨',
      );
      // 持久化不依赖面板存活（iPad 大屏模式下面板可能已卸载）。
      await _saveExternalSubtitles(videoPath);
      if (mounted && context.mounted) {
        BlurSnackBar.show(context, '已加载 $loadedCount 个字幕');
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      logPlayerEvent('Subtitle', '远程字幕挂载失败: $e', level: 'ERROR');
      if (context.mounted) {
        BlurSnackBar.show(context, '加载远程字幕失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 重新挂载列表已有条目（existingIndex 分支使用）：
  // SRT/VTT 走叠层叠加挂载，其余走内核轨单挂，保证「挂载选中」对已有字幕也生效。
  // videoState 由调用方传入：菜单面板卸载后 Provider.of 会抛错，挂载不能依赖它。
  Future<void> _remountExternalSubtitle(
    VideoPlayerState videoState,
    int index,
  ) async {
    if (index < 0 || index >= _externalSubtitles.length) return;
    final subPath = _externalSubtitles[index]['path'] as String?;
    if (subPath == null || subPath.isEmpty) return;
    await videoState.addExternalSubtitleToStack(subPath);
    _externalSubtitles[index]['isActive'] = true;
    if (mounted) setState(() {});
  }

  // 应用外部字幕
  void _applyExternalSubtitle(
    VideoPlayerState videoState,
    String filePath,
    int index,
  ) {
    try {
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
  Future<bool> _switchToEmbeddedSubtitle(
    BuildContext context,
    int trackIndex, {
    bool persistEmbyPreference = true,
  }) async {
    try {
      if (!mounted) return false; // Add mounted check
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      final path = videoState.currentVideoPath ?? '';
      final isEmby = path.startsWith('emby://');
      final source = isEmby ? videoState.embyMediaSourceDescriptor() : null;
      final tracks = videoState.player.mediaInfo.subtitle;
      if (trackIndex >= 0 && (tracks == null || trackIndex >= tracks.length)) {
        return false;
      }
      final preference = trackIndex < 0
          ? const EmbyTrackPreference.disabled()
          : preferenceForEmbyNativeSubtitle(tracks![trackIndex]);

      var didApply = false;
      await runMediaServerMenuSelection(
        MediaServerMenuSurface.nipaplaySubtitle,
        isEmby,
        () async {
          // SRT 走 App 叠层渲染，与内嵌轨道可共存：只清理 ASS/SSA 类外部字幕
          final activeExternal = videoState.getActiveExternalSubtitlePath();
          final activeIsSrt = activeExternal != null &&
              p.extension(activeExternal).toLowerCase() == '.srt';
          if (!activeIsSrt) {
            // 禁用外部字幕 (如果之前有外部 ASS 字幕激活)
            videoState.setExternalSubtitle(
                ""); // Clears external subtitle path in manager

            // 将所有外部字幕设为非激活 (UI state for external subtitles list)
            for (var subtitle in _externalSubtitles) {
              subtitle['isActive'] = false;
            }
          }

          // 如果指定了轨道索引，切换到该内嵌字幕
          if (trackIndex >= 0) {
            // 核心：告诉播放器切换到指定的内嵌字幕轨道索引
            // Note: `activeSubtitleTracks` in `MediaKitPlayerAdapter` expects an index
            // that corresponds to its `_mediaInfo.subtitle` list.
            videoState.player.activeSubtitleTracks = [trackIndex];
            debugPrint(
                '_SubtitleTracksMenu: Switched to embedded subtitle, player instructed with mediaInfo index: $trackIndex');

            // 不需要在此处手动更新SubtitleManager的title/language或调用updateDanmakuTrackInfo。
            // MediaKitPlayerAdapter监听到播放器轨道变化后，会更新其_mediaInfo，
            // 进而触发SubtitleManager通过Player实例的mediaInfo更新其_subtitleTrackInfo。
            // UI应该响应SubtitleManager通过ChangeNotifier发出的更新。
          } else {
            // 关闭字幕 (trackIndex is -1 or invalid)
            videoState.player.activeSubtitleTracks =
                []; // Tell player to use "no" subtitle
            debugPrint(
                '_SubtitleTracksMenu: Turned off subtitles, player instructed.');

            // 清除所有字幕轨道信息 (这部分可能需要审视，是否真的需要清除所有"Danmaku"信息)
            // videoState.clearDanmakuTrackInfo(); // Commenting out for now, as it might be too broad.

            // 明确清除外部字幕的手动设置标记 (这应该由SubtitleManager内部逻辑处理)
            // videoState.updateDanmakuTrackInfo('external_subtitle', {
            //   'isActive': false,
            //   'isManualSet': false
            // });
          }

          if (mounted) {
            setState(
                () {}); // UI update for external list, and potentially for embedded list selection state
          }

          // 保存设置 (主要是保存外部字幕列表的状态，例如哪个是激活的)
          await _saveExternalSubtitles(videoState.currentVideoPath ?? '');
          didApply = true;

          // 通知字幕轨道变化 (This might be redundant if player events drive everything)
        },
        () async {
          if (!persistEmbyPreference || source == null) return false;
          return videoState.persistCurrentEmbyManualPatch(
            EmbyManualSelectionPatch(subtitle: preference),
            currentSource: source,
          );
        },
      );
      return didApply;

      // videoState.onSubtitleTrackChanged(); // Commenting out for now
    } catch (e) {
      // print('切换到内嵌字幕失败: $e');
      debugPrint(
          '_SubtitleTracksMenu: Error switching to embedded subtitle: $e');
      return false;
    }
  }

  // 删除外部字幕
  Future<void> _removeExternalSubtitle(BuildContext context, int index) async {
    if (index < 0 || index >= _externalSubtitles.length) return;

    final subtitleInfo = _externalSubtitles[index];
    final fileName = subtitleInfo['name'];
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);

    // 如果当前字幕是激活的，取消挂载（只卸外部字幕，内嵌轨保持原状；
    // SRT 走叠层不动内嵌，ASS/SSA 才清内核轨）
    if (subtitleInfo['isActive'] == true) {
      final filePath = subtitleInfo['path'] as String;
      await videoState.removeExternalSubtitle(filePath);
      subtitleInfo['isActive'] = false;
    }

    // 从列表中移除
    setState(() {
      _externalSubtitles.removeAt(index);
    });

    // 保存更新后的列表
    await _saveExternalSubtitles(videoState.currentVideoPath ?? '');
    if (context.mounted) {
      BlurSnackBar.show(context, '已移除字幕: $fileName');
    }
  }

  // 处理自动加载的字幕
  void _handleAutoLoadedSubtitle(String path, String fileName) {
    // 检查是否已经添加过相同路径的字幕
    final existingIndex =
        _externalSubtitles.indexWhere((s) => s['path'] == path);
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
    if (context.mounted) {
      final videoPath = Provider.of<VideoPlayerState>(context, listen: false)
              .currentVideoPath ??
          '';
      // 该函数为 void 回调,与原实现一致采用 fire-and-forget
      _saveExternalSubtitles(videoPath);
    }
  }

  // 检查当前是否有激活的外部字幕
  void _checkCurrentExternalSubtitle(VideoPlayerState videoState) {
    // 获取当前外部字幕路径
    final currentPath = videoState.getActiveExternalSubtitlePath();
    if (currentPath == null || currentPath.isEmpty) return;

    // 检查是否已经在列表中
    final existingIndex =
        _externalSubtitles.indexWhere((s) => s['path'] == currentPath);
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
    _saveExternalSubtitles(videoState.currentVideoPath ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final menuColors = PlayerMenuTheme.colorsOf(context);
        // Access SubtitleManager through VideoPlayerState
        final subtitleManager = videoState.subtitleManager;

        // `videoState.player.mediaInfo.subtitle` contains the raw PlayerSubtitleStreamInfo list from the adapter.
        // We iterate this list to get the number of tracks and their original indices.
        final embeddedSubtitleTracksFromPlayer =
            videoState.player.mediaInfo.subtitle;
        final hasEmbeddedSubtitles = embeddedSubtitleTracksFromPlayer != null &&
            embeddedSubtitleTracksFromPlayer.isNotEmpty;
        // For debugging: Print all known tracks in SubtitleManager
        // subtitleManager.subtitleTrackInfo.forEach((key, value) {
        //   debugPrint('_SubtitleTracksMenu: SubtitleManager track cache for key "$key": title="${value['title']}", lang="${value['language']}"');
        // });

        return BaseSettingsMenu(
          title: '字幕轨道',
          onClose: widget.onClose,
          onHoverChanged: widget.onHoverChanged,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 添加加载本地字幕文件的按钮
              if (!kIsWeb) ...[
                _isLoading
                    ? Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                menuColors.accent),
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          BlurButton(
                            icon: Icons.add_circle_outline,
                            text: "加载本地字幕文件",
                            onTap: () => _loadExternalSubtitle(context),
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                            margin: const EdgeInsets.symmetric(horizontal: 0),
                            expandHorizontally: true,
                            borderRadius: BorderRadius.zero,
                          ),
                          if (videoState.currentVideoPath != null &&
                              RemoteSubtitleService.instance
                                  .isPotentialRemoteVideoPath(
                                      videoState.currentVideoPath!)) ...[
                            const SizedBox(height: 8),
                            BlurButton(
                              icon: Icons.cloud_download_outlined,
                              text: "从远程媒体库加载字幕",
                              onTap: () => _loadRemoteSubtitle(context),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 16),
                              margin: const EdgeInsets.symmetric(horizontal: 0),
                              expandHorizontally: true,
                              borderRadius: BorderRadius.zero,
                            ),
                            const SizedBox(height: 8),
                            BlurButton(
                              icon: Icons.cleaning_services_outlined,
                              text: "清除字幕缓存",
                              onTap: () async {
                                await RemoteSubtitleService.instance
                                    .clearSubtitleCache();
                                // 清完重新走自动检测：当前视频字幕立即重新
                                // 下载并挂载（不需要重开视频）。
                                final vp =
                                    videoState.currentVideoPath;
                                if (vp != null && vp.isNotEmpty) {
                                  await videoState.redetectAndLoadSubtitle(vp);
                                }
                                if (context.mounted) {
                                  BlurSnackBar.show(
                                      context, '已清除字幕缓存并重新加载');
                                }
                              },
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 16),
                              margin: const EdgeInsets.symmetric(horizontal: 0),
                              expandHorizontally: true,
                              borderRadius: BorderRadius.zero,
                            ),
                          ],
                        ],
                      ),
                const SizedBox(height: 16),
              ],

              // 外部字幕列表
              if (_externalSubtitles.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 8),
                    child: Text(
                      '外部字幕',
                      locale: Locale("zh-Hans", "zh"),
                      style: TextStyle(
                        color: menuColors.foreground,
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
                      onTap: () async {
                        if (isActive) {
                          // 已激活点击 = 移出叠加（保留在列表，随时可再点激活）
                          final filePath = subtitle['path'] as String;
                          await videoState.removeExternalSubtitle(filePath);
                          setState(() {
                            subtitle['isActive'] = false;
                          });
                          if (context.mounted) {
                            BlurSnackBar.show(context, '已取消该字幕');
                          }
                        } else {
                          final filePath = subtitle['path'] as String;
                          // 多选开关：加入叠加，不影响已激活的其他字幕
                          await videoState.addExternalSubtitleToStack(
                              filePath,
                              displayName: fileName);
                          setState(() {
                            subtitle['isActive'] = true;
                          });
                          if (context.mounted) {
                            BlurSnackBar.show(
                              context,
                              '已叠加字幕: $fileName',
                            );
                          }
                        }
                        // 取消/激活都持久化，否则重开菜单/切后台回来打勾状态回滚
                        await _saveExternalSubtitles(
                            videoState.currentVideoPath ?? '');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? menuColors.selectedBackground
                              : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                              color: menuColors.divider,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isActive
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: isActive
                                  ? menuColors.selectedForeground
                                  : menuColors.foreground,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fileName,
                                    style: TextStyle(
                                      color: isActive
                                          ? menuColors.selectedForeground
                                          : menuColors.foreground,
                                      fontSize: 14,
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  Text(
                                    '类型: ${fileType.toUpperCase()}',
                                    locale: Locale("zh-Hans", "zh"),
                                    style: TextStyle(
                                      color: menuColors.secondaryForeground,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: menuColors.secondaryForeground,
                                size: 18,
                              ),
                              onPressed: () =>
                                  _removeExternalSubtitle(context, index),
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 8),
                    child: Text(
                      '内嵌字幕',
                      locale: Locale("zh-Hans", "zh"),
                      style: TextStyle(
                        color: menuColors.foreground,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // Use embeddedSubtitleTracksFromPlayer for iteration count and original index
                ...embeddedSubtitleTracksFromPlayer
                    .asMap()
                    .entries
                    .map((entry) {
                  final index = entry
                      .key; // This is the original index from player.mediaInfo.subtitle
                  final track = entry.value;

                  // Determine if this track is active.
                  // Active state is based on player's active tracks and no external subtitle being active.
                  final bool hasActiveExternal =
                      _externalSubtitles.any((s) => s['isActive'] == true);
                  // SRT/VTT 走叠层渲染不占内核字幕轨，与内嵌轨可共存：
                  // 只有 ASS/SSA 类（占内核轨的）外部字幕才阻止内嵌轨道勾选。
                  final activeExt = videoState.getActiveExternalSubtitlePath();
                  final blockByExternal = hasActiveExternal &&
                      !(activeExt != null &&
                          (p.extension(activeExt).toLowerCase() == '.srt' ||
                              p.extension(activeExt).toLowerCase() == '.vtt'));
                  final isActive = !blockByExternal &&
                      videoState.player.activeSubtitleTracks.contains(index);

                  // --- Get Title and Language from SubtitleManager ---
                  // The key in subtitleManager.subtitleTrackInfo should match how SubtitleManager stores it.
                  // SubtitleManager.updateEmbeddedSubtitleTrack uses 'embedded_subtitle_$trackIndex'
                  final String managerTrackKey = 'embedded_subtitle_$index';
                  final Map<String, dynamic>? trackDataFromManager =
                      subtitleManager.subtitleTrackInfo[managerTrackKey];

                  String title = track.title?.trim().isNotEmpty == true
                      ? track.title!.trim()
                      : '轨道 ${index + 1}';
                  String language = getSubtitleLanguageName(
                    track.language ?? title,
                  );

                  if (trackDataFromManager != null) {
                    title = trackDataFromManager['title'] as String? ?? title;
                    language =
                        trackDataFromManager['language'] as String? ?? language;
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
                      onTap: () async {
                        if (isActive) {
                          // 关闭字幕
                          final switched =
                              await _switchToEmbeddedSubtitle(context, -1);
                          if (switched && context.mounted) {
                            BlurSnackBar.show(context, '已关闭字幕');
                          }
                        } else {
                          // 先确保禁用外部字幕
                          final switched =
                              await _switchToEmbeddedSubtitle(context, index);
                          if (switched && context.mounted) {
                            BlurSnackBar.show(
                              context,
                              '已切换到字幕: $title',
                            );
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? menuColors.selectedBackground
                              : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                              color: menuColors.divider,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isActive
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: isActive
                                  ? menuColors.selectedForeground
                                  : menuColors.foreground,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title, // Display title from SubtitleManager (or fallback)
                                    style: TextStyle(
                                      color: isActive
                                          ? menuColors.selectedForeground
                                          : menuColors.foreground,
                                      fontSize: 14,
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  Text(
                                    '语言: $language', // Display language from SubtitleManager (or fallback)
                                    locale: Locale("zh-Hans", "zh"),
                                    style: TextStyle(
                                      color: menuColors.secondaryForeground,
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
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    '当前视频没有可用的字幕轨道。\n您可以通过"加载本地字幕文件"按钮添加外部字幕。',
                    locale: Locale("zh-Hans", "zh"),
                    style: TextStyle(
                      color: menuColors.secondaryForeground,
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
