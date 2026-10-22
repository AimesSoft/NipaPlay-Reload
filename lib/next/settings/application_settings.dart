import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/danmaku_next/next2_platform_support.dart';
import 'package:nipaplay/l10n/app_locale_utils.dart';
import 'package:nipaplay/models/danmaku_auto_load_strategy.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/player_abstraction/hwdec_type.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/plugins/danmaku/titan_danmaku_settings.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/danmaku_spoiler_filter_service.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:nipaplay/services/external_player_console_window_service.dart';
import 'package:nipaplay/utils/anime4k_shader_manager.dart';
import 'package:nipaplay/utils/crt_shader_manager.dart';
import 'package:nipaplay/utils/danmaku/style.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/external_player_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'effective.dart';
import 'registry.dart';
import 'setting_descriptions.dart';
import '../tasks/user_consent.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/utils/mpv_utils.dart';

abstract final class ApplicationSettings {
  static const _titles = <String, String>{
    'player.pauseOnBackground': '进入后台暂停',
    'player.desktopHoverSettingsMenuEnabled': '桌面悬停设置菜单',
    'player.instantHidePlayerUiEnabled': '立即隐藏播放器界面',
    'player.showMenuQuickControls': '播放器菜单快捷控制',
    'player.topSendDanmakuButtonVisible': '显示顶部发送弹幕按钮',
    'player.topSkipButtonVisible': '显示顶部跳过按钮',
    'player.topResizeButtonVisible': '显示顶部窗口适配按钮',
    'player.topFrameStepButtonsVisible': '显示顶部逐帧按钮',
    'player.chapterMarkersEnabled': '章节标记',
    'player.minimalProgressBarEnabled': '最小进度条',
    'player.minimalProgressBarColor': '最小进度条颜色',
    'player.useHardwareDecoder': '硬件解码',
    'player.hwdecMode': '硬件解码模式',
    'player.softDecodePixelFormat': '软解输出颜色格式',
    'player.introSkipEnabled': '跳过片头片尾',
    'player.timelinePreviewEnabled': '时间轴截图预览',
    'player.autoFullscreenEnabled': '播放自动全屏',
    'player.autoNextCountdownSeconds': '自动下一话倒计时',
    'player.playbackEndAction': '播放结束行为',
    'player.precacheBufferSizeMb': '预缓存大小（MB）',
    'player.precacheBufferDurationSeconds': '预缓存时长（秒）',
    'player.volumeBoost': '音量增强',
    'player.kernel': '播放器内核',
    'player.fastPlaybackStartup': '快速开始播放',
    'player.customUserAgent': '播放器 User-Agent',
    'player.externalEnabled': '使用外部播放器',
    'player.externalPath': '外部播放器路径',
    'player.externalType': '外部播放器类型',
    'player.externalDanmakuOverlay': '外部播放器弹幕外挂',
    'player.externalAutoSwitchToDanmakuConsole': '自动切换弹幕控制台',
    'player.externalShrinkWindow': '外部播放时缩小窗口',
    'player.externalConsoleWindowMode': '外部播放独立弹幕窗口',
    'player.macosNativeVideoEnabled': 'macOS 原生视频输出',
    'player.androidAudioOutput': 'Android 音频后端',
    'player.erikaAndroidOutputMode': 'Erika Android 视频输出',
    'player.doubleResolutionPlaybackEnabled': '双倍分辨率播放',
    'player.anime4kProfile': 'Anime4K 画质预设',
    'player.crtProfile': 'CRT 画质预设',
    'player.erikaUpscalerMode': 'Erika 超分辨率',
    'player.videoAspectMode': '视频画面适配模式',
    'player.screenshotSaveTarget': '截图保存目标',
    'player.screenshotQuality': '截图质量',
    'player.screenshotFormat': '截图格式',
    'player.screenshotIncludeDanmaku': '截图包含弹幕',
    'player.screenshotIncludeSubtitles': '截图包含字幕',
    'player.screenshotCropLetterbox': '截图裁剪黑边',
    'seek.stepSeconds': '快进快退步长（秒）',
    'seek.speedBoostRate': '长按倍速倍率',
    'seek.skipSeconds': '跳过时间（秒）',
    'danmaku.convertToSimplified': '弹幕转简体',
    'danmaku.autoMatchFirstSearchResultOnHashFail': '哈希匹配失败后自动选择首个结果',
    'danmaku.autoLoadStrategy': '弹幕自动加载策略',
    'danmaku.skipMatching': '跳过弹幕匹配',
    'danmaku.supersample': '弹幕超采样',
    'danmaku.trackGap': 'DFM+ 弹幕轨道间距',
    'danmaku.outlineWidth': '弹幕描边档位',
    'danmaku.rememberOffset': '切换视频保留弹幕偏移',
    'danmaku.renderEngine': '弹幕渲染引擎',
    'danmaku.nextPlusPlusEnabled': 'Next++ 优化引擎',
    'danmaku.pluginRenderer': '已安装插件的弹幕渲染器',
    'danmaku.fontFamily': '弹幕字体名称',
    'danmaku.fontFilePath': '弹幕字体文件',
    'danmaku.spoilerPreventionEnabled': '弹幕防剧透',
    'danmaku.spoilerAiApiUrl': '防剧透 AI 接口地址',
    'danmaku.spoilerAiApiFormat': '防剧透 AI 接口格式',
    'danmaku.spoilerAiModel': '防剧透 AI 模型',
    'danmaku.spoilerAiTemperature': '防剧透 AI 温度',
    'danmaku.spoilerAiDebugPrintResponse': '打印防剧透 AI 响应',
    'subtitle.srtScale': '外挂 SRT 字幕大小',
    'subtitle.srtDelaySeconds': '外挂 SRT 字幕延迟（秒）',
    'subtitle.externalColor': '外挂字幕颜色',
    'subtitle.externalFontName': '外挂字幕字体',
    'subtitle.fontDir': '字幕字体目录',
  };
  static bool Function() erikaVisible =
      () => globals.isTelevision || PlayerFactory.isHarmonyOS;

  static Schema dynamicSchema(String key, Schema fallback) => switch (key) {
        'seek.stepSeconds' => NumberSchema(
            minimum: video?.seekStepMinSeconds ?? 1 / VideoPlayerState.defaultSeekStepFrameRate,
            maximum: video?.seekStepMaxSeconds ?? VideoPlayerState.fallbackSeekStepMaxSeconds),
        'player.kernel' => StringSchema(
            values: PlayerFactory.supportedKernelTypes
                .where((v) => v != PlayerKernelType.erika || erikaVisible())
                .map((v) => v.name)
                .toList()),
        'danmaku.renderEngine' => StringSchema(
            values: DanmakuRenderEngine.values
                .where((v) =>
                    Next2PlatformSupport.isKernelSupported ||
                    (v != DanmakuRenderEngine.next2 &&
                        v != DanmakuRenderEngine.dfmPlus))
                .map((v) => v.name)
                .toList()),
        'danmaku.pluginRenderer' => StringSchema(values: [
            '',
            ...DanmakuKernelFactory.availablePluginRenderers
                .map((v) => v.selectionId)
          ]),
        _ => fallback,
      };

  static bool locallyVisible(String key) {
    final kernel = PlayerFactory.getKernelType();
    final native = globals.isTvOS || kernel == PlayerKernelType.erika;
    final renderer = DanmakuKernelFactory.getKernelType();
    if (key == 'danmaku.manualOffset') return video != null;
    if (key.startsWith('danmaku.titan.')) {
      return DanmakuKernelFactory.activePluginRenderer?.usesTitanSettings ??
          false;
    }
    if (key == 'danmaku.pluginRenderer') {
      return !native &&
          DanmakuKernelFactory.availablePluginRenderers.isNotEmpty;
    }
    if (key == 'danmaku.renderEngine') return !native;
    if (key == 'danmaku.nextPlusPlusEnabled') {
      return !native &&
          DanmakuKernelFactory.activePluginRenderer == null &&
          renderer == DanmakuRenderEngine.nipaplayNext;
    }
    if (key == 'danmaku.supersample') {
      return !native &&
          DanmakuKernelFactory.activePluginRenderer == null &&
          (renderer == DanmakuRenderEngine.next2 ||
              renderer == DanmakuRenderEngine.dfmPlus);
    }
    if (key == 'player.timelinePreviewEnabled' ||
        key == 'player.precacheBufferDurationSeconds') {
      return kernel == PlayerKernelType.mdk;
    }
    if (key == 'player.chapterMarkersEnabled') {
      return kernel == PlayerKernelType.mediaKit;
    }
    if (key == 'player.precacheBufferSizeMb') {
      return kernel == PlayerKernelType.mediaKit;
    }
    if (key == 'player.erikaUpscalerMode') {
      return kernel == PlayerKernelType.erika;
    }
    if (key == 'player.useHardwareDecoder') {
      return kernel == PlayerKernelType.mdk ||
          kernel == PlayerKernelType.mediaKit;
    }
    if (key == 'player.pauseOnBackground') return globals.isPhone;
    if ([
      'player.desktopHoverSettingsMenuEnabled',
      'player.instantHidePlayerUiEnabled',
      'player.autoFullscreenEnabled'
    ].contains(key)) {
      return globals.isDesktop;
    }
    if (key.startsWith('player.external')) return globals.isDesktop;
    if (key == 'player.volumeBoost') return video?.supportsVolumeBoost ?? false;
    if ([
      'player.anime4kProfile',
      'player.crtProfile',
      'player.doubleResolutionPlaybackEnabled'
    ].contains(key)) {
      return kernel == PlayerKernelType.mediaKit;
    }
    return true;
  }

