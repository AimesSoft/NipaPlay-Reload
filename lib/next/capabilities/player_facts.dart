import 'dart:collection';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';

import '../harness_redaction.dart';

/// The stable id of the kernel the player reports by name.
String? playerKernelId(String name) => switch (name) {
      'MDK' => 'mdk',
      'Media Kit' => 'media_kit',
      'Video Player' => 'video_player',
      'Erika' => 'erika',
      _ => null,
    };

String configuredPlayerKernelId() => switch (PlayerFactory.getKernelType()) {
      PlayerKernelType.mdk => 'mdk',
      PlayerKernelType.mediaKit => 'media_kit',
      PlayerKernelType.videoPlayer => 'video_player',
      PlayerKernelType.erika => 'erika',
    };

/// mpv properties read for diagnostics besides the playback menu's own.
const mpvDiagnosticProperties = [
  'frame-drop-count',
  'decoder-frame-drop-count',
  'mistimed-frame-count',
  'vo-delayed-frame-count',
  'video-params/pixelformat',
  'video-params/hw-pixelformat',
  'speed',
  'file-format',
  'demuxer-cache-duration',
  'paused-for-cache',
  'cache-buffering-state',
  'avsync',
];

/// What the kernel playing now reports about the media, read from it now.
Future<JsonMap> readPlayerMediaFacts(Player player) async {
  final name = player.getPlayerKernelName();
  final kernel = playerKernelId(name);
  final details = <String, Object?>{
    ...await player.getDetailedMediaInfoAsync()
  };
  final mpv = kernel == 'media_kit'
      ? await player.readNativeProperties(mpvDiagnosticProperties)
      : const <String, String?>{};
  final streams = player.nativeStreamFacts();
  final active = player.activeAudioTracks;
  return {
    'kernel': {
      'id': kernel,
      'name': name,
      'configured': configuredPlayerKernelId()
    },
    ...playerMediaFacts(
      kernel: kernel,
      info: player.mediaInfo,
      details: details,
      mpv: mpv,
      streams: streams,
      videoDecoder: player.getProperty('decoder.video'),
      audioDecoder: player.getProperty('decoder.audio'),
      activeAudio: active.isEmpty ? null : active.first,
    ),
  };
}

