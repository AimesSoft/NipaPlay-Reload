library video_player_state;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
// import 'package:fvp/mdk.dart';  // Commented out
import '../player_abstraction/player_abstraction.dart'; // <-- NEW IMPORT
import '../player_abstraction/player_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/constants/danmaku_color_presets.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/services.dart';
import 'package:universal_html/html.dart' as web_html;
// Added import for subtitle parser
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:nipaplay/utils/storage_service.dart';
import 'package:path/path.dart' as p;

import 'globals.dart' as globals;
import 'dart:convert';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/manual_danmaku_matcher.dart';
import 'package:nipaplay/services/auto_sync_service.dart'; // 导入自动云同步服务
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/services/jellyfin_playback_sync_service.dart';
import 'package:nipaplay/services/emby_playback_sync_service.dart';
import 'package:nipaplay/services/shared_remote_playback_sync_service.dart';
import 'package:nipaplay/services/web_remote_history_sync_service.dart';
import 'package:nipaplay/services/timeline_danmaku_service.dart'; // 导入时间轴弹幕服务
import 'package:nipaplay/services/danmaku_spoiler_filter_service.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/services/player_remote_control_bridge.dart';
import 'media_info_helper.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/watch_history_database.dart'; // 导入观看记录数据库
import 'package:image/image.dart' as img;
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';

import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:nipaplay/utils/ios_container_path_fixer.dart';
// Added for getTemporaryDirectory
import 'package:crypto/crypto.dart';
import 'package:nipaplay/services/security_bookmark_service.dart';
import 'package:nipaplay/services/photo_library_service.dart';
import 'package:provider/provider.dart';
import '../providers/watch_history_provider.dart';
import 'danmaku_parser.dart';
import 'danmaku_xml_utils.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart'; // Added screen_brightness
import 'package:nipaplay/themes/nipaplay/widgets/brightness_indicator.dart'; // Added import for BrightnessIndicator widget
import 'package:nipaplay/themes/nipaplay/widgets/volume_indicator.dart'; // Added import for VolumeIndicator widget
import 'package:nipaplay/themes/nipaplay/widgets/seek_indicator.dart'; // Added import for SeekIndicator widget
import 'package:volume_controller/volume_controller.dart';

import 'subtitle_manager.dart'; // 导入字幕管理器
import 'subtitle_language_utils.dart';
import 'package:nipaplay/services/file_picker_service.dart'; // Added import for FilePickerService
import 'package:nipaplay/utils/system_resource_monitor.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/player/cupertino_brightness_indicator.dart';
import 'package:nipaplay/themes/cupertino/widgets/player/cupertino_volume_indicator.dart';
import 'package:nipaplay/themes/cupertino/widgets/player/cupertino_seek_indicator.dart';
import 'decoder_manager.dart'; // 导入解码器管理器
import 'package:nipaplay/services/episode_navigation_service.dart'; // 导入剧集导航服务
import 'package:nipaplay/services/auto_next_episode_service.dart';
import 'screen_orientation_manager.dart';
import 'anime4k_shader_manager.dart';
import 'crt_shader_manager.dart';
// 导入MediaKitPlayerAdapter
import '../danmaku_abstraction/danmaku_kernel_factory.dart'; // 弹幕内核工厂
import 'package:nipaplay/danmaku_gpu/lib/gpu_danmaku_overlay.dart'; // 导入GPU弹幕覆盖层
import 'package:flutter/scheduler.dart'; // 添加Ticker导入
import 'danmaku_dialog_manager.dart'; // 导入弹幕对话框管理器
import 'player_kernel_manager.dart'; // 导入播放器内核管理器
import 'shared_remote_history_helper.dart';
import 'package:nipaplay/utils/watch_history_auto_match_helper.dart';
import 'media_source_utils.dart';

part 'video_player_state/video_player_state_metadata.dart';
part 'video_player_state/video_player_state_initialization.dart';
part 'video_player_state/video_player_state_player_setup.dart';
part 'video_player_state/video_player_state_playback_controls.dart';
part 'video_player_state/video_player_state_capture.dart';
part 'video_player_state/video_player_state_preferences.dart';
part 'video_player_state/video_player_state_danmaku.dart';
part 'video_player_state/video_player_state_subtitles.dart';
part 'video_player_state/video_player_state_timeline_preview.dart';
part 'video_player_state/video_player_state_streaming.dart';
part 'video_player_state/video_player_state_navigation.dart';
part 'video_player_state/video_player_state_lifecycle.dart';

enum SubtitleStyleOverrideMode { auto, none, scale, force }

enum SubtitleAlignX { left, center, right }

enum SubtitleAlignY { top, center, bottom }

enum DanmakuOutlineStyle { none, stroke, uniform }

enum DanmakuShadowStyle { none, soft, medium, strong }

enum PlayerStatus {
  idle, // 空闲状态
  loading, // 加载中
  recognizing, // 识别中
  ready, // 准备就绪
  playing, // 播放中
  paused, // 暂停
  error, // 错误
  disposed, // 已释放
}

enum PlaybackEndAction { autoNext, loop, pause, exitPlayer }

extension PlaybackEndActionDisplay on PlaybackEndAction {
  static PlaybackEndAction fromPrefs(String? value) {
    switch (value) {
      case 'pause':
        return PlaybackEndAction.pause;
      case 'exitPlayer':
        return PlaybackEndAction.exitPlayer;
      case 'loop':
        return PlaybackEndAction.loop;
      case 'autoNext':
      default:
        return PlaybackEndAction.autoNext;
    }
  }

  String get prefsValue {
    switch (this) {
      case PlaybackEndAction.autoNext:
        return 'autoNext';
      case PlaybackEndAction.loop:
        return 'loop';
      case PlaybackEndAction.pause:
        return 'pause';
      case PlaybackEndAction.exitPlayer:
        return 'exitPlayer';
    }
  }

  String get label {
    switch (this) {
      case PlaybackEndAction.autoNext:
        return '自动播放下一话';
      case PlaybackEndAction.loop:
        return '循环播放';
      case PlaybackEndAction.pause:
        return '播放完停留在本集';
      case PlaybackEndAction.exitPlayer:
        return '播放结束返回上一页';
    }
  }

  String get description {
    switch (this) {
      case PlaybackEndAction.autoNext:
        return '播放结束后自动倒计时并播放下一话';
      case PlaybackEndAction.loop:
        return '播放结束后从头开始循环播放';
      case PlaybackEndAction.pause:
        return '播放结束后保持在当前页面，不再自动跳转';
      case PlaybackEndAction.exitPlayer:
        return '播放结束后自动返回到视频列表或上一页';
    }
  }
}

enum ScreenshotSaveTarget { ask, photos, file }

extension ScreenshotSaveTargetDisplay on ScreenshotSaveTarget {
  static ScreenshotSaveTarget fromPrefs(int? value) {
    if (value == null) return ScreenshotSaveTarget.ask;
    if (value < 0 || value >= ScreenshotSaveTarget.values.length) {
      return ScreenshotSaveTarget.ask;
    }
    return ScreenshotSaveTarget.values[value];
  }

  int get prefsValue => index;

  String get label {
    switch (this) {
      case ScreenshotSaveTarget.ask:
        return '每次询问';
      case ScreenshotSaveTarget.photos:
        return '相册';
      case ScreenshotSaveTarget.file:
        return '文件';
    }
  }
}

class _VideoDimensionSnapshot {
  final int? srcWidth;
  final int? srcHeight;
  final int? displayWidth;
  final int? displayHeight;

  const _VideoDimensionSnapshot({
    required this.srcWidth,
    required this.srcHeight,
    required this.displayWidth,
    required this.displayHeight,
  });

  bool get hasSource =>
      srcWidth != null && srcWidth! > 0 && srcHeight != null && srcHeight! > 0;

  bool get hasDisplay =>
      displayWidth != null &&
      displayWidth! > 0 &&
      displayHeight != null &&
      displayHeight! > 0;
}

class VideoPlayerState extends ChangeNotifier implements WindowListener {
  late Player player; // 改为 late 修饰，使用 Player.create() 方法创建
  BuildContext? _context;
  bool _isDisposed = false;

  void _notifyListeners() {
    notifyListeners();
  }

