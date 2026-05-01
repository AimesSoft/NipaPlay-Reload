import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'dart:io' as io;
import 'package:image_picker/image_picker.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
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
  bool _isHovered = false;
  bool _isUrlActionHovered = false;
  bool _showUrlInput = false;
  bool _isSubmittingUrl = false;
  late final AnimationController _mascotController;
  late final Animation<double> _mascotScale;
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Material 版本（新的设计）
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final mascotSize = globals.isPhone ? 80.0 : 120.0;

    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _mascotController.forward(from: 0.0),
              child: ScaleTransition(
                scale: _mascotScale,
                child: Image.asset(
                  'assets/girl.png',
                  width: mascotSize,
                  height: mascotSize,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '诶？还没有在播放的视频！',
                    locale: const Locale("zh-Hans", "zh"),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 18),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _isHovered = true),
                    onExit: (_) => setState(() => _isHovered = false),
                    child: GestureDetector(
                      onTap: _handleUploadVideo,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 200),
                        scale: _isHovered ? 1.06 : 1.0,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '选择文件',
                          locale: const Locale("zh-Hans", "zh"),
                          style: TextStyle(
                            color: _isHovered
                                ? const Color(0xFFFF2E55)
                                : textColor,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '从本地文件、相册或文件管理器中打开视频',
                    style: TextStyle(
                      color: textColor.withOpacity(0.68),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildChoiceDivider(textColor),
                  const SizedBox(height: 18),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _isUrlActionHovered = true),
                    onExit: (_) => setState(() => _isUrlActionHovered = false),
                    child: GestureDetector(
                      onTap: _toggleUrlInput,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 200),
                        scale: _isUrlActionHovered ? 1.04 : 1.0,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '输入链接',
                          locale: const Locale("zh-Hans", "zh"),
                          style: TextStyle(
                            color: _isUrlActionHovered
                                ? const Color(0xFFFF2E55)
                                : textColor.withOpacity(0.9),
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '粘贴 http/https 串流直链后直接播放',
                    style: TextStyle(
                      color: textColor.withOpacity(0.68),
                      fontSize: 14,
                    ),
                  ),
                  if (_showUrlInput) ...[
                    const SizedBox(height: 14),
                    _buildUrlInputCard(context, textColor),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceDivider(Color textColor) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: textColor.withOpacity(0.14),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '或',
            style: TextStyle(
              color: textColor.withOpacity(0.56),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: textColor.withOpacity(0.14),
          ),
        ),
      ],
    );
  }

  void _toggleUrlInput() {
    if (globals.isTabletLikeMobile) {
      unawaited(_showUrlInputDialog());
      return;
    }

    setState(() {
      _showUrlInput = !_showUrlInput;
    });

    if (_showUrlInput) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _urlFocusNode.requestFocus();
      });
    }
  }

  Future<void> _showUrlInputDialog() async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    var requestedFocus = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        if (!requestedFocus) {
          requestedFocus = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _urlFocusNode.requestFocus();
          });
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    colorScheme.surface.withOpacity(isDarkMode ? 0.94 : 0.98),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: textColor.withOpacity(0.12)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '输入链接',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '支持 http/https 串流直链，建议使用 Media Kit 或 MDK 内核。',
                    style: TextStyle(
                      color: textColor.withOpacity(0.72),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _urlController,
                    focusNode: _urlFocusNode,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) =>
                        _handlePlayFromUrlFromDialog(dialogContext),
                    decoration: InputDecoration(
                      hintText: 'https://example.com/video.mp4 或签名下载直链',
                      filled: true,
                      fillColor: colorScheme.surface.withOpacity(
                        isDarkMode ? 0.58 : 0.94,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text('取消', style: TextStyle(color: textColor)),
                      ),
                      TextButton(
                        onPressed:
                            _isSubmittingUrl ? null : _pasteUrlFromClipboard,
                        child: Text('粘贴', style: TextStyle(color: textColor)),
                      ),
                      TextButton(
                        onPressed: _isSubmittingUrl
                            ? null
                            : () => _handlePlayFromUrlFromDialog(dialogContext),
                        child: Text(
                          _isSubmittingUrl ? '处理中...' : '播放链接',
                          style: const TextStyle(
                            color: Color(0xFFFF2E55),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handlePlayFromUrlFromDialog(BuildContext dialogContext) async {
    final success = await _handlePlayFromUrl();
    if (!success || !mounted) return;
    if (!dialogContext.mounted) return;
    Navigator.of(dialogContext).pop();
  }

  Widget _buildUrlInputCard(BuildContext context, Color textColor) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(isDarkMode ? 0.36 : 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withOpacity(0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '支持 http/https 串流直链，建议使用 Media Kit 或 MDK 内核。',
            style: TextStyle(
              color: textColor.withOpacity(0.72),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _urlController,
            focusNode: _urlFocusNode,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _handlePlayFromUrl(),
            decoration: InputDecoration(
              hintText: 'https://example.com/video.mp4 或签名下载直链',
              filled: true,
              fillColor: colorScheme.surface.withOpacity(
                isDarkMode ? 0.58 : 0.94,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              HoverScaleTextButton(
                onPressed: _isSubmittingUrl ? null : _pasteUrlFromClipboard,
                child: Text('粘贴', style: TextStyle(color: textColor)),
              ),
              HoverScaleTextButton(
                onPressed: _isSubmittingUrl ? null : _handlePlayFromUrl,
                child: Text(
                  _isSubmittingUrl ? '处理中...' : '播放链接',
                  style: const TextStyle(
                    color: Color(0xFFFF2E55),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
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

  Future<bool> _handlePlayFromUrl() async {
    if (_isSubmittingUrl) return false;

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

    setState(() {
      _isSubmittingUrl = true;
    });

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
        setState(() {
          _isSubmittingUrl = false;
        });
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
            HoverScaleTextButton(
              onPressed: () {
                Navigator.of(context).pop('album');
              },
              child: const Text('相册', style: TextStyle(color: Colors.white)),
            ),
            HoverScaleTextButton(
              onPressed: () {
                Navigator.of(context).pop('file'); // 先 pop
              },
              child: const Text('文件管理器', style: TextStyle(color: Colors.white)),
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
            print("Requesting photos and videos permissions for Android...");
            photoStatus = await Permission.photos.request();
            videoStatus = await Permission.videos.request();
            print(
              "Android permissions status: Photos=$photoStatus, Videos=$videoStatus",
            );

            if (!mounted) return;
            if (photoStatus.isGranted && videoStatus.isGranted) {
              // Android 权限通过，继续选择
              await _pickMediaFromGallery();
            } else {
              // Android 权限被拒绝
              if (!mounted) return;
              print(
                "Android permissions not granted. Photo status: $photoStatus, Video status: $videoStatus",
              );
              if (photoStatus.isPermanentlyDenied ||
                  videoStatus.isPermanentlyDenied) {
                BlurDialog.show<void>(
                  context: context,
                  title: '权限被永久拒绝',
                  content: '您已永久拒绝相关权限。请前往系统设置手动为NipaPlay开启所需权限。',
                  actions: [
                    HoverScaleTextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        openAppSettings();
                      },
                      child: const Text('前往设置'),
                    ),
                    HoverScaleTextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ],
                );
              } else {
                BlurSnackBar.show(context, '需要相册和视频权限才能选择');
              }
            }
          } else if (io.Platform.isIOS) {
            // 在 iOS 上直接尝试选择
            print(
              "iOS: Bypassing permission_handler, directly calling ImagePicker.",
            );
            await _pickMediaFromGallery();
          } else {
            // 其他平台 (如果支持，也直接尝试)
            print(
              "Other platform: Bypassing permission_handler, directly calling ImagePicker/FilePicker.",
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
                  if (context.mounted) {
                    await Provider.of<VideoPlayerState>(
                      context,
                      listen: false,
                    ).initializePlayer(filePath);
                  }
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
                print('选择文件出错但 widget 已 unmounted: $e');
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
        print(
          "Media picking cancelled or failed (possibly due to permissions).",
        );
        videoState.resetPlayer(); // 清除加载状态
      }
    } catch (e) {
      if (!mounted) return;
      print("Error picking media from gallery: $e");
      BlurSnackBar.show(context, '选择相册视频出错: $e');
      // 发生错误时清除加载状态
      Provider.of<VideoPlayerState>(context, listen: false).resetPlayer();
    }
  }
}
