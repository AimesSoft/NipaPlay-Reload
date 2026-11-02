enum ErikaPlaybackState {
  idle,
  opening,
  ready,
  playing,
  paused,
  stopped,
  closed,
  error,
}

enum ErikaEventKind {
  none,
  stateChanged,
  durationChanged,
  positionChanged,
  tracksChanged,
  bufferingChanged,
  videoParamsChanged,
  surfaceAttached,
  surfaceDetached,
  error,
  trackSelectionChanged,
  videoDecoderChanged,
  audioOutputChanged,
  systemMediaNavigationRequested,

  /// The media played to its end on its own (a stop asked for sends none).
  /// Follows the `stopped` state the end brings.
  ended,
}

enum ErikaSystemMediaCommand {
  previous,
  next,
}

enum ErikaTrackKind {
  video,
  audio,
  subtitle,
}

enum ErikaTrackSource {
  embedded,
  external,
}

class ErikaVideoParams {
  const ErikaVideoParams({
    required this.width,
    required this.height,
    required this.primaries,
    required this.transfer,
  });

  factory ErikaVideoParams.fromMap(Map<dynamic, dynamic>? map) {
    return ErikaVideoParams(
      width: _asInt(map?['width']),
      height: _asInt(map?['height']),
      primaries: _asInt(map?['primaries']),
      transfer: _asInt(map?['transfer']),
    );
  }

  final int width;
  final int height;
  final int primaries;
  final int transfer;

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}

class ErikaVideoDecoderInfo {
  const ErikaVideoDecoderInfo({
    required this.stage,
    required this.requestedBackend,
    required this.activeBackend,
    required this.fallbackCount,
    this.previousBackend,
    this.codec,
    this.pixelFormat,
    this.lineSizes = const <int>[],
    this.reason,
  });

  factory ErikaVideoDecoderInfo.fromMap(Map<dynamic, dynamic> map) {
    return ErikaVideoDecoderInfo(
      stage: map['stage'] as String? ?? '',
      requestedBackend: map['requestedBackend'] as String? ?? '',
      previousBackend: map['previousBackend'] as String?,
      activeBackend: map['activeBackend'] as String? ?? '',
      fallbackCount: _asInt(map['fallbackCount']),
      codec: map['codec'] as String?,
      pixelFormat: map['pixelFormat'] as String?,
      lineSizes: switch (map['lineSizes']) {
        final List<dynamic> values => values
            .whereType<num>()
            .map((value) => value.toInt())
            .toList(growable: false),
        _ => const <int>[],
      },
      reason: map['reason'] as String?,
    );
  }

  final String stage;
  final String requestedBackend;
  final String? previousBackend;
  final String activeBackend;
  final int fallbackCount;
  final String? codec;
  final String? pixelFormat;
  final List<int> lineSizes;
  final String? reason;

  static int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}

class ErikaAudioOutputInfo {
  const ErikaAudioOutputInfo({
    required this.recoveryState,
    required this.lastErrorCode,
    required this.recoveryAttempts,
    required this.recoveryCount,
    required this.recoveryFailures,
    required this.transitionSequence,
  });

  factory ErikaAudioOutputInfo.fromMap(Map<dynamic, dynamic> map) {
    return ErikaAudioOutputInfo(
      recoveryState: map['recoveryState'] as String? ?? 'unknown',
      lastErrorCode: _asInt(map['lastErrorCode']),
      recoveryAttempts: _asInt(map['recoveryAttempts']),
      recoveryCount: _asInt(map['recoveryCount']),
      recoveryFailures: _asInt(map['recoveryFailures']),
      transitionSequence: _asInt(map['transitionSequence']),
    );
  }

  final String recoveryState;
  final int lastErrorCode;
  final int recoveryAttempts;
  final int recoveryCount;
  final int recoveryFailures;
  final int transitionSequence;

  bool get isStable => recoveryState == 'stable';
  bool get isDisconnected => recoveryState == 'disconnected';
  bool get isRecovering => recoveryState == 'recovering';
  bool get isFailed => recoveryState == 'failed';

