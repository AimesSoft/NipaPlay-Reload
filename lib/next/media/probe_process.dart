import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

final mediaProbeProcess = MediaProbeProcess();

/// Owns only isolated media probe children. A failed file cannot poison a native player in
/// the application, and cancellation never signals an arbitrary PID.
final class MediaProbeProcess {
  MediaProbeProcess(
      {this.executable, this.timeout = const Duration(seconds: 15)});
  String? executable;
  String? library;
  // Existing headless CLI may explicitly supply ffprobe. Desktop never bundles it.
  String? ffprobeExecutable;
  final Duration timeout;
  final _active = <String, _Probe>{};
  final _recent = <JsonMap>[];
  int _sequence = 0;
  int _starting = 0;

  String? resolveExecutable() {
    if (ffprobeExecutable != null) {
      return File(ffprobeExecutable!).existsSync() ? ffprobeExecutable : null;
    }
    final dir = p.dirname(Platform.resolvedExecutable);
    final name =
        Platform.isWindows ? 'nipa_media_probe.exe' : 'nipa_media_probe';
    return [
      if (executable != null) executable!,
      if (Platform.isMacOS) p.join(dir, '..', 'Helpers', name),
      p.join(dir, name),
    ].where((path) => File(path).existsSync()).firstOrNull;
  }

  String? resolveLibrary() {
    final dir = p.dirname(Platform.resolvedExecutable);
    return [
      if (library != null) library!,
      if (Platform.isMacOS)
        p.join(dir, '..', 'Frameworks', 'erika_flutter.framework', 'Versions',
            'A', 'Frameworks', 'liberika_capi.dylib'),
      if (Platform.isWindows) p.join(dir, 'erika_capi.dll'),
      if (Platform.isLinux) p.join(dir, 'lib', 'liberika_capi.so'),
    ].where((path) => File(path).existsSync()).firstOrNull;
  }

  JsonMap status() => {
        'backend':
            ffprobeExecutable == null ? 'erika_process' : 'ffprobe_process',
        'available': resolveExecutable() != null &&
            (ffprobeExecutable != null || resolveLibrary() != null),
        'executable': resolveExecutable(),
        'library': ffprobeExecutable == null ? resolveLibrary() : null,
        'timeoutMs': timeout.inMilliseconds,
        'capacity': 4,
        'active': [for (final probe in _active.values) probe.json()],
        'recent': List<JsonMap>.of(_recent),
        'recovery':
            'Cancel an active probeId, await its exit, then submit media.library.scan with a new requestId. Existing indexed files and identities are retained; this does not mark a scan successful.',
      };

  Future<JsonMap> cancel(String id) async {
    final probe = _active[id];
    if (probe == null)
      throw const Failure(FailureCode.notFound,
          'Probe is no longer active; read media.probe.status.');
    probe.reason ??= 'cancelled';
    probe.process.kill(ProcessSignal.sigkill);
    try {
      await probe.process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      throw Failure(
          FailureCode.unavailable, 'Probe termination is not confirmed.',
          details: probe.json());
    }
    return {'probeId': id, 'terminated': true, 'filesChanged': false};
  }

  Future<JsonMap> run(String path, {Future<void>? stopRequested}) async {
    final exe = resolveExecutable();
    final native = resolveLibrary();
    if (exe == null || (ffprobeExecutable == null && native == null))
      throw const Failure(FailureCode.unavailable,
          'The Erika probe helper or bundled library is missing; inspect media.probe.status and repair the application installation.');
    if (_active.length + _starting >= 4)
      throw const Failure(FailureCode.unavailable,
          'Media probe capacity is occupied; inspect media.probe.status.',
          retryable: true);
    // Reserve before Process.start yields so parallel requests cannot exceed capacity.
    final id = 'probe-${pid}-${++_sequence}';
    _starting++;
    final Process process;
    try {
      process = await Process.start(
          exe,
          ffprobeExecutable == null
              ? [native!, path]
              : [
                  '-v',
                  'error',
                  '-show_entries',
                  'format=duration,format_name,bit_rate:stream=index,codec_type,codec_name,width,height,avg_frame_rate,pix_fmt,bit_rate,sample_rate,channels,color_space,color_transfer:stream_tags=language,title',
                  '-of',
                  'json',
                  '-i',
                  path
                ]);
    } finally {
      _starting--;
    }
    final probe = _Probe(id, path, process);
    _active[id] = probe;
    void stop(String reason) {
      if (!identical(_active[id], probe)) return;
      probe.reason ??= reason;
      process.kill(ProcessSignal.sigkill);
    }

    final timer = Timer(timeout, () => stop('timeout'));
    if (stopRequested != null)
      unawaited(stopRequested.then((_) => stop('cancelled')));
    final output = BytesBuilder(copy: false),
        errors = BytesBuilder(copy: false);
    final out = process.stdout.listen((bytes) {
      if (output.length + bytes.length <= 4 * 1024 * 1024) {
        output.add(bytes);
      } else {
        stop('output_limit');
      }
    });
    final err = process.stderr.listen((bytes) {
      if (errors.length + bytes.length <= 65536) errors.add(bytes);
    });
    final drains = Future.wait([out.asFuture<void>(), err.asFuture<void>()]);
    try {
      final code =
          await process.exitCode.timeout(timeout + const Duration(seconds: 3));
      await drains.timeout(const Duration(seconds: 1));
      final stderr = utf8.decode(errors.takeBytes(), allowMalformed: true);
      if (probe.reason != null || code != 0) {
        throw Failure(
            FailureCode.unavailable,
            stderr.isEmpty
                ? 'Media probe ${probe.reason ?? "failed"}: $path'
                : stderr,
            details: {...probe.json(), 'exitCode': code, 'stderr': stderr});
      }
      final json = jsonDecode(utf8.decode(output.takeBytes())) as Map;
      final result = ffprobeExecutable == null
          ? parseErikaProbeOutput(json)
          : parseProbeOutput(json);
      _remember({...probe.json(), 'state': 'succeeded', 'exitCode': code});
      return result;
    } catch (error) {
      stop(probe.reason ?? 'failed');
      final details = {...probe.json(), 'state': 'failed', 'error': '$error'};
      _remember(details);
      if (error is Failure) rethrow;
      throw Failure(FailureCode.unavailable, 'Media probe failed: $error',
          details: details);
    } finally {
      timer.cancel();
      await out.cancel();
      await err.cancel();
      // Keep ownership until exit is confirmed. An OS-level unkillable process
      // stays visible, rather than allowing unbounded replacement children.
      unawaited(process.exitCode.then((_) {
        _active.remove(id);
      }));
    }
  }