  static JsonMap remoteParameter(String key) =>
      entries().firstWhere((entry) => entry.key == key).remote!;
  static VideoPlayerState? video;
  static SettingsProvider? settings;
  static Future<String> Function(String path, {bool directory})? authorizePath;
  static VideoPlayerState get player =>
      video ??
      (throw const Failure(
          FailureCode.unavailable, 'Player settings are not attached.'));
  static SettingsProvider get preferences =>
      settings ??
      (throw const Failure(
          FailureCode.unavailable, 'Classic preferences are not attached.'));

  static Future<void> setManualOffset(double value) async {
    player.setManualDanmakuOffset(value);
  }

  static Future<void> setDanmakuFont(String path) async {
    if (path.isEmpty) {
      await player.resetDanmakuFont();
      return;
    }
    if (!await player.importDanmakuFontFile(path)) {
      throw const Failure(
          FailureCode.invalidInput, 'Could not import the font file.');
    }
  }

  static Future<void> setPluginRenderer(String id) async {
    if (id.isEmpty) {
      await DanmakuKernelFactory.saveKernelType(
          DanmakuKernelFactory.getKernelType());
    } else {
      await DanmakuKernelFactory.savePluginRenderer(id);
    }
  }

  static bool defaultConvertToSimplified() =>
      !AppLocaleUtils.isTraditionalChineseLocale(
          PlatformDispatcher.instance.locale);
  static double defaultSupersample() {
    if (globals.isIPad) return 1.5;
    if (globals.isTablet ||
        (globals.isDesktop &&
            PlatformDispatcher.instance.views.first.devicePixelRatio < 2.0)) {
      return 2.0;
    }
    return 0.0;
  }

  static Object? decodeSupersample(Object? raw) => raw is num
      ? raw.toDouble()
      : raw is String
          ? double.parse(raw)
          : raw is bool
              ? (raw ? 2.0 : 0.0)
              : defaultSupersample();

  static String decodeIndexedEnum<T extends Enum>(
      Object? raw, List<T> values, T defaultValue,
      {bool clamp = false}) {
    final index = raw as int? ?? defaultValue.index;
    if (clamp) return values[index.clamp(0, values.length - 1)].name;
    return index >= 0 && index < values.length
        ? values[index].name
        : defaultValue.name;
  }

  static int decodeCompatibleInt(Object? raw, int defaultValue) =>
      switch (raw) {
        int() => raw,
        bool() => raw ? 1 : 0,
        String() => int.tryParse(raw.trim()) ??
            switch (raw.trim().toLowerCase()) {
              'true' => 1,
              'false' => 0,
              _ => defaultValue,
            },
        _ => defaultValue,
      };

