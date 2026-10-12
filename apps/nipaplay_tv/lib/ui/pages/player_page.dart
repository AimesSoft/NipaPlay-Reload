import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay_core/models/danmaku/danmaku_item.dart';
import 'package:nipaplay_core/player/nipa_player.dart';
import 'package:nipaplay_ui_common/l10n/app_localizations.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';

import '../../danmaku/tv_danmaku_overlay.dart';
import '../../data/tv_recent_play_store.dart';
import '../focusable_card.dart';
import '../../danmaku/tv_danmaku_loader.dart';
import '../../player/tv_player_kernel_registry.dart';

/// TV 播放页：core 的 [NipaPlayer] 接口 + TV 自建播放控件与弹幕渲染。
///
/// D-pad：左/右 = 快退/快进 10s，中键 = 播放/暂停，上/下 = 显示/隐藏控件，
/// 返回键退出。弹幕来自 core 的 XML 解析（本页加载内置示例轨道）。
class TvPlayerPage extends StatefulWidget {
  const TvPlayerPage({
    super.key,
    required this.source,
    this.title = '',
    this.danmakuItems = const [],
    this.kernel,
  });

  final MediaSource source;
  final String title;
  final List<DanmakuItem> danmakuItems;

  /// 指定内核；null 时用用户设置（TvPlayerKernelRegistry.loadSelected）。
  final TvPlayerKernel? kernel;

  @override
  State<TvPlayerPage> createState() => _TvPlayerPageState();
}

class _TvPlayerPageState extends State<TvPlayerPage> {
  TvPlayerKernel? _kernel;
  NipaPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;

