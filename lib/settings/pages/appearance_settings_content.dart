import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/models/anime_detail_display_mode.dart';
import 'package:nipaplay/models/background_image_render_mode.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/utils/android_storage_helper.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

class AppearanceSettingsContent extends StatefulWidget {
  const AppearanceSettingsContent({super.key});

  @override
  State<AppearanceSettingsContent> createState() =>
      _AppearanceSettingsContentState();
}

class _AppearanceSettingsContentState extends State<AppearanceSettingsContent> {
  final GlobalKey _themeModeDropdownKey = GlobalKey();
  final GlobalKey _detailModeDropdownKey = GlobalKey();
  final GlobalKey _recentStyleDropdownKey = GlobalKey();
  final GlobalKey _windowDisplayModeDropdownKey = GlobalKey();
  final GlobalKey _backgroundImageDropdownKey = GlobalKey();
  final GlobalKey _blurDropdownKey = GlobalKey();
  final GlobalKey _backgroundRenderModeDropdownKey = GlobalKey();
  final GlobalKey _folderNameDisplayModeDropdownKey = GlobalKey();

  static const List<AdaptiveSettingsColorOption<int>>
      _playerControlColorOptions = [
    AdaptiveSettingsColorOption(
      title: '红色',
      value: 0xFFFF7274,
      color: Color(0xFFFF7274),
    ),
    AdaptiveSettingsColorOption(
      title: '蓝色',
      value: 0xFF40C7FF,
      color: Color(0xFF40C7FF),
    ),
    AdaptiveSettingsColorOption(
      title: '绿色',
      value: 0xFF6DFF69,
      color: Color(0xFF6DFF69),
    ),
    AdaptiveSettingsColorOption(
      title: '青色',
      value: 0xFF4CFFB1,
      color: Color(0xFF4CFFB1),
    ),
    AdaptiveSettingsColorOption(
      title: '白色',
      value: 0xFFFFFFFF,
      color: Color(0xFFFFFFFF),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    final appearanceSettings = context.watch<AppearanceSettingsProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final videoState = context.watch<VideoPlayerState>();
    final homeSections = context.watch<HomeSectionsSettingsProvider>();
    final scaleDivisions = ((AppearanceSettingsProvider.uiScaleMax -
                AppearanceSettingsProvider.uiScaleMin) /
            AppearanceSettingsProvider.uiScaleStep)
        .round();
    final showNipaplayShellSettings = !globals.isPhone;
    final showDesktopOnlySettings = globals.isDesktop;
    final children = <Widget>[
      AdaptiveSettingsSection(
        children: [
          AdaptiveSettingsTile<ThemeMode>.dropdown(
            title: _text(context, '主题模式', '主題模式', 'Theme Mode'),
            subtitle: _text(
              context,
              '选择应用界面的颜色主题',
              '選擇應用介面的顏色主題',
              'Choose the app color theme.',
            ),
            icon: Ionicons.moon_outline,
            phoneIcon: cupertino.CupertinoIcons.circle_lefthalf_fill,
            items: [
              DropdownMenuItemData(
                title: context.l10n.lightMode,
                value: ThemeMode.light,
                isSelected: themeNotifier.themeMode == ThemeMode.light,
              ),
              DropdownMenuItemData(
                title: context.l10n.darkMode,
                value: ThemeMode.dark,
                isSelected: themeNotifier.themeMode == ThemeMode.dark,
              ),
              DropdownMenuItemData(
                title: context.l10n.followSystem,
                value: ThemeMode.system,
                isSelected: themeNotifier.themeMode == ThemeMode.system,
              ),
            ],
            onChanged: (mode) {
              themeNotifier.themeMode = mode;
            },
            dropdownKey: _themeModeDropdownKey,
          ),
          AdaptiveSettingsColorTile<AppAccentColorPreset>(
            title: _text(context, '主题色', '主題色', 'Accent Color'),
            subtitle: _text(
              context,
              '选择应用界面的强调色',
              '選擇應用介面的強調色',
              'Choose the app accent color.',
            ),
            icon: Ionicons.color_palette_outline,
            phoneIcon: cupertino.CupertinoIcons.circle_grid_hex,
            value: appearanceSettings.accentColorPreset,
            options: [
              for (final preset in AppAccentColorPreset.values)
                AdaptiveSettingsColorOption(
                  title: preset.title,
                  value: preset,
                  color: preset.color,
                ),
            ],
            onChanged: appearanceSettings.setAccentColorPreset,
          ),
        ],
      ),
      const SizedBox(height: 16),
      AdaptiveSettingsSection(
        children: [
          AdaptiveSettingsTile<bool>.toggle(
            title: _text(context, '底部进度条', '底部進度條', 'Bottom Progress Bar'),
            subtitle: _text(
              context,
              '播放时在播放器底部显示细进度条',
              '播放時在播放器底部顯示細進度條',
              'Show a thin progress bar at the bottom of the player.',
            ),
            icon: Icons.linear_scale_rounded,
            phoneIcon: cupertino.CupertinoIcons.minus,
            value: videoState.minimalProgressBarEnabled,
            onChanged: videoState.setMinimalProgressBarEnabled,
          ),
          AdaptiveSettingsTile<bool>.toggle(
            title: _text(context, '弹幕密度曲线', '彈幕密度曲線', 'Danmaku Density'),
            subtitle: _text(
              context,
              '在播放器底部显示弹幕密度曲线',
              '在播放器底部顯示彈幕密度曲線',
              'Show the danmaku density chart at the bottom of the player.',
            ),
            icon: Icons.show_chart_rounded,
            phoneIcon: cupertino.CupertinoIcons.chart_bar,
            value: videoState.showDanmakuDensityChart,
            onChanged: videoState.setShowDanmakuDensityChart,
          ),
          AdaptiveSettingsColorTile<int>(
            title: _text(
              context,
              '进度条和曲线颜色',
              '進度條與曲線顏色',
              'Progress and Chart Color',
            ),
            subtitle: _text(
              context,
              '用于底部进度条和弹幕密度曲线',
              '用於底部進度條與彈幕密度曲線',
              'Used by the bottom progress bar and danmaku density chart.',
            ),
            icon: Icons.palette_outlined,
            phoneIcon: cupertino.CupertinoIcons.paintbrush,
            value: videoState.minimalProgressBarColor.toARGB32(),
            options: _playerControlColorOptions,
            onChanged: videoState.setMinimalProgressBarColor,
          ),
          AdaptiveSettingsTile<bool>.toggle(
            title: _text(
              context,
              '左上角发弹幕按钮',
              '左上角發彈幕按鈕',
              'Top Send Danmaku Button',
            ),
            subtitle: _text(
              context,
              '在播放器左上角显示发弹幕按钮',
              '在播放器左上角顯示發彈幕按鈕',
              'Show the send danmaku button at the top left of the player.',
            ),
            icon: Ionicons.chatbubble_ellipses_outline,
            phoneIcon: cupertino.CupertinoIcons.chat_bubble_2,
            value: videoState.playerTopSendDanmakuButtonVisible,
            onChanged: videoState.setPlayerTopSendDanmakuButtonVisible,
          ),
          AdaptiveSettingsTile<bool>.toggle(
            title: _text(
              context,
              '左上角跳过按钮',
              '左上角跳過按鈕',
              'Top Skip Button',
            ),
            subtitle: _text(
              context,
              '在播放器左上角显示跳过按钮',
              '在播放器左上角顯示跳過按鈕',
              'Show the skip button at the top left of the player.',
            ),
            icon: Ionicons.play_skip_forward_outline,
            phoneIcon: cupertino.CupertinoIcons.forward_end,
            value: videoState.playerTopSkipButtonVisible,
            onChanged: videoState.setPlayerTopSkipButtonVisible,
          ),
          if (showDesktopOnlySettings)
            AdaptiveSettingsTile<bool>.toggle(
              title: _text(
                context,
                '左上角窗口适配视频',
                '左上角視窗適配影片',
                'Top Fit Window Button',
              ),
              subtitle: _text(
                context,
                '在播放器左上角显示窗口适配视频按钮',
                '在播放器左上角顯示視窗適配影片按鈕',
                'Show the fit-window-to-video button at the top left.',
              ),
              icon: Ionicons.resize_outline,
              phoneIcon: cupertino.CupertinoIcons.resize,
              value: videoState.playerTopResizeButtonVisible,
              onChanged: videoState.setPlayerTopResizeButtonVisible,
            ),
          AdaptiveSettingsTile<bool>.toggle(
            title: _text(
              context,
              '左上角逐帧后退/前进',
              '左上角逐格後退/前進',
              'Top Frame Step Buttons',
            ),
            subtitle: _text(
              context,
              '在播放器左上角显示逐帧后退和逐帧前进按钮',
              '在播放器左上角顯示逐格後退和逐格前進按鈕',
              'Show frame back and frame forward buttons at the top left.',
            ),
            icon: Ionicons.play_circle_outline,
            phoneIcon: cupertino.CupertinoIcons.play_circle,
            value: videoState.playerTopFrameStepButtonsVisible,
            onChanged: videoState.setPlayerTopFrameStepButtonsVisible,
          ),
        ],
      ),
      const SizedBox(height: 16),
      AdaptiveSettingsSection(
        children: [
          if (globals.isPhone) ...[
            AdaptiveSettingsTile<AnimeDetailDisplayMode>.dropdown(
              title: context.l10n.appearanceAnimeDetailStyle,
              subtitle: _text(
                context,
                '选择番剧详情页展示方式',
                '選擇番劇詳情頁展示方式',
                'Choose the anime detail page layout.',
              ),
              icon: Ionicons.albums_outline,
              phoneIcon: cupertino.CupertinoIcons.rectangle_on_rectangle,
              items: [
                DropdownMenuItemData(
                  title: context.l10n.appearanceDetailSimple,
                  value: AnimeDetailDisplayMode.simple,
                  isSelected: themeNotifier.animeDetailDisplayMode ==
                      AnimeDetailDisplayMode.simple,
                  description: context.l10n.appearanceDetailSimpleSubtitle,
                ),
                DropdownMenuItemData(
                  title: context.l10n.appearanceDetailVivid,
                  value: AnimeDetailDisplayMode.vivid,
                  isSelected: themeNotifier.animeDetailDisplayMode ==
                      AnimeDetailDisplayMode.vivid,
                  description: context.l10n.appearanceDetailVividSubtitle,
                ),
              ],
              onChanged: (mode) {
                themeNotifier.animeDetailDisplayMode = mode;
              },
              dropdownKey: _detailModeDropdownKey,
            ),
            AdaptiveSettingsTile<RecentWatchingStyle>.dropdown(
              title: context.l10n.appearanceRecentWatchingStyle,
              subtitle: _text(
                context,
                '选择最近观看区域的展示方式',
                '選擇最近觀看區域的展示方式',
                'Choose how recently watched items are shown.',
              ),
              icon: Ionicons.time_outline,
              phoneIcon: cupertino.CupertinoIcons.clock,
              items: [
                DropdownMenuItemData(
                  title: context.l10n.appearanceRecentSimple,
                  value: RecentWatchingStyle.simple,
                  isSelected: appearanceSettings.recentWatchingStyle ==
                      RecentWatchingStyle.simple,
                  description: context.l10n.appearanceRecentSimpleSubtitle,
                ),
                DropdownMenuItemData(
                  title: context.l10n.appearanceRecentDetailed,
                  value: RecentWatchingStyle.detailed,
                  isSelected: appearanceSettings.recentWatchingStyle ==
                      RecentWatchingStyle.detailed,
                  description: context.l10n.appearanceRecentDetailedSubtitle,
                ),
              ],
              onChanged: appearanceSettings.setRecentWatchingStyle,
              dropdownKey: _recentStyleDropdownKey,
            ),
          ],
          AdaptiveSettingsTile<bool>.toggle(
            title: _text(
              context,
              '番剧卡片显示介绍',
              '番劇卡片顯示介紹',
              'Show Anime Card Summary',
            ),
            subtitle: _text(
              context,
              '关闭后仅显示封面和标题',
              '關閉後僅顯示封面與標題',
              'When off, cards only show cover art and title.',
            ),
            icon: Ionicons.document_text_outline,
            phoneIcon: cupertino.CupertinoIcons.doc_text,
            value: appearanceSettings.showAnimeCardSummary,
            onChanged: appearanceSettings.setShowAnimeCardSummary,
          ),
        ],
      ),
      const SizedBox(height: 16),
      AdaptiveSettingsSection(
        children: [
          AdaptiveSettingsTile<FolderNameDisplayMode>.dropdown(
            title: _text(
              context,
              '目录名称显示模式',
              '目錄名稱顯示模式',
              'Folder Name Display',
            ),
            subtitle: _text(
              context,
              '设置媒体库管理中过长目录名的显示方式',
              '設定媒體庫管理中過長目錄名的顯示方式',
              'Choose how long folder names are shown in library management.',
            ),
            icon: Ionicons.folder_outline,
            phoneIcon: cupertino.CupertinoIcons.folder,
            items: [
              DropdownMenuItemData(
                title: _text(context, '省略号截断', '省略號截斷', 'Ellipsis'),
                value: FolderNameDisplayMode.ellipsis,
                isSelected: appearanceSettings.folderNameDisplayMode ==
                    FolderNameDisplayMode.ellipsis,
              ),
              DropdownMenuItemData(
                title: _text(context, '多行显示', '多行顯示', 'Multiline'),
                value: FolderNameDisplayMode.multiline,
                isSelected: appearanceSettings.folderNameDisplayMode ==
                    FolderNameDisplayMode.multiline,
              ),
            ],
            onChanged: appearanceSettings.setFolderNameDisplayMode,
            dropdownKey: _folderNameDisplayModeDropdownKey,
          ),
        ],
      ),
      if (globals.isPhone) ...[
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            for (final section in HomeSectionType.values)
              AdaptiveSettingsTile<bool>.toggle(
                title: section.title,
                icon: Ionicons.grid_outline,
                phoneIcon: cupertino.CupertinoIcons.square_grid_2x2,
                value: homeSections.isSectionEnabled(section),
                onChanged: (value) {
                  homeSections.setSectionEnabled(section, value);
                },
              ),
            AdaptiveSettingsTile<void>.card(
              title: context.l10n.restoreDefaults,
              subtitle: context.l10n.restoreDefaultsSubtitle,
              icon: Ionicons.refresh_outline,
              phoneIcon: cupertino.CupertinoIcons.refresh,
              onTap: homeSections.restoreDefaults,
            ),
          ],
        ),
      ],
      if (showNipaplayShellSettings) ...[
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<double>.slider(
              title: _text(context, '界面缩放', '介面縮放', 'UI Scale'),
              subtitle: _text(
                context,
                '调整 NipaPlay 界面的整体大小',
                '調整 NipaPlay 介面的整體大小',
                'Adjust the overall NipaPlay interface size.',
              ),
              icon: Ionicons.expand_outline,
              phoneIcon:
                  cupertino.CupertinoIcons.arrow_up_left_arrow_down_right,
              value: appearanceSettings.uiScale,
              min: AppearanceSettingsProvider.uiScaleMin,
              max: AppearanceSettingsProvider.uiScaleMax,
              divisions: scaleDivisions,
              onChanged: appearanceSettings.setUiScale,
              labelFormatter: (value) => 'x${value.toStringAsFixed(2)}',
            ),
            AdaptiveSettingsTile<NipaplayWindowDisplayMode>.dropdown(
              title: _text(
                context,
                '虚拟窗口显示区域',
                '虛擬視窗顯示區域',
                'Window Display Area',
              ),
              subtitle: _text(
                context,
                '调整 NipaPlay Window 控件的显示范围',
                '調整 NipaPlay Window 控件的顯示範圍',
                'Adjust the display area of NipaPlay Window controls.',
              ),
              icon: Ionicons.expand_outline,
              phoneIcon: cupertino.CupertinoIcons.rectangle_expand_vertical,
              items: [
                DropdownMenuItemData(
                  title: _text(context, '窗口化', '視窗化', 'Windowed'),
                  value: NipaplayWindowDisplayMode.windowed,
                  isSelected: appearanceSettings.windowDisplayMode ==
                      NipaplayWindowDisplayMode.windowed,
                  description: _text(
                    context,
                    '居中弹窗，四周留有较大空白',
                    '置中彈窗，四周留有較大空白',
                    'Centered windows with generous margins.',
                  ),
                ),
                DropdownMenuItemData(
                  title: _text(context, '铺满屏幕', '鋪滿螢幕', 'Fill Screen'),
                  value: NipaplayWindowDisplayMode.filledScreen,
                  isSelected: appearanceSettings.windowDisplayMode ==
                      NipaplayWindowDisplayMode.filledScreen,
                  description: _text(
                    context,
                    '贴近屏幕边缘，仅保留少量间距',
                    '貼近螢幕邊緣，僅保留少量間距',
                    'Stay near screen edges with smaller margins.',
                  ),
                ),
              ],
              onChanged: appearanceSettings.setWindowDisplayMode,
              dropdownKey: _windowDisplayModeDropdownKey,
            ),
          ],
        ),
      ],
      ...[
        const SizedBox(height: 16),
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<String>.dropdown(
              title: _text(context, '背景图像', '背景圖像', 'Background Image'),
              subtitle: _text(
                context,
                '设置应用主界面的背景图片',
                '設定應用主介面的背景圖片',
                'Set the background image for the main interface.',
              ),
              icon: Ionicons.image_outline,
              phoneIcon: cupertino.CupertinoIcons.photo,
              items: [
                _backgroundImageItem(context, themeNotifier, '看板娘'),
                _backgroundImageItem(context, themeNotifier, '看板娘2'),
                _backgroundImageItem(context, themeNotifier, '关闭'),
                _backgroundImageItem(context, themeNotifier, '自定义'),
              ],
              onChanged: (mode) async {
                themeNotifier.backgroundImageMode = mode;
                if (mode == '自定义') {
                  await _pickCustomBackground();
                }
              },
              dropdownKey: _backgroundImageDropdownKey,
            ),
            if (themeNotifier.backgroundImageMode != '关闭') ...[
              AdaptiveSettingsTile<int>.dropdown(
                title: _text(
                  context,
                  '背景毛玻璃效果',
                  '背景毛玻璃效果',
                  'Background Blur',
                ),
                subtitle: _text(
                  context,
                  '调整界面元素的模糊强度',
                  '調整介面元素的模糊強度',
                  'Adjust the blur strength of interface elements.',
                ),
                icon: Ionicons.water_outline,
                phoneIcon: cupertino.CupertinoIcons.drop,
                items: [
                  _blurItem(context, settingsProvider, '无', '無', 'None', 0),
                  _blurItem(
                    context,
                    settingsProvider,
                    '轻微',
                    '輕微',
                    'Light',
                    5,
                  ),
                  _blurItem(
                    context,
                    settingsProvider,
                    '中等',
                    '中等',
                    'Medium',
                    15,
                  ),
                  _blurItem(context, settingsProvider, '高', '高', 'High', 25),
                  _blurItem(
                    context,
                    settingsProvider,
                    '超级',
                    '超級',
                    'Super',
                    50,
                  ),
                  _blurItem(
                    context,
                    settingsProvider,
                    '梦幻',
                    '夢幻',
                    'Dreamy',
                    100,
                  ),
                ],
                onChanged: (blur) {
                  settingsProvider.setBlurPower(blur.toDouble());
                },
                dropdownKey: _blurDropdownKey,
              ),
              AdaptiveSettingsTile<BackgroundImageRenderMode>.dropdown(
                title: _text(
                  context,
                  '背景图像渲染',
                  '背景圖像渲染',
                  'Background Rendering',
                ),
                subtitle: _text(
                  context,
                  '选择背景颜色与图片的合成方式',
                  '選擇背景顏色與圖片的合成方式',
                  'Choose how the background color blends with the image.',
                ),
                icon: Ionicons.color_wand_outline,
                phoneIcon: cupertino.CupertinoIcons.wand_stars,
                items: [
                  DropdownMenuItemData(
                    title: _text(context, '不透明度', '不透明度', 'Opacity'),
                    value: BackgroundImageRenderMode.opacity,
                    isSelected: themeNotifier.backgroundImageRenderMode ==
                        BackgroundImageRenderMode.opacity,
                  ),
                  DropdownMenuItemData(
                    title: _text(context, '柔光', '柔光', 'Soft Light'),
                    value: BackgroundImageRenderMode.softLight,
                    isSelected: themeNotifier.backgroundImageRenderMode ==
                        BackgroundImageRenderMode.softLight,
                  ),
                ],
                onChanged: (mode) {
                  themeNotifier.backgroundImageRenderMode = mode;
                },
                dropdownKey: _backgroundRenderModeDropdownKey,
              ),
              AdaptiveSettingsTile<double>.slider(
                title: _text(
                  context,
                  '背景颜色叠加',
                  '背景顏色疊加',
                  'Background Color Overlay',
                ),
                subtitle: _text(
                  context,
                  '调整覆盖背景颜色的强度',
                  '調整覆蓋背景顏色的強度',
                  'Adjust the strength of the color overlay.',
                ),
                icon: Ionicons.color_palette_outline,
                phoneIcon: cupertino.CupertinoIcons.slider_horizontal_3,
                value: themeNotifier.backgroundImageOverlayOpacity,
                min: 0,
                max: 1,
                divisions: 100,
                onChanged: (value) {
                  themeNotifier.backgroundImageOverlayOpacity = value;
                },
                labelFormatter: (value) => value.toStringAsFixed(2),
              ),
            ],
          ],
        ),
      ],
    ];

    return AdaptiveSettingsPage(
      children: children,
    );
  }

  DropdownMenuItemData<String> _backgroundImageItem(
    BuildContext context,
    ThemeNotifier notifier,
    String value,
  ) {
    return DropdownMenuItemData(
      title: _backgroundImageTitle(context, value),
      value: value,
      isSelected: notifier.backgroundImageMode == value,
    );
  }

  DropdownMenuItemData<int> _blurItem(
    BuildContext context,
    SettingsProvider settingsProvider,
    String zh,
    String zhHant,
    String en,
    int value,
  ) {
    return DropdownMenuItemData(
      title: _text(context, zh, zhHant, en),
      value: value,
      isSelected: settingsProvider.blurPower.round() == value,
    );
  }

  String _backgroundImageTitle(BuildContext context, String value) {
    switch (value) {
      case '看板娘':
        return _text(context, '看板娘', '看板娘', 'Mascot');
      case '看板娘2':
        return _text(context, '看板娘2', '看板娘2', 'Mascot 2');
      case '关闭':
        return _text(context, '关闭', '關閉', 'Off');
      case '自定义':
        return _text(context, '自定义', '自訂', 'Custom');
      default:
        return value;
    }
  }

  Future<void> _pickCustomBackground() async {
    if (!kIsWeb && Platform.isAndroid) {
      final sdkVersion = await AndroidStorageHelper.getAndroidSDKVersion();
      if (!mounted) return;

      final usePhotosPermission = sdkVersion >= 33;
      final status = usePhotosPermission
          ? await Permission.photos.request()
          : await Permission.storage.request();
      if (!mounted) return;

      final canPick =
          status.isGranted || (usePhotosPermission && status.isLimited);
      if (canPick) {
        await _pickImageFromGalleryForBackground();
        return;
      }

      if (status.isPermanentlyDenied) {
        await AdaptiveAlertDialog.show(
          context: context,
          title: _text(
            context,
            '权限已被永久拒绝',
            '權限已被永久拒絕',
            'Permission Permanently Denied',
          ),
          message: usePhotosPermission
              ? _text(
                  context,
                  '媒体访问权限已被永久拒绝。请前往系统设置开启。',
                  '媒體存取權限已被永久拒絕。請前往系統設定開啟。',
                  'Media permission was permanently denied. Enable it in system settings.',
                )
              : _text(
                  context,
                  '存储权限已被永久拒绝。请前往系统设置开启。',
                  '儲存權限已被永久拒絕。請前往系統設定開啟。',
                  'Storage permission was permanently denied. Enable it in system settings.',
                ),
          actions: [
            AlertAction(
              title: _text(context, '取消', '取消', 'Cancel'),
              style: AlertActionStyle.cancel,
              onPressed: () {},
            ),
            AlertAction(
              title: _text(context, '去设置', '前往設定', 'Open Settings'),
              style: AlertActionStyle.primary,
              onPressed: openAppSettings,
            ),
          ],
        );
        return;
      }

      AdaptiveSnackBar.show(
        context,
        message: usePhotosPermission
            ? _text(
                context,
                '需要媒体权限才能选择背景图片',
                '需要媒體權限才能選擇背景圖片',
                'Media permission is required to choose a background image.',
              )
            : _text(
                context,
                '需要存储权限才能选择背景图片',
                '需要儲存權限才能選擇背景圖片',
                'Storage permission is required to choose a background image.',
              ),
      );
      return;
    }

    await _pickImageFromGalleryForBackground();
  }

  Future<void> _pickImageFromGalleryForBackground() async {
    try {
      if (!mounted) return;

      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (!mounted || image == null) return;

      final file = File(image.path);
      var extension = path.extension(image.path);
      if (extension.isEmpty) {
        extension = '.jpg';
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final uniqueFileName = 'custom_background_$timestamp$extension';
      final appDir = await StorageService.getAppStorageDirectory();
      final backgroundDirectoryPath = path.join(appDir.path, 'backgrounds');
      final targetPath = path.join(backgroundDirectoryPath, uniqueFileName);
      final targetDirectory = Directory(backgroundDirectoryPath);

      if (!await targetDirectory.exists()) {
        await targetDirectory.create(recursive: true);
      }

      await file.copy(targetPath);
      if (!mounted) return;
      context.read<ThemeNotifier>().customBackgroundPath = targetPath;

      final dir = Directory(backgroundDirectoryPath);
      if (!await dir.exists()) return;

      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File &&
            entity.path != targetPath &&
            path.basename(entity.path).startsWith('custom_background_')) {
          try {
            await entity.delete();
          } catch (_) {
            // Best-effort cleanup of old custom backgrounds.
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: _text(
          context,
          '选择背景图片时出错: $e',
          '選擇背景圖片時發生錯誤: $e',
          'Error choosing background image: $e',
        ),
      );
    }
  }

  String _text(
    BuildContext context,
    String simplified,
    String traditional,
    String english,
  ) {
    final locale = context.l10n.localeName;
    if (locale == 'en') {
      return english;
    }
    if (locale == 'zh_Hant') {
      return traditional;
    }
    return simplified;
  }
}