  StreamSubscription? _playerKernelChangeSubscription; // 播放器内核切换事件订阅
  StreamSubscription? _danmakuKernelChangeSubscription; // 弹幕内核切换事件订阅
  PlayerStatus _status = PlayerStatus.idle;
  List<String> _statusMessages = []; // 修改为列表存储多个状态消息
  bool _showControls = true;
  bool _showRightMenu = false; // 控制右侧菜单显示状态
  final String _desktopHoverSettingsMenuEnabledKey =
      'desktop_hover_settings_menu_enabled';
  bool _desktopHoverSettingsMenuEnabled = false; // 默认关闭（桌面端）
  final String _instantHidePlayerUiEnabledKey =
      'instant_hide_player_ui_enabled';
  bool _instantHidePlayerUiEnabled = false; // 默认关闭（桌面端）
  bool _isFullscreen = false;
  Rect? _macOSWindowHostedVideoRect;
  double _progress = 0.0;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  int _bufferedPositionMs = 0;
  String? _error;
  final bool _isErrorStopping = false; // <<< ADDED THIS FIELD
  double _aspectRatio = 16 / 9; // 默认16:9，但会根据视频实际比例更新
  String? _currentVideoPath;
  String? _currentActualPlayUrl; // 存储实际播放URL，用于判断转码状态
  PlaybackSession? _currentPlaybackSession;
  int _lastPlaybackStartMs = 0; // 播放开始时间（用于流媒体缓冲期容错）
  static const int _streamingInvalidDataGraceMs = 8000; // 流媒体无效时长容错期
  final Map<String, int?> _jellyfinServerSubtitleSelections = {};
  final Map<String, bool> _jellyfinServerSubtitleBurnInSelections = {};
  final Map<String, int?> _embyServerSubtitleSelections = {};
  final Map<String, bool> _embyServerSubtitleBurnInSelections = {};
  final Map<String, int?> _jellyfinServerAudioSelections = {};
  final Map<String, int?> _embyServerAudioSelections = {};
  String _danmakuOverlayKey = 'idle'; // 弹幕覆盖层的稳定key
  Timer? _uiUpdateTimer; // UI更新定时器（包含位置保存和数据持久化功能）
  // 观看记录节流：记录上一次更新所处的10秒分桶，避免同一时间窗内重复写DB与通知Provider
  int _lastHistoryUpdateBucket = -1;
  // （保留占位，若未来要做更细粒度同步节流可再启用）
  // 🔥 新增：Ticker相关字段
  Ticker? _uiUpdateTicker;
  int _lastTickTime = 0;
  // 节流：UI刷新与位置保存
  int _lastUiNotifyMs = 0; // 上次UI刷新时间
  int _lastSaveTimeMs = 0; // 上次保存时间
  int _lastSavedPositionMs = -1; // 上次已持久化的位置
  final int _uiUpdateIntervalMs = 120; // UI刷新最小间隔（约8.3fps）
  final int _positionSaveIntervalMs = 3000; // 位置保存最小间隔
  final int _positionSaveDeltaThresholdMs = 2000; // 位置保存位移阈值
  // 高频时间轴：提供给弹幕的独立时间源（毫秒）
  final ValueNotifier<double> _playbackTimeMs = ValueNotifier<double>(0);
  Timer? _hideControlsTimer;
  Timer? _hideMouseTimer;
  Timer? _autoHideTimer;
  Timer? _screenshotTimer; // 添加截图定时器
  bool _isControlsHovered = false;
  bool _controlsVisibilityLocked = false;
  bool _isSeeking = false;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey screenshotBoundaryKey = GlobalKey(
    debugLabel: 'player_screenshot_boundary',
  );
  bool _isCapturingScreenshot = false;

  // 添加重置标志，防止在重置过程中更新历史记录
  bool _isResetting = false;
  final String _lastVideoKey = 'last_video_path';
  final String _lastPositionKey = 'last_video_position';
  final String _videoPositionsKey = 'video_positions';
  final String _playbackEndActionKey = 'playback_end_action';
  final String _autoNextCountdownSecondsKey = 'auto_next_countdown_seconds';
  final String _screenshotSaveDirectoryKey = 'screenshot_save_directory';
  final String _screenshotSaveTargetKey = 'screenshot_save_target';
  String? _screenshotSaveDirectory;
  ScreenshotSaveTarget _screenshotSaveTarget = ScreenshotSaveTarget.ask;

  Duration? _lastSeekPosition; // 添加这个字段来记录最后一次seek的位置
  PlaybackEndAction _playbackEndAction = PlaybackEndAction.autoNext;
  int _autoNextCountdownSeconds =
      AutoNextEpisodeService.defaultCountdownSeconds;
  List<Map<String, dynamic>> _danmakuList = [];

  // 多轨道弹幕系统
  final Map<String, Map<String, dynamic>> _danmakuTracks = {};
  final Map<String, bool> _danmakuTrackEnabled = {};
  final double _controlBarHeight = 20.0; // 固定高度
  final String _minimalProgressBarEnabledKey = 'minimal_progress_bar_enabled';
  bool _minimalProgressBarEnabled = false; // 默认关闭
  final String _minimalProgressBarColorKey = 'minimal_progress_bar_color';
  int _minimalProgressBarColor = 0xFFFF7274; // 默认颜色 #ff7274
  final String _showDanmakuDensityChartKey = 'show_danmaku_density_chart';
  bool _showDanmakuDensityChart = false; // 默认关闭弹幕密度曲线图
  final String _precacheBufferSizeMbKey = 'player_precache_buffer_size_mb';
  int _precacheBufferSizeMb = PlayerFactory.defaultPrecacheBufferSizeMb;
  final String _precacheBufferDurationSecondsKey =
      'player_precache_buffer_duration_seconds';
  int _precacheBufferDurationSeconds = 4;
  final String _timelinePreviewEnabledKey = 'timeline_preview_enabled';
  final String _useHardwareDecoderKey = 'use_hardware_decoder';
  bool _useHardwareDecoder = true;

  WatchHistoryProvider? _resolveWatchHistoryProvider() {
    final context = _context;
    if (context != null && context.mounted) {
      try {
        return context.read<WatchHistoryProvider>();
      } catch (_) {}
    }
    final rootContext = globals.navigatorKey.currentState?.overlay?.context;
    if (rootContext != null) {
      try {
        return rootContext.read<WatchHistoryProvider>();
      } catch (_) {}
    }
    return null;
  }

  bool _timelinePreviewEnabled = false; // 默认关闭时间轴缩略图
  bool _timelinePreviewSupported = false;
  int _timelinePreviewIntervalMs = 15000;
  final Map<int, String> _timelinePreviewCache = {};
  final Set<int> _timelinePreviewPending = {};
  int _timelinePreviewSessionId = 0;
  String? _timelinePreviewDirectory;
  String? _timelinePreviewVideoKey;
  AbstractPlayer? _timelinePreviewPlayer;
  PlayerKernelType? _timelinePreviewPlayerKernel;
  String? _timelinePreviewPlayerSource;
  Future<void> _timelinePreviewSerialTask = Future.value();
  final String _danmakuOpacityKey = 'danmaku_opacity';
  double _danmakuOpacity = 1.0; // 默认透明度
  final String _danmakuVisibleKey = 'danmaku_visible';
  bool _danmakuVisible = true; // 默认显示弹幕
  final String _mergeDanmakuKey = 'merge_danmaku';
  bool _mergeDanmaku = false; // 默认不合并弹幕
  final String _danmakuStackingKey = 'danmaku_stacking';
  bool _danmakuStacking = false; // 默认不启用弹幕堆叠
  final String _danmakuRandomColorEnabledKey = 'danmaku_random_color_enabled';
  bool _danmakuRandomColorEnabled = false; // 默认关闭随机染色