  PlayerState _state = PlayerState.idle;
  Duration _position = Duration.zero;
  bool _controlsVisible = true;
  bool _dragging = false;
  double _dragAccum = 0;
  bool _danmakuEnabled = true;
  List<DanmakuItem> _danmakuItems = const [];
  bool _danmakuLoading = false;
  String? _danmakuHint;
  Timer? _saveTimer;
  double _danmakuArea = 0.5;     // 弹幕占画面比例
  String _videoFit = 'auto';     // auto / 16:9 / 4:3
  String _upscaler = 'off';      // 画面超分（Erika artCNN）
  Timer? _hideTimer;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _boot();
    _scheduleHide();
  }

  Future<void> _boot() async {
    try {
      final kernel = widget.kernel ?? await TvPlayerKernelRegistry.loadSelected();
      final player = TvPlayerKernelRegistry.create(kernel);
      _kernel = kernel;
      _player = player;
      _stateSub = player.stateStream.listen((s) {
        if (mounted) setState(() => _state = s);
      });
      _posSub = player.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      // 读取播放偏好（弹幕占比 / 画面比例 / 超分）
      final area = await TvPlaybackPrefs.danmakuArea();
      final fit = await TvPlaybackPrefs.videoFit();
      final up = await TvPlaybackPrefs.upscaler();
      if (!mounted) return;
      setState(() {
        _danmakuArea = area;
        _videoFit = fit;
        _upscaler = up;
      });
      await player.initialize(const PlayerConfig());
      await player.load(widget.source);
      // 恢复上次播放进度
      final saved = await TvRecentPlayStore.progressOf(widget.source.uri);
      if (saved > 3000) {
        await player.seek(Duration(milliseconds: saved));
      }
      // 定期保存进度（每 10s）+ 退出时保存
      _saveTimer?.cancel();
      _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        final p = _position.inMilliseconds;
        if (p > 0) TvRecentPlayStore.saveProgress(widget.source.uri, p);
      });
      // 画面超分：仅 Erika 具备
      await kernelSetUpscaler(player, up);
      await player.play();
      // 自动加载弹幕（按文件名匹配弹弹play）
      unawaited(_loadDanmaku());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    // 退出时保存进度
    final p = _position.inMilliseconds;
    if (p > 0) TvRecentPlayStore.saveProgress(widget.source.uri, p);
    _saveTimer?.cancel();
    _hideTimer?.cancel();
    _stateSub?.cancel();
    _posSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    // 暂停时控件常驻：可随时调整弹幕开关/占比/画面比例
    if (_state == PlayerState.paused) {
      if (mounted && !_controlsVisible) setState(() => _controlsVisible = true);
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying()) {
      await _player?.pause();
    } else {
      await _player?.play();
    }
    _scheduleHide();
  }

  Future<void> _seekBy(int seconds) async {
    final target = _position + Duration(seconds: seconds);
    final duration = _duration();
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > duration ? duration : target);
    await _player?.seek(clamped);
    _scheduleHide();
  }

  /// 触摸拖动进度条：按比例 seek。
  Future<void> _seekToFraction(double fraction) async {
    final f = fraction.clamp(0.0, 1.0);
    final duration = _duration();
    if (duration.inMilliseconds == 0) return;
    await _player?.seek(Duration(
        milliseconds: (duration.inMilliseconds * f).round()));
    _scheduleHide();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.gameButtonA) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _toggleControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD) {
      setState(() => _danmakuEnabled = !_danmakuEnabled);
      return KeyEventResult.handled;
    }
    // 遥控快进/快退：媒体键 + 左右方向键（长按连续触发）
    if (key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(key == LogicalKeyboardKey.mediaFastForward ? 10 : -10);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      // 控件区展开时左右 = 快退/快进（快进快退）
      _seekBy(key == LogicalKeyboardKey.arrowRight ? 10 : -10);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final duration = _duration();
    final total = duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds;
    final progress =
        (_position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 触摸/点击：切换控件显隐（D-pad 用 ↑/↓ 同效）
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                // 长按快进（遥控器"长按右"在触屏 TV 上的等价手势）
                onLongPress: () => _seekBy(10),
                // 左右拖动 = 快进/快退（带进度反馈）
                onHorizontalDragUpdate: (d) {
                  setState(() => _dragging = true);
                  // 每 48px 触发一次 ±5s；累计到阈值才 seek，避免抖动
                  _dragAccum += d.delta.dx;
                  if (_dragAccum.abs() >= 48) {
                    final steps = (_dragAccum / 48).round();
                    _seekBy(steps * 5);
                    _dragAccum = 0;
                  }
                },
                onHorizontalDragEnd: (_) {
                  setState(() => _dragging = false);
                  _scheduleHide();
                },
              ),
            ),
            Center(
              child: _error != null
                  ? _errorPane(l10n)
                  : (_initialized()
                      ? _fitSurface(buildKernelSurface(_kernel!, _player!))
                      : const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF26C6DA)))),
            ),
            if (_error == null)
              TvDanmakuOverlay(
                items: _danmakuItems.isNotEmpty
                    ? _danmakuItems
                    : widget.danmakuItems,
                position: _position,
                enabled: _danmakuEnabled,
                areaRatio: _danmakuArea,
              ),
            if (_danmakuLoading)
              const Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Text('正在匹配弹幕…',
                      style: TextStyle(color: Colors.white54, fontSize: 14)),
                ),
              ),
            if (_danmakuHint != null)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(_danmakuHint!,
                      style: const TextStyle(color: Colors.white38, fontSize: 14)),
                ),
              ),
            // 拖动进度时的可见反馈
            if (_dragging)
              const Center(
                child: Icon(Icons.fast_forward, size: 48, color: Colors.white70),
              ),
            if (_controlsVisible) _controlsOverlay(context, progress),
          ],
        ),
      ),
    );
  }

  /// 画面比例：auto 原样；16:9 / 4:3 强制信箱式比例。
  Widget _fitSurface(Widget surface) {
    switch (_videoFit) {
      case '16:9':
        return Center(
            child: AspectRatio(aspectRatio: 16 / 9, child: surface));
      case '4:3':
        return Center(
            child: AspectRatio(aspectRatio: 4 / 3, child: surface));
      default:
        return surface;
    }
  }

  Widget _errorPane(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
          const SizedBox(height: 16),
          Text('播放失败',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 10),
          Text('$_error',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white54)),
          const SizedBox(height: 8),
          Text(widget.source.uri,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white38)),
          const SizedBox(height: 20),
          Text('按返回键退出',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _controlsOverlay(BuildContext context, double progress) {
    final l10n = context.l10n;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent, Colors.black87],
          stops: [0, 0.4, 1],
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Row(
              children: [
                const Icon(Icons.tv, color: Color(0xFF26C6DA), size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title.isEmpty ? l10n.tabVideoPlay : widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_danmakuEnabled)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.subtitles,
                        color: Color(0xFF26C6DA), size: 22),
                  ),
                Text('D-pad: ←/→ 快进退 · ● 播放/暂停 · ↑/↓ 控件 · D 弹幕',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.white38)),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(_fmt(_position),
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (d) => _seekToFraction(
                              d.localPosition.dx / constraints.maxWidth),
                          onHorizontalDragUpdate: (d) => _seekToFraction(
                              d.localPosition.dx / constraints.maxWidth),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 10,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation(
                                  Color(0xFF26C6DA)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(_fmt(_duration()),
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _togglePlay,
                      child: Icon(
                        _state == PlayerState.playing
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: const Color(0xFF26C6DA),
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(_stateLabel(_state),
                        style: Theme.of(context).textTheme.bodyMedium),
                    const Spacer(),
                    Text(
                        '${_danmakuItems.isNotEmpty ? _danmakuItems.length : widget.danmakuItems.length} 条弹幕'
                        '${_upscaler != 'off' ? ' · 超分 $_upscaler' : ''}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.white38)),
                  ],
                ),
                if (_state == PlayerState.paused) ...[
                  const SizedBox(height: 8),
                  _pausedAdjustRow(context),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 暂停时的调整行：弹幕开关 / 占比 -+ / 画面比例。
  Widget _pausedAdjustRow(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        _adjustChip(
          context,
          icon: Icons.subtitles_outlined,
          label: _danmakuEnabled ? '弹幕开' : '弹幕关',
          onTap: () =>
              setState(() => _danmakuEnabled = !_danmakuEnabled),
        ),
        _adjustChip(
          context,
          icon: Icons.text_fields_outlined,
          label: '占比 ${(_danmakuArea * 100).round()}%',
          onTap: () => _cycleDanmakuArea(),
        ),
        _adjustChip(
          context,
          icon: Icons.aspect_ratio,
          label: '比例 $_videoFit',
          onTap: () => _cycleVideoFit(),
        ),
      ],
    );
  }

  void _cycleDanmakuArea() {
    const steps = [0.3, 0.5, 0.7, 0.9];
    final next = steps
        .firstWhere((e) => e > _danmakuArea + 0.01, orElse: () => steps.first);
    setState(() => _danmakuArea = next);
    TvPlaybackPrefs.setDanmakuArea(next);
  }

  void _cycleVideoFit() {
    const modes = ['auto', '16:9', '4:3'];
    final idx = modes.indexOf(_videoFit);
    final next = modes[(idx + 1) % modes.length];
    setState(() => _videoFit = next);
    TvPlaybackPrefs.setVideoFit(next);
  }

  Widget _adjustChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return FocusableCard(
      onActivate: onTap,
      borderRadius: 10,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: Colors.white70),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.white70)),
        ],
      ),
    );
  }

  bool _isPlaying() =>
      (_kernel == null || _player == null)
          ? false
          : kernelIsPlaying(_kernel!, _player!);

  /// 进入播放页时自动匹配并加载弹幕。
  Future<void> _loadDanmaku() async {
    final uri = Uri.tryParse(widget.source.uri);
    if (uri == null) return;
    final fileName = uri.pathSegments.isEmpty
        ? uri.path
        : uri.pathSegments.last;
    if (fileName.isEmpty) return;
    setState(() {
      _danmakuLoading = true;
      _danmakuHint = null;
    });
    final items = await TvDanmakuLoader.instance.loadForFile(
      fileName: fileName,
      fileSize: 0,
    );
    if (!mounted) return;
    setState(() {
      _danmakuLoading = false;
      if (items == null) {
        _danmakuHint = '弹幕需登录弹弹play账号（「我的」→ 登录）';
      } else if (items.isEmpty) {
        _danmakuHint = '已匹配，但该番剧暂无弹幕';
      } else {
        _danmakuItems = items;
      }
    });
  }

  Duration _duration() =>
      (_kernel == null || _player == null) ? Duration.zero
          : kernelDuration(_kernel!, _player!);

  bool _initialized() =>
      (_kernel != null && _player != null) &&
      kernelIsInitialized(_kernel!, _player!);

  String _stateLabel(PlayerState s) => switch (s) {
        PlayerState.idle => '就绪',
        PlayerState.buffering => '缓冲中',
        PlayerState.playing => '播放中',
        PlayerState.paused => '已暂停',
        PlayerState.completed => '已结束',
        PlayerState.error => '错误',
      };
}

/// 供页面打开本机演示文件（app 外部私有目录，无需额外权限）。
Future<bool> demoFileExists() async {
  final dir = Directory(
      '/sdcard/Android/data/com.aimessoft.nipaplay_tv/files');
  if (!await dir.exists()) return false;
  return dir
      .list()
      .any((e) => e is File && e.path.toLowerCase().endsWith('.mp4'));
}

Future<String?> demoFilePath() async {
  final dir = Directory(
      '/sdcard/Android/data/com.aimessoft.nipaplay_tv/files');
  if (!await dir.exists()) return null;
  await for (final e in dir.list()) {
    if (e is File && e.path.toLowerCase().endsWith('.mp4')) return e.path;
  }
  return null;
}