/// One shape for every kernel's own report; what a kernel does not report
/// is null. kernelDetails keeps the kernel's report as it gave it.
JsonMap playerMediaFacts({
  required String? kernel,
  required PlayerMediaInfo info,
  JsonMap details = const {},
  Map<String, String?> mpv = const {},
  JsonMap streams = const {},
  String? videoDecoder,
  String? audioDecoder,
  int? activeAudio,
}) {
  final props = <String, Object?>{
    if (details['mpvProperties'] case final Map map)
      for (final entry in map.entries) '${entry.key}': entry.value,
    ...mpv,
  };
  Object? p(String key) => props[key];
  final videoParams = _map(details['videoParams']);
  final audioParams = _map(details['audioParams']);
  final erikaDecoder = _map(details['decoder']);
  final stats = _map(details['presenterStats']);
  final streamVideo = _list(streams['video']).map(_map).firstOrNull ?? const {};
  final streamAudios = _list(streams['audio']).map(_map).toList();
  final streamAudio = activeAudio != null && activeAudio < streamAudios.length
      ? streamAudios[activeAudio]
      : streamAudios.firstOrNull ?? const {};
  final video = info.video?.firstOrNull;
  final audios = info.audio ?? const <PlayerAudioStreamInfo>[];
  final audio = activeAudio != null && activeAudio < audios.length
      ? audios[activeAudio]
      : audios.firstOrNull;
  final mpvHwdec = _text(p('hwdec-current'));
  final erikaBackend = _text(erikaDecoder['activeBackend']);
  final decoderName = switch (kernel) {
    'media_kit' => _text(p('video-codec')),
    'erika' => _text(videoDecoder) ?? erikaBackend,
    _ => _text(videoDecoder),
  };
  return {
    'container': {
      'format': _text(p('file-format')) ?? _text(streams['format']),
      'bitrate': _count(p('container-bitrate')) ?? _positive(streams['bitRate']),
    },
    'video': {
      'codec': _text(p('video-format')) ??
          _text(streamVideo['codec']) ??
          _text(erikaDecoder['codec']) ??
          _plainCodec(video?.codecName),
      'width': _positive(p('video-params/w')) ??
          _positive(streamVideo['width']) ??
          _positive(videoParams['width']) ??
          _positive(details['videoWidth']) ??
          _positive(video?.codec.width),
      'height': _positive(p('video-params/h')) ??
          _positive(streamVideo['height']) ??
          _positive(videoParams['height']) ??
          _positive(details['videoHeight']) ??
          _positive(video?.codec.height),
      'displayWidth': _positive(p('dwidth')),
      'displayHeight': _positive(p('dheight')),
      'pixelFormat': _text(p('video-params/pixelformat')) ??
          _text(streamVideo['formatName']) ??
          _text(erikaDecoder['pixelFormat']),
      'hwPixelFormat': _text(p('video-params/hw-pixelformat')),
      'fps': _positiveNumber(p('container-fps')) ??
          _positiveNumber(streamVideo['frameRate']),
      'measuredFps': _positiveNumber(p('estimated-vf-fps')),
      'bitrate': _positive(p('video-bitrate')) ??
          _positive(streamVideo['bitRate']),
      'colorMatrix': _text(p('video-params/colormatrix')),
      'colorPrimaries': _text(p('video-params/colorprimaries')),
      'transfer': _text(p('video-params/transfer')),
    },
    'decoder': {
      'name': decoderName,
      'hardware': switch (kernel) {
        'media_kit' => mpvHwdec == null ? null : mpvHwdec != 'no',
        'erika' => erikaBackend == null ? null : erikaBackend != 'software',
        'mdk' => mdkDecoderIsHardware(decoderName),
        _ => null,
      },
      'method': switch (kernel) {
        'media_kit' => mpvHwdec,
        'erika' => erikaBackend,
        _ => decoderName,
      },
      'requested': switch (kernel) {
        'media_kit' => _text(p('hwdec')),
        'erika' => _text(erikaDecoder['requestedBackend']),
        _ => _list(streams['videoDecoders']).isEmpty
            ? null
            : _list(streams['videoDecoders']).join(','),
      },
    },
    'frames': {
      'dropped': _count(p('frame-drop-count')),
      'decoderDropped': _count(p('decoder-frame-drop-count')),
      'mistimed': _count(p('mistimed-frame-count')),
      'delayed': _count(p('vo-delayed-frame-count')),
      'decoded': _count(stats['decodedVideoFrames']),
      'rendered': _count(stats['renderedVideoFrames']),
    },
    'audio': {
      'codec': _text(p('audio-codec-name')) ??
          _text(streamAudio['codec']) ??
          _plainCodec(audio?.codec.name),
      'decoder': kernel == 'media_kit'
          ? _text(p('audio-codec'))
          : _text(audioDecoder),
      'sampleRate': _positive(p('audio-params/samplerate')) ??
          _positive(p('audio-samplerate')) ??
          _positive(streamAudio['sampleRate']) ??
          _positive(audioParams['sampleRate']) ??
          _positive(audio?.codec.sampleRate),
      'channels': _positive(p('audio-params/channel-count')) ??
          _positive(streamAudio['channels']) ??
          _positive(audioParams['channels']) ??
          _positive(audio?.codec.channels),
      'channelLayout': _text(p('audio-params/channel-layout')) ??
          _text(p('audio-channel-layout')),
      'sampleFormat': _text(p('audio-params/format')) ??
          _text(audioParams['format']),
      'bitrate': _positive(p('audio-bitrate')) ??
          _positive(streamAudio['bitRate']) ??
          _positive(audio?.codec.bitRate),
    },
    'output': {
      'videoOutput': _text(p('current-vo')),
      'gpuApi': _text(p('gpu-api')),
      'gpuContext': _text(p('gpu-context')),
      'rate': _positiveNumber(p('speed')),
      'avsyncSeconds': _number(p('avsync')),
    },
    'cache': {
      'aheadSeconds': _number(p('demuxer-cache-duration')),
      'pausedForCache': _yes(p('paused-for-cache')),
      'bufferingPercent': _count(p('cache-buffering-state')),
    },
    'kernelDetails': redactHarnessJson({
      ...details,
      if (mpv.isNotEmpty) 'diagnosticProperties': mpv,
      if (streams.isNotEmpty) 'streams': streams,
    }),
  };
}