  static int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}

class ErikaTrackCounts {
  const ErikaTrackCounts({
    required this.video,
    required this.audio,
    required this.subtitle,
  });

  factory ErikaTrackCounts.fromMap(Map<dynamic, dynamic>? map) {
    return ErikaTrackCounts(
      video: _asInt(map?['video']),
      audio: _asInt(map?['audio']),
      subtitle: _asInt(map?['subtitle']),
    );
  }

  final int video;
  final int audio;
  final int subtitle;

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}

class ErikaTrackSelection {
  const ErikaTrackSelection({
    this.video,
    this.audio,
    this.subtitle,
  });

  factory ErikaTrackSelection.fromMap(Map<dynamic, dynamic>? map) {
    return ErikaTrackSelection(
      video: _trackId(map?['video']),
      audio: _trackId(map?['audio']),
      subtitle: _trackId(map?['subtitle']),
    );
  }

  final int? video;
  final int? audio;
  final int? subtitle;

  static int? _trackId(Object? value) {
    final id = _asInt(value);
    return id >= 0 ? id : null;
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return -1;
  }
}

class ErikaTrackInfo {
  const ErikaTrackInfo({
    required this.id,
    required this.kind,
    required this.source,
    required this.selected,
    required this.canRemove,
    this.title,
    this.language,
    this.codec,
    this.width = 0,
    this.height = 0,
    this.sampleRate = 0,
    this.channels = 0,
    this.pixelFormat,
    this.sampleFormat,
    this.profile,
    this.level = 0,
    this.bitRate,
    this.frameRateNumerator = 0,
    this.frameRateDenominator = 0,
  });

  factory ErikaTrackInfo.fromMap(Map<dynamic, dynamic> map) {
    return ErikaTrackInfo(
      id: _asInt(map['id']),
      kind: _trackKindFromIndex(_asInt(map['kind'])),
      source: _trackSourceFromIndex(_asInt(map['source'])),
      selected: map['selected'] == true,
      canRemove: map['canRemove'] == true,
      title: map['title'] as String?,
      language: map['language'] as String?,
      codec: map['codec'] as String?,
      width: _asInt(map['width']),
      height: _asInt(map['height']),
      sampleRate: _asInt(map['sampleRate']),
      channels: _asInt(map['channels']),
      pixelFormat: map['pixelFormat'] as String?,
      sampleFormat: map['sampleFormat'] as String?,
      profile: map['profile'] as String?,
      level: _asInt(map['level']),
      bitRate: _asPositiveInt(map['bitRate']),
      frameRateNumerator: _asInt(map['frameRateNumerator']),
      frameRateDenominator: _asInt(map['frameRateDenominator']),
    );
  }

  final int id;
  final ErikaTrackKind kind;
  final ErikaTrackSource source;
  final bool selected;
  final bool canRemove;
  final String? title;
  final String? language;
  final String? codec;
  final int width;
  final int height;
  final int sampleRate;
  final int channels;
  final String? pixelFormat;
  final String? sampleFormat;
  final String? profile;
  final int level;
  final int? bitRate;
  final int frameRateNumerator;
  final int frameRateDenominator;

  double? get framesPerSecond {
    if (frameRateNumerator <= 0 || frameRateDenominator <= 0) {
      return null;
    }
    return frameRateNumerator / frameRateDenominator;
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'kind': kind.name,
      'source': source.name,
      'selected': selected,
      'canRemove': canRemove,
      'title': title,
      'language': language,
      'codec': codec,
      'width': width,
      'height': height,
      'sampleRate': sampleRate,
      'channels': channels,
      'pixelFormat': pixelFormat,
      'sampleFormat': sampleFormat,
      'profile': profile,
      'level': level,
      'bitRate': bitRate,
      'frameRateNumerator': frameRateNumerator,
      'frameRateDenominator': frameRateDenominator,
    };
  }

  bool get isEmbedded => source == ErikaTrackSource.embedded;
  bool get isExternal => source == ErikaTrackSource.external;

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  static int? _asPositiveInt(Object? value) {
    final parsed = _asInt(value);
    return parsed > 0 ? parsed : null;
  }

  static ErikaTrackKind _trackKindFromIndex(int index) {
    if (index >= 0 && index < ErikaTrackKind.values.length) {
      return ErikaTrackKind.values[index];
    }
    return ErikaTrackKind.video;
  }

  static ErikaTrackSource _trackSourceFromIndex(int index) {
    if (index >= 0 && index < ErikaTrackSource.values.length) {
      return ErikaTrackSource.values[index];
    }
    return ErikaTrackSource.embedded;
  }
}

