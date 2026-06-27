// ThemeModePage.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/keyboard_activatable.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/android_storage_helper.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/models/background_image_render_mode.dart';
import 'package:nipaplay/utils/video_player_state.dart';

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
  final GlobalKey _accentColorDropdownKey = GlobalKey();
  final GlobalKey _backgroundRenderModeDropdownKey = GlobalKey();
  final GlobalKey _windowDisplayModeDropdownKey = GlobalKey();
  late BackgroundImageRenderMode _backgroundImageRenderMode;
  late double _backgroundImageOverlayOpacity;
  static const List<_PlayerControlColorOption> _playerControlColorOptions = [
    _PlayerControlColorOption(0xFFFF7274, '红色'),
    _PlayerControlColorOption(0xFF40C7FF, '蓝色'),
    _PlayerControlColorOption(0xFF6DFF69, '绿色'),
    _PlayerControlColorOption(0xFF4CFFB1, '青色'),
    _PlayerControlColorOption(0xFFFFFFFF, '白色'),
  ];

  @override
  void initState() {
    super.initState();
    _backgroundImageRenderMode = widget.themeNotifier.backgroundImageRenderMode;
    _backgroundImageOverlayOpacity =
        widget.themeNotifier.backgroundImageOverlayOpacity;
  }

  Future<void> _pickCustomBackground(BuildContext context) async {
    if (Platform.isAndroid) {
      // 只在 Android 上使用 permission_handler
      final sdkVersion = await AndroidStorageHelper.getAndroidSDKVersion();
      if (!mounted) return;

      final bool usePhotosPermission = sdkVersion >= 33;
      final PermissionStatus status = usePhotosPermission
          ? await Permission.photos.request()
          : await Permission.storage.request();
      if (!mounted) return;

      final bool canPick =
          status.isGranted || (usePhotosPermission && status.isLimited);

      if (canPick) {
        await _pickImageFromGalleryForBackground(context); // 传递 context
      } else {
        // Android 权限被拒绝
        print(
            "Android permission denied for custom background. Status: $status");
        if (status.isPermanentlyDenied) {
          BlurDialog.show(
            context: context,
            title: '权限已被永久拒绝',
            content: usePhotosPermission
                ? '媒体访问权限已被永久拒绝。请前往系统设置开启。'
                : '存储权限已被永久拒绝。请前往系统设置开启。',
            actions: [
              HoverScaleTextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openAppSettings();
                },
                child: const Text('去设置'),
              ),
              HoverScaleTextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          );
        } else {
          BlurSnackBar.show(
            context,
            usePhotosPermission ? '需要媒体权限才能选择背景图片' : '需要存储权限才能选择背景图片',
          );
        }
      }
    } else if (Platform.isIOS) {
      // 在 iOS 上直接尝试选择
      print(
          "iOS: Bypassing permission_handler for custom background, directly calling ImagePicker.");
      await _pickImageFromGalleryForBackground(context); // 传递 context
    } else {
      // 其他平台 (如果支持，也直接尝试)
      print(
          "Other platform: Bypassing permission_handler for custom background, directly calling ImagePicker.");
      await _pickImageFromGalleryForBackground(context); // 传递 context
    }
  }

  // 提取选择图片并设置为背景的逻辑
  Future<void> _pickImageFromGalleryForBackground(BuildContext context) async {
    // 接收 context
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
          extension = '.jpg';
        }

        // 生成基于时间戳的唯一文件名
        final String timestamp =
            DateTime.now().millisecondsSinceEpoch.toString();
        final String uniqueFileName = 'custom_background_$timestamp$extension';

        final appDir = await StorageService.getAppStorageDirectory();
        final String backgroundDirectoryPath =
            path.join(appDir.path, 'backgrounds');
        final targetPath = path.join(backgroundDirectoryPath, uniqueFileName);

        final targetDirectory = Directory(backgroundDirectoryPath);
        if (!await targetDirectory.exists()) {
          await targetDirectory.create(recursive: true);
        }

        // 复制文件
        await file.copy(targetPath);

        // !! 获取旧路径，用于后续可能的比较和清理，如果 ThemeNotifier 先更新，这里需要注意
        // final oldPath = Provider.of<ThemeNotifier>(context, listen: false).customBackgroundPath;

        // 更新 ThemeNotifier 中的路径
        Provider.of<ThemeNotifier>(context, listen: false)
            .customBackgroundPath = targetPath;

        // 清理旧的自定义背景图片
        final dir = Directory(backgroundDirectoryPath);
        if (await dir.exists()) {
          final List<FileSystemEntity> entities = await dir.list().toList();
          for (FileSystemEntity entity in entities) {
            if (entity is File &&
                entity.path != targetPath &&
                path.basename(entity.path).startsWith('custom_background_')) {
              try {
                await entity.delete();
                print('Deleted old background image: ${entity.path}');
              } catch (e) {
                print('Error deleting old background image ${entity.path}: $e');
              }
            }
          }
        }
        // PaintingBinding.instance.imageCache.evict(FileImage(imageFileToClear)); // 这行不再需要，移除
        // print("Evicted image from cache: $targetPath"); // 这行关联代码也移除
      } else {
        print(
            "Custom background image picking cancelled or failed (possibly due to permissions).");
      }
    } catch (e) {
      // 异步操作后再次检查 mounted 状态
      if (!mounted) return;
      print("Error picking custom background image: $e");
      BlurSnackBar.show(context, '选择背景图片时出错: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 获取外观设置提供者
    final appearanceSettings = Provider.of<AppearanceSettingsProvider>(context);
    final settingsProvider = context.watch<SettingsProvider>();
    final videoState = context.watch<VideoPlayerState>();
    final colorScheme = Theme.of(context).colorScheme;
    final int scaleDivisions = ((AppearanceSettingsProvider.uiScaleMax -
                AppearanceSettingsProvider.uiScaleMin) /
            AppearanceSettingsProvider.uiScaleStep)
        .round();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(0),
        child: ListView(
          children: [
            SettingsItem.dropdown(
              title: "主题模式",
              subtitle: "选择应用界面的颜色主题",
              icon: Ionicons.moon_outline,
              items: [
                DropdownMenuItemData(
                  title: "日间模式",
                  value: ThemeMode.light,
                  isSelected: widget.themeNotifier.themeMode == ThemeMode.light,
                ),
                DropdownMenuItemData(
                  title: "夜间模式",
                  value: ThemeMode.dark,
                  isSelected: widget.themeNotifier.themeMode == ThemeMode.dark,
                ),
                DropdownMenuItemData(
                  title: "跟随系统",
                  value: ThemeMode.system,
                  isSelected:
                      widget.themeNotifier.themeMode == ThemeMode.system,
                ),
              ],
              onChanged: (mode) {
                if (mode is ThemeMode) {
                  setState(() {
                    widget.themeNotifier.themeMode = mode;
                    _saveThemeMode(mode);
                  });
                }
              },
              dropdownKey: _dropdownKey,
            ),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            SettingsItem.dropdown(
              title: "主题色",
              subtitle: "选择应用界面的强调色",
              icon: Ionicons.color_palette_outline,
              items: AppAccentColorPreset.values
                  .map(
                    (preset) => DropdownMenuItemData(
                      title: preset.title,
                      value: preset,
                      isSelected:
                          appearanceSettings.accentColorPreset == preset,
                    ),
                  )
                  .toList(),
              onChanged: (preset) {
                if (preset is AppAccentColorPreset) {
                  appearanceSettings.setAccentColorPreset(preset);
                }
              },
              dropdownKey: _accentColorDropdownKey,
            ),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            SettingsItem.toggle(
              title: "底部进度条",
              subtitle: "播放时在播放器底部显示细进度条",
              icon: Icons.linear_scale_rounded,
              value: videoState.minimalProgressBarEnabled,
              onChanged: (value) {
                videoState.setMinimalProgressBarEnabled(value);
              },
            ),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            SettingsItem.toggle(
              title: "弹幕密度曲线",
              subtitle: "在播放器底部显示弹幕密度曲线",
              icon: Icons.show_chart_rounded,
              value: videoState.showDanmakuDensityChart,
              onChanged: (value) {
                videoState.setShowDanmakuDensityChart(value);
              },
            ),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            _buildPlayerControlColorSetting(videoState, colorScheme),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            SettingsItem.toggle(
              title: "左上角发弹幕按钮",
              subtitle: "在播放器左上角显示发弹幕按钮",
              icon: Ionicons.chatbubble_ellipses_outline,
              value: videoState.playerTopSendDanmakuButtonVisible,
              onChanged: (value) {
                videoState.setPlayerTopSendDanmakuButtonVisible(value);
              },
            ),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            SettingsItem.toggle(
              title: "左上角跳过按钮",
              subtitle: "在播放器左上角显示跳过按钮",
              icon: Ionicons.play_skip_forward_outline,
              value: videoState.playerTopSkipButtonVisible,
              onChanged: (value) {
                videoState.setPlayerTopSkipButtonVisible(value);
              },
            ),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            SettingsItem.toggle(
              title: "左上角窗口适配视频",
              subtitle: "在播放器左上角显示窗口适配视频按钮（桌面端）",
              icon: Ionicons.resize_outline,
              value: videoState.playerTopResizeButtonVisible,
              onChanged: (value) {
                videoState.setPlayerTopResizeButtonVisible(value);
              },
            ),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            SettingsItem.toggle(
              title: "左上角逐帧后退/前进",
              subtitle: "在播放器左上角显示逐帧后退和逐帧前进按钮",
              icon: Ionicons.play_circle_outline,
              value: videoState.playerTopFrameStepButtonsVisible,
              onChanged: (value) {
                videoState.setPlayerTopFrameStepButtonsVisible(value);
              },
            ),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            SettingsItem.toggle(
              title: "番剧卡片显示介绍",
              subtitle: "关闭后仅显示封面和标题",
              icon: Ionicons.document_text_outline,
              value: appearanceSettings.showAnimeCardSummary,
              onChanged: (value) {
                appearanceSettings.setShowAnimeCardSummary(value);
              },
            ),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            SettingsItem.slider(
              title: "界面缩放",
              subtitle: "调整 NipaPlay 界面的整体大小",
              icon: Ionicons.expand_outline,
              value: appearanceSettings.uiScale,
              min: AppearanceSettingsProvider.uiScaleMin,
              max: AppearanceSettingsProvider.uiScaleMax,
              divisions: scaleDivisions,
              onChanged: (value) {
                appearanceSettings.setUiScale(value);
              },
              labelFormatter: (value) => 'x${value.toStringAsFixed(2)}',
            ),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            SettingsItem.dropdown(
              title: "虚拟窗口显示区域",
              subtitle: "调整 NipaPlay Window 控件的显示范围",
              icon: Ionicons.expand_outline,
              items: [
                DropdownMenuItemData(
                  title: "窗口化",
                  value: NipaplayWindowDisplayMode.windowed,
                  isSelected: appearanceSettings.windowDisplayMode ==
                      NipaplayWindowDisplayMode.windowed,
                  description: "居中弹窗，四周留有较大空白",
                ),
                DropdownMenuItemData(
                  title: "铺满屏幕",
                  value: NipaplayWindowDisplayMode.filledScreen,
                  isSelected: appearanceSettings.windowDisplayMode ==
                      NipaplayWindowDisplayMode.filledScreen,
                  description: "贴近屏幕边缘，仅保留少量间距",
                ),
              ],
              onChanged: (mode) {
                if (mode is NipaplayWindowDisplayMode) {
                  appearanceSettings.setWindowDisplayMode(mode);
                }
              },
              dropdownKey: _windowDisplayModeDropdownKey,
            ),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            SettingsItem.dropdown(
              title: "背景图像",
              subtitle: "设置应用主界面的背景图片",
              icon: Ionicons.image_outline,
              items: [
                DropdownMenuItemData(
                  title: "看板娘",
                  value: "看板娘",
                  isSelected: widget.themeNotifier.backgroundImageMode == "看板娘",
                ),
                DropdownMenuItemData(
                  title: "看板娘2",
                  value: "看板娘2",
                  isSelected:
                      widget.themeNotifier.backgroundImageMode == "看板娘2",
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
              onChanged: (mode) async {
                setState(() {
                  widget.themeNotifier.backgroundImageMode = mode;
                  _saveBackgroundImageMode(mode);
                });
                if (mode == "自定义") {
                  await _pickCustomBackground(context);
                }
              },
              dropdownKey: _backgroundImageDropdownKey,
            ),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            if (widget.themeNotifier.backgroundImageMode != "关闭") ...[
              SettingsItem.dropdown(
                title: "背景毛玻璃效果",
                subtitle: "调整界面元素的模糊强度",
                icon: Ionicons.water_outline,
                items: [
                  DropdownMenuItemData(
                    title: "无",
                    value: 0,
                    isSelected: settingsProvider.blurPower == 0,
                  ),
                  DropdownMenuItemData(
                    title: "轻微",
                    value: 5,
                    isSelected: settingsProvider.blurPower == 5,
                  ),
                  DropdownMenuItemData(
                    title: "中等",
                    value: 15,
                    isSelected: settingsProvider.blurPower == 15,
                  ),
                  DropdownMenuItemData(
                    title: "高",
                    value: 25,
                    isSelected: settingsProvider.blurPower == 25,
                  ),
                  DropdownMenuItemData(
                    title: "超级",
                    value: 50,
                    isSelected: settingsProvider.blurPower == 50,
                  ),
                  DropdownMenuItemData(
                    title: "梦幻",
                    value: 100,
                    isSelected: settingsProvider.blurPower == 100,
                  ),
                ],
                onChanged: (blur) {
                  context
                      .read<SettingsProvider>()
                      .setBlurPower(blur.toDouble());
                },
                dropdownKey: _blurDropdownKey,
              ),
              Divider(
                  color: colorScheme.onSurface.withOpacity(0.12), height: 1),
              SettingsItem.dropdown(
                title: "背景图像渲染",
                subtitle: "选择背景颜色与图片的合成方式",
                icon: Ionicons.color_wand_outline,
                items: [
                  DropdownMenuItemData(
                    title: "不透明度",
                    value: BackgroundImageRenderMode.opacity,
                    isSelected: _backgroundImageRenderMode ==
                        BackgroundImageRenderMode.opacity,
                  ),
                  DropdownMenuItemData(
                    title: "柔光",
                    value: BackgroundImageRenderMode.softLight,
                    isSelected: _backgroundImageRenderMode ==
                        BackgroundImageRenderMode.softLight,
                  ),
                ],
                onChanged: (mode) {
                  if (mode is BackgroundImageRenderMode) {
                    setState(() {
                      _backgroundImageRenderMode = mode;
                    });
                    widget.themeNotifier.backgroundImageRenderMode = mode;
                  }
                },
                dropdownKey: _backgroundRenderModeDropdownKey,
              ),
              Divider(
                  color: colorScheme.onSurface.withOpacity(0.12), height: 1),
              SettingsItem.slider(
                title: "背景颜色叠加",
                subtitle: "调整覆盖背景颜色的强度",
                icon: Ionicons.color_palette_outline,
                value: _backgroundImageOverlayOpacity,
                min: 0,
                max: 1,
                divisions: 100,
                onChanged: (value) {
                  setState(() {
                    _backgroundImageOverlayOpacity = value;
                  });
                  widget.themeNotifier.backgroundImageOverlayOpacity = value;
                },
                labelFormatter: (value) => value.toStringAsFixed(2),
              ),
              Divider(
                  color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerControlColorSetting(
    VideoPlayerState videoState,
    ColorScheme colorScheme,
  ) {
    final selectedColor = videoState.minimalProgressBarColor.toARGB32();
    return ListTile(
      leading: Icon(
        Icons.palette_outlined,
        color: colorScheme.onSurface.withOpacity(0.7),
      ),
      title: Text(
        '进度条和曲线颜色',
        locale: const Locale("zh-Hans", "zh"),
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Text(
        '用于底部进度条和弹幕密度曲线',
        locale: const Locale("zh-Hans", "zh"),
        style: TextStyle(
          color: colorScheme.onSurface.withOpacity(0.7),
        ),
      ),
      trailing: SizedBox(
        width: 188,
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: _playerControlColorOptions
              .map(
                (option) => _buildPlayerControlColorSwatch(
                  option,
                  selectedColor: selectedColor,
                  videoState: videoState,
                  colorScheme: colorScheme,
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildPlayerControlColorSwatch(
    _PlayerControlColorOption option, {
    required int selectedColor,
    required VideoPlayerState videoState,
    required ColorScheme colorScheme,
  }) {
    final color = Color(option.colorValue);
    final isSelected = selectedColor == option.colorValue;
    final checkColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black87;
    bool isFocused = false;
    return Tooltip(
      message: option.label,
      child: StatefulBuilder(
        builder: (context, setLocalState) {
          final isActive = isSelected || isFocused;
          return KeyboardActivatable(
            onActivate: () {
              videoState.setMinimalProgressBarColor(option.colorValue);
            },
            onFocusChange: (focused) =>
                setLocalState(() => isFocused = focused),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  videoState.setMinimalProgressBarColor(option.colorValue);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isActive
                          ? AppAccentColors.current
                          : colorScheme.onSurface.withOpacity(0.22),
                      width: isActive ? 3 : 1,
                    ),
                    boxShadow: [
                      if (isActive)
                        BoxShadow(
                          color:
                              AppAccentColors.current.withValues(alpha: 0.22),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: checkColor,
                        )
                      : null,
                ),
              ),
            ),
          );
        },
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

  Future<void> _saveBackgroundImageMode(String mode) async {
    await SettingsStorage.saveString('backgroundImageMode', mode);
  }
}

class _PlayerControlColorOption {
  const _PlayerControlColorOption(this.colorValue, this.label);

  final int colorValue;
  final String label;
}
