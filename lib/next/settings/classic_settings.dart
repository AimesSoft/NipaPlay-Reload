import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/background_image_render_mode.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/services/desktop_exit_preferences.dart';
import 'package:nipaplay/services/desktop_picture_in_picture_preferences.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';
import 'package:nipaplay/services/desktop_startup_window_preferences.dart';
import 'package:nipaplay/services/file_log_service.dart';
import 'package:nipaplay/services/update_service.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/hotkey_service.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../capabilities/classic_home.dart';

import 'application_settings.dart';
import 'denylist.dart';
import 'registry.dart';
import '../tasks/user_consent.dart';

List<SchemaViolation> validateGithubProxy(Object? value) {
  final text = (value as String).trim();
  if (text.isEmpty) return [];
  final uri = Uri.tryParse(text);
  if ((!text.startsWith('http://') && !text.startsWith('https://')) ||
      !text.endsWith('/') || uri == null || !uri.hasAuthority || uri.host.isEmpty) {
    return [const SchemaViolation('/value', 'Use an HTTP(S) URL ending in /, or empty to disable.')];
  }
  return [];
}

/// Bind to the same providers that Classic widgets consume.
final class ClassicSettings {
  ClassicSettings({
    required this.appearance,
    required this.language,
    required this.home,
    required this.theme,
    required this.developer,
    required this.labs,
    required this.webdav,
    required this.plugins,
  });
  final AppearanceSettingsProvider appearance;
  final AppLanguageProvider language;
  final HomeSectionsSettingsProvider home;
  final ThemeNotifier theme;
  final DeveloperOptionsProvider developer;
  final LabsSettingsProvider labs;
  final WebDAVQuickAccessProvider webdav;
  final PluginService plugins;
  static ClassicSettings? attached;
  static ClassicSettings get current =>
      attached ??
      (throw const Failure(
          FailureCode.unavailable, 'Classic settings are not attached.'));

  static const _writers = {
    'appearance.accentColor': 'setAccentColorPreset',
    'appearance.automaticUiScale': 'setAutomaticUiScale',
    'appearance.themeMode': 'themeMode',
    'appearance.backgroundImageMode': 'backgroundImageMode',
    'appearance.customBackgroundPath': 'customBackgroundPath',
    'appearance.backgroundRenderMode': 'backgroundImageRenderMode',
    'appearance.backgroundOverlayOpacity': 'backgroundImageOverlayOpacity',
    'appearance.homeSectionsOrder': 'reorderSections',
    'appearance.homeSectionsDisabled': 'setSectionEnabled',
    'general.desktopExitBehavior': 'save',
    'general.startupWindowState': 'saveState',
    'general.startupWindowPosition': 'savePosition',
    'general.startupWindowWidth': 'saveSize',
    'general.startupWindowHeight': 'saveSize',
    'general.pictureInPicturePosition': 'savePosition',
    'general.autoCheckUpdates': 'setAutoCheckEnabled',
    'diagnostics.collectLogs': 'setEnableDebugLogCollection',
    'diagnostics.fileLog': 'setEnableFileLog',
    'webdavQuick.showTab': 'setShowWebDAVTab',
  };

  static String _writer(String key) {
    final field = key.split('.').last;
    return _writers[key] ?? 'set${field[0].toUpperCase()}${field.substring(1)}';
  }

  Future<void> get ready async {
    await appearance.ready;
    await home.ready;
    await developer.ready;
    await labs.ready;
    await webdav.loadSettings();
  }

