import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:glassmorphism/glassmorphism.dart';
import '../utils/video_player_state.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../widgets/blur_dialog.dart';
import '../widgets/blur_snackbar.dart';
import '../utils/globals.dart' as globals;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

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
      if (globals.isPhone) {
        // 手机端弹窗选择来源
        final source = await BlurDialog.show<String>(
          context: context,
          title: '选择来源',
          content: '请选择视频来源',
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('album'),
              child: const Text('相册'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('file'),
              child: const Text('文件管理器'),
            ),
          ],
        );
        if (source == 'album') {
          PermissionStatus photoStatus;
          PermissionStatus videoStatus;

          if (Platform.isAndroid) {
            // 请求照片和视频权限 (Android 13+ 需要)
            // permission_handler 会处理旧版本的 storage 权限映射
            print("Requesting photos and videos permissions for Android...");
            photoStatus = await Permission.photos.request();
            videoStatus = await Permission.videos.request();
            print("Android permissions status: Photos=$photoStatus, Videos=$videoStatus");
          } else if (Platform.isIOS) {
            // iOS 通常只需要 photos 权限
            print("Requesting photos permission for iOS...");
            photoStatus = await Permission.photos.request();
            videoStatus = photoStatus; // iOS 上 photos 权限通常涵盖视频
            print("iOS permissions status: Photos=$photoStatus");
          } else {
            photoStatus = PermissionStatus.granted;
            videoStatus = PermissionStatus.granted;
          }

          // 检查权限是否都已授予 (根据需要调整，如果只选图片就只检查photoStatus)
          if (!mounted) return; // 检查 widget 是否还在树中
          if (photoStatus.isGranted && videoStatus.isGranted) { // 需要照片和视频权限
            try {
              final picker = ImagePicker();
              // 使用 pickMedia 因为你需要视频
              final XFile? picked = await picker.pickMedia(); 
              if (picked != null) {
                final extension = picked.path.split('.').last.toLowerCase();
                // 允许mp4和mkv
                if (!['mp4', 'mkv'].contains(extension)) { 
                  if (!mounted) return;
                  BlurSnackBar.show(context, '请选择 MP4 或 MKV 格式的视频文件');
                  return;
                }
                if (!mounted) return;
                await context.read<VideoPlayerState>().initializePlayer(picked.path);
              }
            } catch (e) {
              if (!mounted) return;
              BlurSnackBar.show(context, '选择相册视频出错: $e');
            }
          } else {
            // 权限被拒绝
            if (!mounted) return;
            BlurSnackBar.show(context, '需要相册权限才能选择视频');
            // 可以考虑引导用户去设置开启权限
            // openAppSettings(); 
          }
        } else if (source == 'file') {
          try {
            FilePickerResult? result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['mp4', 'mkv'],
              allowMultiple: false,
            );
            if (result != null) {
              final file = File(result.files.single.path!);
              await context.read<VideoPlayerState>().initializePlayer(file.path);
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('选择文件出错: $e')),
            );
          }
        }
      } else {
        // 桌面端：记忆上次打开的文件夹
        String? lastDir;
        try {
          final prefs = await SharedPreferences.getInstance();
          lastDir = prefs.getString('last_video_dir');
        } catch (e) {
          lastDir = null;
        }
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['mp4', 'mkv'],
          allowMultiple: false,
          initialDirectory: lastDir,
        );
        if (result != null) {
          final file = File(result.files.single.path!);
          // 记忆本次目录
          try {
            final prefs = await SharedPreferences.getInstance();
            final dir = file.parent.path;
            await prefs.setString('last_video_dir', dir);
          } catch (e) {
            // 忽略记忆目录失败
          }
          await context.read<VideoPlayerState>().initializePlayer(file.path);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择视频时出错: $e')),
      );
    }
  }
} 