class ErikaPlayerEvent {
  const ErikaPlayerEvent({
    required this.playerId,
    required this.kind,
    required this.state,
    required this.duration,
    required this.position,
    required this.buffering,
    required this.video,
    required this.tracks,
    required this.trackList,
    required this.trackSelection,
    this.status = 0,
    this.error,
    this.message,
    this.decoder,
    this.audio,
    this.systemMediaCommand,
  });

  factory ErikaPlayerEvent.fromMap(Map<dynamic, dynamic> map) {
    return ErikaPlayerEvent(
      playerId: _asInt(map['playerId']),
      kind: _eventKindFromIndex(_asInt(map['kind'])),
      state: _stateFromIndex(_asInt(map['state'])),
      duration: Duration(microseconds: _asInt(map['durationMicros'])),
      position: Duration(microseconds: _asInt(map['positionMicros'])),
      buffering: map['buffering'] == true,
      video: ErikaVideoParams.fromMap(map['video'] as Map<dynamic, dynamic>?),
      tracks: ErikaTrackCounts.fromMap(
        map['tracks'] as Map<dynamic, dynamic>?,
      ),
      trackList: _trackListFromValue(map['trackList']),
      trackSelection: ErikaTrackSelection.fromMap(
        map['trackSelection'] as Map<dynamic, dynamic>?,
      ),
      status: _asInt(map['status']),
      error: map['error'] as String?,
      message: map['message'] as String?,
      decoder: switch (map['decoder']) {
        final Map<dynamic, dynamic> value =>
          ErikaVideoDecoderInfo.fromMap(value),
        _ => null,
      },
      audio: switch (map['audio']) {
        final Map<dynamic, dynamic> value =>
          ErikaAudioOutputInfo.fromMap(value),
        _ => null,
      },
      systemMediaCommand: switch (map['navigation']) {
        'previous' => ErikaSystemMediaCommand.previous,
        'next' => ErikaSystemMediaCommand.next,
        _ => null,
      },
    );
  }

  final int playerId;
  final ErikaEventKind kind;
  final ErikaPlaybackState state;
  final Duration duration;
  final Duration position;
  final bool buffering;
  final ErikaVideoParams video;
  final ErikaTrackCounts tracks;
  final List<ErikaTrackInfo> trackList;
  final ErikaTrackSelection trackSelection;
  final int status;
  final String? error;
  final String? message;
  final ErikaVideoDecoderInfo? decoder;
  final ErikaAudioOutputInfo? audio;
  final ErikaSystemMediaCommand? systemMediaCommand;

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }

  static ErikaEventKind _eventKindFromIndex(int index) {
    if (index >= 0 && index < ErikaEventKind.values.length) {
      return ErikaEventKind.values[index];
    }
    return ErikaEventKind.none;
  }

  static ErikaPlaybackState _stateFromIndex(int index) {
    if (index >= 0 && index < ErikaPlaybackState.values.length) {
      return ErikaPlaybackState.values[index];
    }
    return ErikaPlaybackState.error;
  }

  static List<ErikaTrackInfo> _trackListFromValue(Object? value) {
    if (value is! List) {
      return const <ErikaTrackInfo>[];
    }
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map(ErikaTrackInfo.fromMap)
        .toList(growable: false);
  }
}
