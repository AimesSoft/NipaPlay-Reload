import 'dart:async';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay_core/player/nipa_player.dart';

/// Erika 内核适配器：core [NipaPlayer] 的 TV 实现之一。
///
/// Erika 是自研播放内核（Rust/原生），支持 Android/iOS/tvOS/macOS/Windows/OHOS。
/// 通过 [ErikaVideoView] 提供平台视图或纹理表面，事件流给出状态与进度。
class ErikaNipaAdapter implements NipaPlayer {
  final ErikaPlayer _player = ErikaPlayer();
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  StreamSubscription<ErikaPlayerEvent>? _eventSub;
  PlayerState _state = PlayerState.idle;
  Duration _duration = Duration.zero;
  bool _ready = false;
  bool _playing = false;

  @override
  PlayerCapabilities get capabilities => const PlayerCapabilities(
        supportsExternalSubtitles: true,
        supportsBufferRange: false,
        supportsDecoderSelection: true,
        supportsPropertyQuery: false,
      );

  @override
  Future<void> initialize(PlayerConfig config) async {
    _eventSub = _player.events.listen(_onEvent);
    await _player.ensureCreated();
  }

  void _onEvent(ErikaPlayerEvent event) {
    if (event.duration > Duration.zero) _duration = event.duration;
    if (!_positionController.isClosed) {
      _positionController.add(event.position);
    }
    if (event.error != null) {
      _emitState(PlayerState.error);
      return;
    }
    if (event.buffering) {
      _emitState(PlayerState.buffering);
      return;
    }
    final s = event.state;
    if (s == ErikaPlaybackState.playing) {
      _playing = true;
      _emitState(PlayerState.playing);
    } else if (s == ErikaPlaybackState.paused) {
      _playing = false;
      _emitState(PlayerState.paused);
    } else if (s == ErikaPlaybackState.closed ||
        s == ErikaPlaybackState.stopped) {
      _playing = false;
      _emitState(PlayerState.completed);
    }
  }

  @override
  Future<void> load(MediaSource source) async {
    _emitState(PlayerState.buffering);
    await _player.open(source.uri, httpHeaders: source.httpHeaders);
    _ready = true;
  }

  void _emitState(PlayerState next) {
    if (_state == next || _stateController.isClosed) return;
    _state = next;
    _stateController.add(next);
  }

  @override
  Future<void> play() async {
    await _player.play();
    _emitState(PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _emitState(PlayerState.paused);
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    if (!_positionController.isClosed) _positionController.add(position);
  }

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  NipaPlayerSurface createSurfaceHandle() {
    if (!_ready) return const NipaPlayerSurface.none();
    // Erika 在移动端走纹理/平台视图，由 buildSurface 决定实际形态。
    return const NipaPlayerSurface.platformView(0);
  }

  /// TV 侧渲染入口：Erika 提供现成视图 Widget。
  Widget buildSurface({BoxFit fit = BoxFit.contain}) {
    return ErikaVideoView(player: _player);
  }

  Duration get duration => _duration;
  Duration get position => _duration; // 由事件流更新，页面用 positionStream
  bool get isInitialized => _ready;
  bool get isPlaying => _playing;
  double get aspectRatio => 16 / 9;

  @override
  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    await _player.close();
    await _player.dispose();
    await _stateController.close();
    await _positionController.close();
  }
}

/// Erika 内核工厂：自研内核，Android/tvOS/桌面可用。
class ErikaNipaFactory implements PlayerFactory {
  const ErikaNipaFactory();

  @override
  NipaPlayer create() => ErikaNipaAdapter();

  @override
  bool supportsPlatform(NipaTargetPlatform platform) =>
      platform == NipaTargetPlatform.android ||
      platform == NipaTargetPlatform.ios ||
      platform == NipaTargetPlatform.tvos ||
      platform == NipaTargetPlatform.macos ||
      platform == NipaTargetPlatform.windows ||
      platform == NipaTargetPlatform.ohos;

  @override
  int get priority => 80;
}
