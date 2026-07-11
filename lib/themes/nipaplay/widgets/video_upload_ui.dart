import 'dart:async';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'dart:io' as io;
import 'package:image_picker/image_picker.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/playback/adaptive_playback_entry_view.dart';
import 'package:nipaplay/playback/unified_playback_entry_model.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/text_input_dialog.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/external_player_service.dart';

class VideoUploadUI extends StatefulWidget {
  const VideoUploadUI({super.key});

  @override
  State<VideoUploadUI> createState() => _VideoUploadUIState();
}

class _VideoUploadUIState extends State<VideoUploadUI>
    with SingleTickerProviderStateMixin {
  late final AnimationController _mascotController;
  late final Animation<double> _mascotScale;
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  final ValueNotifier<bool> _isSubmittingUrl = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _mascotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _mascotScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.18,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.18,
          end: 0.95,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 0.95,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
    ]).animate(_mascotController);
  }

  @override
  void dispose() {
    _mascotController.dispose();
    _urlController.dispose();
    _urlFocusNode.dispose();
    _isSubmittingUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptivePlaybackEntryView(
      content: unifiedPlaybackEntryContent,
      mascotScale: _mascotScale,
      onMascotTap: () => _mascotController.forward(from: 0),
      onSelectFile: _handleUploadVideo,
      onOpenUrlInput: () => unawaited(_showUrlInputDialog()),
    );
  }

  Future<void> _showUrlInputDialog() async {
    await BlurDialog.show<void>(
      context: context,
      title: unifiedPlaybackEntryContent.enterUrlLabel,
      hidePhoneBottomBar: false,
      contentWidget: AdaptivePlaybackUrlDialogContent(
        content: unifiedPlaybackEntryContent,
        controller: _urlController,
        focusNode: _urlFocusNode,
        isSubmitting: _isSubmittingUrl,
        onPaste: _pasteUrlFromClipboard,
        onEditOneTimeUserAgent: _showOneTimeUADialog,
        onPlay: _handlePlayFromUrl,
      ),
    );
  }

  Future<void> _pasteUrlFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) {
        if (!mounted) return;
        BlurSnackBar.show(context, '剪贴板里没有可用链接');
        return;
      }
      _urlController.text = text;
      _urlController.selection = TextSelection.fromPosition(
        TextPosition(offset: _urlController.text.length),
      );
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '读取剪贴板失败: $e');
    }
  }

  /// 串流播放的"自定义UA(仅一次)"：设置仅对下一次播放这条链接生效的一次性 UA。
  Future<void> _showOneTimeUADialog() async {
    final result = await TextInputDialog.show(
      context,
      title: '自定义 User-Agent（仅本次播放）',
      subtitle: '仅对下一次播放生效，不影响长期设置。',
      hintText: 'Mozilla/5.0 ...',
      initialValue: PlayerFactory.getOneTimeUA() ?? '',
      minLines: 2,
    );
    if (result == null) return; // 用户取消
    PlayerFactory.setOneTimeUA(result);
    if (!mounted) return;
    BlurSnackBar.show(
      context,
      result.isEmpty ? '已清除一次性 UA，本次将使用长期/默认 UA' : '已设置一次性 UA，本次播放生效',
    );
  }

  Future<bool> _handlePlayFromUrl() async {
    if (_isSubmittingUrl.value) return false;

    final rawInput = _urlController.text.trim();
    final uri = Uri.tryParse(rawInput);
    final isValidHttpUrl = uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;

    if (!isValidHttpUrl) {
      BlurSnackBar.show(context, '请输入有效的 http/https 视频链接');
      _urlFocusNode.requestFocus();
      return false;
    }

    _isSubmittingUrl.value = true;

    final videoState = context.read<VideoPlayerState>();
    videoState.setPreInitLoadingState('正在准备串流链接...');

    try {
      final playableItem = PlayableItem(videoPath: rawInput);
      if (await ExternalPlayerService.tryHandlePlayback(
        context,
        playableItem,
      )) {
        videoState.resetPlayer();
        return true;
      }

      await videoState.initializePlayer(rawInput);
      return true;
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '播放链接失败: $e');
      }
      await videoState.resetPlayer();
      return false;
    } finally {
      if (mounted) {
        _isSubmittingUrl.value = false;
      }
    }
  }

  Future<void> _handleUploadVideo() async {
    try {
      if (kIsWeb) {
        // Web 平台逻辑
        final videoState = context.read<VideoPlayerState>();
        videoState.setPreInitLoadingState('正在准备视频文件...');

        final filePickerService = FilePickerService();
        final fileName = await filePickerService.pickVideoFile();
        if (fileName == null) {
          videoState.resetPlayer();
          return;
        }
        if (!mounted) {
          videoState.resetPlayer();
          return;
        }
        final url = filePickerService.getWebObjectUrl(fileName);
        if (url == null || url.isEmpty) {
          videoState.resetPlayer();
          if (mounted) {
            BlurSnackBar.show(context, '无法读取视频文件');
          }
          return;
        }

        final playableItem = PlayableItem(
          videoPath: fileName,
          actualPlayUrl: url,
        );
        if (await ExternalPlayerService.tryHandlePlayback(
          context,
          playableItem,
        )) {
          videoState.resetPlayer();
          return;
        }

        Future.microtask(() async {
          await videoState.initializePlayer(fileName, actualPlayUrl: url);
        });
      } else if (io.Platform.isAndroid || io.Platform.isIOS) {
        // 移动端弹窗选择来源，iPad 也需要显式相册入口。
        final source = await BlurDialog.show<String>(
          context: context,
          title: '选择来源',
          content: '请选择视频来源',
          actions: [
            AdaptiveMediaActionButton(
              label: '相册',
              onPressed: () {
                Navigator.of(context).pop('album');
              },
              desktopIcon: Icons.photo_library_outlined,
              phoneIcon: cupertino.CupertinoIcons.photo_on_rectangle,
            ),
            AdaptiveMediaActionButton(
              label: '文件管理器',
              onPressed: () {
                Navigator.of(context).pop('file'); // 先 pop
              },
              desktopIcon: Icons.folder_open_rounded,
              phoneIcon: cupertino.CupertinoIcons.folder_open,
            ),
          ],
        );

        if (!mounted) return; // 检查 mounted 状态

        if (source == 'album') {
          if (io.Platform.isAndroid) {
            // 只在 Android 上使用 permission_handler
            PermissionStatus photoStatus;
            PermissionStatus videoStatus;
            // 请求照片和视频权限 (Android 13+ 需要)
            debugPrint(
              'Requesting photos and videos permissions for Android...',
            );
            photoStatus = await Permission.photos.request();
            videoStatus = await Permission.videos.request();
            debugPrint(
              'Android permissions status: Photos=$photoStatus, '
              'Videos=$videoStatus',
            );

            if (!mounted) return;
            if (photoStatus.isGranted && videoStatus.isGranted) {
              // Android 权限通过，继续选择
              await _pickMediaFromGallery();
            } else {
              // Android 权限被拒绝
              if (!mounted) return;
              debugPrint(
                'Android permissions not granted. Photo status: $photoStatus, '
                'Video status: $videoStatus',
              );
              if (photoStatus.isPermanentlyDenied ||
                  videoStatus.isPermanentlyDenied) {
                BlurDialog.show<void>(
                  context: context,
                  title: '权限被永久拒绝',
                  content: '您已永久拒绝相关权限。请前往系统设置手动为NipaPlay开启所需权限。',
                  actions: [
                    AdaptiveMediaActionButton(
                      label: '前往设置',
                      onPressed: () {
                        Navigator.of(context).pop();
                        openAppSettings();
                      },
                      desktopIcon: Icons.settings_outlined,
                      phoneIcon: cupertino.CupertinoIcons.settings,
                      emphasis: AdaptiveMediaActionEmphasis.primary,
                    ),
                    AdaptiveMediaActionButton(
                      label: '取消',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                );
              } else {
                BlurSnackBar.show(context, '需要相册和视频权限才能选择');
              }
            }
          } else if (io.Platform.isIOS) {
            // 在 iOS 上直接尝试选择
            debugPrint(
              'iOS: Bypassing permission_handler, directly calling '
              'ImagePicker.',
            );
            await _pickMediaFromGallery();
          } else {
            // 其他平台 (如果支持，也直接尝试)
            debugPrint(
              'Other platform: Bypassing permission_handler, directly '
              'calling ImagePicker/FilePicker.',
            );
            await _pickMediaFromGallery(); // 或者根据平台选择不同的picker逻辑
          }
        } else if (source == 'file') {
          // 使用 Future.delayed ensure pop 完成后再执行
          await Future.delayed(const Duration(milliseconds: 100), () async {
            if (!mounted) return; // 在延迟后再次检查 mounted
            try {
              // 先显示加载界面，然后再选择文件
              final videoState = Provider.of<VideoPlayerState>(
                context,
                listen: false,
              );
              videoState.setPreInitLoadingState('正在准备视频文件...');

              // 使用FilePickerService选择视频文件
              final filePickerService = FilePickerService();
              final filePath = await filePickerService.pickVideoFile();

              if (!mounted) return; // 再次检查

              if (filePath != null) {
                // 此处不需要再次设置加载状态，因为已经在选择文件前设置了

                final playableItem = PlayableItem(videoPath: filePath);
                if (await ExternalPlayerService.tryHandlePlayback(
                  context,
                  playableItem,
                )) {
                  videoState.resetPlayer();
                  return;
                }

                // 然后在下一帧初始化播放器
                Future.microtask(() async {
                  await videoState.initializePlayer(filePath);
                });
              } else {
                // 用户取消了选择，清除加载状态
                videoState.resetPlayer();
              }
            } catch (e) {
              // ignore: use_build_context_synchronously
              if (mounted) {
                // 确保 mounted
                BlurSnackBar.show(context, '选择文件出错: $e');
                // 发生错误时清除加载状态
                Provider.of<VideoPlayerState>(
                  context,
                  listen: false,
                ).resetPlayer();
              } else {
                debugPrint('选择文件出错但 widget 已 unmounted: $e');
              }
            }
          });
        }
      } else {
        // 桌面端：使用FilePickerService选择视频文件
        // 先显示加载界面，然后再选择文件
        final videoState = context.read<VideoPlayerState>();
        videoState.setPreInitLoadingState('正在准备视频文件...');

        final filePickerService = FilePickerService();
        final filePath = await filePickerService.pickVideoFile();
        if (!mounted) {
          videoState.resetPlayer();
          return;
        }

        if (filePath != null) {
          // 此处不需要再次设置加载状态，因为已经在选择文件前设置了

          final playableItem = PlayableItem(videoPath: filePath);
          if (await ExternalPlayerService.tryHandlePlayback(
            context,
            playableItem,
          )) {
            videoState.resetPlayer();
            return;
          }

          // 然后在下一帧初始化播放器
          Future.microtask(() async {
            await videoState.initializePlayer(filePath);
          });
        } else {
          // 用户取消了选择，清除加载状态
          videoState.resetPlayer();
        }
      }
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '选择视频时出错: $e');
    }
  }

  // 提取出一个公共的选择媒体的方法
  Future<void> _pickMediaFromGallery() async {
    try {
      // 先显示加载界面，然后再选择文件
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.setPreInitLoadingState('正在准备视频文件...');

      final picker = ImagePicker();
      final XFile? picked = await picker.pickVideo(source: ImageSource.gallery);
      if (!mounted) return; // 再次检查 mounted

      if (picked != null) {
        final extension = picked.path.split('.').last.toLowerCase();
        if (!['mp4', 'mkv'].contains(extension)) {
          BlurSnackBar.show(context, '请选择 MP4 或 MKV 格式的视频文件');
          videoState.resetPlayer(); // 如果选择了不支持的格式，清除加载状态
          return;
        }

        final playableItem = PlayableItem(videoPath: picked.path);
        if (await ExternalPlayerService.tryHandlePlayback(
          context,
          playableItem,
        )) {
          videoState.resetPlayer();
          return;
        }

        // 已经在前面设置了加载状态，这里不需要再次设置

        // 然后在下一帧初始化播放器
        Future.microtask(() async {
          await videoState.initializePlayer(picked.path);
        });
      } else {
        // 用户可能取消了选择，或者 image_picker 因为权限问题返回了 null
        debugPrint(
          'Media picking cancelled or failed (possibly due to permissions).',
        );
        videoState.resetPlayer(); // 清除加载状态
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error picking media from gallery: $e');
      BlurSnackBar.show(context, '选择相册视频出错: $e');
      // 发生错误时清除加载状态
      Provider.of<VideoPlayerState>(context, listen: false).resetPlayer();
    }
  }
}
