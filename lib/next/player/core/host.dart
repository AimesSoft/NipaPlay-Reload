import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../harness_redaction.dart';
import '../../settings/registry.dart' show SettingsAccess;
import '../kernel/driver.dart';
import '../progress/records.dart';
import '../subtitles/controller.dart';
import '../subtitles/cue_index.dart';
import '../subtitles/look.dart';
import 'arbiter.dart';
import 'session.dart';

/// What the playback layer cannot play yet, and why (D5: no fallback to
/// Classic's player). [reason] is the fact's word; [facts] say what was
/// asked.
final class OpenRefused implements Exception {
  const OpenRefused(this.reason, this.message, [this.facts = const {}]);

  /// source_not_supported, kernel_not_supported, external_player.
  final String reason;
  final String message;
  final JsonMap facts;

  JsonMap toJson() => {'reason': reason, 'message': message, ...facts};

  @override
  String toString() => 'OpenRefused($reason): $message';
}

/// Next's playback (player-core design §1.3): one session at a time, each
/// on a kernel instance of its own under the process's one lease.
///
/// Opens and closes are taken in order; a close does not wait for an open
/// under way to finish, it fences it.
final class NextPlayerHost {
  NextPlayerHost({
    required this.createDriver,
    required this.configuredKernel,
    required this.levels,
    PlaybackRecords? records,
    KernelArbiter? arbiter,
    bool Function()? usesExternalPlayer,
  })  : records = records ?? const SharedPlaybackRecords(),
        arbiter = arbiter ?? KernelArbiter.instance,
        _usesExternalPlayer = usesExternalPlayer ?? (() => false);

  /// The kernels this layer drives (P1: MDK).
  static const supportedKernels = {KernelId.mdk};
  static const historyCapacity = 20;

  /// Kernel lifecycles kept for measurement (a few hundred bytes each).
  static const lifecycleCapacity = 1000;

  final Future<KernelDriver> Function(KernelId kernel, KernelLease lease)
      createDriver;

  /// The kernel setting's id (media_kit, mdk…).
  final String Function() configuredKernel;
  final Future<PlayerLevels> Function() levels;
  final PlaybackRecords records;
  final KernelArbiter arbiter;
  final bool Function() _usesExternalPlayer;

  /// Subtitle files parsed for what plays and what played last.
  final cues = CueCache();

  /// The subtitle library's side (it attaches while Next's interface is
  /// open): asked for a media's subtitles when it opens, told the choices
  /// made in the player.
  SubtitleLoader? subtitleLoader;
  SubtitleRecorder? subtitleRecorder;

  SharedPreferences? _prefs;
  SubtitleLook _look = const SubtitleLook();

  /// The shared subtitle settings as last read.
  SubtitleLook get look => _look;

