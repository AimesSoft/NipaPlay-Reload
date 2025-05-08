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
    PermissionStatus status;
    if (Platform.isAndroid) {
      // Android 13+ 需要 photos 权限
      status = await Permission.photos.request();
    } else if (Platform.isIOS) {
      status = await Permission.photos.request();
    } else {
      status = PermissionStatus.granted; // 其他平台假设不需要
    }

    if (!mounted) return;

    if (status.isGranted) {
      try {
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );

        if (image != null) {
          final file = File(image.path);
          final fileName = path.basename(file.path);
          
          final appDir = await getApplicationDocumentsDirectory();
          final targetPath = path.join(appDir.path, 'backgrounds', fileName);
          
          await Directory(path.dirname(targetPath)).create(recursive: true);
          
          await file.copy(targetPath);
          
          // 使用 Provider.of<ThemeNotifier>(context, listen: false) 更安全
          Provider.of<ThemeNotifier>(context, listen: false).customBackgroundPath = targetPath;
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择背景图片时出错: $e')),
        );
      }
    } else {
      // 权限被拒绝
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要相册权限才能选择背景图片')),
      );
      // 可以考虑引导用户去设置开启权限
      // openAppSettings();
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