  Future<void> close() async {
    for (final id in _active.keys.toList()) {
      try {
        await cancel(id);
      } on Failure {/* Still visible in status. */}
    }
  }

  void _remember(JsonMap value) {
    _recent.insert(0, value);
    if (_recent.length > 20) _recent.removeLast();
  }
}

final class _Probe {
  _Probe(this.id, this.path, this.process);
  final String id, path;
  final Process process;
  final started = DateTime.now().toUtc();
  String? reason;
  JsonMap json() => {
        'probeId': id,
        'path': path,
        'pid': process.pid,
        'startedAt': started.toIso8601String(),
        'elapsedMs': DateTime.now().toUtc().difference(started).inMilliseconds,
        'state': reason == null ? 'running' : 'terminating',
        if (reason != null) 'reason': reason
      };
}

JsonMap parseProbeOutput(Map json) {
  final duration = (json['format'] as Map?)?['duration'];
  final streams = [
    for (final s in (json['streams'] as List? ?? const []).whereType<Map>())
      if (s['codec_type'] == 'subtitle') s
  ];
  int? positive(Object? value) {
    final n = int.tryParse('$value');
    return n != null && n > 0 ? n : null;
  }

  double? fps(Object? value) {
    final parts = '$value'.split('/');
    final a = double.tryParse(parts.first),
        b = parts.length == 2 ? double.tryParse(parts.last) : 1;
    return a != null && b != null && b > 0 && a > 0 ? a / b : null;
  }

  final all = (json['streams'] as List? ?? const []).whereType<Map>();
  return {
    'technical': {
      'container': (json['format'] as Map?)?['format_name'],
      'bitrate': positive((json['format'] as Map?)?['bit_rate']),
      'video': [
        for (final s in all.where((s) => s['codec_type'] == 'video'))
          {
            'codec': s['codec_name'],
            'width': s['width'],
            'height': s['height'],
            'fps': fps(s['avg_frame_rate']),
            'pixelFormat': s['pix_fmt'],
            'bitrate': positive(s['bit_rate']),
            'colorSpace': s['color_space'],
            'colorTransfer': s['color_transfer'],
          }
      ],
      'audio': [
        for (final s in all.where((s) => s['codec_type'] == 'audio'))
          {
            'codec': s['codec_name'],
            'channels': s['channels'],
            'sampleRate': positive(s['sample_rate']),
            'bitrate': positive(s['bit_rate']),
            'language': (s['tags'] as Map?)?['language'],
            'title': (s['tags'] as Map?)?['title'],
          }
      ],
    },
    'durationMs': double.tryParse('$duration') == null
        ? null
        : (double.parse('$duration') * 1000).round(),
    'subtitles': [
      for (final (i, s) in streams.indexed)
        {
          'index': i,
          'streamIndex': s['index'],
          'language': (s['tags'] as Map?)?['language'] ?? 'und',
          'title': (s['tags'] as Map?)?['title'],
          'format': s['codec_name'],
        }
    ],
  };
}

JsonMap parseErikaProbeOutput(Map json) {
  Object? value(Object? envelope) {
    if (envelope is! Map || envelope['ok'] != true) {
      throw Failure(
          FailureCode.unavailable,
          envelope is Map
              ? '${envelope['error'] ?? 'Erika returned no facts.'}'
              : 'Missing Erika response.');
    }
    return envelope['value'];
  }

  final container = value(json['container']) as Map;
  if (container['mediaOpen'] != true) {
    throw const Failure(
        FailureCode.unavailable, 'Erika did not open the media.');
  }
  final tracks = (value(json['tracks']) as List).cast<Map>();
  int? duration;
  for (final envelope in json['events'] as List) {
    final event = value(envelope) as Map;
    final micros = event['durationMicros'] as num?;
    if (micros != null && micros > 0) duration = (micros / 1000).round();
  }
  return {
    'durationMs': duration,
    'technical': {
      'container': container['format'],
      'bitrate': container['bitRate'],
      'video': [
        for (final t in tracks.where((t) => t['kind'] == 0))
          {
            'codec': t['codec'],
            'width': t['width'],
            'height': t['height'],
            'pixelFormat': t['pixelFormat'],
            'profile': t['profile'],
            'dolbyVisionProfile': t['dolbyVisionProfile'],
          }
      ],
      'audio': [
        for (final t in tracks.where((t) => t['kind'] == 1))
          {
            'codec': t['codec'],
            'channels': t['channels'],
            'sampleRate': t['sampleRate'],
            'language': t['language'],
            'title': t['title'],
          }
      ],
    },
    'subtitles': [
      for (final (i, t) in tracks.where((t) => t['kind'] == 2).indexed)
        {
          'index': i,
          'streamIndex': t['id'],
          'language': t['language'] ?? 'und',
          'title': t['title'],
          'format': t['codec'],
        }
    ],
  };
}