  Future<void> _readSettings() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      _look = SubtitleLook.read(prefs);
    } catch (error) {
      debugPrint('[NextPlayer] subtitle settings: $error');
    }
  }

  /// Where and when the overlay draws [path] (kept per file, D3).
  OverlayPlacement placementOf(String path) {
    final prefs = _prefs;
    return prefs == null
        ? const OverlayPlacement()
        : OverlayPlacement.read(prefs, path);
  }

  /// Keeps [placement] for [path] and applies it to what plays.
  Future<void> setPlacement(String path, OverlayPlacement placement) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await SettingsAccess.persist(OverlayPlacement.key(path),
        () => placement.write(prefs, path).then((_) => true));
    _current.value?.subtitles.placementChanged(path, placement);
  }

  /// Keeps a shared subtitle setting ([key] as Classic stores it) and
  /// applies it to what plays.
  Future<void> setSubtitleSetting(String key, double value) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await SettingsAccess.persist(key, () => prefs.setDouble(key, value));
    _look = SubtitleLook.read(prefs);
    await _current.value?.subtitles.lookChanged(_look);
  }

  final _current = ValueNotifier<PlaybackSession?>(null);
  final _events = StreamController<PlaybackEvent>.broadcast(sync: true);
  Future<void> _turn = Future.value();
  int _count = 0;
  final _refusals = ListQueue<JsonMap>();
  final _ended = ListQueue<JsonMap>();
  final _lifecycles = ListQueue<JsonMap>();
  bool _disposed = false;

  ValueListenable<PlaybackSession?> get current => _current;

  /// Every session's events, in order.
  Stream<PlaybackEvent> get events => _events.stream;

  /// What [request] would be opened from, or why it cannot be.
  ResolvedSource resolve(MediaRequest request) {
    final locator = request.locator;
    final drive = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(locator);
    final uri = drive ? null : Uri.tryParse(locator);
    final scheme = uri?.scheme ?? '';
    final String path;
    if (scheme == 'file') {
      path = uri!.toFilePath(windows: Platform.isWindows);
    } else if (scheme.isEmpty && (drive || p.isAbsolute(locator))) {
      path = locator;
    } else if (const {
      'http',
      'https',
      'webdav',
      'smb',
      'jellyfin',
      'emby',
      'mesh',
      'dandanplay',
      'rtsp',
      'rtmp',
      'content'
    }.contains(scheme)) {
      path = locator;
    } else {
      throw OpenRefused(
          'source_not_supported',
          'Use an absolute local path or a supported media source URL; '
              '${scheme.isEmpty ? 'a relative path' : 'the $scheme scheme'} '
              'does not identify a playable source.',
          {'source': scheme.isEmpty ? 'relative_path' : scheme});
    }
    final kernel = configuredKernel();
    if (!supportedKernels.any((k) => k.id == kernel)) {
      throw OpenRefused(
          'kernel_not_supported',
          'Next\'s playback layer runs on MDK only; the kernel setting is '
              '$kernel.',
          {'configured': kernel, 'supported': [for (final k in supportedKernels) k.id]});
    }
    if (_usesExternalPlayer()) {
      throw const OpenRefused('external_player',
          'Next\'s playback layer does not hand media to an external player yet.');
    }
    return ResolvedSource(
        locator: path,
        uri: path,
        kind: scheme.isEmpty || scheme == 'file' ? 'local' : scheme);
  }

  /// Opens [request] after closing what plays. Completes once the open
  /// plan ended: the session is active, failed or (closed meanwhile)
  /// closed. Throws [OpenRefused] before anything closes.
  Future<PlaybackSession> open(
    MediaRequest request, {
    ResolvedSource? resolvedSource,
    void Function(PlaybackSession session)? onCreated,
  }) async {
    final ResolvedSource source;
    try {
      final checked = resolve(request);
      source = resolvedSource ?? checked;
    } on OpenRefused catch (refused) {
      _refused(request, refused);
      rethrow;
    }
    final made = _turn.then((_) async {
      final previous = _current.value;
      if (previous != null) await previous.close(reason: 'replaced');
      if (_disposed) throw StateError('Next\'s playback has closed.');
      final playerLevels = await levels();
      await _readSettings();
      final session = PlaybackSession(
          'internal:$pid:${++_count}:1',
          request.withLocator(source.locator),
          source,
          SessionDeps(
            arbiter: arbiter,
            createDriver: (lease) => createDriver(KernelId.mdk, lease),
            records: records,
            levels: playerLevels,
            cues: cues,
            look: _look,
            placementOf: placementOf,
            subtitleLoader: () => subtitleLoader,
            subtitleRecorder: () => subtitleRecorder,
          ));
      onCreated?.call(session);
      _current.value = session;
      session.events.listen(_events.add, onDone: () => _gone(session));
      unawaited(session.start());
      return session;
    });
    _turn = made.then((_) {}, onError: (Object _) {});
    final session = await made;
    await session.opened;
    return session;
  }

  /// Closes what plays, its progress saved; nothing opens instead.
  Future<void> close({required String reason}) async {
    final session = _current.value;
    if (session == null) return;
    await session.close(reason: reason);
  }

  void _gone(PlaybackSession session) {
    final kernel = session.driver?.lifecycle;
    _ended.add({...session.facts(), 'kernel': kernel});
    while (_ended.length > historyCapacity) {
      _ended.removeFirst();
    }
    if (kernel != null) {
      _lifecycles.add(kernel);
      while (_lifecycles.length > lifecycleCapacity) {
        _lifecycles.removeFirst();
      }
    }
    if (identical(_current.value, session)) _current.value = null;
  }

  void _refused(MediaRequest request, OpenRefused refused) {
    _refusals.add({
      'at': DateTime.now().toUtc().toIso8601String(),
      'path': redactHarnessText(request.locator),
      'origin': request.origin,
      ...refused.toJson(),
    });
    while (_refusals.length > historyCapacity) {
      _refusals.removeFirst();
    }
  }

  /// A shared setting changed (D3, D8): what it says now applies to what
  /// plays.
  void settingChanged(String key, Object? value) {
    final session = _current.value;
    if (key.startsWith('subtitle.')) {
      // The registry kept it in the shared preferences already.
      unawaited(_readSettings().then((_) => session?.subtitles.lookChanged(_look)));
      return;
    }
    if (session == null || value is! num) return;
    final t = session.transport.value;
    switch (key) {
      case 'player.volume':
        if (t.volume == value.toDouble()) return;
        unawaited(session.setVolume(value.toDouble(), origin: 'settings'));
      case 'player.volumeBoost':
        unawaited(session.setVolume(session.transport.value.volume,
            origin: 'settings', boost: value.toDouble()));
      case 'playback.rate':
        if (t.rate == value.toDouble()) return;
        unawaited(session.setRate(value.toDouble(), origin: 'settings'));
    }
  }

  /// The session, the last ones that ended (with their kernel's
  /// lifecycle), the refusals and the lease.
  JsonMap facts() => {
        'current': _current.value?.facts(),
        'kernel': _current.value?.driver?.lifecycle,
        'configuredKernel': configuredKernel(),
        'supportedKernels': [for (final k in supportedKernels) k.id],
        'recent': [for (final e in _ended.toList().reversed.take(5)) e],
        'refusals': [for (final r in _refusals.toList().reversed.take(5)) r],
        'lease': arbiter.facts(),
      };

  /// Every session's kernel lifecycle kept (creation, open, release), for
  /// lab measurement.
  List<JsonMap> get lifecycles => List.of(_lifecycles);

  Future<void> dispose() async {
    _disposed = true;
    await close(reason: 'nipaplay_closing');
  }
}
