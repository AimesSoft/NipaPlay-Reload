import 'package:flutter/foundation.dart';

import 'package:nipaplay_core/player_abstraction/abstract_player.dart' as core;
import 'package:nipaplay_core/player_abstraction/player_data_models.dart';
import 'package:nipaplay_core/player_abstraction/player_enums.dart';
import 'player_factory.dart';

/// A [core.AbstractPlayer] that defers creating the real kernel-backed player
/// until the first media is opened. Startup constructs exactly one of these
/// (via `Player()`), so the app idle cost no longer includes the mdk-sdk /
/// libmpv / Erika native library load and its decoder pools.
///
/// Everything except [setMedia]/[prepare] is answered with inert defaults
/// before materialization — that is safe because `VideoPlayerState`'s
/// startup path only reads settings-facing accessors (volume, kernel name,
/// texture id) and never drives playback without having opened media first,
/// and `open`/`setMedia` are the only entry points that lead to playback.
class LazyPlayerDelegate
    implements
        core.AbstractPlayer,
        core.MediaLoadAwarePlayer,
        core.AsyncDisposablePlayer,
        core.AsyncSeekPlayer,
        core.AsyncExternalSubtitlePlayer,
        core.GifExportCapablePlayer {
  LazyPlayerDelegate(this._factory);

  final PlayerFactory _factory;
  core.AbstractPlayer? _real;
  bool _materializing = false;
  String _pendingMedia = '';
  PlayerMediaType? _pendingMediaType;

  /// The realized kernel player, or null while nothing has been opened.
  core.AbstractPlayer? get realized => _real;

  core.AbstractPlayer get _requireReal => _real!;

  /// Creates the real kernel player if not yet created. Called from
  /// [setMedia] (the only path that leads to playback) and from
  /// [retryCurrentMediaLoad].
  void _materialize() {
    if (_real != null || _materializing) {
      return;
    }
    _materializing = true;
    try {
      _real = _factory.createPlayer();
      final media = _pendingMedia;
      final type = _pendingMediaType;
      if (media.isNotEmpty && type != null) {
        _real!.setMedia(media, type);
      }
    } finally {
      _materializing = false;
    }
  }

  bool get _hasReal => _real != null;

  @override
  void setMedia(String path, PlayerMediaType type) {
    _pendingMedia = path;
    _pendingMediaType = type;
    _materialize();
    _requireReal.setMedia(path, type);
  }

  @override
  String get media => _hasReal ? _requireReal.media : _pendingMedia;
  @override
  set media(String value) {
    _pendingMedia = value;
    if (_hasReal) _requireReal.media = value;
  }

  @override
  Future<void> prepare() async {
    _materialize();
    await _requireReal.prepare();
  }

  @override
  Future<bool> retryCurrentMediaLoad() async {
    final delegate = _real;
    if (delegate is core.MediaLoadAwarePlayer) {
      // Unrelated interfaces do not type-promote; cast explicitly.
      return (delegate as core.MediaLoadAwarePlayer).retryCurrentMediaLoad();
    }
    return false;
  }

  @override
  void dispose() {
    _real?.dispose();
    _real = null;
  }

  @override
  Future<void> disposeAsync() async {
    final real = _real;
    _real = null;
    if (real == null) return;
    if (real is core.AsyncDisposablePlayer) {
      await (real as core.AsyncDisposablePlayer).disposeAsync();
    } else {
      real.dispose();
    }
  }

  // ── Inert before materialization; forwarded afterwards ──
  // Media-load readiness lives on the optional MediaLoadAwarePlayer
  // capability, so forward through capability checks like the Player
  // wrapper does.

  core.MediaLoadAwarePlayer? get _mediaLoadAware =>
      _real is core.MediaLoadAwarePlayer ? _real as core.MediaLoadAwarePlayer : null;

  @override
  bool get isMediaReady => _mediaLoadAware?.isMediaReady ?? false;

  @override
  bool get hasReceivedRealPosition =>
      _mediaLoadAware?.hasReceivedRealPosition ?? true;

  @override
  bool get hasMediaLoadFailed => _mediaLoadAware?.hasMediaLoadFailed ?? false;

  @override
  String? get mediaLoadError => _mediaLoadAware?.mediaLoadError;

  @override
  Future<bool> waitUntilMediaReady({required Duration timeout}) async {
    final aware = _mediaLoadAware;
    if (aware == null) return false;
    return aware.waitUntilMediaReady(timeout: timeout);
  }

  @override
  int get position => _hasReal ? _requireReal.position : 0;
  @override
  int get bufferedPosition => _hasReal ? _requireReal.bufferedPosition : 0;

  @override
  double get volume => _hasReal ? _requireReal.volume : 1.0;
  @override
  set volume(double value) {
    if (_hasReal) _requireReal.volume = value;
  }

  @override
  double get playbackRate => _hasReal ? _requireReal.playbackRate : 1.0;
  @override
  set playbackRate(double value) {
    if (_hasReal) _requireReal.playbackRate = value;
  }

  @override
  PlayerPlaybackState get state =>
      _hasReal ? _requireReal.state : PlayerPlaybackState.stopped;
  @override
  set state(PlayerPlaybackState value) {
    if (_hasReal) _requireReal.state = value;
  }

  @override
  ValueListenable<int?> get textureId =>
      _hasReal ? _requireReal.textureId : ValueNotifier<int?>(null);

  @override
  PlayerMediaInfo get mediaInfo =>
      _hasReal ? _requireReal.mediaInfo : PlayerMediaInfo(duration: 0);

  @override
  List<int> get activeSubtitleTracks =>
      _hasReal ? _requireReal.activeSubtitleTracks : const <int>[];
  @override
  set activeSubtitleTracks(List<int> value) {
    if (_hasReal) _requireReal.activeSubtitleTracks = value;
  }

  @override
  List<int> get activeAudioTracks =>
      _hasReal ? _requireReal.activeAudioTracks : const <int>[];
  @override
  set activeAudioTracks(List<int> value) {
    if (_hasReal) _requireReal.activeAudioTracks = value;
  }

  @override
  void setBufferRange({int minMs = -1, int maxMs = -1, bool drop = false}) {
    // Buffer configuration is applied by the real kernel on creation; the
    // adapters re-apply it on open.
    if (_hasReal) _requireReal.setBufferRange(minMs: minMs, maxMs: maxMs, drop: drop);
  }

  @override
  bool get supportsExternalSubtitles => _hasReal && _requireReal.supportsExternalSubtitles;

  @override
  Future<int?> updateTexture() async =>
      _hasReal ? _requireReal.updateTexture() : null;

  @override
  Future<void> seekAndWait({required int position}) async {
    if (!_hasReal) return;
    // MdkPlayerAdapter implements the async-seek capability; others fall back
    // to the sync seek inside their own seekAndWait equivalent — mirror the
    // Player wrapper's capability dispatch.
    final delegate = _requireReal;
    if (delegate is core.AsyncSeekPlayer) {
      await (delegate as core.AsyncSeekPlayer).seekAndWait(position: position);
    } else {
      delegate.seek(position: position);
    }
  }

  @override
  void seek({required int position}) {
    if (_hasReal) _requireReal.seek(position: position);
  }

  @override
  Future<void> setExternalSubtitleAsync(String path) async {
    final delegate = _requireReal;
    if (delegate is core.AsyncExternalSubtitlePlayer) {
      await (delegate as core.AsyncExternalSubtitlePlayer)
          .setExternalSubtitleAsync(path);
    }
  }

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    if (!_hasReal) return null;
    return _requireReal.snapshot(width: width, height: height);
  }

  core.GifExportCapablePlayer? get _gifCapable =>
      _real is core.GifExportCapablePlayer ? _real as core.GifExportCapablePlayer : null;

  @override
  bool get supportsGifExport => _gifCapable?.supportsGifExport ?? false;
  @override
  Future<core.GifExportResult> exportGif(core.GifExportRequest request) {
    final capable = _gifCapable;
    if (capable != null) {
      return capable.exportGif(request);
    }
    _materialize();
    final capableAfter = _gifCapable;
    if (capableAfter != null) {
      return capableAfter.exportGif(request);
    }
    return Future<core.GifExportResult>.value(core.GifExportResult(
      outputPath: request.outputPath,
      width: request.outputWidth,
      height: request.outputHeight,
      frameCount: 0,
      fileSize: 0,
    ));
  }

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {
    // Decoder selection is sticky per adapter (applied on creation), but the
    // kernel player may not exist yet — stash nothing; adapters re-apply on
    // open via their own sticky properties.
    if (_hasReal) _requireReal.setDecoders(type, decoders);
  }

  @override
  List<String> getDecoders(PlayerMediaType type) =>
      _hasReal ? _requireReal.getDecoders(type) : const <String>[];

  @override
  String? getProperty(String key) =>
      _hasReal ? _requireReal.getProperty(key) : null;

  @override
  void setProperty(String key, String value) {
    if (_hasReal) _requireReal.setProperty(key, value);
  }

  @override
  void setUserAgent(String ua) {
    if (_hasReal) _requireReal.setUserAgent(ua);
  }

  @override
  Future<void> setVideoSurfaceSize({int? width, int? height}) async {
    if (_hasReal) await _requireReal.setVideoSurfaceSize(width: width, height: height);
  }

  @override
  Future<void> setChapter(int index) async {
    if (_hasReal) await _requireReal.setChapter(index);
  }

  @override
  Future<void> playDirectly() async {
    if (!_hasReal) return;
    await _requireReal.playDirectly();
  }

  @override
  Future<void> pauseDirectly() async {
    if (!_hasReal) return;
    await _requireReal.pauseDirectly();
  }

  @override
  void setPlaybackRate(double rate) {
    if (_hasReal) _requireReal.setPlaybackRate(rate);
  }

  @override
  void stepForward() {
    if (_hasReal) _requireReal.stepForward();
  }

  @override
  void stepBackward() {
    if (_hasReal) _requireReal.stepBackward();
  }
}
