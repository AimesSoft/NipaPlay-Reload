import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';

import '../harness_redaction.dart';

/// Kernel ids as playback reports them, and the kernel type each names.
const kernelTypesById = <String, PlayerKernelType>{
  'mdk': PlayerKernelType.mdk,
  'media_kit': PlayerKernelType.mediaKit,
  'video_player': PlayerKernelType.videoPlayer,
  'erika': PlayerKernelType.erika,
};

String kernelIdOf(PlayerKernelType type) =>
    kernelTypesById.entries.firstWhere((e) => e.value == type).key;

/// mpv properties playback.kernel reads every time, besides those asked for.
const mpvKernelSnapshot = [
  'mpv-version',
  'ffmpeg-version',
  'hwdec',
  'hwdec-current',
  'hwdec-codecs',
  'vd',
  'vo',
  'current-vo',
  'gpu-api',
  'gpu-context',
  'gpu-hwdec-interop',
  'video-sync',
  'interpolation',
  'deband',
  'scale',
  'dscale',
  'cscale',
  'vf',
  'af',
  'tone-mapping',
  'target-colorspace-hint',
  'hdr-compute-peak',
  'video-output-levels',
  'framedrop',
  'ao',
  'current-ao',
  'audio-device',
  'audio-channels',
  'audio-exclusive',
  'audio-spdif',
  'speed',
  'cache',
  'cache-secs',
  'demuxer-max-bytes',
  'demuxer-readahead-secs',
  'network-timeout',
  'user-agent',
  'http-proxy',
  'sub-ass-override',
  'sub-codepage',
];

/// MDK player properties playback.kernel reads every time. MDK answers only
/// for a property that was set on this player.
const mdkKernelSnapshot = [
  'auto_load',
  'subtitle',
  'cc',
  'continue_at_end',
  'keep_open',
  'buffer',
  'demux.buffer.ranges',
  'video.decoders',
  'audio.decoders',
  'video.decoder',
  'audio.decoder',
  'decoder',
  'video.avfilter',
  'audio.avfilter',
  'subtitle.scale',
  'avformat.user_agent',
  'avio.user_agent',
  'avformat.http_proxy',
  'avio.http_proxy',
];

/// Erika's settings playback.set_kernel_properties takes, and their values.
const erikaKernelSettings = <String, List<String>>{
  'upscaler': ['off', 'artCnnC4F16', 'artCnnC4F32', 'artCnnC4F16Ds'],
  'debugHud': ['true', 'false'],
};

PlayerUpscalerMode erikaUpscalerMode(String name) => switch (name) {
      'artCnnC4F16' => PlayerUpscalerMode.erikaArtCnnC4F16,
      'artCnnC4F32' => PlayerUpscalerMode.erikaArtCnnC4F32,
      'artCnnC4F16Ds' => PlayerUpscalerMode.erikaArtCnnC4F16Ds,
      _ => PlayerUpscalerMode.off,
    };

String erikaUpscalerName(PlayerUpscalerMode mode) => switch (mode) {
      PlayerUpscalerMode.erikaArtCnnC4F16 => 'artCnnC4F16',
      PlayerUpscalerMode.erikaArtCnnC4F32 => 'artCnnC4F32',
      PlayerUpscalerMode.erikaArtCnnC4F16Ds => 'artCnnC4F16Ds',
      PlayerUpscalerMode.off => 'off',
    };

/// What Erika keeps to itself, its diagnostics snapshot included;
/// playback.kernel names them so their absence is not read as zero.
const erikaNotReported = [
  'network.throughput',
  'network.retries',
  'buffering.reason',
  'decoder.warnings',
  'audio.device',
  'audio.latencyMs',
  'subtitle.renderer',
  'subtitle.missingFonts',
  'danmaku.dropped',
  'hdr.metadata',
  'hdr.dolbyVision',
  'decoder.selection',
];

/// Erika methods that only read: they leave the player as it was.
bool erikaReadsOnly(String method, Map<String, Object?> arguments) {
  if (method == 'invokeJson') {
    final inner = arguments['method'];
    final innerArguments = arguments['arguments'];
    return inner is String &&
        inner != 'invokeJson' &&
        erikaReadsOnly(inner,
            innerArguments is Map<String, Object?> ? innerArguments : const {});
  }
  return method.startsWith('get') ||
      const {'listMethods', 'tracks', 'trackSelection', 'danmakuTracks'}
          .contains(method);
}