  final String _anime4kProfileKey = 'anime4k_profile';
  Anime4KProfile _anime4kProfile = Anime4KProfile.off;
  List<String> _anime4kShaderPaths = const <String>[];
  final Map<String, String> _anime4kRecommendedMpvOptions = const {
    'scale': 'ewa_lanczossharp',
    'cscale': 'ewa_lanczossoft',
    'dscale': 'mitchell',
    'sigmoid-upscaling': 'yes',
    'deband': 'yes',
    'scale-antiring': '0.7',
  };
  final Map<String, String> _anime4kDefaultMpvOptions = const {
    'scale': 'bilinear',
    'cscale': 'bilinear',
    'dscale': 'mitchell',
    'sigmoid-upscaling': 'no',
    'deband': 'no',
    'scale-antiring': '0.0',
  };
  final String _doubleResolutionPlaybackKey = 'double_resolution_playback';
  bool _doubleResolutionPlaybackEnabled = false;
  final String _crtProfileKey = 'crt_profile';
  CrtProfile _crtProfile = CrtProfile.off;
  List<String> _crtShaderPaths = const <String>[];

  // 弹幕类型屏蔽
  final String _blockTopDanmakuKey = 'block_top_danmaku';
  final String _blockBottomDanmakuKey = 'block_bottom_danmaku';
  final String _blockScrollDanmakuKey = 'block_scroll_danmaku';
  bool _blockTopDanmaku = false; // 默认不屏蔽顶部弹幕
  bool _blockBottomDanmaku = false; // 默认不屏蔽底部弹幕
  bool _blockScrollDanmaku = false; // 默认不屏蔽滚动弹幕

  // 时间轴告知弹幕轨道状态
  final String _timelineDanmakuEnabledKey = 'timeline_danmaku_enabled';
  bool _isTimelineDanmakuEnabled = true;

  // 弹幕屏蔽词
  final String _danmakuBlockWordsKey = 'danmaku_block_words';
  List<String> _danmakuBlockWords = []; // 弹幕屏蔽词列表
  int _totalDanmakuCount = 0; // 添加一个字段来存储总弹幕数

  // 防剧透模式
  final String _spoilerPreventionEnabledKey = 'spoiler_prevention_enabled';
  bool _spoilerPreventionEnabled = false;
  bool _isSpoilerDanmakuAnalyzing = false;
  String? _spoilerDanmakuAnalysisHash;
  String? _spoilerDanmakuRunningAnalysisHash;
  Set<String> _spoilerDanmakuTexts = <String>{};
  Timer? _spoilerDanmakuAnalysisDebounceTimer;
  String? _spoilerDanmakuPendingAnalysisHash;
  _SpoilerAiRequestConfig? _spoilerDanmakuPendingRequestConfig;
  List<String>? _spoilerDanmakuPendingTexts;
  String? _spoilerDanmakuPendingTargetVideoPath;

  // 防剧透 AI 设置
  final String _spoilerAiUseCustomKeyKey = 'spoiler_ai_use_custom_key';
  bool _spoilerAiUseCustomKey = true; // 兼容旧设置，固定为自定义接口
  final String _spoilerAiApiFormatKey = 'spoiler_ai_api_format';
  SpoilerAiApiFormat _spoilerAiApiFormat = SpoilerAiApiFormat.openai;
  final String _spoilerAiApiUrlKey = 'spoiler_ai_api_url';
  String _spoilerAiApiUrl = '';
  final String _spoilerAiApiKeyKey = 'spoiler_ai_api_key';
  String _spoilerAiApiKey = '';
  final String _spoilerAiModelKey = 'spoiler_ai_model';
  String _spoilerAiModel = 'gpt-5';
  final String _spoilerAiTemperatureKey = 'spoiler_ai_temperature';
  double _spoilerAiTemperature = 0.5;
  final String _spoilerAiDebugPrintResponseKey =
      'spoiler_ai_debug_print_response';
  bool _spoilerAiDebugPrintResponse = false;

  // 弹幕字体大小设置
  final String _danmakuFontSizeKey = 'danmaku_font_size';
  double _danmakuFontSize = 0.0; // 默认为0表示使用系统默认值
  final String _danmakuFontFilePathKey = 'danmaku_font_file_path';
  String _danmakuFontFilePath = '';
  final String _danmakuFontFamilyKey = 'danmaku_font_family';
  String _danmakuFontFamily = '';
  final String _danmakuOutlineStyleKey = 'danmaku_outline_style';
  DanmakuOutlineStyle _danmakuOutlineStyle = DanmakuOutlineStyle.uniform;
  final String _danmakuShadowStyleKey = 'danmaku_shadow_style';
  DanmakuShadowStyle _danmakuShadowStyle = DanmakuShadowStyle.strong;
  static const double minSubtitleScale = 0.5;
  static const double maxSubtitleScale = 2.5;
  static const double defaultSubtitleScale = 1.0;
  static const double subtitleDelayQuickAdjustRangeSeconds = 30.0;
  static const double subtitleDelayStep = 0.1;
  static const double defaultSubtitleDelaySeconds = 0.0;
  static const double defaultSubtitlePosition = 100.0;
  static const double minSubtitlePosition = 0.0;
  static const double maxSubtitlePosition = 100.0;
  static const double defaultSubtitleMarginX = 0.0;
  static const double defaultSubtitleMarginY = 0.0;
  static const double defaultSubtitleOpacity = 1.0;
  static const double defaultSubtitleBorderSize = 3.0;
  static const double defaultSubtitleShadowOffset = 0.0;
  static const int defaultSubtitleColorValue = 0xFFFFFFFF;
  static const int defaultSubtitleBorderColorValue = 0xFF000000;
  static const int defaultSubtitleShadowColorValue = 0xFF000000;
  static const SubtitleStyleOverrideMode defaultSubtitleOverrideMode =
      SubtitleStyleOverrideMode.auto;
  static const SubtitleAlignX defaultSubtitleAlignX = SubtitleAlignX.center;
  static const SubtitleAlignY defaultSubtitleAlignY = SubtitleAlignY.bottom;
  final String _subtitleScaleKey = 'subtitle_scale';
  final String _subtitleDelayKey = 'subtitle_delay_seconds';
  final String _subtitlePositionKey = 'subtitle_position';
  final String _subtitleAlignXKey = 'subtitle_align_x';
  final String _subtitleAlignYKey = 'subtitle_align_y';
  final String _subtitleMarginXKey = 'subtitle_margin_x';
  final String _subtitleMarginYKey = 'subtitle_margin_y';
  final String _subtitleOpacityKey = 'subtitle_opacity';
  final String _subtitleBorderSizeKey = 'subtitle_border_size';
  final String _subtitleShadowOffsetKey = 'subtitle_shadow_offset';
  final String _subtitleBoldKey = 'subtitle_bold';
  final String _subtitleItalicKey = 'subtitle_italic';
  final String _subtitleColorKey = 'subtitle_color';
  final String _subtitleBorderColorKey = 'subtitle_border_color';
  final String _subtitleShadowColorKey = 'subtitle_shadow_color';
  final String _subtitleFontNameKey = 'subtitle_font_name';
  final String _subtitleFontDirKey = 'subtitle_font_dir';
  final String _subtitleOverrideModeKey = 'subtitle_override_mode';
  double _subtitleScale = defaultSubtitleScale;
  double _subtitleDelaySeconds = defaultSubtitleDelaySeconds;
  double _subtitlePosition = defaultSubtitlePosition;
  SubtitleAlignX _subtitleAlignX = defaultSubtitleAlignX;
  SubtitleAlignY _subtitleAlignY = defaultSubtitleAlignY;
  double _subtitleMarginX = defaultSubtitleMarginX;
  double _subtitleMarginY = defaultSubtitleMarginY;
  double _subtitleOpacity = defaultSubtitleOpacity;
  double _subtitleBorderSize = defaultSubtitleBorderSize;
  double _subtitleShadowOffset = defaultSubtitleShadowOffset;
  bool _subtitleBold = false;
  bool _subtitleItalic = false;
  int _subtitleColorValue = defaultSubtitleColorValue;
  int _subtitleBorderColorValue = defaultSubtitleBorderColorValue;
  int _subtitleShadowColorValue = defaultSubtitleShadowColorValue;
  String _subtitleFontName = '';
  String _subtitleFontDir = '';
  SubtitleStyleOverrideMode _subtitleOverrideMode = defaultSubtitleOverrideMode;

  // 弹幕轨道显示区域设置
  final String _danmakuDisplayAreaKey = 'danmaku_display_area';
  double _danmakuDisplayArea =
      1.0; // 默认全屏显示（0.0=单行，1.0=全屏，0.67=2/3，0.33=1/3，0.25=1/4，0.125=1/8）

