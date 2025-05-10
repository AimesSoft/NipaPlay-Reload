// ThemeModePage.dart
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/globals.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/utils/theme_utils.dart';
import 'package:nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

class ThemeModePage extends StatefulWidget {
  final ThemeNotifier themeNotifier;

  const ThemeModePage({super.key, required this.themeNotifier});

  @override
  // ignore: library_private_types_in_public_api
  _ThemeModePageState createState() => _ThemeModePageState();
}

class _ThemeModePageState extends State<ThemeModePage> {
  final GlobalKey _dropdownKey = GlobalKey();
  final GlobalKey _blurDropdownKey = GlobalKey();
  final GlobalKey _backgroundImageDropdownKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 不再需要在 initState 中加载背景图像模式，因为已经在 main.dart 中加载了
  }

  Future<void> _pickCustomBackground(BuildContext context) async {
    if (Platform.isAndroid) { // 只在 Android 上使用 permission_handler
      PermissionStatus status = await Permission.photos.request();
      if (!mounted) return;

      if (status.isGranted) {
        await _pickImageFromGalleryForBackground(context); // 传递 context
      } else {
        // Android 权限被拒绝
        print("Android photos permission denied for custom background. Status: $status");
        if (status.isPermanentlyDenied) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('相册权限已被永久拒绝。请前往系统设置开启。'),
              action: SnackBarAction(
                label: '去设置',
                onPressed: openAppSettings,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要相册权限才能选择背景图片')),
          );
        }
      }
    } else if (Platform.isIOS) { // 在 iOS 上直接尝试选择
      print("iOS: Bypassing permission_handler for custom background, directly calling ImagePicker.");
      await _pickImageFromGalleryForBackground(context); // 传递 context
    } else { // 其他平台 (如果支持，也直接尝试)
      print("Other platform: Bypassing permission_handler for custom background, directly calling ImagePicker.");
      await _pickImageFromGalleryForBackground(context); // 传递 context
    }
  }

  // 提取选择图片并设置为背景的逻辑
  Future<void> _pickImageFromGalleryForBackground(BuildContext context) async { // 接收 context
    try {
      // 在异步操作前检查 mounted 状态
      if (!mounted) return;

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      // 异步操作后再次检查 mounted 状态
      if (!mounted) return;

      if (image != null) {
        final file = File(image.path);
        
        // 获取原始文件的扩展名
        String extension = path.extension(image.path); 
        if (extension.isEmpty) { 
          // 如果 image_picker 返回的路径不含扩展名, imageQuality: 85 暗示JPEG
          extension = '.jpg'; 
        }

        // 定义固定的文件名
        final String fixedFileName = 'custom_background$extension'; 

        final appDir = await getApplicationDocumentsDirectory();
        // 在 'backgrounds' 子目录下保存，文件名固定
        final targetPath = path.join(appDir.path, 'backgrounds', fixedFileName); 
        
        final targetDirectory = Directory(path.dirname(targetPath));
        if (!await targetDirectory.exists()) {
          await targetDirectory.create(recursive: true);
        }
        
        // 复制文件，如果目标文件已存在，File.copy() 会覆盖它
        await file.copy(targetPath); 
        
        // 更新 ThemeNotifier 中的路径
        Provider.of<ThemeNotifier>(context, listen: false).customBackgroundPath = targetPath;
        
      } else {
        print("Custom background image picking cancelled or failed (possibly due to permissions).");
      }
    } catch (e) {
      // 异步操作后再次检查 mounted 状态
      if (!mounted) return;
      print("Error picking custom background image: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择背景图片时出错: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(0),
        child: Column(
          children: [
            ListTile(
              title: Text("主题模式", style: getTitleTextStyle(context)),
              trailing: BlurDropdown<ThemeMode>(
                dropdownKey: _dropdownKey,
                items: [
                  DropdownMenuItemData(
                    title: "日间模式",
                    value: ThemeMode.light,
                    isSelected:
                        widget.themeNotifier.themeMode == ThemeMode.light,
                  ),
                  DropdownMenuItemData(
                    title: "夜间模式",
                    value: ThemeMode.dark,
                    isSelected:
                        widget.themeNotifier.themeMode == ThemeMode.dark,
                  ),
                  DropdownMenuItemData(
                    title: "跟随系统",
                    value: ThemeMode.system,
                    isSelected:
                        widget.themeNotifier.themeMode == ThemeMode.system,
                  ),
                ],
                onItemSelected: (mode) {
                  setState(() {
                    widget.themeNotifier.themeMode = mode;
                    _saveThemeMode(mode);
                  });
                },
              ),
            ),
            ListTile(
              title: Text("毛玻璃效果", style: getTitleTextStyle(context)),
              trailing: BlurDropdown<int>(
                dropdownKey: _blurDropdownKey,
                items: [
                  DropdownMenuItemData(
                    title: "无",
                    value: 0,
                    isSelected: widget.themeNotifier.blurPower == 0,
                  ),
                  DropdownMenuItemData(
                    title: "轻微",
                    value: 5,
                    isSelected: widget.themeNotifier.blurPower == 5,
                  ),
                  DropdownMenuItemData(
                    title: "中等",
                    value: 15,
                    isSelected: widget.themeNotifier.blurPower == 15,
                  ),
                  DropdownMenuItemData(
                    title: "高",
                    value: 25,
                    isSelected: widget.themeNotifier.blurPower == 25,
                  ),
                  DropdownMenuItemData(
                    title: "超级",
                    value: 50,
                    isSelected: widget.themeNotifier.blurPower == 50,
                  ),
                  DropdownMenuItemData(
                    title: "梦幻",
                    value: 100,
                    isSelected: widget.themeNotifier.blurPower == 100,
                  ),
                ],
                onItemSelected: (blur) {
                  setState(() {
                    widget.themeNotifier.blurPower =
                        blur.toDouble(); // 将 blur 转换为 double
                    _saveBlurPower(blur.toDouble());
                  });
                },
              ),
            ),
            ListTile(
              title: Text("背景图像", style: getTitleTextStyle(context)),
              trailing: BlurDropdown<String>(
                dropdownKey: _backgroundImageDropdownKey,
                items: [
                  DropdownMenuItemData(
                    title: "看板娘",
                    value: "看板娘",
                    isSelected: widget.themeNotifier.backgroundImageMode == "看板娘",
                  ),
                  DropdownMenuItemData(
                    title: "关闭",
                    value: "关闭",
                    isSelected: widget.themeNotifier.backgroundImageMode == "关闭",
                  ),
                  DropdownMenuItemData(
                    title: "自定义",
                    value: "自定义",
                    isSelected: widget.themeNotifier.backgroundImageMode == "自定义",
                  ),
                ],
                onItemSelected: (mode) async {
                  setState(() {
                    widget.themeNotifier.backgroundImageMode = mode;
                    _saveBackgroundImageMode(mode);
                  });
                  if (mode == "自定义") {
                    await _pickCustomBackground(context);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    String modeString;
    switch (mode) {
      case ThemeMode.light:
        modeString = 'light';
        break;
      case ThemeMode.dark:
        modeString = 'dark';
        break;
      default:
        modeString = 'system';
    }
    await SettingsStorage.saveString('themeMode', modeString);
  }

  Future<void> _saveBlurPower(double blur) async {
    await SettingsStorage.saveDouble('blurPower', blur);
    setState(() {
      blurPower = blur;
    });
  }

  Future<void> _saveBackgroundImageMode(String mode) async {
    await SettingsStorage.saveString('backgroundImageMode', mode);
  }
}