/// diagnostics.status player.details, from the same facts as playback.info.
/// hwdec is the active hardware method, "no" in software, null when unknown.
JsonMap diagnosticsPlayerDetails(JsonMap media, {required bool buffering}) {
  final video = media['video'] as JsonMap;
  final audio = media['audio'] as JsonMap;
  final decoder = media['decoder'] as JsonMap;
  return {
    'videoCodec': video['codec'],
    'audioCodec': audio['codec'],
    'videoWidth': video['width'],
    'videoHeight': video['height'],
    'fps': video['fps'] ?? video['measuredFps'],
    'hwdec': switch (decoder['hardware']) {
      true => decoder['method'],
      false => 'no',
      _ => null,
    },
    'decoder': decoder['name'],
    'hardwareDecoding': decoder['hardware'],
    'droppedFrames': (media['frames'] as JsonMap)['dropped'],
    'buffering': buffering,
  };
}

/// MDK names the decoder it opened; FFmpeg and dav1d decode in software.
bool? mdkDecoderIsHardware(String? name) {
  if (name == null) return null;
  final lower = name.toLowerCase();
  final base = lower.split(':').first;
  if (base == 'ffmpeg') {
    final hwaccel = RegExp(r'hwaccel=([a-z0-9_]+)').firstMatch(lower)?[1];
    return hwaccel != null && hwaccel != 'no' && hwaccel != 'none';
  }
  if (base == 'dav1d') return false;
  const hardware = {
    'vt', 'videotoolbox', 'mft', 'd3d11', 'd3d12', 'dxva', 'cuda', 'nvdec',
    'qsv', 'vaapi', 'vdpau', 'mediacodec', 'amediacodec', 'oh', 'rkmpp',
    'v4l2m2m', 'mmal',
  };
  return hardware.contains(base) ? true : null;
}

Map<String, Object?> _map(Object? value) => value is Map
    ? {for (final entry in value.entries) '${entry.key}': entry.value}
    : const {};
List<Object?> _list(Object? value) => value is List ? value : const [];
String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

num? _number(Object? value) =>
    value is num ? value : value is String ? num.tryParse(value.trim()) : null;
num? _positiveNumber(Object? value) {
  final number = _number(value);
  return number == null || number <= 0 || number.isNaN ? null : number;
}

int? _count(Object? value) {
  final number = _number(value);
  return number == null || number < 0 ? null : number.round();
}

int? _positive(Object? value) {
  final number = _count(value);
  return number == null || number == 0 ? null : number;
}

bool? _yes(Object? value) => value is bool
    ? value
    : value == 'yes'
        ? true
        : value == 'no'
            ? false
            : null;

/// MDK's stream codec without a name of its own is its parameter dump.
String? _plainCodec(String? name) {
  final text = _text(name);
  if (text == null || text.contains('CodecParameters(')) return null;
  return text;
}

/// Categories of a playback failure, mapped from the kernel's own error, a
/// look at the local file, or the step that failed; anything else is unknown.
const playbackFailureCategories = [
  'file_not_found',
  'permission_denied',
  'unsupported_format',
  'network',
  'unauthorized',
  'source_failed',
  'timeout',
  'unknown',
];

const _stageCategories = {
  'file_check': 'file_not_found',
  'stream_session': 'source_failed',
  'remote_path': 'source_failed',
  'web_format': 'unsupported_format',
  'media_ready_timeout': 'timeout',
};