  // 弹幕速度设置
  final String _danmakuSpeedMultiplierKey = 'danmaku_speed_multiplier';
  final double _minDanmakuSpeedMultiplier = 0.5;
  final double _maxDanmakuSpeedMultiplier = 2.0;
  final double _baseDanmakuScrollDurationSeconds = 10.0;
  double _danmakuSpeedMultiplier = 1.0; // 默认标准速度
  final String _rememberDanmakuOffsetKey = 'remember_danmaku_offset';
  bool _rememberDanmakuOffset = false; // 是否在切换视频时保留手动弹幕偏移
  double _manualDanmakuOffset = 0.0; // 手动设置的弹幕偏移
  double _autoDanmakuOffset = 0.0; // 弹弹Play自动匹配的时间偏移

  // 添加播放速度相关状态
  static const double minPlaybackRate = 0.01;
  static const double maxPlaybackRate = 5.0;
  static const double defaultSeekStepFrameRate = 24.0;
  static const double fallbackSeekStepMaxSeconds = 600.0;
  static const double seekStepComparisonEpsilon = 0.0005;
  final String _playbackRateKey = 'playback_rate';
  double _playbackRate = 1.0; // 默认1倍速
  bool _isSpeedBoostActive = false; // 是否正在倍速播放（长按状态）
  double _normalPlaybackRate = 1.0; // 正常播放速度
  final String _speedBoostRateKey = 'speed_boost_rate';
  double _speedBoostRate = 2.0; // 长按倍速播放的倍率，默认2倍速

  // 快进快退时间设置
  final String _seekStepSecondsKey = 'seek_step_seconds';
  double _seekStepSeconds = 10.0; // 默认10秒
  double? _seekStepFrameRateEstimate;

  // 跳过时间设置
  final String _skipSecondsKey = 'skip_seconds';
  int _skipSeconds = 90; // 默认90秒
  final String _pauseOnBackgroundKey = 'pause_on_background';
  bool _pauseOnBackground = globals.isMobilePlatform;

  dynamic danmakuController; // 添加弹幕控制器属性
  Duration _videoDuration = Duration.zero; // 添加视频时长状态
  bool _isFullscreenTransitioning = false;
  String? _currentThumbnailPath; // 添加当前缩略图路径
  String? _currentVideoHash; // 缓存当前视频的哈希值，避免重复计算
  bool _isCapturingFrame = false; // 是否正在截图，避免并发截图
  final List<VoidCallback> _thumbnailUpdateListeners = []; // 缩略图更新监听器列表
  String? _animeTitle; // 添加动画标题属性
  String? _episodeTitle; // 添加集数标题属性
  bool _isEpisodeNavigating = false; // 防止重复切集
  bool _navigationDialogVisible = false; // 控制切集对话框

  // 从 historyItem 传入的弹幕 ID（用于保持弹幕关联）
  int? _episodeId; // 存储从 historyItem 传入的 episodeId
  int? _animeId; // 存储从 historyItem 传入的 animeId
  WatchHistoryItem? _initialHistoryItem; // 记录首次传入的历史记录，便于初始化时复用元数据

  // 字幕管理器
  late SubtitleManager _subtitleManager;

  // Screen Brightness Control
  double _currentBrightness =
      0.5; // Default, will be updated by _loadInitialBrightness
  double _initialDragBrightness = 0.5; // To store brightness when drag starts
  bool _isBrightnessIndicatorVisible = false;
  Timer? _brightnessIndicatorTimer;
  OverlayEntry? _brightnessOverlayEntry; // <<< ADDED THIS LINE

  // Volume Control State
  static const Duration _volumeSaveDebounceDuration = Duration(
    milliseconds: 400,
  );
  final String _playerVolumeKey = 'player_volume';
  double _currentVolume = 0.5; // Default volume
  double _initialDragVolume = 0.5;
  bool _isVolumeIndicatorVisible = false;
  Timer? _volumeIndicatorTimer;
  OverlayEntry? _volumeOverlayEntry;
  Timer? _volumePersistenceTimer;
  VolumeController? _systemVolumeController;
  StreamSubscription<double>? _systemVolumeSubscription;
  bool _isSystemVolumeUpdating = false;
  double? _pendingSystemVolume;
  bool _isDrainingSystemVolumeQueue = false;

  // 播放自动全屏
  final String _autoFullscreenEnabledKey = 'auto_fullscreen_enable';
  bool _autoFullscreenEnabled = false;

  bool get _useSystemVolume => globals.isMobilePlatform && !kIsWeb;

  void _queueSystemVolumeUpdate(double volume) {
    if (!_useSystemVolume) return;
    if (_systemVolumeController == null) return;
    _pendingSystemVolume = volume.clamp(0.0, 1.0);
    if (_isDrainingSystemVolumeQueue) return;
    _isDrainingSystemVolumeQueue = true;
    unawaited(_drainSystemVolumeQueue());
  }

  Future<void> _drainSystemVolumeQueue() async {
    try {
      while (true) {
        final double? target = _pendingSystemVolume;
        if (target == null) return;
        _pendingSystemVolume = null;
        await _setSystemVolume(target);
      }
    } finally {
      _isDrainingSystemVolumeQueue = false;
      final double? remaining = _pendingSystemVolume;
      if (remaining != null) {
        _queueSystemVolumeUpdate(remaining);
      }
    }
  }

  void _ensurePlayerVolumeMatchesPlatformPolicy() {
    if (!_useSystemVolume) return;
    try {
      // 在移动端使用系统音量时，播放器内部音量应保持 1.0，避免与系统音量叠乘导致音量偏小。
      if ((player.volume - 1.0).abs() > 0.0001) {
        player.volume = 1.0;
      }
    } catch (_) {}
  }

  // Horizontal Seek Drag State
  bool _isSeekingViaDrag = false;
  Duration _dragSeekStartPosition = Duration.zero;
  double _accumulatedDragDx = 0.0;
  Timer?
      _seekIndicatorTimer; // For showing a temporary seek UI (not implemented yet)
  OverlayEntry?
      _seekOverlayEntry; // For a temporary seek UI (not implemented yet)
  Duration _dragSeekTargetPosition =
      Duration.zero; // To show target position during drag
  bool _isSeekIndicatorVisible = false; // <<< ADDED THIS LINE

  // 右边缘悬浮菜单状态
  bool _isRightEdgeHovered = false;
  Timer? _rightEdgeHoverTimer;
  OverlayEntry? _hoverSettingsMenuOverlay;

  // 加载状态相关
  bool _isInFinalLoadingPhase = false; // 是否处于最终加载阶段，用于优化动画性能

  // 解码器管理器
  late DecoderManager _decoderManager;

  bool _hasInitialScreenshot = false; // 添加标记跟踪是否已进行第一次播放截图
  bool _needsAnime4KSurfaceScaleRefresh = false;
  int _anime4kSurfaceScaleRequestId = 0;

  // 平板设备菜单栏隐藏状态
  bool _isAppBarHidden = false;

  // 新增回调：当发生严重播放错误且应弹出时调用
  Function()? onSeriousPlaybackErrorAndShouldPop;

  // 获取菜单栏隐藏状态
  bool get isAppBarHidden => _isAppBarHidden;
  bool get useHardwareDecoder => _useHardwareDecoder;

  // 检查是否为平板设备（使用globals中的判定逻辑）
  bool get isTablet => globals.isTablet;

  VideoPlayerState() {
    // 创建临时播放器实例，后续会被 _initialize 中的异步创建替换
    player = Player();
    _ensurePlayerVolumeMatchesPlatformPolicy();
    _subtitleManager = SubtitleManager(player: player);
    _decoderManager = DecoderManager(player: player);
    onExternalSubtitleAutoLoaded = _onExternalSubtitleAutoLoaded;
    PlayerRemoteControlBridge.instance.attach(this);
    _initialize();
  }

  void _scheduleVolumePersistence({bool immediate = false}) {
    if (!globals.isMobilePlatform) return;
    _volumePersistenceTimer?.cancel();
    if (immediate) {
      _volumePersistenceTimer = null;
      unawaited(_savePlayerVolumePreference(_currentVolume));
      return;
    }
    _volumePersistenceTimer = Timer(_volumeSaveDebounceDuration, () {
      _volumePersistenceTimer = null;
      unawaited(_savePlayerVolumePreference(_currentVolume));
    });
  }

