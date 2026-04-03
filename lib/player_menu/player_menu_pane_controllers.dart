import 'package:flutter/foundation.dart';

import 'package:nipaplay/player_menu/player_menu_models.dart';
import 'package:nipaplay/utils/video_player_state.dart';

/// 基类：封装子菜单所依赖的逻辑控制器
abstract class PlayerMenuPaneController extends ChangeNotifier {
  PlayerMenuPaneController({required this.videoState}) {
    videoState.addListener(_handleVideoStateChanged);
  }

  final VideoPlayerState videoState;

  /// 每个控制器都对应一个 Pane 方便外部识别
  PlayerMenuPaneId get paneId;

  void _handleVideoStateChanged() => onVideoStateChanged();

  @protected
  void onVideoStateChanged() {
    // 默认直接把 VideoPlayerState 的变化同步给 UI
    notifyListeners();
  }

  @mustCallSuper
  @override
  void dispose() {
    videoState.removeListener(_handleVideoStateChanged);
    super.dispose();
  }
}

/// 倍速菜单控制器：提供统一的倍速数据与操作
class PlaybackRatePaneController extends PlayerMenuPaneController {
  PlaybackRatePaneController({required super.videoState});

  static const List<double> _speedOptions = [
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    2.5,
    3.0,
    4.0,
    5.0,
  ];

  List<double> get speedOptions => _speedOptions;

  double get currentRate => videoState.playbackRate;

  double get minCustomRate => VideoPlayerState.minPlaybackRate;

  double get maxCustomRate => VideoPlayerState.maxPlaybackRate;

  bool get isSpeedBoostActive => videoState.isSpeedBoostActive;

  Future<void> setPlaybackRate(double rate) => videoState.setPlaybackRate(rate);

  @override
  PlayerMenuPaneId get paneId => PlayerMenuPaneId.playbackRate;
}

/// 播放设置控制器：同一套逻辑供不同主题的 UI 复用
class SeekStepPaneController extends PlayerMenuPaneController {
  SeekStepPaneController({required super.videoState}) {
    videoState.refreshSeekStepFrameRateEstimate();
  }

  static const List<double> _seekStepPresetOptions = [
    0.5,
    1.0,
    5.0,
    10.0,
    15.0,
    30.0,
    60.0,
  ];
  static const List<double> _speedBoostOptions = [
    1.25,
    1.5,
    2.0,
    2.5,
    3.0,
    4.0,
    5.0,
  ];

  static const int minSkipSeconds = 10;
  static const int maxSkipSeconds = 600;

  List<double> get seekStepOptions {
    final min = seekStepMinSeconds;
    final max = seekStepMaxSeconds;
    final values = <double>[min, ..._seekStepPresetOptions];
    final result = <double>[];
    for (final raw in values) {
      final clamped = raw.clamp(min, max).toDouble();
      final alreadyAdded = result.any(
        (value) =>
            (value - clamped).abs() <
            VideoPlayerState.seekStepComparisonEpsilon,
      );
      if (!alreadyAdded) {
        result.add(clamped);
      }
    }
    return result;
  }

  List<double> get speedBoostOptions => _speedBoostOptions;

  double get seekStepSeconds => videoState.seekStepSeconds;

  double get seekStepMinSeconds => videoState.seekStepMinSeconds;

  double get seekStepMaxSeconds => videoState.seekStepMaxSeconds;

  bool get hasSeekStepDurationLimit => videoState.hasSeekStepDurationLimit;

  double get seekStepFrameRate => videoState.seekStepFrameRate;

  String get seekStepDisplayLabel => videoState.seekStepDisplayLabel;

  String get seekStepSummaryLabel => videoState.seekStepSummaryLabel;

  String get seekStepInputValue =>
      videoState.formatSeekStepSecondsValue(seekStepSeconds);

  String get seekStepMinimumInputValue =>
      videoState.formatSeekStepSecondsValue(seekStepMinSeconds);

  String get seekStepMaximumInputValue =>
      videoState.formatSeekStepSecondsValue(seekStepMaxSeconds);

  String get seekStepInputRangeHint {
    final minimum = seekStepMinimumInputValue;
    final maximum = seekStepMaximumInputValue;
    if (hasSeekStepDurationLimit) {
      return '可输入 $minimum ~ $maximum 秒，最大不会超过当前视频时长';
    }
    return '可输入 $minimum ~ $maximum 秒，时长未就绪时先按默认上限处理';
  }

  String formatSeekStepLabel(
    double seconds, {
    bool preferFrameLabel = false,
    bool includeFrameApproximation = false,
  }) => videoState.formatSeekStepLabel(
    seconds,
    preferFrameLabel: preferFrameLabel,
    includeFrameApproximation: includeFrameApproximation,
  );

  bool isSeekStepSelected(double seconds) =>
      (seekStepSeconds - seconds).abs() <
      VideoPlayerState.seekStepComparisonEpsilon;

  bool isFrameSeekStep(double seconds) =>
      videoState.isFrameSeekStepValue(seconds);

  double get speedBoostRate => videoState.speedBoostRate;

  int get skipSeconds => videoState.skipSeconds;

  Future<void> setSeekStepSeconds(double seconds) =>
      videoState.setSeekStepSeconds(seconds);

  Future<void> setSpeedBoostRate(double rate) =>
      videoState.setSpeedBoostRate(rate);

  Future<void> setSkipSeconds(int seconds) =>
      videoState.setSkipSeconds(_clampSkipSeconds(seconds));

  Future<void> increaseSkipSeconds([int delta = 10]) =>
      setSkipSeconds(skipSeconds + delta);

  Future<void> decreaseSkipSeconds([int delta = 10]) =>
      setSkipSeconds(skipSeconds - delta);

  int _clampSkipSeconds(int value) =>
      value.clamp(minSkipSeconds, maxSkipSeconds).toInt();

  @override
  PlayerMenuPaneId get paneId => PlayerMenuPaneId.seekStep;
}

/// 字幕设置控制器：提供字幕大小设置（Media Kit / libass）
class SubtitleSettingsPaneController extends PlayerMenuPaneController {
  SubtitleSettingsPaneController({required super.videoState});

  double get subtitleScale => videoState.subtitleScale;

  Future<void> setSubtitleScale(double scale) =>
      videoState.setSubtitleScale(scale);

  double get minScale => VideoPlayerState.minSubtitleScale;

  double get maxScale => VideoPlayerState.maxSubtitleScale;

  @override
  PlayerMenuPaneId get paneId => PlayerMenuPaneId.subtitleSettings;
}

typedef PlayerMenuPaneControllerBuilder =
    PlayerMenuPaneController Function(VideoPlayerState videoState);

/// 注册已经完成逻辑解耦的 Pane，方便主题统一取用
class PlayerMenuPaneControllerFactory {
  PlayerMenuPaneControllerFactory._();

  static final Map<PlayerMenuPaneId, PlayerMenuPaneControllerBuilder>
  _builders = {
    PlayerMenuPaneId.playbackRate: (videoState) =>
        PlaybackRatePaneController(videoState: videoState),
    PlayerMenuPaneId.seekStep: (videoState) =>
        SeekStepPaneController(videoState: videoState),
    PlayerMenuPaneId.subtitleSettings: (videoState) =>
        SubtitleSettingsPaneController(videoState: videoState),
  };

  static bool supports(PlayerMenuPaneId paneId) =>
      _builders.containsKey(paneId);

  static PlayerMenuPaneController? tryCreate(
    PlayerMenuPaneId paneId,
    VideoPlayerState videoState,
  ) {
    final builder = _builders[paneId];
    return builder?.call(videoState);
  }
}