/// The category a kernel or player message names, or null.
String? errorTextCategory(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final t = text.toLowerCase();
  bool has(List<String> words) => words.any(t.contains);
  if (has(['401', '403', 'unauthorized', 'forbidden'])) return 'unauthorized';
  if (has(['permission denied', 'operation not permitted', 'access denied',
    'eacces', 'eperm'])) {
    return 'permission_denied';
  }
  if (has(['no such file', 'file not found', 'does not exist', 'enoent'])) {
    return 'file_not_found';
  }
  if (has(['404', 'not found', 'http error'])) return 'source_failed';
  if (has(['timed out', 'timeout', 'etimedout'])) return 'timeout';
  if (has(['connection', 'network', 'tcp:', 'tls', 'ssl', 'resolve',
    'unreachable', 'econn', 'socket', 'host'])) {
    return 'network';
  }
  if (has(['unrecognized file format', 'failed to recognize file format',
    'invalid data found', 'unsupported', 'no video or audio streams',
    'could not find codec', 'codec not found', 'decoder', 'demux'])) {
    return 'unsupported_format';
  }
  return null;
}

/// A failure's category: a local file's state first, then the kernel's own
/// messages, then the player's, then the step.
String playbackFailureCategory({
  String? stage,
  String? kernelMessage,
  String? mediaMessage,
  String? playerMessage,
  JsonMap? file,
}) {
  if (file != null) {
    if (file['exists'] == false) return 'file_not_found';
    if (file['readable'] == false) return 'permission_denied';
  }
  return errorTextCategory(kernelMessage) ??
      errorTextCategory(mediaMessage) ??
      errorTextCategory(playerMessage) ??
      _stageCategories[stage] ??
      'unknown';
}

/// Raw player or kernel text as reported, redacted and bounded.
String? safePlayerText(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final redacted = redactHarnessText(text);
  return redacted.length > 2000
      ? '${redacted.substring(0, 2000)}[truncated]'
      : redacted;
}

/// Playback failures of this process while Next is on, newest last. Each is
/// also published as the playback.failed event.
final class PlaybackFailures {
  PlaybackFailures._();
  static final instance = PlaybackFailures._();
  static const capacity = 50;
  final _records = ListQueue<JsonMap>();
  int _sequence = 0;

  List<JsonMap> get records => List.unmodifiable(_records);

  JsonMap? latestFor(String sessionId) {
    for (final record in _records.toList().reversed) {
      if (record['sessionId'] == sessionId) return record;
    }
    return null;
  }

  void clear() => _records.clear();

  /// Completes a captured failure, keeps it and returns it.
  Future<JsonMap> record(JsonMap captured) async {
    final local = captured.remove('_localPath') as String?;
    final file = local == null ? null : await probeLocalFile(local);
    final messages = captured['messages'] as JsonMap;
    final record = <String, Object?>{
      'failureId': 'pf-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}',
      ...captured,
      'category': playbackFailureCategory(
          stage: captured['stage'] as String?,
          kernelMessage: messages['kernel'] as String?,
          mediaMessage: messages['media'] as String?,
          playerMessage: messages['player'] as String?,
          file: file),
      'file': file,
    };
    _records.add(record);
    while (_records.length > capacity) {
      _records.removeFirst();
    }
    return record;
  }

  static String? localPathOf(String? path) {
    if (path == null || path.isEmpty) return null;
    final uri = Uri.tryParse(path);
    if (uri != null && uri.scheme == 'file') {
      try {
        return uri.toFilePath(windows: Platform.isWindows);
      } on UnsupportedError {
        return null;
      }
    }
    if (uri != null && uri.scheme.length > 1) return null;
    return path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)
        ? path
        : null;
  }
}

/// Whether a local file is there and can be opened for reading now.
Future<JsonMap> probeLocalFile(String path) async {
  final type = await FileSystemEntity.type(path);
  if (type == FileSystemEntityType.notFound) {
    return {'exists': false, 'readable': null};
  }
  if (type != FileSystemEntityType.file) {
    return {'exists': true, 'readable': null, 'type': type.toString()};
  }
  try {
    final handle = await File(path).open();
    await handle.close();
    return {'exists': true, 'readable': true};
  } on FileSystemException catch (error) {
    return {
      'exists': true,
      'readable': false,
      'osError': error.osError?.message,
    };
  }
}
