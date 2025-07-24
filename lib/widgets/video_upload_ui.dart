import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../utils/video_player_state.dart';
import 'dart:io' as io;
import 'package:universal_html/html.dart' as web_html;
import 'package:image_picker/image_picker.dart';
import '../widgets/blur_dialog.dart';
import '../widgets/blur_snackbar.dart';
import '../utils/globals.dart' as globals;
import 'package:permission_handler/permission_handler.dart';
import '../services/file_picker_service.dart';
import 'package:file_picker/file_picker.dart';

class VideoUploadUI extends StatefulWidget {
  const VideoUploadUI({super.key});

  @override
  State<VideoUploadUI> createState() => _VideoUploadUIState();
}

class _VideoUploadUIState extends State<VideoUploadUI> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassmorphicContainer(
        width: 300,
        height: 250,
        borderRadius: 20,
        blur: 20,
        alignment: Alignment.center,
        border: 1,
        linearGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFffffff).withOpacity(0.1),
            const Color(0xFFFFFFFF).withOpacity(0.05),
          ],
        ),
        borderGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFffffff).withOpacity(0.5),
            const Color((0xFFFFFFFF)).withOpacity(0.5),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.video_library,
              size: 64,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            const Text(
              '上传视频开始播放',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 24),
            MouseRegion(
              onEnter: (_) => setState(() => _isHovered = true),
              onExit: (_) => setState(() => _isHovered = false),
              cursor: SystemMouseCursors.click,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 150),
                scale: _isPressed ? 0.95 : _isHovered ? 1.05 : 1.0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _isHovered ? 0.8 : 1.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        GlassmorphicContainer(
                          width: 150,
                          height: 50,
                          borderRadius: 12,
                          blur: 10,
                          alignment: Alignment.center,
                          border: 1,
                          linearGradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFFffffff).withOpacity(_isHovered ? 0.15 : 0.1),
                              const Color(0xFFFFFFFF).withOpacity(_isHovered ? 0.1 : 0.05),
                            ],
                          ),
                          borderGradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFFffffff).withOpacity(_isHovered ? 0.7 : 0.5),
                              const Color((0xFFFFFFFF)).withOpacity(_isHovered ? 0.7 : 0.5),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              '选择视频',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTapDown: (_) => setState(() => _isPressed = true),
                              onTapUp: (_) => setState(() => _isPressed = false),
                              onTapCancel: () => setState(() => _isPressed = false),
                              onTap: _handleUploadVideo,
                              splashColor: Colors.white.withOpacity(0.2),
                              highlightColor: Colors.white.withOpacity(0.1),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleUploadVideo() async {
    try {
      if (kIsWeb) {
        // Web 平台逻辑
        final videoState = context.read<VideoPlayerState>();
        videoState.setPreInitLoadingState('正在准备视频文件...');
        
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.video,
        );

        if (result != null && result.files.single.bytes != null) {
          final fileBytes = result.files.single.bytes!;
          final fileName = result.files.single.name;
          
          final blob = web_html.Blob([fileBytes]);
          final url = web_html.Url.createObjectUrlFromBlob(blob);

          Future.microtask(() async {
            await videoState.initializePlayer(
              fileName, // 使用文件名作为标识
              actualPlayUrl: url,
            );
          });
        } else {
          // 用户取消了选择
          videoState.resetPlayer();
        }
      } else if (globals.isPhone) {
        // 手机端弹窗选择来源
        final source = await BlurDialog.show<String>(
          context: context,
          title: '选择来源',
          content: '请选择视频来源',
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop('album');
              },
              child: const Text('相册'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop('file'); // 先 pop
              },
              child: const Text('文件管理器'),
            ),
          ],
        );

        if (!mounted) return; // 检查 mounted 状态

        if (source == 'album') {
          if (io.Platform.isAndroid) { // 只在 Android 上使用 permission_handler
            PermissionStatus photoStatus;
            PermissionStatus videoStatus;
            // 请求照片和视频权限 (Android 13+ 需要)
            print("Requesting photos and videos permissions for Android...");
            photoStatus = await Permission.photos.request();
            videoStatus = await Permission.videos.request();
            print("Android permissions status: Photos=$photoStatus, Videos=$videoStatus");

            if (!mounted) return;
            if (photoStatus.isGranted && videoStatus.isGranted) {
              // Android 权限通过，继续选择
              await _pickMediaFromGallery(); 
            } else {
              // Android 权限被拒绝
              if (!mounted) return;
              print("Android permissions not granted. Photo status: $photoStatus, Video status: $videoStatus");
              if (photoStatus.isPermanentlyDenied || videoStatus.isPermanentlyDenied) {
                BlurDialog.show<void>(
                  context: context,
                  title: '权限被永久拒绝',
                  content: '您已永久拒绝相关权限。请前往系统设置手动为NipaPlay开启所需权限。',
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        openAppSettings();
                      },
                      child: const Text('前往设置'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ],
                );
              } else {
                BlurSnackBar.show(context, '需要相册和视频权限才能选择');
              }
            }
          } else if (io.Platform.isIOS) { // 在 iOS 上直接尝试选择
            print("iOS: Bypassing permission_handler, directly calling ImagePicker.");
            await _pickMediaFromGallery(); 
          } else { // 其他平台 (如果支持，也直接尝试)
            print("Other platform: Bypassing permission_handler, directly calling ImagePicker/FilePicker.");
            await _pickMediaFromGallery(); // 或者根据平台选择不同的picker逻辑
          }
        } else if (source == 'file') {
          // 使用 Future.delayed ensure pop 完成后再执行
          await Future.delayed(const Duration(milliseconds: 100), () async { 
            if (!mounted) return; // 在延迟后再次检查 mounted
            try {
              // 先显示加载界面，然后再选择文件
              final videoState = Provider.of<VideoPlayerState>(context, listen: false);
              videoState.setPreInitLoadingState('正在准备视频文件...');
              
              // 使用FilePickerService选择视频文件
              final filePickerService = FilePickerService();
              final filePath = await filePickerService.pickVideoFile();

              if (!mounted) return; // 再次检查

              if (filePath != null) {
                // 此处不需要再次设置加载状态，因为已经在选择文件前设置了
                
                // 然后在下一帧初始化播放器
                Future.microtask(() async {
                  if (context.mounted) { 
                    await Provider.of<VideoPlayerState>(context, listen: false)
                              .initializePlayer(filePath);
                  }
                });
              } else {
                // 用户取消了选择，清除加载状态
                videoState.resetPlayer();
              }
            } catch (e) {
              // ignore: use_build_context_synchronously
              if (mounted) { // 确保 mounted
                BlurSnackBar.show(context, '选择文件出错: $e');
                // 发生错误时清除加载状态
                Provider.of<VideoPlayerState>(context, listen: false).resetPlayer();
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
      // 使用 pickMedia 因为你需要视频
      final XFile? picked = await picker.pickMedia();
      if (!mounted) return; // 再次检查 mounted

      if (picked != null) {
        final extension = picked.path.split('.').last.toLowerCase();
        if (!['mp4', 'mkv'].contains(extension)) {
          BlurSnackBar.show(context, '请选择 MP4 或 MKV 格式的视频文件');
          videoState.resetPlayer(); // 如果选择了不支持的格式，清除加载状态
          return;
        }
        
        // 已经在前面设置了加载状态，这里不需要再次设置
        
        // 然后在下一帧初始化播放器
        Future.microtask(() async {
          await videoState.initializePlayer(picked.path);
        });
      } else {
        // 用户可能取消了选择，或者 image_picker 因为权限问题返回了 null
        print("Media picking cancelled or failed (possibly due to permissions).");
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