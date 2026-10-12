import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay_core/models/danmaku/danmaku_item.dart';
import 'package:nipaplay_core/player/nipa_player.dart';
import 'package:nipaplay_ui_common/l10n/app_localizations.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';

import '../../danmaku/tv_danmaku_overlay.dart';
import '../../player/video_player_nipa_adapter.dart';

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
  });

  final MediaSource source;
  final String title;
  final List<DanmakuItem> danmakuItems;

  @override
  State<TvPlayerPage> createState() => _TvPlayerPageState();
}

class _TvPlayerPageState extends State<TvPlayerPage> {
  final _player = VideoPlayerNipaAdapter();
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;

  PlayerState _state = PlayerState.idle;
  Duration _position = Duration.zero;
  bool _controlsVisible = true;
  bool _danmakuEnabled = true;
  Timer? _hideTimer;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _stateSub = _player.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _posSub = _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _boot();
    _scheduleHide();
  }

  Future<void> _boot() async {
    try {
      await _player.initialize(const PlayerConfig());
      await _player.load(widget.source);
      await _player.play();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _stateSub?.cancel();
    _posSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _togglePlay() async {
    if (_player.isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
    _scheduleHide();
  }

  Future<void> _seekBy(int seconds) async {
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _player.duration ? _player.duration : target);
    await _player.seek(clamped);
    _scheduleHide();
  }

  /// 触摸拖动进度条：按比例 seek。
  Future<void> _seekToFraction(double fraction) async {
    final f = fraction.clamp(0.0, 1.0);
    final duration = _player.duration;
    if (duration.inMilliseconds == 0) return;
    await _player.seek(Duration(
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
    final duration = _player.duration;
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
              ),
            ),
            Center(
              child: _error != null
                  ? _errorPane(l10n)
                  : (_player.isInitialized
                      ? _player.buildSurface()
                      : const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF26C6DA)))),
            ),
            if (_error == null)
              TvDanmakuOverlay(
                items: widget.danmakuItems,
                position: _position,
                enabled: _danmakuEnabled,
              ),
            if (_controlsVisible) _controlsOverlay(context, progress),
          ],
        ),
      ),
    );
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
                    Text(_fmt(_player.duration),
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
                    Text('${widget.danmakuItems.length} 条弹幕',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.white38)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
