import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'globals.dart' as globals;

class ScreenOrientationManager {
  static const Duration _harmonyPlatformCallTimeout = Duration(
    milliseconds: 300,
  );

  static ScreenOrientationManager? _instance;
  static ScreenOrientationManager get instance =>
      _instance ??= ScreenOrientationManager._();

  ScreenOrientationManager._()
      : _isHarmonyOSOverride = null,
        _isMobilePlatformOverride = null,
        _isTabletOverride = null;

  @visibleForTesting
  ScreenOrientationManager.forTesting({
    required bool isHarmonyOS,
    bool? isMobilePlatform,
    bool? isTablet,
  })  : _isHarmonyOSOverride = isHarmonyOS,
        _isMobilePlatformOverride = isMobilePlatform,
        _isTabletOverride = isTablet;

  final bool? _isHarmonyOSOverride;
  final bool? _isMobilePlatformOverride;
  final bool? _isTabletOverride;

  bool get _isMobilePlatform =>
      _isMobilePlatformOverride ?? globals.isMobilePlatform;
  bool get _isTablet => _isTabletOverride ?? globals.isTablet;

  bool _isTransitioning = false;
  Future<void> _orientationTail = Future<void>.value();
  int _pendingOrientations = 0;
  bool _isTabletDevice = false; // 记录是否为平板设备（基于进入时的判断，固定不变）

  // 获取当前是否处于横屏状态
  bool get isLandscape {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.width > size.height;
  }

  // 是否正在转换中
  bool get isTransitioning => _isTransitioning || _pendingOrientations > 0;

  Future<void> _queueOrientation(Future<void> Function() change) {
    _pendingOrientations++;
    final operation = _orientationTail.then((_) => change()).whenComplete(() {
      _pendingOrientations--;
    });
    _orientationTail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// OHOS can apply a system-bar change without replying on the channel.
  /// All playback callers must use the same bounded wait, including tablet
  /// startup, fullscreen controls and the final step of resetPlayer.
  Future<void> setSystemUiMode(SystemUiMode mode) => _awaitSystemChromeCall(
        SystemChrome.setEnabledSystemUIMode(mode),
        'enable ${mode.name} system UI',
      );

  // 设置初始屏幕方向（进入播放器时调用）
  Future<void> setInitialOrientation() async {
    if (!_isMobilePlatform) return;

    // 记录是否为平板设备（基于进入时的判断，固定不变）
    _isTabletDevice = _isTablet;

    _isTransitioning = true;
    try {
      if (_isTabletDevice) {
        // 平板设备：强制横屏并锁定
        await _setLandscapeOnly();
      } else {
        // 手机设备：设置为竖屏
        await _setPortraitOnly();
      }
    } finally {
      _isTransitioning = false;
    }
  }

  // 播放视频时的屏幕方向设置
  Future<void> setVideoPlayingOrientation() async {
    if (!_isMobilePlatform) return;

    _isTransitioning = true;
    try {
      if (_isTabletDevice) {
        // 每次播放都重新确认横屏，修复退出或外部操作留下的竖屏锁定。
        await _setLandscapeOnly(allowTransientPortrait: false);
      } else {
        // 手机开始播放时默认进入横屏全屏。
        await _setLandscapeOnly();
      }
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> setPhonePlaybackLandscape() async {
    if (!_isMobilePlatform || _isTablet) return;
    _isTransitioning = true;
    try {
      await _setLandscapeOnly();
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> setPhonePlaybackPortrait() async {
    if (!_isMobilePlatform || _isTablet) return;
    _isTransitioning = true;
    try {
      await _setPortraitOnly();
    } finally {
      _isTransitioning = false;
    }
  }

  // 停止播放视频时的屏幕方向设置
  Future<void> setVideoStoppedOrientation() async {
    if (!_isMobilePlatform) return;

    _isTransitioning = true;
    try {
      if (_isTabletDevice) {
        // 平板主界面沿用启动后的横屏策略，不恢复系统启动前的竖屏。
        await _setLandscapeOnly(allowTransientPortrait: false);
      } else {
        // 手机设备：切换回竖屏
        await _setPortraitOnly();
      }
    } finally {
      _isTransitioning = false;
    }
  }

  // 重置播放器时的屏幕方向设置
  Future<void> resetOrientation() async {
    if (!_isMobilePlatform) return;

    _isTransitioning = true;
    try {
      if (_isTabletDevice) {
        // 与平板主界面的横屏策略一致，避免退出后锁死在竖屏。
        await _setLandscapeOnly(allowTransientPortrait: false);
      } else {
        // 手机设备：切换回竖屏
        await _setPortraitOnly();
      }
    } finally {
      _isTransitioning = false;
    }
  }

  // 设置横屏并锁定
  // allowTransientPortrait 用于从竖屏过渡到横屏时的短暂放开（某些设备需要）。
  Future<void> _setLandscapeOnly({bool allowTransientPortrait = true}) =>
      _queueOrientation(() =>
          _applyLandscapeOnly(allowTransientPortrait: allowTransientPortrait));

  Future<void> _applyLandscapeOnly(
      {required bool allowTransientPortrait}) async {
    try {
      if (allowTransientPortrait) {
        await _awaitSystemChromeCall(
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
            DeviceOrientation.portraitUp,
          ]),
          'allow transient portrait before landscape',
        );
        await Future.delayed(const Duration(milliseconds: 100));
      }
      await _awaitSystemChromeCall(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
        'lock landscape orientation',
      );

      if (_isTabletDevice) {
        // 平板设备不自动隐藏系统UI，由全屏按钮控制
        await setSystemUiMode(SystemUiMode.edgeToEdge);
      } else {
        // 手机设备隐藏系统UI
        await setSystemUiMode(SystemUiMode.immersiveSticky);
      }

      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('设置横屏时出错: $e');
    }
  }

  // 设置竖屏并锁定
  Future<void> _setPortraitOnly() => _queueOrientation(_applyPortraitOnly);

  Future<void> _applyPortraitOnly() async {
    try {
      await _awaitSystemChromeCall(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
          DeviceOrientation.portraitUp,
        ]),
        'allow transient landscape before portrait',
      );
      await Future.delayed(const Duration(milliseconds: 100));
      await _awaitSystemChromeCall(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]),
        'lock portrait orientation',
      );
      await setSystemUiMode(SystemUiMode.edgeToEdge);
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('设置竖屏时出错: $e');
    }
  }

  // 恢复自由旋转（不建议使用，除非特殊需求）
  Future<void> enableFreeRotation() async {
    if (!_isMobilePlatform) return;

    try {
      await _awaitSystemChromeCall(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
        'enable free rotation',
      );
      await setSystemUiMode(SystemUiMode.edgeToEdge);
    } catch (e) {
      debugPrint('恢复自由旋转时出错: $e');
    }
  }

  Future<void> _awaitSystemChromeCall(
    Future<void> operation,
    String description,
  ) async {
    if (!(_isHarmonyOSOverride ?? globals.isHarmonyOS)) {
      await operation;
      return;
    }

    try {
      await operation.timeout(_harmonyPlatformCallTimeout);
    } on TimeoutException {
      // The HarmonyOS Flutter embedder applies orientation/system-UI changes
      // but may never reply to the platform-channel request. Playback startup
      // must not remain blocked waiting for that missing reply.
      debugPrint(
        '[ScreenOrientationManager] HarmonyOS platform call timed out '
        '($description); continuing.',
      );
    }
  }
}