/// What each kernel lets Next read and set for one playback.
JsonMap kernelControls(String? kernel, Iterable<PlayerKernelType> reopen) {
  final reopenWith = [for (final type in reopen) kernelIdOf(type)];
  return switch (kernel) {
    'media_kit' => {
        'properties': {'read': 'any_mpv_property', 'write': 'any_mpv_property'},
        'decoders': const <String>[],
        'commands': 'any_mpv_command',
        'watch': true,
        'invoke': false,
        'reopenWith': reopenWith,
      },
    'mdk' => {
        'properties': {
          'read': 'set_properties_only',
          'write': 'any_mdk_property'
        },
        'decoders': ['video', 'audio'],
        'commands': null,
        'watch': true,
        'invoke': false,
        'reopenWith': reopenWith,
      },
    'erika' => {
        'properties': {'read': 'none', 'write': 'listed'},
        'settings': erikaKernelSettings,
        'decoders': const <String>[],
        'commands': null,
        'watch': false,
        'invoke': true,
        'reopenWith': reopenWith,
      },
    _ => {
        'properties': {'read': 'none', 'write': 'none'},
        'decoders': const <String>[],
        'commands': null,
        'watch': false,
        'invoke': false,
        'reopenWith': reopenWith,
      },
  };
}

final _secretName = RegExp(
    r'password|secret|token|cookie|authorization|api[_-]?key|passkey',
    caseSensitive: false);

/// A kernel value as it may leave NipaPlay: secrets removed.
Object? safeKernelValue(String name, Object? value) {
  if (value is List) {
    return [for (final item in value) safeKernelValue(name, item)];
  }
  if (value is! String) return value;
  if (value.isNotEmpty && _secretName.hasMatch(name)) return '[redacted]';
  return redactHarnessText(value);
}

final _networkName = RegExp(
    r'proxy|user[-_]?agent|header|cookie|referr?er|tls|ssl|ca[-_]?file',
    caseSensitive: false);
final _address = RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://');
final _networkOption = RegExp(
    r'(proxy|headers?|cookies?|user[-_]?agent|referr?er)\s*[=:]',
    caseSensitive: false);

/// Why a kernel setting waits for the person at NipaPlay: it can send
/// traffic or credentials somewhere else (a proxy, request headers,
/// cookies, user agent or referrer, TLS trust, an option text that sets one
/// of these, or a value that is itself an address). Null when it does not.
String? kernelSettingConsent(String name, String value) {
  if (_networkName.hasMatch(name)) return 'network';
  if (_address.hasMatch(value) || _networkOption.hasMatch(value)) {
    return 'network';
  }
  return null;
}

/// mpv command prefixes, which come before the command name.
const _mpvPrefixes = {
  'osd-auto', 'no-osd', 'osd-bar', 'osd-msg', 'osd-msg-bar', 'raw',
  'expand-properties', 'repeatable', 'nonrepeatable', 'async', 'sync',
};

/// The mpv command [args] without its prefixes.
List<String> mpvCommandBody(List<String> args) {
  var i = 0;
  while (i < args.length && _mpvPrefixes.contains(args[i])) {
    i++;
  }
  return args.sublist(i);
}

/// The property an mpv command changes, when it changes one.
String? mpvCommandProperty(List<String> args) {
  final body = mpvCommandBody(args);
  if (body.isEmpty) return null;
  switch (body.first) {
    case 'vf' || 'af':
      return body.first;
    case 'set' || 'add' || 'cycle' || 'multiply' || 'change-list':
      return body.length > 1 ? body[1] : null;
    case 'cycle-values':
      final i = body.length > 1 && body[1] == '!reverse' ? 2 : 1;
      return body.length > i ? body[i] : null;
  }
  return null;
}

/// mpv commands that leave nothing behind past the file playing.
const mpvTransientCommands = {
  'seek', 'revert-seek', 'frame-step', 'frame-back-step', 'sub-seek',
  'sub-step', 'screenshot', 'screenshot-to-file', 'screenshot-raw',
  'show-text', 'show-progress', 'print-text', 'expand-text', 'expand-path',
  'normalize-path', 'escape-ass', 'run', 'subprocess', 'script-message',
  'script-message-to', 'script-binding', 'drop-buffers', 'ab-loop',
  'ab-loop-dump-cache', 'ab-loop-align-cache', 'dump-cache', 'sub-add',
  'sub-remove', 'sub-reload', 'audio-add', 'audio-remove', 'audio-reload',
  'video-add', 'video-remove', 'video-reload', 'rescan-external-files',
  'write-watch-later-config',
};

/// Why an mpv command waits for the person at NipaPlay: it sets a
/// property that needs it, or an argument is an address or sets a proxy,
/// header, cookie, user agent or referrer. Running programs (run,
/// subprocess) does not wait. Null when it does not.
String? kernelCommandConsent(List<String> args) {
  final body = mpvCommandBody(args);
  if (body.isEmpty || const {'run', 'subprocess'}.contains(body.first)) {
    return null;
  }
  final property = mpvCommandProperty(args);
  if (property != null &&
      kernelSettingConsent(property, body.skip(1).join(' ')) != null) {
    return 'network';
  }
  for (final arg in body.skip(1)) {
    if (_address.hasMatch(arg) || _networkOption.hasMatch(arg)) {
      return 'network';
    }
  }
  return null;
}

