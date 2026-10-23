import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/services/security_bookmark_service.dart';
import 'package:nipaplay/utils/external_player_utils.dart';

import '../../capabilities/media_models.dart';
import '../../harness_redaction.dart';

/// A launch receipt, not invented playback telemetry. NipaPlay does not own
/// the external player's transport or its progress. Process exit is pushed.
final class ExternalHandoff extends ChangeNotifier {
  ExternalHandoff(
      {required this.enabled,
      required this.playerPath,
      required this.playerType,
      this.userAgent});
  final bool Function() enabled;
  final String Function() playerPath;
  final ExternalPlayerType Function() playerType;
  final String Function()? userAgent;
  Process? _process;
  PlayableItem? _item;
  String? _id;
  String? _resolved;
  int _generation = 0;
  int? _exitCode;
  bool _disposed = false;
  bool get active => _item != null;
  Future<int>? get launchExit => _process?.exitCode;

  Future<void> open(PlayableItem item, {Duration? start}) async {
    if (_disposed) throw StateError('External handoff is disposed.');
    final generation = ++_generation;
    final path = playerPath().trim();
    final type = playerType();
    if (path.isEmpty || type == ExternalPlayerType.unset) {
      throw const Failure(
          FailureCode.invalidInput, 'Choose an external player path and type.');
    }
    final source = await resolveExternalPlayerMediaPath(item);
    if (source == null || source.isEmpty) {
      throw const Failure(
          FailureCode.unavailable, 'The media address could not be resolved.');
    }
    final resolved = Platform.isMacOS
        ? await SecurityBookmarkService.resolveBookmark(path) ?? path
        : path;
    if (_disposed || generation != _generation) return;
    final args = launchArguments(source, type,
        start: start, userAgent: userAgent?.call() ?? '');
    final app = Platform.isMacOS && resolved.toLowerCase().endsWith('.app');
    final process = await Process.start(app ? '/usr/bin/open' : resolved,
        app ? ['-a', resolved, '--args', ...args] : args);
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    if (app && await process.exitCode != 0) {
      throw const Failure(FailureCode.unavailable,
          'LaunchServices could not open the selected external player.');
    }
    if (_disposed || generation != _generation) return;
    _process = process;
    _item = item;
    _resolved = source;
    _exitCode = null;
    _id = 'external:${process.pid}:$generation';
    notifyListeners();
    unawaited(process.exitCode.then((code) {
      if (generation != _generation) return;
      // open(1) exiting only confirms LaunchServices handoff, not player exit.
      _exitCode = code;
      if (!app) _item = null;
      _process = null;
      notifyListeners();
    }));
  }

  static List<String> launchArguments(String source, ExternalPlayerType type,
      {Duration? start, String userAgent = ''}) {
    final seconds = (start?.inMicroseconds ?? 0) / 1e6;
    return switch (type) {
      ExternalPlayerType.mpv || ExternalPlayerType.mpvNet => [
          if (start != null) '--start=$seconds',
          if (userAgent.isNotEmpty) '--user-agent=$userAgent',
          '--',
          source
        ],
      ExternalPlayerType.vlc => [
          if (start != null) '--start-time=$seconds',
          if (userAgent.isNotEmpty) '--http-user-agent=$userAgent',
          source
        ],
      ExternalPlayerType.potPlayer => [
          source,
          if (start != null) '/seek=${_potTime(start)}',
          if (userAgent.isNotEmpty) '/user_agent=$userAgent'
        ],
      _ => [source],
    };
  }

  static String _potTime(Duration d) =>
      '${d.inHours}:${d.inMinutes.remainder(60)}:${d.inSeconds.remainder(60)}.${d.inMilliseconds.remainder(1000).toString().padLeft(3, '0')}';

  JsonMap facts() => {
        'player': playerType().name,
        'status': '在外部播放器中播放',
        'path': redactHarnessText(_resolved ?? ''),
        'pid': _process?.pid,
        'launchExitCode': _exitCode,
        'telemetryAvailable': false,
        'controlAvailable': false,
        'ownership': 'handoff'
      };

  PlaybackSnapshot snapshot() => PlaybackSnapshot(
      player: 'external',
      status: 'external',
      hasVideo: false,
      paused: null,
      path: _item?.videoPath,
      seriesTitle: _item?.title,
      episodeTitle: _item?.subtitle,
      animeId: _item?.animeId,
      episodeId: _item?.episodeId,
      positionMs: null,
      durationMs: null,
      rate: null,
      canPrevious: false,
      canNext: false,
      sessionId: _id,
      observedAt: DateTime.now(),
      external: facts(),
      supportedControls: const []);

  /// Clear NipaPlay's receipt only; the external app belongs to the user.
  void clear() {
    _generation++;
    _item = null;
    _process = null;
    _id = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
