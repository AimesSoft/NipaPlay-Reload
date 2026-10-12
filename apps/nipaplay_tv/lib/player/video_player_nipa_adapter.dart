import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nipaplay_core/player/nipa_player.dart';
import 'package:video_player/video_player.dart';

/// TV 版内核适配器：把官方 video_player 插件包装成 core 的统一 [NipaPlayer] 接口。
///
/// 这验证了阶段一的架构承诺：core 只定义接口，各版本各自提供内核实现。
/// 普通版把四内核（media_kit / MDK / Erika / video_player）绑在 app 侧，
/// TV 版从这里起步，后续可替换为 media_kit 以获得更全的格式与字幕支持。
class VideoPlayerNipaAdapter implements NipaPlayer {
  VideoPlayerController? _controller;
  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  Timer? _positionTimer;
  PlayerState _state = PlayerState.idle;

  @override
  PlayerCapabilities get capabilities => const PlayerCapabilities(
        supportsExternalSubtitles: true,
        supportsBufferRange: false,
        supportsDecoderSelection: false,
        supportsPropertyQuery: false,
      );

  @override
  Future<void> initialize(PlayerConfig config) async {
    // video_player 无初始化配置入口；UA/代理需在 load 时按 MediaSource 提供。
  }

  @override
  Future<void> load(MediaSource source) async {
    await disposeControllerOnly();
    final uri = Uri.parse(source.uri);
    final controller = source.httpHeaders.isEmpty
        ? VideoPlayerController.networkUrl(uri)
        : VideoPlayerController.networkUrl(uri, httpHeaders: source.httpHeaders);
    _controller = controller;
    await controller.initialize();
    controller.addListener(_onControllerTick);
    _emitState(controller.value.isPlaying
        ? PlayerState.playing
        : PlayerState.paused);
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final value = _controller?.value;
      if (value != null && value.isInitialized) {
        _positionController.add(value.position);
      }
    });
  }

  void _onControllerTick() {
    final value = _controller?.value;
    if (value == null) return;
    if (value.hasError) {
      _emitState(PlayerState.error);
      return;
    }
    if (!value.isInitialized) {
      _emitState(PlayerState.buffering);
      return;
    }
    if (value.isCompleted) {
      _emitState(PlayerState.completed);
    } else if (value.isPlaying) {
      _emitState(PlayerState.playing);
    } else if (value.isBuffering) {
      _emitState(PlayerState.buffering);
    } else {
      _emitState(PlayerState.paused);
    }
  }

  void _emitState(PlayerState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  @override
  Future<void> play() async {
    await _controller?.play();
  }

  @override
  Future<void> pause() async {
    await _controller?.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _controller?.seekTo(position);
    _positionController.add(position);
  }

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  NipaPlayerSurface createSurfaceHandle() {
    // video_player 的底层句柄（playerId）标记为 visibleForTesting，不适合跨包读取；
    // 这里按 core 的语义只声明"由本适配器提供纹理表面"，
    // 具体纹理 Widget 由 buildSurface() 在 TV 侧构造。
    if (!(_controller?.value.isInitialized ?? false)) {
      return const NipaPlayerSurface.none();
    }
    return const NipaPlayerSurface.platformView(0);
  }

  /// TV 侧渲染入口：按 core 的 surface 描述符构造平台视图 Widget。
  Widget buildSurface({BoxFit fit = BoxFit.contain}) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }

  Duration get duration => _controller?.value.duration ?? Duration.zero;
  Duration get position => _controller?.value.position ?? Duration.zero;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isPlaying => _controller?.value.isPlaying ?? false;
  double get aspectRatio => _controller?.value.aspectRatio ?? 16 / 9;

  Future<void> disposeControllerOnly() async {
    _positionTimer?.cancel();
    _positionTimer = null;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onControllerTick);
      await controller.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    await disposeControllerOnly();
    await _stateController.close();
    await _positionController.close();
  }
}

/// TV 版内核工厂：声明本内核支持 Android/移动/桌面（video_player 平台能力）。
class VideoPlayerNipaFactory implements PlayerFactory {
  const VideoPlayerNipaFactory();

  @override
  NipaPlayer create() => VideoPlayerNipaAdapter();

  @override
  bool supportsPlatform(NipaTargetPlatform platform) =>
      platform == NipaTargetPlatform.android ||
      platform == NipaTargetPlatform.ios ||
      platform == NipaTargetPlatform.web;

  @override
  int get priority => 10;
}