  static List<SettingEntry> entries() {
    final entries = <SettingEntry>[];
    void add(String key, String title, Schema schema, Object? fallback,
        String storage, Future<void> Function(Object?) write,
        {String source = 'lib/providers/appearance_settings_provider.dart',
        String? setter,
        String? description,
        String apply = 'immediate',
        String scope = 'user',
        List<String> additionalStorageKeys = const [],
        Object? Function(Object?)? decode,
        Future<Object?> Function()? read,
        bool Function()? visible,
        Object? Function()? dynamicDefault,
        List<SchemaViolation> Function(Object?)? validate}) {
      Object? decodeValue(Object? raw) => decode == null
          ? raw ?? dynamicDefault?.call() ?? fallback
          : decode(raw);
      entries.add(SettingEntry(
        key: key,
        title: title,
        description: description ?? '调整$title，复用 Classic 的持久化与应用方式。',
        schema: schema,
        defaultValue: fallback,
        dynamicDefaultValue: dynamicDefault,
        storageKey: storage,
        scope: scope,
        apply: apply,
        additionalStorageKeys: additionalStorageKeys,
        reader: source,
        writer: '$source#${setter ?? _writer(key)}',
        decodeStorage: decodeValue,
        read: read ??
            () async => decodeValue(
                (await SharedPreferences.getInstance()).get(storage)),
        write: (value) async {
          await current.ready;
          if (key == 'appearance.blurPower' ||
              key == 'plugins.githubProxyUrl') {
            await ApplicationSettings.preferences.ready;
          }
          await write(value);
        },
        visible: visible,
        validateValue: validate,
      ));
    }

    void appearanceBool(
            String name,
            String title,
            String storage,
            bool fallback,
            Future<void> Function(AppearanceSettingsProvider, bool) write) =>
        add('appearance.$name', title, const BooleanSchema(), fallback, storage,
            (v) => write(current.appearance, v as bool));
    appearanceBool('showAnimeCardSummary', '番剧卡片简介', 'show_anime_card_summary',
        true, (p, v) => p.setShowAnimeCardSummary(v));
    appearanceBool(
        'showQuarterlyAnimeReview',
        '首页新番回顾',
        'show_quarterly_anime_review',
        true,
        (p, v) => p.setShowQuarterlyAnimeReview(v));
    appearanceBool(
        'showMediaLibraryNewBadge',
        '媒体库 NEW 标识',
        SettingsKeys.showMediaLibraryNewBadge,
        true,
        (p, v) => p.setShowMediaLibraryNewBadge(v));
    appearanceBool(
        'diffuseLowResolutionPosters',
        '低清推荐海报晕染',
        'diffuse_low_resolution_recommendation_posters',
        true,
        (p, v) => p.setDiffuseLowResolutionPosters(v));
    appearanceBool('showHomeHeroBanner', '主页推荐轮播大图', 'show_home_hero_banner',
        true, (p, v) => p.setShowHomeHeroBanner(v));
    appearanceBool(
        'showHomeHeroSideCardTop',
        '主页上方推荐小卡片',
        'show_home_hero_side_card_top',
        true,
        (p, v) => p.setShowHomeHeroSideCardTop(v));
    appearanceBool(
        'showHomeHeroSideCardBottom',
        '主页下方推荐小卡片',
        'show_home_hero_side_card_bottom',
        true,
        (p, v) => p.setShowHomeHeroSideCardBottom(v));
    add(
        'appearance.accentColor',
        '主题色',
        StringSchema(
            values:
                AppAccentColorPreset.values.map((e) => e.storageKey).toList()),
        AppAccentColorPreset.rose.storageKey,
        'app_accent_color_preset',
        (v) => current.appearance.setAccentColorPreset(
            AppAccentColorPreset.fromStorageKey(v as String)));
    add(
        'appearance.folderNameDisplayMode',
        '目录名称显示',
        StringSchema(
            values: FolderNameDisplayMode.values.map((e) => e.name).toList()),
        'ellipsis',
        'folder_name_display_mode',
        (v) => current.appearance.setFolderNameDisplayMode(
            FolderNameDisplayMode.values.byName(v as String)),
        decode: (raw) => ApplicationSettings.decodeIndexedEnum(
            raw, FolderNameDisplayMode.values, FolderNameDisplayMode.ellipsis));
    add(
        'appearance.windowDisplayMode',
        '窗口显示区域',
        StringSchema(
            values:
                NipaplayWindowDisplayMode.values.map((e) => e.name).toList()),
        'windowed',
        'nipaplay_window_display_mode',
        (v) => current.appearance.setWindowDisplayMode(
            NipaplayWindowDisplayMode.values.byName(v as String)),
        dynamicDefault: () => globals.isTablet ? 'filledScreen' : 'windowed',
        decode: (raw) => ApplicationSettings.decodeIndexedEnum(
            raw,
            NipaplayWindowDisplayMode.values,
            globals.isTablet
                ? NipaplayWindowDisplayMode.filledScreen
                : NipaplayWindowDisplayMode.windowed));
    add(
        'appearance.uiScale',
        '界面缩放',
        const NumberSchema(
            minimum: AppearanceSettingsProvider.uiScaleMin,
            maximum: AppearanceSettingsProvider.uiScaleMax),
        1.0,
        'ui_scale_factor',
        (v) => current.appearance.setUiScale((v as num).toDouble()),
        additionalStorageKeys: ['ui_scale_automatic'],
        dynamicDefault: () =>
            attached?.appearance.automaticUiScaleValue ??
            (globals.isTelevision || globals.isTablet ? 1.2 : 1.0),
        read: () async {
          final prefs = await SharedPreferences.getInstance();
          final saved = prefs.getDouble('ui_scale_factor');
          final automatic =
              attached?.appearance.supportsAutomaticUiScale ?? false;
          if (automatic &&
              (prefs.getBool('ui_scale_automatic') ?? saved == null)) {
            return current.appearance.automaticUiScaleValue;
          }
          return saved ??
              (globals.isTelevision || globals.isTablet ? 1.2 : 1.0);
        });
    add(
        'appearance.automaticUiScale',
        '自动界面缩放',
        const BooleanSchema(),
        true,
        'ui_scale_automatic',
        (v) => current.appearance.setAutomaticUiScale(v as bool),
        visible: () =>
            attached?.appearance.supportsAutomaticUiScale ??
            globals.isAndroidTv,
        read: () async {
          final prefs = await SharedPreferences.getInstance();
          return prefs.getBool('ui_scale_automatic') ??
              !prefs.containsKey('ui_scale_factor');
        });
    const themeSource = 'lib/utils/theme_notifier.dart';
    Future<void> themeChange(void Function(ThemeNotifier) change) async {
      change(current.theme);
      await current.theme.pendingSave;
    }

    add(
        'appearance.themeMode',
        '主题模式',
        const StringSchema(values: ['system', 'light', 'dark']),
        'system',
        'themeMode',
        (v) => themeChange(
            (p) => p.themeMode = ThemeMode.values.byName(v as String)),
        dynamicDefault: () => globals.isTelevision ? 'dark' : 'system',
        source: themeSource);
    add(
        'appearance.backgroundImageMode',
        '背景图像',
        const StringSchema(values: ['看板娘', '看板娘2', '关闭', '自定义']),
        '关闭',
        'backgroundImageMode',
        (v) => themeChange((p) => p.backgroundImageMode = v as String),
        source: themeSource);
    add('appearance.customBackgroundPath', '自定义背景图像', const StringSchema(),
        'assets/images/main_image.png', 'customBackgroundPath', (v) async {
      final value = v as String;
      final path =
          value.startsWith('assets/') ? value : await authorizedPath(value);
      await themeChange((p) => p.customBackgroundPath = path);
    },
        dynamicDefault: () => globals.isDesktop || globals.isTablet
            ? 'assets/images/main_image.png'
            : 'assets/images/main_image_mobile.png',
        source: themeSource,
        scope: 'device');
    add(
        'appearance.backgroundRenderMode',
        '背景图像渲染',
        const StringSchema(values: ['opacity', 'soft_light']),
        'opacity',
        ThemeNotifier.backgroundImageRenderModeKey,
        (v) => themeChange((p) => p.backgroundImageRenderMode =
            BackgroundImageRenderModeStorage.fromString(v as String)),
        source: themeSource);
    add(
        'appearance.backgroundOverlayOpacity',
        '背景颜色叠加',
        const NumberSchema(minimum: 0, maximum: 1),
        0.3,
        ThemeNotifier.backgroundImageOverlayOpacityKey,
        (v) => themeChange(
            (p) => p.backgroundImageOverlayOpacity = (v as num).toDouble()),
        source: themeSource);
    add(
        'appearance.blurPower',
        '背景毛玻璃',
        NumberSchema(minimum: 0, maximum: globals.isTelevision ? 25 : 100),
        0.0,
        'blurPower',
        (v) =>
            ApplicationSettings.preferences.setBlurPower((v as num).toDouble()),
        source: 'lib/providers/settings_provider.dart',
        validate: (v) => [0, 5, 15, 25, if (!globals.isTelevision) ...[50, 100]].contains(v)
            ? [] : [const SchemaViolation('/value', 'Choose a Classic blur preset.')]);
    const homeSource = 'lib/providers/home_sections_settings_provider.dart';
    final sectionKeys =
        HomeSectionType.values.map((e) => e.storageKey).toList();
    add(
        'appearance.homeSectionsOrder',
        '首页分区顺序',
        ArraySchema(StringSchema(values: sectionKeys)),
        sectionKeys,
        'home_sections_order', (v) async {
      final order = (v as List).cast<String>();
      for (var i = 0; i < order.length; i++) {
        final old = current.home.orderedSections
            .indexWhere((s) => s.storageKey == order[i]);
        if (old != i) {
          await current.home.reorderSections(old, old < i ? i + 1 : i);
        }
      }
    },
        source: homeSource,
        validate: (v) => (v as List).length == sectionKeys.length &&
                v.toSet().length == sectionKeys.length
            ? []
            : [
                const SchemaViolation(
                    '/value', 'Every section must occur exactly once.')
              ]);
    add(
        'appearance.homeSectionsDisabled',
        '隐藏首页分区',
        ArraySchema(StringSchema(values: sectionKeys)),
        const <String>[],
        'home_sections_disabled', (v) async {
      for (final section in HomeSectionType.values) {
        await current.home.setSectionEnabled(
            section, !(v as List).contains(section.storageKey));
      }
    }, source: homeSource);
    add(
        'language.mode',
        '语言',
        const StringSchema(
            values: ['auto', 'simplified', 'traditional', 'english']),
        'auto',
        SettingsKeys.appLanguageMode,
        (v) => current.language.setMode(switch (v) {
              'simplified' => AppLanguageMode.simplifiedChinese,
              'traditional' => AppLanguageMode.traditionalChinese,
              'english' => AppLanguageMode.english,
              _ => AppLanguageMode.auto,
            }),
        source: 'lib/providers/app_language_provider.dart',
        setter: 'setMode');
    const generalSource =
        'lib/services/desktop_startup_window_preferences.dart';
    add(
        'general.desktopExitBehavior',
        '关闭窗口时',
        StringSchema(
            values: DesktopExitBehavior.values.map((e) => e.name).toList()),
        DesktopExitBehavior.askEveryTime.name,
        DesktopExitPreferences.key,
        (v) => DesktopExitPreferences.save(
            DesktopExitBehavior.values.byName(v as String)),
        source: 'lib/services/desktop_exit_preferences.dart',
        decode: (raw) => DesktopExitPreferences.parse(raw as String?).name,
        visible: () => globals.isDesktop);
    add(
        'general.startupWindowState',
        '启动窗口状态',
        const StringSchema(values: ['windowed', 'maximized']),
        'maximized',
        'desktop_startup_window_state',
        (v) => DesktopStartupWindowPreferences.saveState(
            DesktopStartupWindowState.values.byName(v as String)),
        source: generalSource,
        apply: 'restart_app',
        visible: () => globals.isDesktop);
    add(
        'general.startupWindowPosition',
        '启动窗口位置',
        StringSchema(
            values: DesktopStartupWindowPosition.values
                .map((e) => e.name)
                .toList()),
        'center',
        'desktop_startup_window_position',
        (v) => DesktopStartupWindowPreferences.savePosition(
            DesktopStartupWindowPosition.values.byName(v as String)),
        source: generalSource,
        apply: 'restart_app',
        visible: () => globals.isDesktop);
    for (final dimension in ['width', 'height']) {
      final width = dimension == 'width';
      add(
          'general.startupWindow${width ? 'Width' : 'Height'}',
          '启动窗口${width ? '宽度' : '高度'}',
          NumberSchema(minimum: width ? 600 : 400),
          width ? 1280.0 : 720.0,
          'desktop_startup_window_$dimension', (v) async {
        final size = await DesktopStartupWindowPreferences.loadSize();
        await DesktopStartupWindowPreferences.saveSize(Size(
            width ? (v as num).toDouble() : size.width,
            width ? size.height : (v as num).toDouble()));
      },
          source: generalSource,
          apply: 'restart_app',
          visible: () => globals.isDesktop);
    }
    add(
        'general.pictureInPicturePosition',
        '画中画停靠位置',
        StringSchema(
            values: DesktopPictureInPicturePosition.values
                .map((e) => e.name)
                .toList()),
        'topRight',
        'desktop_picture_in_picture_window_position', (v) async {
      final position =
          DesktopPictureInPicturePosition.values.byName(v as String);
      await DesktopPictureInPicturePreferences.savePosition(position);
      await DesktopPlayerWindowService.instance
          .updatePictureInPicturePlacement(position);
    },
        source: 'lib/services/desktop_picture_in_picture_preferences.dart',
        visible: () => globals.isDesktop);
    add(
        'general.defaultHomeTab',
        '默认主页',
        StringSchema(values: [
          'home',
          'video',
          'webdav',
          'media_library',
          if (globals.isDownloaderSupportedPlatform) 'torrent',
          'account'
        ]),
        'home',
        'default_home_tab',
        (v) => current.webdav.setDefaultHomeTab(v as String),
        additionalStorageKeys: ['default_page_index'],
        source: 'lib/providers/webdav_quick_access_provider.dart',
        description: '通用与 WebDAV 快捷页共用的默认主页；WebDAV Tab 关闭时实际回落到首页。',
        read: () async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('default_home_tab') ??
          switch (prefs.getInt('default_page_index')) {
            1 => 'video',
            2 => 'media_library',
            3 => 'account',
            _ => 'home',
          };
    });
    add(
        'general.autoCheckUpdates',
        '自动检查更新',
        const BooleanSchema(),
        true,
        SettingsKeys.autoCheckUpdatesInBackground,
        (v) => UpdateService.setAutoCheckEnabled(v as bool),
        source: 'lib/services/update_service.dart', read: () async {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(SettingsKeys.autoCheckUpdatesInBackground) ??
          prefs.getBool(SettingsKeys.legacyAutoCheckUpdatesOnAboutPage) ??
          true;
    });
    add(
        'network.httpProxy',
        '统一 HTTP 代理',
        const StringSchema(),
        '',
        SettingsKeys.playerHttpProxy,
        (v) => PlayerFactory.saveHttpProxy(v as String),
        source: 'lib/player_abstraction/player_factory.dart',
        setter: 'saveHttpProxy',
        description:
            'HTTP 代理端点（仅 http://host:port，不带认证）。为空时使用系统代理。播放器下次打开媒体生效；应用网络请求沿用现有统一代理。',
        apply: 'reload_player',
        visible: () => globals.isDesktop,
        validate: (v) {
          try {
            AppHttpProxy.validate(v as String);
            return [];
          } on FormatException {
            return [
              const SchemaViolation('/value',
                  'Expected an HTTP proxy endpoint without authentication, or empty for system proxy.')
            ];
          }
        });
    add(
        'network.allowInvalidCertificates',
        '允许自签名证书（全局）',
        const BooleanSchema(),
        false,
        'trusted_cert_global_allow_v1',
        (v) => current.developer.setAllowInvalidCertsGlobal(v as bool),
        source: 'lib/providers/developer_options_provider.dart',
        setter: 'setAllowInvalidCertsGlobal',
        description: '复用 Classic 全局证书信任开关，允许 Dart HTTP 请求接受无效或自签名证书。仅 IO 平台生效。');
    add(
        'plugins.githubProxyUrl',
        'GitHub 代理',
        const StringSchema(),
        '',
        SettingsKeys.githubProxyUrl,
        (v) async {
          final value = (v as String).trim();
          if (value.isNotEmpty) {
            final response = await http.get(Uri.parse('${value}https://raw.githubusercontent.com/AimesSoft/Nipaplay-plugins/refs/heads/main/plugins.json'))
                .timeout(const Duration(seconds: 10));
            if (response.statusCode != 200) {
              throw Failure(FailureCode.unavailable, 'GitHub proxy connectivity check failed (${response.statusCode}); previous value retained.');
            }
          }
          await ApplicationSettings.preferences.setGithubProxyUrl(value);
        },
        source: 'lib/providers/settings_provider.dart',
        description: '插件市场与更新使用的 GitHub 加速前缀；空字符串关闭加速。非空值须为 HTTP(S) 地址并以 / 结尾；沿用 Classic 请求插件索引测试，HTTP 200 才保存。',
        validate: validateGithubProxy);
    const developerSource = 'lib/providers/developer_options_provider.dart';
    add(
        'diagnostics.showSystemResources',
        '系统资源监控',
        const BooleanSchema(),
        false,
        'show_system_resources',
        (v) => current.developer.setShowSystemResources(v as bool),
        source: developerSource);
    add('diagnostics.collectLogs', '终端日志收集', const BooleanSchema(), true,
        'enable_debug_log_collection', (v) async {
      await current.developer.setEnableDebugLogCollection(v as bool);
      if (v) {
        DebugLogService().startCollecting();
      } else {
        DebugLogService().stopCollecting();
      }
    }, source: developerSource);
    add('diagnostics.fileLog', '写入日志文件', const BooleanSchema(), true,
        'enable_file_log', (v) async {
      await current.developer.setEnableFileLog(v as bool);
      if (v) {
        await FileLogService().start();
      } else {
        await FileLogService().stop();
      }
    }, source: developerSource);
    add(
        'labs.enableErikaPlayerKernel',
        'Erika 内核实验开关',
        const BooleanSchema(),
        false,
        SettingsKeys.labsEnableErikaPlayerKernel,
        (v) => current.labs.setEnableErikaPlayerKernel(v as bool),
        source: 'lib/providers/labs_settings_provider.dart');
    add(
        'labs.enableImmersiveAnimeDetail',
        '沉浸式番剧详情',
        const BooleanSchema(),
        false,
        SettingsKeys.labsEnableImmersiveAnimeDetail,
        (v) => current.labs.setEnableImmersiveAnimeDetail(v as bool),
        source: 'lib/providers/labs_settings_provider.dart');
    for (final shortcut in HotkeyService.defaultShortcuts.entries) {
      add(
          'shortcuts.${shortcut.key}',
          '快捷键 ${shortcut.key}',
          const StringSchema(minLength: 1),
          shortcut.value,
          'keyboard_shortcuts', (v) async {
        if (HotkeyService().allShortcuts.isEmpty) {
          await HotkeyService().loadShortcuts();
        }
        final conflict = HotkeyService().allShortcuts.entries.any(
            (entry) => entry.key != shortcut.key && entry.value == v);
        if (conflict && !await showUserConsent('快捷键冲突',
            '这个快捷键已被其他操作使用，要替换吗？', '替换')) {
          throw const Failure(FailureCode.conflict, '用户没有同意替换快捷键');
        }
        await HotkeyService().updateShortcut(shortcut.key, v as String);
      },
          source: 'lib/utils/hotkey_service.dart',
          description: '沿用 Classic 快捷键格式与冲突提示；冲突时由用户在应用内选择替换或取消。替换与 Classic 一样只更新目标动作。',
          setter: 'updateShortcut',
          decode: (raw) => raw == null
              ? shortcut.value
              : (jsonDecode(raw as String) as Map)[shortcut.key] ??
                  shortcut.value,
          validate: (v) => HotkeyService().isValidShortcut(v as String)
              ? []
              : [
                  const SchemaViolation('/value',
                      'Use a Classic shortcut such as Ctrl+K, 空格, ← or F1.')
                ]);
    }
    const webdavSource = 'lib/providers/webdav_quick_access_provider.dart';
    void dav(
            String name,
            String title,
            Schema schema,
            Object fallback,
            String storage,
            Future<void> Function(WebDAVQuickAccessProvider, Object?) write,
            {List<SchemaViolation> Function(Object?)? validate}) =>
        add('webdavQuick.$name', title, schema, fallback, storage,
            (v) => write(current.webdav, v),
            source: webdavSource, validate: validate);
    dav('showTab', '显示 WebDAV Tab', const BooleanSchema(), false,
        'show_webdav_tab', (p, v) => p.setShowWebDAVTab(v as bool));
    dav(
        'defaultServerName',
        '默认服务器',
        const StringSchema(),
        '',
        'webdav_default_server_name',
        (p, v) => p.setDefaultServerName(v as String));
    dav(
        'defaultDirectory',
        '默认目录',
        const StringSchema(),
        '/',
        'webdav_default_directory',
        (p, v) => p.setDefaultDirectory(v as String));
    dav(
        'sortPreset',
        '文件排序',
        StringSchema(
            values: WebDAVSortPreset.values.map((e) => e.value).toList()),
        'default',
        'webdav_sort_preset',
        (p, v) => p.setSortPreset(WebDAVSortPreset.fromValue(v as String)));
    dav(
        'showPathBreadcrumb',
        '显示路径导航',
        const BooleanSchema(),
        true,
        'webdav_show_path_breadcrumb',
        (p, v) => p.setShowPathBreadcrumb(v as bool));
    dav(
        'autoEnterSeasonFolder',
        '自动进入 Season 文件夹',
        const BooleanSchema(),
        false,
        'webdav_auto_enter_season_folder',
        (p, v) => p.setAutoEnterSeasonFolder(v as bool));
    dav(
        'seasonFolderPattern',
        'Season 匹配模式',
        const StringSchema(),
        'Season*',
        'webdav_season_folder_pattern',
        (p, v) => p.setSeasonFolderPattern(v as String));
    dav('bgmIdQuickMatch', 'bgmid 快速匹配', const BooleanSchema(), false,
        'webdav_bgmid_quick_match', (p, v) => p.setBgmIdQuickMatch(v as bool));
    dav(
        'bgmIdMatchPattern',
        'bgmid 匹配规则',
        const StringSchema(),
        r'bgm(id)?[=-](\d+)',
        'webdav_bgmid_match_pattern',
        (p, v) => p.setBgmIdMatchPattern(v as String),
        validate: validateCapturePattern);
    dav(
        'tmdbIdQuickMatch',
        'tmdbId 快速匹配',
        const BooleanSchema(),
        false,
        'webdav_tmdbid_quick_match',
        (p, v) => p.setTmdbIdQuickMatch(v as bool));
    dav(
        'tmdbIdMatchPattern',
        'tmdbId 匹配规则',
        const StringSchema(),
        r'tmdb(id)?[=-](\d+)',
        'webdav_tmdbid_match_pattern',
        (p, v) => p.setTmdbIdMatchPattern(v as String),
        validate: validateCapturePattern);
    dav(
        'episodeOffsetEnabled',
        '匹配弹幕自动剧集偏移',
        const BooleanSchema(),
        false,
        'webdav_episode_offset',
        (p, v) => p.setEpisodeOffsetEnabled(v as bool));
    dav('enableSearch', '文件搜索', const BooleanSchema(), true,
        'webdav_enable_search', (p, v) => p.setEnableSearch(v as bool));
    dav(
        'searchScope',
        '搜索范围',
        StringSchema(
            values: WebDAVSearchScope.values.map((e) => e.value).toList()),
        'current_with_depth',
        'webdav_search_scope',
        (p, v) => p.setSearchScope(WebDAVSearchScope.fromValue(v as String)));
    dav(
        'searchDepthLimit',
        '层级限制',
        const IntegerSchema(minimum: 1, maximum: 10),
        3,
        'webdav_search_depth_limit',
        (p, v) => p.setSearchDepthLimit(v as int));
    dav(
        'searchTargets',
        '搜索文件夹与视频',
        const ArraySchema(StringSchema(values: ['folder', 'video'])),
        ['folder', 'video'],
        'webdav_search_targets',
        (p, v) => p.setSearchTargets((v as List)
            .map((e) => WebDAVSearchTarget.fromValue(e as String))
            .toSet()),
        validate: (v) => (v as List).isNotEmpty && v.toSet().length == v.length
            ? []
            : [
                const SchemaViolation(
                    '/value', 'Search targets must be unique.')
              ]);
    dav(
        'searchTimeout',
        '搜索超时',
        const IntegerSchema(minimum: 0),
        30,
        'webdav_search_timeout',
        (p, v) => p.setSearchTimeout(WebDAVSearchTimeout.fromSeconds(v as int)),
        validate: (v) => [0, 10, 30, 60].contains(v)
            ? []
            : [
                const SchemaViolation(
                    '/value', 'Expected 0, 10, 30 or 60 seconds.')
              ]);
    dav(
        'searchRequestInterval',
        '请求间隔',
        const IntegerSchema(minimum: 0, maximum: 1000),
        100,
        'webdav_search_request_interval',
        (p, v) => p.setSearchRequestInterval(v as int));
    dav(
        'searchMaxResults',
        '最大结果数',
        const IntegerSchema(minimum: 50, maximum: 2000),
        500,
        'webdav_search_max_results',
        (p, v) => p.setSearchMaxResults(v as int));
    add('appearance.quarterlyReviewSort', '季度回顾排序',
        const StringSchema(values: ['airDate', 'commentNewest', 'commentOldest', 'ratingHigh', 'ratingLow']),
        'airDate', 'quarterly_review_sort_v1', (value) async {
          final home = classicHome();
          if (home != null) {
            await home.setReviewSort(value as String);
          } else {
            await (await SharedPreferences.getInstance()).setString('quarterly_review_sort_v1', value as String);
          }
        }, source: 'lib/themes/nipaplay/widgets/dashboard_home_page_quarterly_review_logic.dart',
        setter: '_setQuarterlyReviewSort');
    return entries;
  }

  static List<SchemaViolation> validateCapturePattern(Object? value) {
    final pattern = value as String;
    try {
      RegExp(pattern);
    } on FormatException {
      return [const SchemaViolation('/value', 'Invalid regular expression.')];
    }
    return RegExp(r'(?<!\\)\(').hasMatch(pattern)
        ? []
        : [const SchemaViolation('/value', 'A capture group is required.')];
  }

  static Future<String> authorizedPath(String path, {bool directory = false}) {
    final authorize = ApplicationSettings.authorizePath;
    if (authorize == null) {
      throw const Failure(
          FailureCode.unavailable, 'Authorized path scope is not attached.');
    }
    return authorize(path, directory: directory);
  }

  static bool _loginSetting(String id, String title) =>
      isSettingDenied('pluginSetting.$id') ||
      isSettingDenied('pluginSetting.$title') ||
      RegExp(r'password|passwd|token|secret|api[\s_-]?key|cookie|authorization|密码|密碼|密钥|密鑰|令牌|憑證|凭证',
              caseSensitive: false)
          .hasMatch('$id $title');

  List<SettingEntry> pluginEntries() => [
        for (final plugin in plugins.plugins)
          SettingEntry(
            key: 'plugins.enabled.${Uri.encodeComponent(plugin.manifest.id)}',
            title: '启用 ${plugin.manifest.name}',
            description: 'Classic 插件启用状态；启用时载入插件并调用 initialize，停用时调用 destroy。',
            schema: const BooleanSchema(),
            defaultValue:
                plugin.manifest.id == 'builtin.cn_sensitive_danmaku_filter',
            storageKey: 'plugin_enabled_ids',
            reader: 'lib/plugins/plugin_service.dart',
            writer: 'lib/plugins/plugin_service.dart#setPluginEnabled',
            decodeStorage: (raw) => raw == null
                ? plugin.manifest.id == 'builtin.cn_sensitive_danmaku_filter'
                : (raw as List).contains(plugin.manifest.id),
            read: () async {
              final raw = (await SharedPreferences.getInstance())
                  .getStringList('plugin_enabled_ids');
              return raw == null
                  ? plugin.manifest.id == 'builtin.cn_sensitive_danmaku_filter'
                  : raw.contains(plugin.manifest.id);
            },
            write: (v) =>
                plugins.setPluginEnabled(plugin.manifest.id, v as bool),
          ),
        for (final plugin in plugins.plugins)
          for (final entry in plugin.uiEntries)
            if ((entry.isSwitch || entry.isTextInput) &&
                !_loginSetting(entry.id, entry.title) &&
                !isSettingDenied('pluginSetting.${plugin.manifest.id}') &&
                !isSettingDenied(
                    'plugin_switch_setting_${plugin.manifest.id}::${entry.id}'))
              SettingEntry(
                key:
                    'plugins.settings.${Uri.encodeComponent(plugin.manifest.id)}.${Uri.encodeComponent(entry.id)}',
                title: '${plugin.manifest.name} / ${entry.title}',
                description: entry.description ?? entry.title,
                schema: entry.isSwitch
                    ? const BooleanSchema()
                    : const StringSchema(),
                defaultValue: entry.isSwitch
                    ? entry.enabled!
                    : entry.textSetting!.defaultValue ?? '',
                storageKey: entry.isSwitch
                    ? 'plugin_switch_setting_${plugin.manifest.id}::${entry.id}'
                    : '@runtime:pluginText.${plugin.manifest.id}::${entry.id}',
                storageKind: entry.isSwitch
                    ? 'shared_preferences'
                    : 'classic_plugin_service',
                reader: 'lib/plugins/plugin_service.dart',
                writer:
                    'lib/plugins/plugin_service.dart#set${entry.isSwitch ? 'Switch' : 'Text'}SettingValue',
                decodeStorage: (raw) =>
                    raw ??
                    (entry.isSwitch
                        ? entry.enabled!
                        : entry.textSetting!.defaultValue ?? ''),
                read: () async => entry.isSwitch
                    ? (await SharedPreferences.getInstance()).getBool(
                            'plugin_switch_setting_${plugin.manifest.id}::${entry.id}') ??
                        entry.enabled!
                    : plugins.getTextSettingValue(plugin.manifest.id, entry.id),
                write: (v) => entry.isSwitch
                    ? plugins.setSwitchSettingValue(
                        plugin.manifest.id, entry.id, v as bool)
                    : plugins.setTextSettingValue(
                        plugin.manifest.id, entry.id, v as String),
              ),
      ];
}