  static Future<Object?> readPreference(
      String key, String physicalKey, Object? Function(Object?) decode) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(physicalKey);
    if (key == 'danmaku.supersample') {
      return decode(raw ?? prefs.get('danmaku_supersample'));
    }
    if (key == 'danmaku.autoLoadStrategy' || key == 'danmaku.skipMatching') {
      final resolved = resolveDanmakuAutoLoadSettings(
          persistedStrategy: prefs.getString('danmaku_auto_load_strategy'),
          persistedSkipMatching: prefs.getBool('skip_danmaku_matching'),
          legacyAutoMatchOnPlay: prefs.getBool('danmaku_auto_match_on_play'));
      return key == 'danmaku.autoLoadStrategy'
          ? resolved.strategy.name
          : resolved.skipMatching;
    }
    if (key == 'player.externalType' && raw == null) {
      final path = prefs.getString('external_player_path') ?? '';
      return path.isEmpty
          ? ExternalPlayerType.unset.name
          : detectExternalPlayerType(path).name;
    }
    if (key == 'danmaku.convertToSimplified' &&
        raw == null &&
        (prefs.getString('app_language_mode') ?? 'auto') != 'auto') {
      return true;
    }
    return decode(raw);
  }

  static Object? decodeTitan(Object? raw, String field, Object? fallback) =>
      raw == null
          ? fallback
          : (jsonDecode(raw as String) as Map)[field] ?? fallback;
  static String settingColorHex(int value) =>
      '#${value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  static Color parseSettingColor(String value) =>
      Color(int.parse(value.replaceFirst('#', ''), radix: 16));

  static List<SettingEntry> entries() {
    final entries = <SettingEntry>[];
    void add(
      String key,
      String title,
      Schema schema,
      Object? defaultValue,
      String storageKey,
      Future<void> Function(Object?) write, {
      String scope = 'user',
      String apply = 'immediate',
      String source =
          'lib/utils/video_player_state/video_player_state_preferences.dart',
      required String setter,
      Object? Function(Object?)? decode,
      bool Function()? visible,
      JsonMap? remote,
      bool path = false,
      bool directory = false,
      Future<Object?> Function()? runtimeRead,
    }) {
      final displayTitle = _titles[key] ?? title;
      final entryApply =
          ['player.hwdecMode', 'player.softDecodePixelFormat'].contains(key)
              ? 'reload_player'
              : apply;
      Object? defaultForEntry() => key == 'danmaku.convertToSimplified'
          ? settings?.defaultDanmakuConvertToSimplified ??
              defaultConvertToSimplified()
          : defaultValue;
      Object? decodeValue(Object? raw) =>
          decode == null ? raw ?? defaultForEntry() : decode(raw);
      entries.add(SettingEntry(
          key: key,
          title: displayTitle,
          description: describeWithApply(
              applicationSettingDescriptions[key] ?? '', entryApply),
          schema: schema,
          dynamicSchema: () => dynamicSchema(key, schema),
          validateValue: (value) {
            if (key == 'danmaku.fontSize' && value != 0 &&
                (value as num) < DanmakuStyle.minDanmakuFontSize) {
              return [const SchemaViolation('/value', 'Use 0 for automatic size or 12–60 pixels.')];
            }
            if (key == 'player.minimalProgressBarColor' &&
                ![0xFFFF7274, 0xFF40C7FF, 0xFF6DFF69, 0xFF4CFFB1, 0xFFFFFFFF].contains(value)) {
              return [const SchemaViolation('/value', 'Choose a Classic preset color.')];
            }
            if (key == 'danmaku.supersample' &&
                ![0.0, 1.5, 2.0].contains(value)) {
              return [
                const SchemaViolation('/value', 'Expected 0.0, 1.5 or 2.0.')
              ];
            }
            if ([
                  'subtitle.color',
                  'subtitle.borderColor',
                  'subtitle.shadowColor',
                  'subtitle.externalColor'
                ].contains(key) &&
                !RegExp(r'^#[0-9A-Fa-f]{8}$').hasMatch(value as String)) {
              return [const SchemaViolation('/value', 'Expected #AARRGGBB.')];
            }
            if (key == 'danmaku.outlineWidth' &&
                ![0.0, 1.0, 2.0].contains(value)) {
              return [
                const SchemaViolation(
                    '/value', 'Expected outline level 0, 1 or 2.')
              ];
            }
            return [];
          },
          defaultValue: defaultValue,
          dynamicDefaultValue:
              key == 'danmaku.convertToSimplified' ? defaultForEntry : null,
          storageKey: storageKey,
          scope: scope,
          apply: entryApply,
          reader: source,
          writer: '$source#$setter',
          visible: () => locallyVisible(key) && (visible?.call() ?? true),
          effective: EffectiveRules.resolve,
          remote: remote,
          decodeStorage: decodeValue,
          read:
              runtimeRead ?? () => readPreference(key, storageKey, decodeValue),
          write: (value) async {
            if (path && (value as String).isNotEmpty) {
              final authorize = authorizePath;
              if (authorize == null) {
                throw const Failure(FailureCode.unavailable,
                    'Authorized path scope is not attached.');
              }
              value = await authorize(value, directory: directory);
            }
            await write(value);
          }));
    }

    add(
        'player.pauseOnBackground',
        'player.pauseOnBackground',
        const BooleanSchema(),
        globals.isMobilePlatform,
        'pause_on_background', (value) async {
      await player.setPauseOnBackground(value as bool);
    },
        setter: 'setPauseOnBackground',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'player.desktopHoverSettingsMenuEnabled',
        'player.desktopHoverSettingsMenuEnabled',
        const BooleanSchema(),
        false,
        'desktop_hover_settings_menu_enabled', (value) async {
      await player.setDesktopHoverSettingsMenuEnabled(value as bool);
    },
        setter: 'setDesktopHoverSettingsMenuEnabled',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'player.instantHidePlayerUiEnabled',
        'player.instantHidePlayerUiEnabled',
        const BooleanSchema(),
        false,
        'instant_hide_player_ui_enabled', (value) async {
      await player.setInstantHidePlayerUiEnabled(value as bool);
    },
        setter: 'setInstantHidePlayerUiEnabled',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'player.showMenuQuickControls',
        'player.showMenuQuickControls',
        const BooleanSchema(),
        false,
        'show_player_menu_quick_controls', (value) async {
      await player.setShowPlayerMenuQuickControls(value as bool);
    },
        setter: 'setShowPlayerMenuQuickControls',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'player.topSendDanmakuButtonVisible',
        'player.topSendDanmakuButtonVisible',
        const BooleanSchema(),
        true,
        'player_top_send_danmaku_button_visible', (value) async {
      await player.setPlayerTopSendDanmakuButtonVisible(value as bool);
    },
        setter: 'setPlayerTopSendDanmakuButtonVisible',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'player.topSkipButtonVisible',
        'player.topSkipButtonVisible',
        const BooleanSchema(),
        false,
        'player_top_skip_button_visible', (value) async {
      await player.setPlayerTopSkipButtonVisible(value as bool);
    },
        setter: 'setPlayerTopSkipButtonVisible',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'player.topResizeButtonVisible',
        'player.topResizeButtonVisible',
        const BooleanSchema(),
        false,
        'player_top_resize_button_visible', (value) async {
      await player.setPlayerTopResizeButtonVisible(value as bool);
    },
        setter: 'setPlayerTopResizeButtonVisible',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'player.topFrameStepButtonsVisible',
        'player.topFrameStepButtonsVisible',
        const BooleanSchema(),
        false,
        'player_top_frame_step_buttons_visible', (value) async {
      await player.setPlayerTopFrameStepButtonsVisible(value as bool);
    },
        setter: 'setPlayerTopFrameStepButtonsVisible',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add('player.chapterMarkersEnabled', 'player.chapterMarkersEnabled',
        const BooleanSchema(), true, 'chapter_markers_enabled', (value) async {
      await player.setChapterMarkersEnabled(value as bool);
    },
        setter: 'setChapterMarkersEnabled',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'player.minimalProgressBarEnabled',
        'player.minimalProgressBarEnabled',
        const BooleanSchema(),
        false,
        'minimal_progress_bar_enabled', (value) async {
      await player.setMinimalProgressBarEnabled(value as bool);
    },
        setter: 'setMinimalProgressBarEnabled',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add('player.useHardwareDecoder', 'player.useHardwareDecoder',
        const BooleanSchema(), true, 'use_hardware_decoder', (value) async {
      await player.setHardwareDecoderEnabled(value as bool);
    },
        setter: 'setHardwareDecoderEnabled',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'device');
    add('player.introSkipEnabled', 'player.introSkipEnabled',
        const BooleanSchema(), true, 'intro_skip_enabled', (value) async {
      await player.setIntroSkipEnabled(value as bool);
    },
        setter: 'setIntroSkipEnabled',
        source:
            'lib/utils/video_player_state/video_player_state_intro_skip.dart',
        scope: 'user');
    add(
        'player.timelinePreviewEnabled',
        'player.timelinePreviewEnabled',
        const BooleanSchema(),
        false,
        'timeline_preview_enabled', (value) async {
      if (value == true && !player.timelinePreviewEnabled &&
          !await showUserConsent('开启警告',
              '开启时间轴截图预览会在后台生成截图，可能导致播放卡顿或性能下降。要开启吗？', '开启')) {
        throw const Failure(FailureCode.conflict, '用户没有同意开启时间轴截图预览');
      }
      await player.setTimelinePreviewEnabled(value as bool);
    },
        setter: 'setTimelinePreviewEnabled',
        source:
            'lib/utils/video_player_state/video_player_state_timeline_preview.dart',
        scope: 'user');
    add('player.autoFullscreenEnabled', 'player.autoFullscreenEnabled',
        const BooleanSchema(), false, 'auto_fullscreen_enable', (value) async {
      await player.setAutoFullscreenEnabled(value as bool);
    },
        setter: 'setAutoFullscreenEnabled',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'player.doubleResolutionPlaybackEnabled',
        'player.doubleResolutionPlaybackEnabled',
        const BooleanSchema(),
        false,
        'double_resolution_playback', (value) async {
      await player.setDoubleResolutionPlaybackEnabled(value as bool);
    },
        setter: 'setDoubleResolutionPlaybackEnabled',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'device');
    add(
        'player.screenshotIncludeDanmaku',
        'player.screenshotIncludeDanmaku',
        const BooleanSchema(),
        true,
        'screenshot_include_danmaku', (value) async {
      await player.setScreenshotCaptureIncludesDanmaku(value as bool);
    },
        setter: 'setScreenshotCaptureIncludesDanmaku',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'player.screenshotIncludeSubtitles',
        'player.screenshotIncludeSubtitles',
        const BooleanSchema(),
        true,
        'screenshot_include_subtitles', (value) async {
      await player.setScreenshotCaptureIncludesSubtitles(value as bool);
    },
        setter: 'setScreenshotCaptureIncludesSubtitles',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'player.screenshotCropLetterbox',
        'player.screenshotCropLetterbox',
        const BooleanSchema(),
        true,
        'screenshot_crop_letterbox', (value) async {
      await player.setScreenshotCropLetterbox(value as bool);
    },
        setter: 'setScreenshotCropLetterbox',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'playback.rate',
        '播放速度',
        const NumberSchema(minimum: 0.01, maximum: 5.0),
        1.0,
        'playback_rate', (value) async {
      await player.setPlaybackRate((value as num).toDouble());
    },
        setter: 'setPlaybackRate',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {'label': '播放速度', 'type': 'double', 'step': 0.05});
    add(
        'seek.stepSeconds',
        'seek.stepSeconds',
        const NumberSchema(minimum: 1 / 24, maximum: 600),
        10.0,
        'seek_step_seconds', (value) async {
      await player.setSeekStepSeconds((value as num).toDouble());
    },
        setter: 'setSeekStepSeconds',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart');
    add(
        'seek.speedBoostRate',
        'seek.speedBoostRate',
        const NumberSchema(minimum: 0.01, maximum: 5.0),
        2.0,
        'speed_boost_rate', (value) async {
      await player.setSpeedBoostRate((value as num).toDouble());
    },
        setter: 'setSpeedBoostRate',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart');
    add(
        'seek.skipSeconds',
        'seek.skipSeconds',
        const IntegerSchema(minimum: 10, maximum: 600),
        90,
        'skip_seconds', (value) async {
      await player.setSkipSeconds((value as num).toInt());
    },
        setter: 'setSkipSeconds',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart');
    add(
        'player.autoNextCountdownSeconds',
        'player.autoNextCountdownSeconds',
        const IntegerSchema(minimum: 0, maximum: 15),
        3,
        'auto_next_countdown_seconds', (value) async {
      await player.setAutoNextCountdownSeconds((value as num).toInt());
    },
        setter: 'setAutoNextCountdownSeconds',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart');
    add(
        'player.precacheBufferSizeMb',
        'player.precacheBufferSizeMb',
        const IntegerSchema(minimum: 4, maximum: 512),
        32,
        'player_precache_buffer_size_mb', (value) async {
      await player.setPrecacheBufferSizeMb((value as num).toInt());
    },
        setter: 'setPrecacheBufferSizeMb',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'device');
    add(
        'player.precacheBufferDurationSeconds',
        'player.precacheBufferDurationSeconds',
        const IntegerSchema(minimum: 1, maximum: 120),
        4,
        'player_precache_buffer_duration_seconds', (value) async {
      await player.setPrecacheBufferDurationSeconds((value as num).toInt());
    },
        setter: 'setPrecacheBufferDurationSeconds',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'device');
    add(
        'player.volumeBoost',
        'player.volumeBoost',
        const NumberSchema(minimum: 1, maximum: 2),
        1.0,
        'player_volume_boost', (value) async {
      await player.setVolumeBoost((value as num).toDouble());
    }, setter: 'setVolumeBoost', source: 'lib/utils/video_player_state.dart');
    add(
        'player.minimalProgressBarColor',
        'player.minimalProgressBarColor',
        const IntegerSchema(minimum: 0, maximum: 0xFFFFFFFF),
        0xFFFF7274,
        'minimal_progress_bar_color', (value) async {
      await player.setMinimalProgressBarColor((value as num).toInt());
    },
        setter: 'setMinimalProgressBarColor',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart');
    add('player.volume', '播放音量',
        const NumberSchema(minimum: 0, maximum: 1), 0.5,
        globals.isMobilePlatform ? '@runtime:player.volume' : 'player_volume',
        (value) => player.setPlaybackVolume((value as num).toDouble()),
        setter: 'setPlaybackVolume', scope: 'device',
        visible: () => video != null,
        runtimeRead: globals.isMobilePlatform ? () async => player.currentSystemVolume : null);
    add('player.brightness', '播放亮度',
        const NumberSchema(minimum: 0, maximum: 1), 0.5,
        '@runtime:player.brightness',
        (value) => player.setPlaybackBrightness((value as num).toDouble()),
        setter: 'setPlaybackBrightness', scope: 'device',
        visible: () => video != null && globals.isMobilePlatform,
        runtimeRead: () async => player.currentScreenBrightness);
    add(
        'player.playbackEndAction',
        'player.playbackEndAction',
        StringSchema(
            values: PlaybackEndAction.values.map((v) => v.name).toList()),
        PlaybackEndAction.autoNext.name,
        'playback_end_action', (value) async {
      await player.setPlaybackEndAction(
          PlaybackEndAction.values.byName(value as String));
    },
        setter: 'setPlaybackEndAction',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'player.anime4kProfile',
        'player.anime4kProfile',
        StringSchema(values: Anime4KProfile.values.map((v) => v.name).toList()),
        Anime4KProfile.off.name,
        'anime4k_profile', (value) async {
      await player
          .setAnime4KProfile(Anime4KProfile.values.byName(value as String));
    },
        setter: 'setAnime4KProfile',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'device',
        decode: (raw) => decodeIndexedEnum(
            decodeCompatibleInt(raw, Anime4KProfile.off.index),
            Anime4KProfile.values,
            Anime4KProfile.off));
    add(
        'player.crtProfile',
        'player.crtProfile',
        StringSchema(values: CrtProfile.values.map((v) => v.name).toList()),
        CrtProfile.off.name,
        'crt_profile', (value) async {
      await player.setCrtProfile(CrtProfile.values.byName(value as String));
    },
        setter: 'setCrtProfile',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'device',
        decode: (raw) => decodeIndexedEnum(
            decodeCompatibleInt(raw, CrtProfile.off.index),
            CrtProfile.values,
            CrtProfile.off));
    add(
        'player.erikaUpscalerMode',
        'player.erikaUpscalerMode',
        StringSchema(
            values: PlayerUpscalerMode.values.map((v) => v.name).toList()),
        PlayerUpscalerMode.off.name,
        'erika_upscaler_mode', (value) async {
      await player.setErikaUpscalerMode(
          PlayerUpscalerMode.values.byName(value as String));
    },
        setter: 'setErikaUpscalerMode',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'device',
        decode: (raw) => decodeIndexedEnum(
            raw, PlayerUpscalerMode.values, PlayerUpscalerMode.off));
    add(
        'player.hwdecMode',
        'player.hwdecMode',
        StringSchema(values: HwDecType.values.map((v) => v.name).toList()),
        HwDecType.auto.name,
        'hwdec_mode', (value) async {
      await player.setHwdecMode(HwDecType.values.byName(value as String));
    },
        setter: 'setHwdecMode',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'device');
    add(
        'player.videoAspectMode',
        'player.videoAspectMode',
        StringSchema(
            values: VideoAspectMode.values.map((v) => v.name).toList()),
        VideoAspectMode.contain.name,
        'video_aspect_mode', (value) async {
      await player
          .setVideoAspectMode(VideoAspectMode.values.byName(value as String));
    },
        setter: 'setVideoAspectMode',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add(
        'player.screenshotSaveTarget',
        'player.screenshotSaveTarget',
        StringSchema(
            values: ScreenshotSaveTarget.values.map((v) => v.name).toList()),
        ScreenshotSaveTarget.file.name,
        'screenshot_save_target', (value) async {
      await player.setScreenshotSaveTarget(
          ScreenshotSaveTarget.values.byName(value as String));
    },
        setter: 'setScreenshotSaveTarget',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user',
        decode: (raw) =>
            ScreenshotSaveTargetDisplay.fromPrefs(raw as int?).name);
    add(
        'player.screenshotQuality',
        'player.screenshotQuality',
        StringSchema(
            values: ScreenshotQuality.values.map((v) => v.name).toList()),
        ScreenshotQuality.ultra.name,
        'screenshot_quality', (value) async {
      await player.setScreenshotQuality(
          ScreenshotQuality.values.byName(value as String));
    },
        setter: 'setScreenshotQuality',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user',
        decode: (raw) => ScreenshotQualityDisplay.fromPrefs(raw as int?).name);
    add(
        'player.screenshotFormat',
        'player.screenshotFormat',
        StringSchema(
            values: ScreenshotFormat.values.map((v) => v.name).toList()),
        ScreenshotFormat.jpeg.name,
        'screenshot_format', (value) async {
      await player
          .setScreenshotFormat(ScreenshotFormat.values.byName(value as String));
    },
        setter: 'setScreenshotFormat',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'user');
    add('player.softDecodePixelFormat', 'player.softDecodePixelFormat',
        const StringSchema(), '', 'soft_decode_pixel_format', (value) async {
      await player.setSoftDecodePixelFormat(value as String);
    },
        setter: 'setSoftDecodePixelFormat',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        scope: 'device');
    add('player.fastPlaybackStartup', 'player.fastPlaybackStartup',
        const BooleanSchema(), false, 'fast_playback_startup', (value) async {
      await preferences.setFastPlaybackStartup(value as bool);
    },
        setter: 'setFastPlaybackStartup',
        source: 'lib/providers/settings_provider.dart');
    add('player.externalEnabled', 'player.externalEnabled',
        const BooleanSchema(), false, 'external_player_enabled', (value) async {
      if (value == true && preferences.externalPlayerPath.trim().isEmpty) {
        final path = await detectInstalledMpv() ??
            await FilePickerService().pickExternalPlayerExecutable();
        if (path == null || path.trim().isEmpty) {
          throw const Failure(FailureCode.conflict, '用户没有选择外部播放器');
        }
        await preferences.setExternalPlayerPath(path);
        await preferences.setExternalPlayerType(detectExternalPlayerType(path));
      }
      await preferences.setUseExternalPlayer(value as bool);
    },
        setter: 'setUseExternalPlayer',
        source: 'lib/providers/settings_provider.dart');
    add(
        'player.externalDanmakuOverlay',
        'player.externalDanmakuOverlay',
        const BooleanSchema(),
        true,
        'external_player_danmaku_overlay', (value) async {
      await preferences.setExternalPlayerDanmakuOverlay(value as bool);
    },
        setter: 'setExternalPlayerDanmakuOverlay',
        source: 'lib/providers/settings_provider.dart');
    add(
        'player.externalAutoSwitchToDanmakuConsole',
        'player.externalAutoSwitchToDanmakuConsole',
        const BooleanSchema(),
        true,
        'external_player_auto_switch_to_danmaku_console', (value) async {
      await preferences
          .setExternalPlayerAutoSwitchToDanmakuConsole(value as bool);
    },
        setter: 'setExternalPlayerAutoSwitchToDanmakuConsole',
        source: 'lib/providers/settings_provider.dart');
    add(
        'player.externalShrinkWindow',
        'player.externalShrinkWindow',
        const BooleanSchema(),
        false,
        'external_player_shrink_window', (value) async {
      await preferences.setExternalPlayerShrinkWindow(value as bool);
    },
        setter: 'setExternalPlayerShrinkWindow',
        source: 'lib/providers/settings_provider.dart');
    add(
        'player.externalConsoleWindowMode',
        'player.externalConsoleWindowMode',
        const BooleanSchema(),
        false,
        'external_player_console_window_mode', (value) async {
      await preferences.setExternalPlayerConsoleWindowMode(value as bool);
      if (value && ExternalPlayerConsoleService.hasActiveSession) {
        await ExternalPlayerConsoleWindowService.instance.showControlsWindow();
      } else if (!value) {
        await ExternalPlayerConsoleWindowService.instance.closeAll();
      }
    },
        setter: 'setExternalPlayerConsoleWindowMode',
        source: 'lib/providers/settings_provider.dart');
    add(
        'danmaku.convertToSimplified',
        'danmaku.convertToSimplified',
        const BooleanSchema(),
        defaultConvertToSimplified(),
        'danmaku_convert_to_simplified', (value) async {
      await preferences.setDanmakuConvertToSimplified(value as bool);
    },
        setter: 'setDanmakuConvertToSimplified',
        source: 'lib/providers/settings_provider.dart');
    add(
        'danmaku.autoMatchFirstSearchResultOnHashFail',
        'danmaku.autoMatchFirstSearchResultOnHashFail',
        const BooleanSchema(),
        true,
        'danmaku_auto_match_first_search_result_on_hash_fail', (value) async {
      await preferences
          .setAutoMatchDanmakuFirstSearchResultOnHashFail(value as bool);
    },
        setter: 'setAutoMatchDanmakuFirstSearchResultOnHashFail',
        source: 'lib/providers/settings_provider.dart');
    add('danmaku.skipMatching', 'danmaku.skipMatching', const BooleanSchema(),
        false, 'skip_danmaku_matching', (value) async {
      await preferences.setSkipDanmakuMatching(value as bool);
    },
        setter: 'setSkipDanmakuMatching',
        source: 'lib/providers/settings_provider.dart');
    add('player.externalPath', 'player.externalPath', const StringSchema(), '',
        'external_player_path', (value) async {
      final path = value as String;
      if (path.isNotEmpty && (!p.isAbsolute(path) ||
          await FileSystemEntity.type(path) == FileSystemEntityType.notFound)) {
        throw const Failure(FailureCode.invalidInput, 'Use an existing absolute player executable or application bundle path.');
      }
      await preferences.setExternalPlayerPath(path);
    },
        setter: 'setExternalPlayerPath',
        source: 'lib/providers/settings_provider.dart',
        scope: 'device');
    add(
        'player.externalType',
        'player.externalType',
        StringSchema(
            values: ExternalPlayerType.values.map((v) => v.name).toList()),
        ExternalPlayerType.unset.name,
        'external_player_type', (value) async {
      await preferences.setExternalPlayerType(
          ExternalPlayerType.values.byName(value as String));
    },
        setter: 'setExternalPlayerType',
        source: 'lib/providers/settings_provider.dart');
    add(
        'danmaku.autoLoadStrategy',
        'danmaku.autoLoadStrategy',
        StringSchema(
            values: DanmakuAutoLoadStrategy.values
                .where((v) => v.name != 'manual')
                .map((v) => v.name)
                .toList()),
        DanmakuAutoLoadStrategy.remoteAndLocal.name,
        'danmaku_auto_load_strategy', (value) async {
      await preferences.setDanmakuAutoLoadStrategy(
          DanmakuAutoLoadStrategy.values.byName(value as String));
    },
        setter: 'setDanmakuAutoLoadStrategy',
        source: 'lib/providers/settings_provider.dart');
    add(
        'danmaku.supersample',
        'danmaku.supersample',
        const NumberSchema(minimum: 0, maximum: 2),
        defaultSupersample(),
        'danmaku_supersample_v2', (value) async {
      await preferences.setDanmakuSupersample((value as num).toDouble());
    },
        setter: 'setDanmakuSupersample',
        source: 'lib/providers/settings_provider.dart',
        decode: (raw) => decodeSupersample(raw));
    add(
        'player.kernel',
        'player.kernel',
        StringSchema(
            values: PlayerKernelType.values.map((v) => v.name).toList()),
        PlayerFactory.defaultKernelType.name,
        'player_kernel_type', (value) async {
      await PlayerFactory.saveKernelType(
          PlayerKernelType.values.byName(value as String));
    },
        setter: 'saveKernelType',
        source: 'lib/player_abstraction/player_factory.dart',
        scope: 'device',
        apply: 'reload_player',
        decode: (raw) => raw == null
            ? PlayerFactory.defaultKernelType.name
            : PlayerKernelType.values[(raw as num).toInt()].name);
    add(
        'player.macosNativeVideoEnabled',
        'player.macosNativeVideoEnabled',
        const BooleanSchema(),
        false,
        'macos_native_video_enabled', (value) async {
      await PlayerFactory.saveMacOSNativeVideoEnabled(value as bool);
    },
        setter: 'saveMacOSNativeVideoEnabled',
        source: 'lib/player_abstraction/player_factory.dart',
        scope: 'device',
        apply: 'reload_player',
        visible: () =>
            !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS);
    add(
        'player.androidAudioOutput',
        'player.androidAudioOutput',
        const StringSchema(values: ['opensles', 'audiotrack']),
        'opensles',
        'android_audio_output', (value) async {
      await PlayerFactory.saveAndroidAudioOutput(value as String);
    },
        setter: 'saveAndroidAudioOutput',
        source: 'lib/player_abstraction/player_factory.dart',
        scope: 'device',
        apply: 'restart_app',
        visible: () =>
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    add(
        'player.erikaAndroidOutputMode',
        'player.erikaAndroidOutputMode',
        StringSchema(
            values: PlayerErikaAndroidOutputMode.values
                .map((v) => v.name)
                .toList()),
        PlayerErikaAndroidOutputMode.sdr.name,
        'erika_android_output_mode', (value) async {
      await PlayerFactory.saveErikaAndroidOutputMode(
          PlayerErikaAndroidOutputMode.values.byName(value as String));
    },
        setter: 'saveErikaAndroidOutputMode',
        source: 'lib/player_abstraction/player_factory.dart',
        scope: 'device',
        apply: 'reload_player',
        decode: (raw) => decodeIndexedEnum(
            raw,
            PlayerErikaAndroidOutputMode.values,
            PlayerErikaAndroidOutputMode.sdr),
        visible: () =>
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    add('player.customUserAgent', 'player.customUserAgent',
        const StringSchema(), '', 'custom_player_ua', (value) async {
      await PlayerFactory.saveCustomPlayerUA(value as String);
    },
        setter: 'saveCustomPlayerUA',
        source: 'lib/player_abstraction/player_factory.dart',
        apply: 'reload_player');
    add('danmaku.visible', '显示弹幕', const BooleanSchema(), true,
        'danmaku_visible', (value) async {
      await player.setDanmakuVisible(value as bool);
    },
        setter: 'setDanmakuVisible',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {'label': '显示弹幕', 'type': 'bool'});
    add('danmaku.showDensityChart', '显示弹幕密度图', const BooleanSchema(), false,
        'show_danmaku_density_chart', (value) async {
      await player.setShowDanmakuDensityChart(value as bool);
    },
        setter: 'setShowDanmakuDensityChart',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {'label': '显示弹幕密度图', 'type': 'bool'});
    add('danmaku.randomColor', '弹幕随机染色', const BooleanSchema(), false,
        'danmaku_random_color_enabled', (value) async {
      await player.setDanmakuRandomColorEnabled(value as bool);
    },
        setter: 'setDanmakuRandomColorEnabled',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {'label': '弹幕随机染色', 'type': 'bool'});
    add('danmaku.stacking', '启用弹幕堆叠', const BooleanSchema(), false,
        'danmaku_stacking', (value) async {
      await player.setDanmakuStacking(value as bool);
    },
        setter: 'setDanmakuStacking',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {'label': '启用弹幕堆叠', 'type': 'bool'});
    add('danmaku.merge', '合并弹幕', const BooleanSchema(), false, 'merge_danmaku',
        (value) async {
      await player.setMergeDanmaku(value as bool);
    },
        setter: 'setMergeDanmaku',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {'label': '合并弹幕', 'type': 'bool'});
    add('danmaku.blockTop', '屏蔽顶部弹幕', const BooleanSchema(), false,
        'block_top_danmaku', (value) async {
      await player.setBlockTopDanmaku(value as bool);
    },
        setter: 'setBlockTopDanmaku',
        source:
            'lib/utils/video_player_state/video_player_state_subtitles.dart',
        remote: {'label': '屏蔽顶部弹幕', 'type': 'bool'});
    add('danmaku.blockBottom', '屏蔽底部弹幕', const BooleanSchema(), false,
        'block_bottom_danmaku', (value) async {
      await player.setBlockBottomDanmaku(value as bool);
    },
        setter: 'setBlockBottomDanmaku',
        source:
            'lib/utils/video_player_state/video_player_state_subtitles.dart',
        remote: {'label': '屏蔽底部弹幕', 'type': 'bool'});
    add('danmaku.blockScroll', '屏蔽滚动弹幕', const BooleanSchema(), false,
        'block_scroll_danmaku', (value) async {
      await player.setBlockScrollDanmaku(value as bool);
    },
        setter: 'setBlockScrollDanmaku',
        source:
            'lib/utils/video_player_state/video_player_state_subtitles.dart',
        remote: {'label': '屏蔽滚动弹幕', 'type': 'bool'});
    add('danmaku.timelineEnabled', '时间轴告知弹幕', const BooleanSchema(), true,
        'timeline_danmaku_enabled', (value) async {
      await player.toggleTimelineDanmaku(value as bool);
    },
        setter: 'toggleTimelineDanmaku',
        source:
            'lib/utils/video_player_state/video_player_state_subtitles.dart',
        remote: {'label': '时间轴告知弹幕', 'type': 'bool'});
    add('danmaku.rememberOffset', 'danmaku.rememberOffset',
        const BooleanSchema(), false, 'remember_danmaku_offset', (value) async {
      await player.setRememberDanmakuOffset(value as bool);
    },
        setter: 'setRememberDanmakuOffset',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart');
    add(
        'danmaku.spoilerPreventionEnabled',
        'danmaku.spoilerPreventionEnabled',
        const BooleanSchema(),
        false,
        'spoiler_prevention_enabled', (value) async {
      await player.setSpoilerPreventionEnabled(value as bool);
    },
        setter: 'setSpoilerPreventionEnabled',
        source:
            'lib/utils/video_player_state/video_player_state_subtitles.dart');
    add(
        'danmaku.spoilerAiDebugPrintResponse',
        'danmaku.spoilerAiDebugPrintResponse',
        const BooleanSchema(),
        false,
        'spoiler_ai_debug_print_response', (value) async {
      await player.setSpoilerAiDebugPrintResponse(value as bool);
    },
        setter: 'setSpoilerAiDebugPrintResponse',
        source:
            'lib/utils/video_player_state/video_player_state_subtitles.dart');
    add('danmaku.opacity', '弹幕透明度', const NumberSchema(minimum: 0, maximum: 1),
        1.0, 'danmaku_opacity', (value) async {
      await player.setDanmakuOpacity((value as num).toDouble());
    },
        setter: 'setDanmakuOpacity',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {
          'label': '弹幕透明度',
          'type': 'double',
          'min': 0,
          'max': 1,
          'step': 0.01
        });
    add(
        'danmaku.fontSize',
        '弹幕字体大小',
        const NumberSchema(minimum: 0,
            maximum: DanmakuStyle.maxDanmakuFontSize),
        0.0,
        'danmaku_font_size', (value) async {
      await player.setDanmakuFontSize((value as num).toDouble(), commit: true);
    },
        setter: 'setDanmakuFontSize',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {
          'label': '弹幕字体大小',
          'type': 'double',
          'min': 8,
          'max': 100,
          'step': 1
        });
    add(
        'danmaku.speedMultiplier',
        '弹幕速度倍率',
        const NumberSchema(minimum: 0.5, maximum: 2),
        1.0,
        'danmaku_speed_multiplier', (value) async {
      await player.setDanmakuSpeedMultiplier((value as num).toDouble());
    },
        setter: 'setDanmakuSpeedMultiplier',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {
          'label': '弹幕速度倍率',
          'type': 'double',
          'min': 0.5,
          'max': 3,
          'step': 0.01
        });
    add(
        'danmaku.displayArea',
        '弹幕显示区域',
        const NumberSchema(minimum: 0, maximum: 1),
        1.0,
        'danmaku_display_area', (value) async {
      await player.setDanmakuDisplayArea((value as num).toDouble());
    },
        setter: 'setDanmakuDisplayArea',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {
          'label': '弹幕显示区域',
          'type': 'double',
          'min': 0.1,
          'max': 1,
          'step': 0.1
        });
    add(
        'danmaku.trackGap',
        'danmaku.trackGap',
        const NumberSchema(minimum: 0, maximum: 2),
        0.15,
        'danmaku_dfm_plus_track_gap', (value) async {
      await player.setDanmakuDfmPlusTrackGap((value as num).toDouble());
    },
        setter: 'setDanmakuDfmPlusTrackGap',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart');
    add(
        'danmaku.outlineWidth',
        'danmaku.outlineWidth',
        const NumberSchema(minimum: 0, maximum: 2),
        globals.isTvOS ? 1.0 : 2.0,
        'next2_danmaku_outline_width', (value) async {
      await player.setNext2DanmakuOutlineWidth((value as num).toDouble());
    },
        setter: 'setNext2DanmakuOutlineWidth',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart');
    add(
        'danmaku.spoilerAiTemperature',
        'danmaku.spoilerAiTemperature',
        const NumberSchema(minimum: 0, maximum: 2),
        0.5,
        'spoiler_ai_temperature', (value) async {
      await player.setSpoilerAiTemperature((value as num).toDouble());
    },
        setter: 'setSpoilerAiTemperature',
        source:
            'lib/utils/video_player_state/video_player_state_subtitles.dart');
    add(
        'danmaku.outlineStyle',
        '弹幕描边样式',
        StringSchema(
            values: DanmakuOutlineStyle.values.map((v) => v.name).toList()),
        globals.isMobilePlatform
            ? DanmakuOutlineStyle.stroke.name
            : DanmakuOutlineStyle.uniform.name,
        'danmaku_outline_style', (value) async {
      await player.setDanmakuOutlineStyle(
          DanmakuOutlineStyle.values.byName(value as String));
    },
        setter: 'setDanmakuOutlineStyle',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) => decodeIndexedEnum(
            raw,
            DanmakuOutlineStyle.values,
            globals.isMobilePlatform
                ? DanmakuOutlineStyle.stroke
                : DanmakuOutlineStyle.uniform),
        remote: {
          'label': '弹幕描边样式',
          'type': 'enum',
          'options': DanmakuOutlineStyle.values
              .map((v) => {'value': v.name, 'label': v.name})
              .toList()
        });
    add(
        'danmaku.shadowStyle',
        '弹幕阴影样式',
        StringSchema(
            values: DanmakuShadowStyle.values.map((v) => v.name).toList()),
        globals.isMobilePlatform
            ? DanmakuShadowStyle.none.name
            : DanmakuShadowStyle.strong.name,
        'danmaku_shadow_style', (value) async {
      await player.setDanmakuShadowStyle(
          DanmakuShadowStyle.values.byName(value as String));
    },
        setter: 'setDanmakuShadowStyle',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) => decodeIndexedEnum(
            raw,
            DanmakuShadowStyle.values,
            globals.isMobilePlatform
                ? DanmakuShadowStyle.none
                : DanmakuShadowStyle.strong),
        remote: {
          'label': '弹幕阴影样式',
          'type': 'enum',
          'options': DanmakuShadowStyle.values
              .map((v) => {'value': v.name, 'label': v.name})
              .toList()
        });
    add('danmaku.fontFamily', 'danmaku.fontFamily', const StringSchema(), '',
        'danmaku_font_family', (value) async {
      await player.setDanmakuFontFamily(value as String);
    },
        setter: 'setDanmakuFontFamily',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart');
    add('danmaku.fontFilePath', 'danmaku.fontFilePath', const StringSchema(),
        '', 'danmaku_font_file_path', (value) async {
      await setDanmakuFont(value as String);
    },
        setter: 'setDanmakuFont',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        path: true);
    add('danmaku.blockWords', '弹幕屏蔽词', const ArraySchema(StringSchema()),
        <String>[], 'danmaku_block_words', (value) async {
      await player.setDanmakuBlockWords(List<String>.from(value as List));
    },
        setter: 'setDanmakuBlockWords',
        source:
            'lib/utils/video_player_state/video_player_state_subtitles.dart',
        decode: (raw) => raw == null
            ? <String>[]
            : List<String>.from(jsonDecode(raw as String) as List),
        remote: {'label': '弹幕屏蔽词', 'type': 'string_list'});
    add(
        'danmaku.manualOffset',
        '弹幕手动偏移',
        const NumberSchema(),
        0.0,
        '@runtime:danmaku.manualOffset', (value) async {
      await setManualOffset((value as num).toDouble());
    },
        setter: 'setManualOffset',
        source: 'lib/utils/video_player_state.dart',
        remote: {
          'label': '弹幕手动偏移',
          'type': 'double',
          'min': -30,
          'max': 30,
          'step': 0.1
        },
        runtimeRead: () async => player.manualDanmakuOffset);
    add(
        'danmaku.renderEngine',
        'danmaku.renderEngine',
        StringSchema(
            values: DanmakuRenderEngine.values.map((v) => v.name).toList()),
        DanmakuKernelFactory.defaultEngine.name,
        'danmaku_render_engine', (value) async {
      await DanmakuKernelFactory.saveKernelType(
          DanmakuRenderEngine.values.byName(value as String));
    },
        setter: 'saveKernelType',
        source: 'lib/danmaku_abstraction/danmaku_kernel_factory.dart',
        scope: 'device',
        decode: (raw) => raw == null
            ? DanmakuKernelFactory.defaultEngine.name
            : DanmakuRenderEngine.values[(raw as num).toInt()].name);
    add(
        'danmaku.nextPlusPlusEnabled',
        'danmaku.nextPlusPlusEnabled',
        const BooleanSchema(),
        false,
        'labs_enable_next_plus_plus_engine', (value) async {
      await DanmakuKernelFactory.saveEnableNextPlusPlus(value as bool);
    },
        setter: 'saveEnableNextPlusPlus',
        source: 'lib/danmaku_abstraction/danmaku_kernel_factory.dart');
    add('danmaku.pluginRenderer', 'danmaku.pluginRenderer',
        const StringSchema(), '', 'danmaku_plugin_renderer', (value) async {
      await setPluginRenderer(value as String);
    },
        setter: 'setPluginRenderer',
        source: 'lib/danmaku_abstraction/danmaku_kernel_factory.dart');
    add('danmaku.spoilerAiApiUrl', 'danmaku.spoilerAiApiUrl',
        const StringSchema(), '', 'spoiler_ai_api_url', (value) async {
      await player.setSpoilerAiApiUrl(value as String);
    },
        setter: 'setSpoilerAiApiUrl',
        source:
            'lib/utils/video_player_state/video_player_state_subtitles.dart');
    add('danmaku.spoilerAiModel', 'danmaku.spoilerAiModel',
        const StringSchema(), 'gpt-5', 'spoiler_ai_model', (value) async {
      await player.setSpoilerAiModel(value as String);
    },
        setter: 'setSpoilerAiModel',
        source:
            'lib/utils/video_player_state/video_player_state_subtitles.dart');
    add(
        'danmaku.spoilerAiApiFormat',
        'danmaku.spoilerAiApiFormat',
        StringSchema(
            values: SpoilerAiApiFormat.values.map((v) => v.name).toList()),
        'openai',
        'spoiler_ai_api_format', (value) async {
      await player.setSpoilerAiApiFormat(
          SpoilerAiApiFormat.values.byName(value as String));
    },
        setter: 'setSpoilerAiApiFormat',
        source:
            'lib/utils/video_player_state/video_player_state_subtitles.dart');
    add(
        'subtitle.scale',
        '字幕大小',
        const NumberSchema(minimum: 0.5, maximum: 2.5),
        1.0,
        'subtitle_scale', (value) async {
      await player.setSubtitleScale((value as num).toDouble());
    },
        setter: 'setSubtitleScale',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {'label': '字幕大小', 'type': 'double', 'step': 0.05});
    add(
        'subtitle.srtScale',
        'subtitle.srtScale',
        const NumberSchema(minimum: 0.5, maximum: 2.5),
        1.0,
        'srt_subtitle_scale', (value) async {
      await player.setSrtSubtitleScale((value as num).toDouble());
    },
        setter: 'setSrtSubtitleScale',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart');
    add('subtitle.delaySeconds', '字幕时间偏移', const NumberSchema(), 0.0,
        'subtitle_delay_seconds', (value) async {
      await player.setSubtitleDelaySeconds((value as num).toDouble());
    },
        setter: 'setSubtitleDelaySeconds',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {
          'label': '字幕时间偏移',
          'type': 'double',
          'step': VideoPlayerState.subtitleDelayStep
        });
    add('subtitle.srtDelaySeconds', 'subtitle.srtDelaySeconds',
        const NumberSchema(), 0.0, 'srt_subtitle_delay', (value) async {
      await player.setSrtSubtitleDelaySeconds((value as num).toDouble());
    },
        setter: 'setSrtSubtitleDelaySeconds',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart');
    add(
        'subtitle.position',
        '字幕垂直位置',
        const NumberSchema(minimum: 0, maximum: 100),
        100.0,
        'subtitle_position', (value) async {
      await player.setSubtitlePosition((value as num).toDouble());
    },
        setter: 'setSubtitlePosition',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {
          'label': '字幕垂直位置',
          'type': 'double',
          'min': 0,
          'max': 100,
          'step': 1
        });
    add('subtitle.marginX', '字幕横向边距', const NumberSchema(), 0.0,
        'subtitle_margin_x', (value) async {
      await player.setSubtitleMarginX((value as num).toDouble());
    },
        setter: 'setSubtitleMarginX',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {
          'label': '字幕横向边距',
          'type': 'double',
          'min': -500,
          'max': 500,
          'step': 1
        });
    add('subtitle.marginY', '字幕纵向边距', const NumberSchema(), 0.0,
        'subtitle_margin_y', (value) async {
      await player.setSubtitleMarginY((value as num).toDouble());
    },
        setter: 'setSubtitleMarginY',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {
          'label': '字幕纵向边距',
          'type': 'double',
          'min': -500,
          'max': 500,
          'step': 1
        });
    add('subtitle.opacity', '字幕透明度', const NumberSchema(minimum: 0, maximum: 1),
        1.0, 'subtitle_opacity', (value) async {
      await player.setSubtitleOpacity((value as num).toDouble());
    },
        setter: 'setSubtitleOpacity',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {
          'label': '字幕透明度',
          'type': 'double',
          'min': 0,
          'max': 1,
          'step': 0.01
        });
    add(
        'subtitle.borderSize',
        '字幕描边粗细',
        const NumberSchema(minimum: 0, maximum: 10),
        3.0,
        'subtitle_border_size', (value) async {
      await player.setSubtitleBorderSize((value as num).toDouble());
    },
        setter: 'setSubtitleBorderSize',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {
          'label': '字幕描边粗细',
          'type': 'double',
          'min': 0,
          'max': 20,
          'step': 0.1
        });
    add(
        'subtitle.shadowOffset',
        '字幕阴影偏移',
        const NumberSchema(minimum: 0, maximum: 10),
        0.0,
        'subtitle_shadow_offset', (value) async {
      await player.setSubtitleShadowOffset((value as num).toDouble());
    },
        setter: 'setSubtitleShadowOffset',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {
          'label': '字幕阴影偏移',
          'type': 'double',
          'min': 0,
          'max': 20,
          'step': 0.1
        });
    add(
        'subtitle.alignX',
        '字幕水平对齐',
        StringSchema(values: SubtitleAlignX.values.map((v) => v.name).toList()),
        SubtitleAlignX.center.name,
        'subtitle_align_x', (value) async {
      await player
          .setSubtitleAlignX(SubtitleAlignX.values.byName(value as String));
    },
        setter: 'setSubtitleAlignX',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) => decodeIndexedEnum(
            raw, SubtitleAlignX.values, SubtitleAlignX.center,
            clamp: true),
        remote: {
          'label': '字幕水平对齐',
          'type': 'enum',
          'options': SubtitleAlignX.values
              .map((v) => {'value': v.name, 'label': v.name})
              .toList()
        });
    add(
        'subtitle.alignY',
        '字幕垂直对齐',
        StringSchema(values: SubtitleAlignY.values.map((v) => v.name).toList()),
        SubtitleAlignY.bottom.name,
        'subtitle_align_y', (value) async {
      await player
          .setSubtitleAlignY(SubtitleAlignY.values.byName(value as String));
    },
        setter: 'setSubtitleAlignY',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) => decodeIndexedEnum(
            raw, SubtitleAlignY.values, SubtitleAlignY.bottom,
            clamp: true),
        remote: {
          'label': '字幕垂直对齐',
          'type': 'enum',
          'options': SubtitleAlignY.values
              .map((v) => {'value': v.name, 'label': v.name})
              .toList()
        });
    add(
        'subtitle.overrideMode',
        '字幕样式接管',
        StringSchema(
            values:
                SubtitleStyleOverrideMode.values.map((v) => v.name).toList()),
        SubtitleStyleOverrideMode.auto.name,
        'subtitle_override_mode', (value) async {
      await player.setSubtitleOverrideMode(
          SubtitleStyleOverrideMode.values.byName(value as String));
    },
        setter: 'setSubtitleOverrideMode',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) => decodeIndexedEnum(raw,
            SubtitleStyleOverrideMode.values, SubtitleStyleOverrideMode.auto,
            clamp: true),
        remote: {
          'label': '字幕样式接管',
          'type': 'enum',
          'options': SubtitleStyleOverrideMode.values
              .map((v) => {'value': v.name, 'label': v.name})
              .toList()
        });
    add('subtitle.bold', '字幕加粗', const BooleanSchema(), false, 'subtitle_bold',
        (value) async {
      await player.setSubtitleBold(value as bool);
    },
        setter: 'setSubtitleBold',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {'label': '字幕加粗', 'type': 'bool'});
    add('subtitle.italic', '字幕斜体', const BooleanSchema(), false,
        'subtitle_italic', (value) async {
      await player.setSubtitleItalic(value as bool);
    },
        setter: 'setSubtitleItalic',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {'label': '字幕斜体', 'type': 'bool'});
    add(
        'subtitle.color',
        '字幕颜色',
        const StringSchema(),
        '#FFFFFFFF',
        'subtitle_color',
        (value) async {
          await player.setSubtitleColor(parseSettingColor(value as String));
        },
        setter: 'setSubtitleColor',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = '#FFFFFFFF';
          return raw == null ? defaultValue : settingColorHex(raw as int);
        },
        remote: {'label': '字幕颜色', 'type': 'string'});
    add(
        'subtitle.borderColor',
        '字幕描边颜色',
        const StringSchema(),
        '#FF000000',
        'subtitle_border_color',
        (value) async {
          await player
              .setSubtitleBorderColor(parseSettingColor(value as String));
        },
        setter: 'setSubtitleBorderColor',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = '#FF000000';
          return raw == null ? defaultValue : settingColorHex(raw as int);
        },
        remote: {'label': '字幕描边颜色', 'type': 'string'});
    add(
        'subtitle.shadowColor',
        '字幕阴影颜色',
        const StringSchema(),
        '#FF000000',
        'subtitle_shadow_color',
        (value) async {
          await player
              .setSubtitleShadowColor(parseSettingColor(value as String));
        },
        setter: 'setSubtitleShadowColor',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = '#FF000000';
          return raw == null ? defaultValue : settingColorHex(raw as int);
        },
        remote: {'label': '字幕阴影颜色', 'type': 'string'});
    add(
        'subtitle.externalColor',
        'subtitle.externalColor',
        const StringSchema(),
        '#FFFFFFFF',
        'external_subtitle_color',
        (value) async {
          await player
              .setExternalSubtitleColor(parseSettingColor(value as String));
        },
        setter: 'setExternalSubtitleColor',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = '#FFFFFFFF';
          return raw == null ? defaultValue : settingColorHex(raw as int);
        });
    add('subtitle.fontName', '字幕字体', const StringSchema(), '',
        'subtitle_font_name', (value) async {
      await player.setSubtitleFontName(value as String);
    },
        setter: 'setSubtitleFontName',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        remote: {'label': '字幕字体', 'type': 'string'});
    add('subtitle.externalFontName', 'subtitle.externalFontName',
        const StringSchema(), '', 'external_subtitle_font_name', (value) async {
      await player.setExternalSubtitleFontName(value as String);
    },
        setter: 'setExternalSubtitleFontName',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart');
    add('subtitle.fontDir', 'subtitle.fontDir', const StringSchema(), '',
        'subtitle_font_dir', (value) async {
      await player.setSubtitleFontDir(value as String);
    },
        setter: 'setSubtitleFontDir',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        path: true,
        directory: true);
    add(
        'danmaku.titan.opacity',
        'danmaku.titan.opacity',
        const NumberSchema(minimum: 0.2, maximum: 1),
        0.85,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(opacity: (value as num).toDouble()));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = 0.85;
          return decodeTitan(raw, 'opacity', defaultValue);
        });
    add(
        'danmaku.titan.fontSize',
        'danmaku.titan.fontSize',
        const NumberSchema(minimum: 0.5, maximum: 2),
        1.0,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(fontSize: (value as num).toDouble()));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = 1.0;
          return decodeTitan(raw, 'fontSize', defaultValue);
        });
    add(
        'danmaku.titan.bold',
        'danmaku.titan.bold',
        const BooleanSchema(),
        true,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(
              player.titanDanmakuSettings.copyWith(bold: value as bool));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = true;
          return decodeTitan(raw, 'bold', defaultValue);
        });
    add(
        'danmaku.titan.fontBorder',
        'danmaku.titan.fontBorder',
        const IntegerSchema(minimum: 0, maximum: 2),
        0,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(fontBorder: (value as num).toInt()));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = 0;
          return decodeTitan(raw, 'fontBorder', defaultValue);
        });
    add(
        'danmaku.titan.fontFamily',
        'danmaku.titan.fontFamily',
        const StringSchema(),
        TitanDanmakuSettings.defaultFontFamily,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(fontFamily: value as String));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = TitanDanmakuSettings.defaultFontFamily;
          return decodeTitan(raw, 'fontFamily', defaultValue);
        });
    add(
        'danmaku.titan.speedPlus',
        'danmaku.titan.speedPlus',
        const NumberSchema(minimum: 0.25, maximum: 3),
        1.0,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(speedPlus: (value as num).toDouble()));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = 1.0;
          return decodeTitan(raw, 'speedPlus', defaultValue);
        });
    add(
        'danmaku.titan.density',
        'danmaku.titan.density',
        const NumberSchema(minimum: 0.1, maximum: 1),
        1.0,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(density: (value as num).toDouble()));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = 1.0;
          return decodeTitan(raw, 'density', defaultValue);
        });
    add(
        'danmaku.titan.duration',
        'danmaku.titan.duration',
        const NumberSchema(minimum: 2, maximum: 12),
        4.5,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(duration: (value as num).toDouble()));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = 4.5;
          return decodeTitan(raw, 'duration', defaultValue);
        });
    add(
        'danmaku.titan.limit',
        'danmaku.titan.limit',
        const IntegerSchema(minimum: 0, maximum: 1000),
        300,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(limit: (value as num).toInt()));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = 300;
          return decodeTitan(raw, 'limit', defaultValue);
        });
    add(
        'danmaku.titan.trackGap',
        'danmaku.titan.trackGap',
        const NumberSchema(minimum: 0, maximum: 0.5),
        globals.isPhone ? 0.15 : 0.0,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(trackGap: (value as num).toDouble()));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          final defaultValue = globals.isPhone ? 0.15 : 0.0;
          return decodeTitan(raw, 'trackGap', defaultValue);
        });
    add(
        'danmaku.titan.preventShade',
        'danmaku.titan.preventShade',
        const BooleanSchema(),
        false,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(preventShade: value as bool));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = false;
          return decodeTitan(raw, 'preventShade', defaultValue);
        });
    add(
        'danmaku.titan.offsetTop',
        'danmaku.titan.offsetTop',
        const IntegerSchema(minimum: -100, maximum: 100),
        3,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(offsetTop: (value as num).toInt()));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = 3;
          return decodeTitan(raw, 'offsetTop', defaultValue);
        });
    add(
        'danmaku.titan.offsetBottom',
        'danmaku.titan.offsetBottom',
        const IntegerSchema(minimum: -100, maximum: 100),
        0,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(offsetBottom: (value as num).toInt()));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = 0;
          return decodeTitan(raw, 'offsetBottom', defaultValue);
        });
    add(
        'danmaku.titan.maxLength',
        'danmaku.titan.maxLength',
        const IntegerSchema(minimum: 0, maximum: 1000),
        50,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(maxLength: (value as num).toInt()));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = 50;
          return decodeTitan(raw, 'maxLength', defaultValue);
        });
    add(
        'danmaku.titan.isRecyclingDom',
        'danmaku.titan.isRecyclingDom',
        const BooleanSchema(),
        true,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(isRecyclingDom: value as bool));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = true;
          return decodeTitan(raw, 'isRecyclingDom', defaultValue);
        });
    add(
        'danmaku.titan.isRecyclingModel',
        'danmaku.titan.isRecyclingModel',
        const BooleanSchema(),
        false,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(isRecyclingModel: value as bool));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = false;
          return decodeTitan(raw, 'isRecyclingModel', defaultValue);
        });
    add(
        'danmaku.titan.forbidShrinkState',
        'danmaku.titan.forbidShrinkState',
        const BooleanSchema(),
        true,
        'titan_danmaku_settings',
        (value) async {
          await player.commitTitanDanmakuSettings(player.titanDanmakuSettings
              .copyWith(forbidShrinkState: value as bool));
        },
        setter: 'commitTitanDanmakuSettings',
        source:
            'lib/utils/video_player_state/video_player_state_preferences.dart',
        decode: (raw) {
          const defaultValue = true;
          return decodeTitan(raw, 'forbidShrinkState', defaultValue);
        });
    add(
        'player.screenshotDirectory',
        '截图保存目录',
        const StringSchema(),
        '',
        'screenshot_save_directory',
        (value) => player.setScreenshotSaveDirectory(
            (value as String).isEmpty ? null : value),
        setter: 'setScreenshotSaveDirectory',
        scope: 'device',
        path: true,
        directory: true,
        visible: () => !kIsWeb);
    return entries;
  }
}