/// Why an Erika invoke waits for the person at NipaPlay: an argument names
/// or holds a network setting or an address.
String? kernelInvokeConsent(Object? arguments) {
  bool walk(Object? value, [String key = '']) {
    if (key.isNotEmpty && _networkName.hasMatch(key)) return true;
    if (value is Map) {
      return value.entries.any((e) => walk(e.value, '${e.key}'));
    }
    if (value is List) return value.any((v) => walk(v));
    return value is String &&
        (_address.hasMatch(value) || _networkOption.hasMatch(value));
  }

  return walk(arguments) ? 'network' : null;
}

/// A kernel answer as it may leave NipaPlay: secrets removed, long text cut.
Object? safeKernelResult(Object? value) {
  Object? cut(Object? v) => switch (v) {
        String s when s.length > 16000 => '${s.substring(0, 16000)}[truncated]',
        Map m => {for (final e in m.entries) '${e.key}': cut(e.value)},
        List l => [for (final x in l.take(1000)) cut(x)],
        _ => v,
      };
  return cut(redactHarnessJson(value));
}

/// Erika's counters, kept from one read to diff against the next.
final class ErikaSample {
  const ErikaSample(this.at, this.instance, this.path, this.stats);
  final DateTime at;
  final int instance;
  final String? path;
  final JsonMap stats;
}

const _windowCounters = {
  'decodedVideoFrames': 'decodedFrames',
  'renderedVideoFrames': 'renderedFrames',
  'hardwareVideoFrames': 'hardwareFrames',
  'softwareVideoFrames': 'softwareFrames',
  'cpuVideoFrameFallbacks': 'cpuFallbackFrames',
  'videoFrameBackpressureDrops': 'backpressureDrops',
  'importFailures': 'importFailures',
  'renderFailures': 'renderFailures',
  'audioFailures': 'audioFailures',
  'audioClockUnderflowFrames': 'audioUnderflowFrames',
  'audioRecoveryCount': 'audioRecoveries',
  'audioRecoveryFailures': 'audioRecoveryFailures',
  'hdrSourceFrames': 'hdrSourceFrames',
  'hdr10OutputFrames': 'hdr10OutputFrames',
  'sdrTonemapFrames': 'sdrTonemapFrames',
};

/// The change in Erika's counters between two reads of the same player
/// and media, with frame rates over that window. Null with the reason when
/// the two reads cannot be compared.
({JsonMap? window, String? reason}) erikaWindow(
    ErikaSample? previous, ErikaSample current,
    {required String source}) {
  if (previous == null) return (window: null, reason: 'no_previous_read');
  if (previous.instance != current.instance) {
    return (window: null, reason: 'player_changed');
  }
  if (previous.path != current.path) {
    return (window: null, reason: 'media_changed');
  }
  final elapsed = current.at.difference(previous.at);
  if (elapsed < const Duration(milliseconds: 500)) {
    return (window: null, reason: 'too_short');
  }
  if (elapsed > const Duration(minutes: 2)) {
    return (window: null, reason: 'too_old');
  }
  final changes = <String, Object?>{};
  for (final entry in _windowCounters.entries) {
    final before = previous.stats[entry.key];
    final after = current.stats[entry.key];
    if (before is! num || after is! num) {
      changes[entry.value] = null;
      continue;
    }
    if (after < before) return (window: null, reason: 'counters_reset');
    changes[entry.value] = (after - before).toInt();
  }
  final seconds = elapsed.inMicroseconds / 1e6;
  double? rate(Object? frames) =>
      frames is int ? double.parse((frames / seconds).toStringAsFixed(2)) : null;
  return (
    window: {
      'source': source,
      'from': previous.at.toIso8601String(),
      'to': current.at.toIso8601String(),
      'seconds': double.parse(seconds.toStringAsFixed(3)),
      'decodedFps': rate(changes['decodedFrames']),
      'renderedFps': rate(changes['renderedFrames']),
      ...changes,
    },
    reason: null,
  );
}

