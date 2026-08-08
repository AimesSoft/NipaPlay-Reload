import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 大屏幕模式下的 UI 音效类型。
enum LargeScreenUiSfx {
  /// 焦点在可交互元素之间移动（键盘/手柄方向键导航）
  focusChange,

  /// 开关类设置项切换为开启
  switchOn,

  /// 开关类设置项切换为关闭
  switchOff,

  /// 打开子页面 / 进入二级面板 / 选择类设置项展开
  openSubPage,

  /// 关闭子页面 / 退出二级面板
  closeSubPage,

  /// 播放器菜单面板弹出
  menuOpen,

  /// 播放器菜单面板收起
  menuClose,

  /// 侧边栏 Tab 切换（媒体库页面的本地媒体库等按钮 / 播放器菜单分类切换）
  tabSwitch,

  /// 设置中滑动条类设置项的值变化（左右键调节）
  sliderChange,
}

/// 大屏幕模式 UI 音效服务。
///
/// 仅在大屏幕模式激活时播放音效。所有音效文件位于 `assets/sfx/` 目录下。
///
/// 使用懒加载的播放器池：每种音效类型对应一个独立的 [AudioPlayer]，
/// 避免快速连续触发时互相打断（如连续方向键导航）。
class LargeScreenUiSfxService with ChangeNotifier {
  LargeScreenUiSfxService() {
    // 设置全局 AudioContext：使用 mixWithOthers 确保与其他音频源共存。
    // 注意：macOS 上 AudioContext 是 no-op，不影响播放。
    try {
      AudioPlayer.global.setAudioContext(
        AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
      debugPrint('LargeScreenUiSfxService: 全局 AudioContext 已设置');
    } catch (e) {
      debugPrint('LargeScreenUiSfxService: 设置 AudioContext 失败 (可忽略): $e');
    }
  }

  /// 枚举值到 asset 路径（相对于 assets/ 目录）的映射。
  static const Map<LargeScreenUiSfx, String> _assetPaths = {
    LargeScreenUiSfx.focusChange: 'sfx/focus_change.ogg',
    LargeScreenUiSfx.switchOn: 'sfx/switch_on.ogg',
    LargeScreenUiSfx.switchOff: 'sfx/switch_off.ogg',
    LargeScreenUiSfx.openSubPage: 'sfx/open_sub_page.ogg',
    LargeScreenUiSfx.closeSubPage: 'sfx/close_sub_page.ogg',
    LargeScreenUiSfx.menuOpen: 'sfx/menu_open.ogg',
    LargeScreenUiSfx.menuClose: 'sfx/menu_close.ogg',
    LargeScreenUiSfx.tabSwitch: 'sfx/tab_switch.ogg',
    LargeScreenUiSfx.sliderChange: 'sfx/slider_change.ogg',
  };

  final Map<LargeScreenUiSfx, AudioPlayer> _players = {};

  bool _largeScreenModeActive = false;
  bool _enabled = true;

  /// 当前是否处于大屏幕模式。仅当为 true 时才播放音效。
  bool get largeScreenModeActive => _largeScreenModeActive;

  set largeScreenModeActive(bool value) {
    if (_largeScreenModeActive == value) return;
    _largeScreenModeActive = value;
    debugPrint('LargeScreenUiSfxService: largeScreenModeActive = $value');
    notifyListeners();
  }

  /// 用户是否开启了大屏幕 UI 音效（预留设置项，默认 true）。
  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  /// 获取或创建指定音效类型对应的播放器。
  AudioPlayer _playerFor(LargeScreenUiSfx sfx) {
    return _players.putIfAbsent(sfx, () {
      final player = AudioPlayer();
      player.setReleaseMode(ReleaseMode.stop);
      player.onPlayerStateChanged.listen((state) {
        debugPrint('LargeScreenUiSfxService: 播放器状态 ($sfx): $state');
      });
      player.onLog.listen((msg) {
        debugPrint('LargeScreenUiSfxService: 播放器日志 ($sfx): $msg');
      });
      return player;
    });
  }

  /// 播放指定类型的 UI 音效。
  ///
  /// 如果大屏幕模式未激活或音效被禁用，则静默返回。
  /// 同一音效类型的连续播放会打断前一次（如快速连续方向键），
  /// 不同音效类型互不影响。
  Future<void> play(LargeScreenUiSfx sfx) async {
    if (!_largeScreenModeActive || !_enabled) {
      debugPrint(
        'LargeScreenUiSfxService: 跳过播放 ($sfx) — '
        'largeScreenModeActive=$_largeScreenModeActive, enabled=$_enabled',
      );
      return;
    }
    final assetPath = _assetPaths[sfx];
    if (assetPath == null) {
      debugPrint('LargeScreenUiSfxService: 未知音效类型 $sfx，无路径映射');
      return;
    }
    debugPrint('LargeScreenUiSfxService: 播放音效 $sfx (路径: $assetPath)');
    try {
      final player = _playerFor(sfx);
      await player.play(AssetSource(assetPath), volume: 1.0);
    } catch (e) {
      debugPrint('LargeScreenUiSfxService: 播放音效失败 ($sfx): $e');
    }
  }

  /// 便捷方法：焦点切换
  Future<void> playFocusChange() => play(LargeScreenUiSfx.focusChange);

  /// 便捷方法：开关开启
  Future<void> playSwitchOn() => play(LargeScreenUiSfx.switchOn);

  /// 便捷方法：开关关闭
  Future<void> playSwitchOff() => play(LargeScreenUiSfx.switchOff);

  /// 便捷方法：打开子页面
  Future<void> playOpenSubPage() => play(LargeScreenUiSfx.openSubPage);

  /// 便捷方法：关闭子页面
  Future<void> playCloseSubPage() => play(LargeScreenUiSfx.closeSubPage);

  /// 便捷方法：菜单弹出
  Future<void> playMenuOpen() => play(LargeScreenUiSfx.menuOpen);

  /// 便捷方法：菜单收起
  Future<void> playMenuClose() => play(LargeScreenUiSfx.menuClose);

  /// 便捷方法：分区栏切换
  Future<void> playTabSwitch() => play(LargeScreenUiSfx.tabSwitch);

  /// 便捷方法：滑动条值变化
  Future<void> playSliderChange() => play(LargeScreenUiSfx.sliderChange);

  @override
  void dispose() {
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
    super.dispose();
  }
}