  Future<void> _savePlayerVolumePreference(double volume) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_playerVolumeKey, volume.clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('保存播放器音量失败: $e');
    }
  }

  Future<void> _initializeSystemVolumeController() async {
    if (!_useSystemVolume) return;
    try {
      _systemVolumeController ??= VolumeController.instance;
      _systemVolumeController!.showSystemUI = false;
      _systemVolumeSubscription?.cancel();
      _systemVolumeSubscription = _systemVolumeController!.addListener(
        _handleExternalSystemVolumeChange,
        // 初始音量由 _loadInitialVolume 主动读取，避免初始化阶段回调打乱持久化/恢复逻辑。
        fetchInitialVolume: false,
      );
    } catch (e) {
      debugPrint('初始化系统音量控制失败: $e');
    }
  }

  void _handleExternalSystemVolumeChange(double volume) {
    if (!_useSystemVolume) return;
    if (_isSystemVolumeUpdating) return;
    final double normalized = volume.clamp(0.0, 1.0);
    if ((_currentVolume - normalized).abs() < 0.001) {
      return;
    }
    _currentVolume = normalized;
    _initialDragVolume = normalized;
    _ensurePlayerVolumeMatchesPlatformPolicy();
    _showVolumeIndicator();
    _scheduleVolumePersistence();
    notifyListeners();
  }

  Future<void> _setSystemVolume(double volume) async {
    if (!_useSystemVolume) return;
    if (_systemVolumeController == null) return;
    _isSystemVolumeUpdating = true;
    try {
      await _systemVolumeController!.setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
      debugPrint('设置系统音量失败: $e');
    } finally {
      Future.microtask(() {
        _isSystemVolumeUpdating = false;
      });
    }
  }

  // Getters
  Rect? get macOSWindowHostedVideoRect => _macOSWindowHostedVideoRect;
  PlayerStatus get status => _status;
  List<String> get statusMessages => _statusMessages;
  bool get showControls => _showControls;
  bool get usesMacOSNativePlatformVideoSurface =>
      !kIsWeb && Platform.isMacOS && player.prefersPlatformVideoSurface;

  int get effectiveUiUpdateIntervalMs {
    if (!usesMacOSNativePlatformVideoSurface) {
      return _uiUpdateIntervalMs;
    }
    if (!_showControls && !_isSeeking) {
      return 1000;
    }
    return 250;
  }

  void setMacOSWindowHostedVideoRect(Rect? rect) {
    final normalizedRect = rect == null || rect.isEmpty
        ? null
        : Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height);
    if (_rectsMatch(_macOSWindowHostedVideoRect, normalizedRect)) {
      return;
    }
    _macOSWindowHostedVideoRect = normalizedRect;
    notifyListeners();
  }

  bool _rectsMatch(Rect? a, Rect? b) {
    if (a == null || b == null) {
      return a == b;
    }
    return (a.left - b.left).abs() < 0.01 &&
        (a.top - b.top).abs() < 0.01 &&
        (a.width - b.width).abs() < 0.01 &&
        (a.height - b.height).abs() < 0.01;
  }

  bool get isDisposed => _isDisposed;
  bool get showRightMenu => _showRightMenu;
  bool get desktopHoverSettingsMenuEnabled => _desktopHoverSettingsMenuEnabled;
  bool get instantHidePlayerUiEnabled => _instantHidePlayerUiEnabled;
  bool get isFullscreen => _isFullscreen;
  double get progress => _progress;
  int get bufferedPosition => _bufferedPositionMs;
  double get bufferedProgress {
    final durationMs = _duration.inMilliseconds;
    if (durationMs <= 0) {
      return 0.0;
    }
    final raw = _bufferedPositionMs / durationMs;
    if (raw.isNaN || raw.isInfinite) {
      return _progress.clamp(0.0, 1.0).toDouble();
    }
    final clamped = raw.clamp(0.0, 1.0).toDouble();
    return clamped < _progress ? _progress : clamped;
  }

  Duration get duration => _duration;
  Duration get position => _position;
  String? get error => _error;
  double get aspectRatio => _aspectRatio;
  bool get hasVideo =>
      _status == PlayerStatus.ready ||
      _status == PlayerStatus.playing ||
      _status == PlayerStatus.paused;
  bool get isPaused => _status == PlayerStatus.paused;
  FocusNode get focusNode => _focusNode;
  PlaybackEndAction get playbackEndAction => _playbackEndAction;
  int get autoNextCountdownSeconds => _autoNextCountdownSeconds;
  String? get screenshotSaveDirectory => _screenshotSaveDirectory;
  ScreenshotSaveTarget get screenshotSaveTarget => _screenshotSaveTarget;
  List<Map<String, dynamic>> get danmakuList => _danmakuList;
  Map<String, Map<String, dynamic>> get danmakuTracks => _danmakuTracks;
  Map<String, bool> get danmakuTrackEnabled => _danmakuTrackEnabled;
  double get controlBarHeight => _controlBarHeight;
  bool get minimalProgressBarEnabled => _minimalProgressBarEnabled;
  Color get minimalProgressBarColor => Color(_minimalProgressBarColor);
  bool get showDanmakuDensityChart => _showDanmakuDensityChart;
  int get precacheBufferSizeMb => _precacheBufferSizeMb;
  int get precacheBufferDurationSeconds => _precacheBufferDurationSeconds;
  double get danmakuOpacity => _danmakuOpacity;
  bool get danmakuVisible => _danmakuVisible;
  bool get mergeDanmaku => _mergeDanmaku;
  double get danmakuFontSize => _danmakuFontSize;
  String get danmakuFontFilePath => _danmakuFontFilePath;
  String get danmakuFontFamily => _danmakuFontFamily;
  DanmakuOutlineStyle get danmakuOutlineStyle => _danmakuOutlineStyle;
  DanmakuShadowStyle get danmakuShadowStyle => _danmakuShadowStyle;
  double get subtitleScale => _subtitleScale;
  double get subtitleDelayCustomLimitSeconds {
    final durationSeconds = _duration.inMilliseconds / 1000;
    if (durationSeconds <= 0) {
      return subtitleDelayQuickAdjustRangeSeconds;
    }
    return durationSeconds.toDouble();
  }

  bool get hasSubtitleDelayDurationLimit => _duration.inMilliseconds > 0;
  bool get autoFullscreenEnabled => _autoFullscreenEnabled;

  double _resolveSubtitleDelaySecondsForCurrentVideo(double value) {
    final limit = subtitleDelayCustomLimitSeconds;
    return value.clamp(-limit, limit).toDouble();
  }

  double clampSubtitleDelayToCurrentVideoDuration(double value) {
    return _resolveSubtitleDelaySecondsForCurrentVideo(value);
  }

  double get subtitleDelaySeconds =>
      _resolveSubtitleDelaySecondsForCurrentVideo(_subtitleDelaySeconds);

  double? _parseSeekStepFrameRateNumericToken(String value) {
    final directNumber = double.tryParse(value);
    if (directNumber != null && directNumber.isFinite && directNumber > 0) {
      return directNumber;
    }

    final fractionMatch = RegExp(
      r'^([0-9]+(?:\.[0-9]+)?)\s*/\s*([0-9]+(?:\.[0-9]+)?)$',
    ).firstMatch(value);
    if (fractionMatch == null) return null;

    final numerator = double.tryParse(fractionMatch.group(1) ?? '');
    final denominator = double.tryParse(fractionMatch.group(2) ?? '');
    if (numerator == null ||
        denominator == null ||
        !numerator.isFinite ||
        !denominator.isFinite ||
        denominator <= 0) {
      return null;
    }

    final fps = numerator / denominator;
    if (fps.isFinite && fps > 0) {
      return fps;
    }
    return null;
  }

  double? _parseSeekStepFrameRateValue(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final fps = value.toDouble();
      if (fps.isFinite && fps > 0) {
        return fps;
      }
      return null;
    }
    if (value is String) {
      final trimmed = value.trim().toLowerCase();
      if (trimmed.isEmpty) return null;

      final directValue = _parseSeekStepFrameRateNumericToken(trimmed);
      if (directValue != null) {
        return directValue;
      }

      final labeledFractionMatch = RegExp(
            r'([0-9]+(?:\.[0-9]+)?)\s*/\s*([0-9]+(?:\.[0-9]+)?)\s*(?:fps|frames?\s*(?:/|per)\s*second|frame\s*rate|framerate)',
          ).firstMatch(trimmed) ??
          RegExp(
            r'(?:fps|frames?\s*(?:/|per)\s*second|frame\s*rate|framerate)[\s:=]*([0-9]+(?:\.[0-9]+)?)\s*/\s*([0-9]+(?:\.[0-9]+)?)',
          ).firstMatch(trimmed);
      if (labeledFractionMatch != null) {
        final numerator = double.tryParse(labeledFractionMatch.group(1) ?? '');
        final denominator = double.tryParse(
          labeledFractionMatch.group(2) ?? '',
        );
        if (numerator != null &&
            denominator != null &&
            numerator.isFinite &&
            denominator.isFinite &&
            denominator > 0) {
          final fps = numerator / denominator;
          if (fps.isFinite && fps > 0) {
            return fps;
          }
        }
      }

      final labeledMatch = RegExp(
            r'([0-9]+(?:\.[0-9]+)?)\s*(?:fps|frames?\s*(?:/|per)\s*second|frame\s*rate|framerate)',
          ).firstMatch(trimmed) ??
          RegExp(
            r'(?:fps|frames?\s*(?:/|per)\s*second|frame\s*rate|framerate)[\s:=]*([0-9]+(?:\.[0-9]+)?)',
          ).firstMatch(trimmed);
      if (labeledMatch != null) {
        final fps = double.tryParse(labeledMatch.group(1) ?? '');
        if (fps != null && fps.isFinite && fps > 0) {
          return fps;
        }
      }
    }
    return null;
  }

  double? _extractSeekStepFrameRate(Map<String, dynamic> info) {
    Map<String, dynamic> toStringKeyedMap(dynamic raw) {
      if (raw is Map) {
        return raw.map(
          (dynamic key, dynamic value) => MapEntry(key.toString(), value),
        );
      }
      return <String, dynamic>{};
    }

    final mpvProperties = toStringKeyedMap(info['mpvProperties']);
    final directCandidates = <dynamic>[
      mpvProperties['container-fps'],
      mpvProperties['estimated-vf-fps'],
      info['fps'],
      info['frameRate'],
    ];
    for (final candidate in directCandidates) {
      final parsed = _parseSeekStepFrameRateValue(candidate);
      if (parsed != null) {
        return parsed;
      }
    }

    final videoEntries = info['video'];
    if (videoEntries is List) {
      for (final entry in videoEntries) {
        final mapEntry = toStringKeyedMap(entry);
        final parsed = _parseSeekStepFrameRateValue(mapEntry['fps']) ??
            _parseSeekStepFrameRateValue(mapEntry['frameRate']) ??
            _parseSeekStepFrameRateValue(mapEntry['frame_rate']) ??
            _parseSeekStepFrameRateValue(mapEntry['raw']);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    final videoParams = toStringKeyedMap(info['videoParams']);
    return _parseSeekStepFrameRateValue(videoParams['fps']) ??
        _parseSeekStepFrameRateValue(videoParams['frameRate']);
  }

  String _trimTrailingZerosForDisplay(String value) {
    if (!value.contains('.')) return value;
    return value
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String formatSeekStepSecondsValue(double value) {
    final safeValue = value.isFinite ? value : 0.0;
    if ((safeValue - safeValue.roundToDouble()).abs() <
        seekStepComparisonEpsilon) {
      return safeValue.round().toString();
    }
    final decimals = safeValue < 1 ? 3 : 2;
    return _trimTrailingZerosForDisplay(safeValue.toStringAsFixed(decimals));
  }

  double get seekStepFrameRate {
    if (_seekStepFrameRateEstimate != null &&
        _seekStepFrameRateEstimate!.isFinite &&
        _seekStepFrameRateEstimate! > 0) {
      return _seekStepFrameRateEstimate!;
    }
    final detected = _extractSeekStepFrameRate(player.getDetailedMediaInfo());
    if (detected == null) {
      return defaultSeekStepFrameRate;
    }
    return detected;
  }

  Future<void> refreshSeekStepFrameRateEstimate() async {
    if (!hasVideo) return;
    try {
      final info = await player.getDetailedMediaInfoAsync();
      final detected = _extractSeekStepFrameRate(info);
      if (detected == null || !detected.isFinite || detected <= 0) {
        return;
      }
      if (_seekStepFrameRateEstimate != null &&
          (_seekStepFrameRateEstimate! - detected).abs() <
              seekStepComparisonEpsilon) {
        return;
      }
      _seekStepFrameRateEstimate = detected;
      notifyListeners();
    } catch (_) {}
  }

  double get seekStepMinSeconds {
    final max = seekStepMaxSeconds;
    final frameSeconds = 1 / seekStepFrameRate;
    final safeFrameSeconds = frameSeconds.isFinite && frameSeconds > 0
        ? frameSeconds
        : (1 / defaultSeekStepFrameRate);
    if (max <= 0) {
      return safeFrameSeconds;
    }
    return safeFrameSeconds.clamp(0.001, max).toDouble();
  }

  double get seekStepMaxSeconds {
    final durationSeconds = _duration.inMilliseconds / 1000;
    if (durationSeconds <= 0) {
      return fallbackSeekStepMaxSeconds;
    }
    return durationSeconds.toDouble();
  }

  bool get hasSeekStepDurationLimit => _duration.inMilliseconds > 0;

  double _resolveSeekStepSecondsForCurrentVideo(double value) {
    final max = seekStepMaxSeconds;
    if (max <= 0) {
      return seekStepMinSeconds;
    }
    final min = seekStepMinSeconds.clamp(0.001, max).toDouble();
    return value.clamp(min, max).toDouble();
  }

  double clampSeekStepToCurrentVideoDuration(double value) {
    return _resolveSeekStepSecondsForCurrentVideo(value);
  }

  bool isFrameSeekStepValue(double value) =>
      (value - seekStepMinSeconds).abs() < seekStepComparisonEpsilon;

  String formatSeekStepLabel(
    double value, {
    bool preferFrameLabel = false,
    bool includeFrameApproximation = false,
  }) {
    final resolved = _resolveSeekStepSecondsForCurrentVideo(value);
    final secondsLabel = '${formatSeekStepSecondsValue(resolved)} 秒';
    if (preferFrameLabel && isFrameSeekStepValue(resolved)) {
      if (includeFrameApproximation) {
        return '1 帧（约 $secondsLabel）';
      }
      return '1 帧';
    }
    return secondsLabel;
  }

  double get seekStepSeconds =>
      _resolveSeekStepSecondsForCurrentVideo(_seekStepSeconds);

  Duration get seekStepDuration {
    final milliseconds = (seekStepSeconds * 1000).round();
    return Duration(milliseconds: milliseconds <= 0 ? 1 : milliseconds);
  }

  String get seekStepDisplayLabel =>
      formatSeekStepLabel(seekStepSeconds, preferFrameLabel: true);

  String get seekStepSummaryLabel => formatSeekStepLabel(
        seekStepSeconds,
        preferFrameLabel: true,
        includeFrameApproximation: true,
      );

  double get subtitleDelaySliderMinSeconds {
    final limit = subtitleDelayCustomLimitSeconds;
    final current = subtitleDelaySeconds;
    return (current - subtitleDelayQuickAdjustRangeSeconds)
        .clamp(-limit, limit)
        .toDouble();
  }

  double get subtitleDelaySliderMaxSeconds {
    final limit = subtitleDelayCustomLimitSeconds;
    final current = subtitleDelaySeconds;
    return (current + subtitleDelayQuickAdjustRangeSeconds)
        .clamp(-limit, limit)
        .toDouble();
  }

  int get subtitleDelaySliderDivisions {
    final span = subtitleDelaySliderMaxSeconds - subtitleDelaySliderMinSeconds;
    if (span <= 0) return 1;
    return (span / subtitleDelayStep).round().clamp(1, 600);
  }

  double get subtitlePosition => _subtitlePosition;
  SubtitleAlignX get subtitleAlignX => _subtitleAlignX;
  SubtitleAlignY get subtitleAlignY => _subtitleAlignY;
  double get subtitleMarginX => _subtitleMarginX;
  double get subtitleMarginY => _subtitleMarginY;
  double get subtitleOpacity => _subtitleOpacity;
  double get subtitleBorderSize => _subtitleBorderSize;
  double get subtitleShadowOffset => _subtitleShadowOffset;
  bool get subtitleBold => _subtitleBold;
  bool get subtitleItalic => _subtitleItalic;
  Color get subtitleColor => Color(_subtitleColorValue);
  Color get subtitleBorderColor => Color(_subtitleBorderColorValue);
  Color get subtitleShadowColor => Color(_subtitleShadowColorValue);
  String get subtitleFontName => _subtitleFontName;
  String get subtitleFontDir => _subtitleFontDir;
  SubtitleStyleOverrideMode get subtitleOverrideMode => _subtitleOverrideMode;
  double get danmakuDisplayArea => _danmakuDisplayArea;
  double get danmakuSpeedMultiplier => _danmakuSpeedMultiplier;
  double get danmakuScrollDurationSeconds =>
      _baseDanmakuScrollDurationSeconds / _danmakuSpeedMultiplier;
  bool get danmakuStacking => _danmakuStacking;
  bool get danmakuRandomColorEnabled => _danmakuRandomColorEnabled;
  bool get rememberDanmakuOffset => _rememberDanmakuOffset;
  double get manualDanmakuOffset => _manualDanmakuOffset;
  double get autoDanmakuOffset => _autoDanmakuOffset;
  bool get pauseOnBackground => _pauseOnBackground;
  Anime4KProfile get anime4kProfile => _anime4kProfile;
  bool get isAnime4KEnabled => _anime4kProfile != Anime4KProfile.off;
  bool get isAnime4KSupported => _supportsAnime4KForCurrentPlayer();
  bool get doubleResolutionPlaybackEnabled => _doubleResolutionPlaybackEnabled;
  bool get isDoubleResolutionSupported => _supportsAnime4KForCurrentPlayer();
  List<String> get anime4kShaderPaths => List.unmodifiable(_anime4kShaderPaths);
  CrtProfile get crtProfile => _crtProfile;
  bool get isCrtEnabled => _crtProfile != CrtProfile.off;
  bool get isCrtSupported => _supportsAnime4KForCurrentPlayer();
  List<String> get crtShaderPaths => List.unmodifiable(_crtShaderPaths);
  Duration get videoDuration => _videoDuration;
  String? get currentVideoPath => _currentVideoPath;
  String? get currentActualPlayUrl => _currentActualPlayUrl; // 当前实际播放URL
  PlaybackSession? get currentPlaybackSession => _currentPlaybackSession;
  String get danmakuOverlayKey => _danmakuOverlayKey; // 弹幕覆盖层的稳定key
  String? get animeTitle => _animeTitle; // 添加动画标题getter
  String? get episodeTitle => _episodeTitle; // 添加集数标题getter
  int? get animeId => _animeId; // 添加动画ID getter
  int? get episodeId => _episodeId; // 添加剧集ID getter

  bool hasJellyfinServerAudioSelection(String itemId) =>
      _jellyfinServerAudioSelections.containsKey(itemId);

  int? getJellyfinServerAudioSelection(String itemId) =>
      _jellyfinServerAudioSelections[itemId];

  void setJellyfinServerAudioSelection(String itemId, int? index) {
    if (_jellyfinServerAudioSelections[itemId] == index) return;
    _jellyfinServerAudioSelections[itemId] = index;
    notifyListeners();
  }

  bool hasEmbyServerAudioSelection(String itemId) =>
      _embyServerAudioSelections.containsKey(itemId);

  int? getEmbyServerAudioSelection(String itemId) =>
      _embyServerAudioSelections[itemId];

  void setEmbyServerAudioSelection(String itemId, int? index) {
    if (_embyServerAudioSelections[itemId] == index) return;
    _embyServerAudioSelections[itemId] = index;
    notifyListeners();
  }

  // 获取时间轴告知弹幕轨道状态
  bool get isTimelineDanmakuEnabled => _isTimelineDanmakuEnabled;

  bool get spoilerPreventionEnabled => _spoilerPreventionEnabled;
  bool get spoilerAiUseCustomKey => _spoilerAiUseCustomKey;
  SpoilerAiApiFormat get spoilerAiApiFormat => _spoilerAiApiFormat;
  String get spoilerAiApiUrl => _spoilerAiApiUrl;
  String get spoilerAiApiKey => _spoilerAiApiKey;
  bool get spoilerAiHasApiKey => _spoilerAiApiKey.trim().isNotEmpty;
  bool get spoilerAiConfigReady =>
      _spoilerAiApiUrl.trim().isNotEmpty &&
      _spoilerAiApiKey.trim().isNotEmpty &&
      _spoilerAiModel.trim().isNotEmpty;
  String get spoilerAiModel => _spoilerAiModel;
  double get spoilerAiTemperature => _spoilerAiTemperature;
  bool get spoilerAiDebugPrintResponse => _spoilerAiDebugPrintResponse;

  // 字幕管理器相关的getter
  SubtitleManager get subtitleManager => _subtitleManager;
  String? get currentExternalSubtitlePath =>
      _subtitleManager.currentExternalSubtitlePath;
  Map<String, Map<String, dynamic>> get subtitleTrackInfo =>
      _subtitleManager.subtitleTrackInfo;

  // Brightness Getters
  double get currentScreenBrightness => _currentBrightness;
  bool get isBrightnessIndicatorVisible => _isBrightnessIndicatorVisible;

  // Volume Getters
  double get currentSystemVolume => _currentVolume;

  void setManualDanmakuOffset(double offset) {
    if ((_manualDanmakuOffset - offset).abs() < 0.0001) {
      return;
    }
    _manualDanmakuOffset = offset;
    notifyListeners();
  }

  void _setAutoDanmakuOffset(double offset) {
    if ((_autoDanmakuOffset - offset).abs() < 0.0001) {
      return;
    }
    _autoDanmakuOffset = offset;
    notifyListeners();
  }

  bool get isVolumeUIVisible =>
      _isVolumeIndicatorVisible; // Renamed for clarity

  // Seek Indicator Getter
  bool get isSeekIndicatorVisible =>
      _isSeekIndicatorVisible; // <<< ADDED THIS GETTER
  Duration get dragSeekTargetPosition =>
      _dragSeekTargetPosition; // <<< ADDED THIS GETTER

  // 弹幕类型屏蔽Getters
  bool get blockTopDanmaku => _blockTopDanmaku;
  bool get blockBottomDanmaku => _blockBottomDanmaku;
  bool get blockScrollDanmaku => _blockScrollDanmaku;
  List<String> get danmakuBlockWords => _danmakuBlockWords;
  int get totalDanmakuCount => _totalDanmakuCount;

  // 获取是否处于最终加载阶段
  bool get isInFinalLoadingPhase => _isInFinalLoadingPhase;

  // 解码器管理器相关的getter
  DecoderManager get decoderManager => _decoderManager;

  // 获取播放器内核名称（通过静态方法）
  String get playerCoreName => player.getPlayerKernelName();

  // 播放速度相关的getter
  double get playbackRate => _playbackRate;
  double get effectivePlaybackRate =>
      _isSpeedBoostActive ? _speedBoostRate : _playbackRate;
  bool get isSpeedBoostActive => _isSpeedBoostActive;
  double get speedBoostRate => _speedBoostRate;

  // 跳过时间的getter
  int get skipSeconds => _skipSeconds;

  // 右边缘悬浮菜单的getter
  bool get isRightEdgeHovered => _isRightEdgeHovered;
  // 对外暴露的高频播放时间
  ValueListenable<double> get playbackTimeMs => _playbackTimeMs;

  @override
  void dispose() {
    _isDisposed = true;
    PlayerRemoteControlBridge.instance.detach(this);

    // Jellyfin同步：如果是Jellyfin流媒体，停止同步
    if (_currentVideoPath != null &&
        _currentVideoPath!.startsWith('jellyfin://')) {
      try {
        final itemId = _currentVideoPath!.replaceFirst('jellyfin://', '');
        final syncService = JellyfinPlaybackSyncService();
        // 注意：dispose方法不能是async，所以这里使用同步方式处理
        // 在dispose中我们只清理同步服务状态，不发送网络请求
        syncService.dispose();
      } catch (e) {
        debugPrint('Jellyfin播放销毁同步失败: $e');
      }
    }

    // Emby同步：如果是Emby流媒体，停止同步
    if (_currentVideoPath != null && _currentVideoPath!.startsWith('emby://')) {
      try {
        final itemId = _currentVideoPath!.replaceFirst('emby://', '');
        final syncService = EmbyPlaybackSyncService();
        // 注意：dispose方法不能是async，所以这里使用同步方式处理
        // 在dispose中我们只清理同步服务状态，不发送网络请求
        syncService.dispose();
      } catch (e) {
        debugPrint('Emby播放销毁同步失败: $e');
      }
    }

    // 退出视频播放时触发自动云同步
    if (_currentVideoPath != null) {
      try {
        // 使用Future.microtask在下一个事件循环中异步执行，避免dispose中的异步问题
        Future.microtask(() async {
          await AutoSyncService.instance.syncOnPlaybackEnd();
          debugPrint('退出视频时云同步成功');
        });
      } catch (e) {
        debugPrint('退出视频时云同步失败: $e');
      }
    }

    _scheduleVolumePersistence(immediate: true);
    _volumePersistenceTimer?.cancel();
    _systemVolumeSubscription?.cancel();
    _systemVolumeSubscription = null;
    _systemVolumeController?.removeListener();
    _systemVolumeController = null;
    player.dispose();
    _focusNode.dispose();
    _uiUpdateTimer?.cancel(); // 清理UI更新定时器

    // 🔥 新增：清理Ticker资源
    if (_uiUpdateTicker != null) {
      _uiUpdateTicker!.stop();
      _uiUpdateTicker!.dispose();
      _uiUpdateTicker = null;
    }

    _hideControlsTimer?.cancel();
    _hideMouseTimer?.cancel();
    _autoHideTimer?.cancel();
    _screenshotTimer?.cancel();
    _spoilerDanmakuAnalysisDebounceTimer?.cancel();
    _spoilerDanmakuAnalysisDebounceTimer = null;
    _spoilerDanmakuPendingAnalysisHash = null;
    _spoilerDanmakuPendingRequestConfig = null;
    _spoilerDanmakuPendingTexts = null;
    _spoilerDanmakuPendingTargetVideoPath = null;
    _spoilerDanmakuRunningAnalysisHash = null;
    _brightnessIndicatorTimer
        ?.cancel(); // Already cancelled here or in _hideBrightnessIndicator
    if (_brightnessOverlayEntry != null) {
      // ADDED THIS BLOCK
      _brightnessOverlayEntry!.remove();
      _brightnessOverlayEntry = null;
    }
    _volumeIndicatorTimer?.cancel(); // <<< ADDED
    if (_volumeOverlayEntry != null) {
      // <<< ADDED
      _volumeOverlayEntry!.remove();
      _volumeOverlayEntry = null;
    }
    _seekIndicatorTimer?.cancel(); // <<< ADDED
    if (_seekOverlayEntry != null) {
      // <<< ADDED
      _seekOverlayEntry!.remove();
      _seekOverlayEntry = null;
    }
    _rightEdgeHoverTimer?.cancel(); // 清理右边缘悬浮定时器
    if (_hoverSettingsMenuOverlay != null) {
      // 清理悬浮设置菜单
      _hoverSettingsMenuOverlay!.remove();
      _hoverSettingsMenuOverlay = null;
    }
    WakelockPlus.disable();
    //debugPrint("Wakelock disabled on dispose.");
    if (!kIsWeb) {
      windowManager.removeListener(this);
    }
    _playerKernelChangeSubscription?.cancel(); // 取消播放器内核切换事件订阅
    _danmakuKernelChangeSubscription?.cancel(); // 取消弹幕内核切换事件订阅
    super.dispose();
  }

  // 设置窗口管理器监听器
  void _setupWindowManagerListener() {
    if (kIsWeb) return;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.addListener(this);
    }
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'enter-full-screen' || eventName == 'leave-full-screen') {
      windowManager.isFullScreen().then((isFullscreen) {
        if (isFullscreen != _isFullscreen) {
          _isFullscreen = isFullscreen;
          notifyListeners();
        }
      });
    }
  }

  @override
  void onWindowEnterFullScreen() {
    windowManager.isFullScreen().then((isFullscreen) {
      if (isFullscreen != _isFullscreen) {
        _isFullscreen = isFullscreen;
        notifyListeners();
      }
    });
  }

  @override
  void onWindowLeaveFullScreen() {
    windowManager.isFullScreen().then((isFullscreen) {
      if (!isFullscreen && _isFullscreen) {
        _isFullscreen = false;
        notifyListeners();
      }
    });
  }

  @override
  void onWindowBlur() {}

  @override
  void onWindowClose() async {
    // Changed from onWindowClose() async
    //debugPrint("VideoPlayerState: onWindowClose called. Saving position.");
    _saveCurrentPositionToHistory(); // Removed await as the method likely returns void
  }

  @override
  void onWindowDocked() {}

  @override
  void onWindowFocus() {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowMinimize() {}

  @override
  void onWindowMove() {}

  @override
  void onWindowMoved() {}

  @override
  void onWindowResize() {}

  @override
  void onWindowResized() {}

  @override
  void onWindowRestore() {}

  @override
  void onWindowUnDocked() {}

  @override
  void onWindowUndocked() {}

  @override
  void onWindowUnmaximize() {}

  /// 获取当前时间窗口内的弹幕（分批加载/懒加载）
  List<Map<String, dynamic>> getActiveDanmakuList(
    double currentTime, {
    double window = 15.0,
  }) {
    // 先过滤掉被屏蔽的弹幕
    final filteredDanmakuList = getFilteredDanmakuList();

    // 然后在过滤后的列表中查找时间窗口内的弹幕
    return filteredDanmakuList.where((d) {
      final t = d['time'] as double? ?? 0.0;
      return t >= currentTime - window && t <= currentTime + window;
    }).toList();
  }

  // 获取过滤后的弹幕列表
  List<Map<String, dynamic>> getFilteredDanmakuList() {
    return _danmakuList
        .where((danmaku) => !shouldBlockDanmaku(danmaku))
        .toList();
  }

  // 添加setter用于设置外部字幕自动加载回调
  set onExternalSubtitleAutoLoaded(Function(String, String)? callback) {
    _subtitleManager.onExternalSubtitleAutoLoaded = callback;
  }

  // 检查是否可以播放上一话
  bool get canPlayPreviousEpisode {
    if (_currentVideoPath == null) return false;

    final navigationService = EpisodeNavigationService.instance;

    // 如果有剧集信息，可以使用数据库导航
    if (navigationService.canUseDatabaseNavigation(_animeId, _episodeId)) {
      return true;
    }

    // 如果是本地文件，可以使用文件系统导航
    if (navigationService.canUseFileSystemNavigation(_currentVideoPath!)) {
      return true;
    }

    // 如果是流媒体，可以使用简单导航（Jellyfin/Emby的adjacentTo API）
    if (navigationService.canUseStreamingNavigation(_currentVideoPath!)) {
      return true;
    }

    return false;
  }

  // 检查是否可以播放下一话
  bool get canPlayNextEpisode {
    if (_currentVideoPath == null) return false;

    final navigationService = EpisodeNavigationService.instance;

    // 如果有剧集信息，可以使用数据库导航
    if (navigationService.canUseDatabaseNavigation(_animeId, _episodeId)) {
      return true;
    }

    // 如果是本地文件，可以使用文件系统导航
    if (navigationService.canUseFileSystemNavigation(_currentVideoPath!)) {
      return true;
    }

    // 如果是流媒体，可以使用简单导航（Jellyfin/Emby的adjacentTo API）
    if (navigationService.canUseStreamingNavigation(_currentVideoPath!)) {
      return true;
    }

    return false;
  }
}