/// Erika's report in one shape: what it says as it says it, a few facts
/// read straight off it (the decoder in use is hardware unless Erika names
/// software; a fallback happened when it counts one or names a previous
/// backend), and the window since the previous read.
JsonMap erikaKernelFacts(JsonMap status,
    {JsonMap? window, String? windowUnavailable}) {
  Map<String, Object?> map(Object? value) => value is Map
      ? {for (final entry in value.entries) '${entry.key}': entry.value}
      : const {};
  final stats = map(status['presenterStats']);
  final decoder = map(status['decoder']);
  final diagnostics = status['diagnostics'] is Map
      ? redactHarnessJson(map(status['diagnostics']))
      : null;
  final scheduler = map(map(map(diagnostics)['timing'])['scheduler']);
  final output = map(status['outputStatus']);
  final params = map(status['videoParams']);
  Object? s(String key) => stats.isEmpty ? null : stats[key];
  final active = decoder['activeBackend'] as String?;
  final fallbacks = decoder['fallbackCount'];
  final tracks = (status['tracks'] as List?)?.cast<Map>();
  final video = tracks
      ?.where((t) => t['kind'] == 'video')
      .fold<Map?>(null, (found, t) => found ?? (t['selected'] == true ? t : null));
  final num? fpsNum = video?['frameRateNumerator'] as num?;
  final num? fpsDen = video?['frameRateDenominator'] as num?;
  return {
    'reportedAt': status['presenterStatsAt'],
    'decoder': {
      'activeBackend': active,
      'requestedBackend': decoder['requestedBackend'],
      'previousBackend': decoder['previousBackend'],
      'fallbackCount': fallbacks,
      'stage': decoder['stage'],
      'reason': decoder['reason'],
      'codec': decoder['codec'],
      'pixelFormat': decoder['pixelFormat'],
      'hardware': active == null || active.isEmpty ? null : active != 'software',
      'fellBack': decoder.isEmpty
          ? null
          : (fallbacks is num && fallbacks > 0) ||
              decoder['previousBackend'] != null,
    },
    'frames': {
      'decoded': s('decodedVideoFrames'),
      'rendered': s('renderedVideoFrames'),
      'hardware': s('hardwareVideoFrames'),
      'software': s('softwareVideoFrames'),
      'zeroCopy': s('zeroCopyVideoFrames'),
      'directZeroCopy': s('directZeroCopyVideoFrames'),
      'sharedHandle': s('sharedHandleVideoFrames'),
      'cpuFallbacks': s('cpuVideoFrameFallbacks'),
      'backpressureDrops': s('videoFrameBackpressureDrops'),
      'importFailures': s('importFailures'),
      'renderFailures': s('renderFailures'),
      'lastRenderMicros': s('lastRenderMicros'),
      'lastRenderCurrentMicros': s('lastRenderCurrentMicros'),
      'nominalFps': fpsNum != null && fpsDen != null && fpsNum > 0 && fpsDen > 0
          ? double.parse((fpsNum / fpsDen).toStringAsFixed(3))
          : null,
      'lateDropped': scheduler['lateDroppedFrames'],
    },
    'audio': {
      'pushedFrames': s('pushedAudioFrames'),
      'clockReadFrames': s('audioClockReadFrames'),
      'clockQueuedFrames': s('audioClockQueuedFrames'),
      'underflowFrames': s('audioClockUnderflowFrames'),
      'failures': s('audioFailures'),
      'recoveryState': s('audioRecoveryState'),
      'lastErrorCode': s('audioLastErrorCode'),
      'recoveryAttempts': s('audioRecoveryAttempts'),
      'recoveryCount': s('audioRecoveryCount'),
      'recoveryFailures': s('audioRecoveryFailures'),
      'outputEvent': status['audioOutput'],
      'device': null,
      'latencyMs': null,
    },
    'hdr': {
      'sourceFrames': s('hdrSourceFrames'),
      'hdr10OutputFrames': s('hdr10OutputFrames'),
      'sdrTonemapFrames': s('sdrTonemapFrames'),
      'hdr10OutputActive': s('hdr10OutputActive'),
      'hdr10MetadataUpdates': s('hdr10MetadataUpdates'),
      'hdr10MetadataFailures': s('hdr10MetadataFailures'),
      'hdr10OutputFailures': s('hdr10OutputFailures'),
      'output': output.isEmpty ? null : output,
      'videoPrimaries': params['primaries'],
      'videoTransfer': params['transfer'],
      'metadata': null,
      'dolbyVision': null,
    },
    'window': window,
    if (window == null) 'windowUnavailable': windowUnavailable,
    'upscaler': status['upscalerStatus'],
    'resources': status['resourceStatus'],
    'tracks': tracks == null
        ? null
        : [for (final t in tracks) redactHarnessJson(t)],
    'debugHud': status['debugHud'],
    'lastError': status['lastError'] is String
        ? redactHarnessText(status['lastError'] as String)
        : null,
    'errors': status['errors'],
    'diagnostics': diagnostics,
    'notReported': erikaNotReported,
  };
}
