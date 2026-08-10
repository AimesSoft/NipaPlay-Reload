import 'media_server_playback.dart';

class EmbyTrackFingerprint {
  const EmbyTrackFingerprint({
    this.language,
    this.normalizedTitle,
    this.codec,
    this.channels,
    this.isExternal,
  });

  final String? language;
  final String? normalizedTitle;
  final String? codec;
  final int? channels;
  final bool? isExternal;

  @override
  bool operator ==(Object other) =>
      other is EmbyTrackFingerprint &&
      language == other.language &&
      normalizedTitle == other.normalizedTitle &&
      codec == other.codec &&
      channels == other.channels &&
      isExternal == other.isExternal;

  @override
  int get hashCode =>
      Object.hash(language, normalizedTitle, codec, channels, isExternal);
}

class EmbyReleaseIdentity {
  const EmbyReleaseIdentity({
    required this.normalizedFullName,
    required this.families,
    required this.features,
  });

  final String normalizedFullName;
  final Set<String> families;
  final Set<String> features;
}

class EmbyTechnicalFingerprint {
  const EmbyTechnicalFingerprint({
    this.height,
    this.videoCodec,
    this.hdr,
    this.container,
  });

  final int? height;
  final String? videoCodec;
  final String? hdr;
  final String? container;
}

class EmbyVideoStreamDescriptor {
  const EmbyVideoStreamDescriptor({
    required this.index,
    this.codec,
    this.profile,
    this.level,
    this.width,
    this.height,
    this.frameRate,
    this.bitDepth,
    this.hdr,
    this.bitRate,
  });

  final int index;
  final String? codec;
  final String? profile;
  final String? level;
  final int? width;
  final int? height;
  final double? frameRate;
  final int? bitDepth;
  final String? hdr;
  final int? bitRate;
}

class EmbyAudioTrackDescriptor {
  const EmbyAudioTrackDescriptor({
    required this.index,
    this.language,
    this.title,
    this.codec,
    this.channels,
    this.sampleRate,
    this.bitRate,
    required this.isDefault,
    required this.fingerprint,
  });

  final int index;
  final String? language;
  final String? title;
  final String? codec;
  final int? channels;
  final int? sampleRate;
  final int? bitRate;
  final bool isDefault;
  final EmbyTrackFingerprint fingerprint;
}

class EmbySubtitleTrackDescriptor {
  const EmbySubtitleTrackDescriptor({
    required this.index,
    this.language,
    this.title,
    this.codec,
    required this.isExternal,
    required this.isDefault,
    required this.isForced,
    required this.fingerprint,
  });

  final int index;
  final String? language;
  final String? title;
  final String? codec;
  final bool isExternal;
  final bool isDefault;
  final bool isForced;
  final EmbyTrackFingerprint fingerprint;
}

class EmbyMediaSourceDescriptor {
  const EmbyMediaSourceDescriptor({
    required this.source,
    required this.displayName,
    required this.summary,
    required this.technical,
    required this.videoTracks,
    required this.audioTracks,
    required this.subtitleTracks,
  });

  final PlaybackMediaSource source;
  final String displayName;
  final String summary;
  final EmbyTechnicalFingerprint technical;
  final List<EmbyVideoStreamDescriptor> videoTracks;
  final List<EmbyAudioTrackDescriptor> audioTracks;
  final List<EmbySubtitleTrackDescriptor> subtitleTracks;
}

class EmbySelectionContext {
  const EmbySelectionContext({
    required this.accountKey,
    required this.seriesId,
    required this.episodeId,
  });

  final String accountKey;
  final String seriesId;
  final String episodeId;
}

enum EmbyTrackPreferenceMode { followDefault, disabled, track }

class EmbyTrackPreference {
  const EmbyTrackPreference.followDefault()
      : mode = EmbyTrackPreferenceMode.followDefault,
        fingerprint = null,
        sourceIndex = null,
        mediaSourceId = null;

  const EmbyTrackPreference.disabled()
      : mode = EmbyTrackPreferenceMode.disabled,
        fingerprint = null,
        sourceIndex = null,
        mediaSourceId = null;

  const EmbyTrackPreference.track(
    EmbyTrackFingerprint value, {
    this.sourceIndex,
    this.mediaSourceId,
  })  : assert((sourceIndex == null) == (mediaSourceId == null)),
        assert(sourceIndex == null || sourceIndex >= 0),
        mode = EmbyTrackPreferenceMode.track,
        fingerprint = value;

  final EmbyTrackPreferenceMode mode;
  final EmbyTrackFingerprint? fingerprint;
  final int? sourceIndex;
  final String? mediaSourceId;
}

enum EmbyResolvedTrackMode { followDefault, disabled, track }

class EmbyResolvedTrackSelection {
  const EmbyResolvedTrackSelection.followDefault()
      : mode = EmbyResolvedTrackMode.followDefault,
        sourceIndex = null,
        fingerprint = null;

  const EmbyResolvedTrackSelection.disabled()
      : mode = EmbyResolvedTrackMode.disabled,
        sourceIndex = null,
        fingerprint = null;

  const EmbyResolvedTrackSelection.track({
    required this.sourceIndex,
    required this.fingerprint,
  })  : assert(sourceIndex != null && sourceIndex >= 0),
        mode = EmbyResolvedTrackMode.track;

  final EmbyResolvedTrackMode mode;
  final int? sourceIndex;
  final EmbyTrackFingerprint? fingerprint;
}

class EmbyResolvedTrackBundle {
  const EmbyResolvedTrackBundle({
    required this.audio,
    required this.subtitle,
  });

  final EmbyResolvedTrackSelection audio;
  final EmbyResolvedTrackSelection subtitle;
}

class EmbyEpisodePreference {
  const EmbyEpisodePreference({
    this.mediaSourceId,
    this.displayName,
    this.audio,
    this.subtitle,
    required this.updatedAt,
  });

  final String? mediaSourceId;

  /// Original media-source name retained for this episode's UI label.
  final String? displayName;
  final EmbyTrackPreference? audio;
  final EmbyTrackPreference? subtitle;
  final DateTime updatedAt;

  bool get isEmpty =>
      mediaSourceId == null &&
      displayName == null &&
      audio == null &&
      subtitle == null;
}

class EmbySeriesPreference {
  const EmbySeriesPreference({
    this.normalizedFullName,
    this.families = const <String>{},
    this.features = const <String>{},
    this.technical,
    this.audio,
    this.subtitle,
  });

  final String? normalizedFullName;
  final Set<String> families;
  final Set<String> features;
  final EmbyTechnicalFingerprint? technical;
  final EmbyTrackPreference? audio;
  final EmbyTrackPreference? subtitle;

  bool get isEmpty =>
      normalizedFullName == null &&
      families.isEmpty &&
      features.isEmpty &&
      technical == null &&
      audio == null &&
      subtitle == null;
}

class EmbyGlobalPreference {
  const EmbyGlobalPreference({
    this.families = const <String>{},
    this.technical,
    this.audio,
    this.subtitle,
  });

  final Set<String> families;
  final EmbyTechnicalFingerprint? technical;
  final EmbyTrackPreference? audio;
  final EmbyTrackPreference? subtitle;

  bool get isEmpty =>
      families.isEmpty &&
      technical == null &&
      audio == null &&
      subtitle == null;
}

class EmbyPreferenceLayers {
  const EmbyPreferenceLayers({this.episode, this.series, this.global});

  final EmbyEpisodePreference? episode;
  final EmbySeriesPreference? series;
  final EmbyGlobalPreference? global;

  bool get isEmpty =>
      (episode == null || episode!.isEmpty) &&
      (series == null || series!.isEmpty) &&
      (global == null || global!.isEmpty);
}

class EmbyManualSelectionPatch {
  const EmbyManualSelectionPatch({this.source, this.audio, this.subtitle});

  final EmbyMediaSourceDescriptor? source;
  final EmbyTrackPreference? audio;
  final EmbyTrackPreference? subtitle;
}

enum EmbySelectionReason {
  episodeExact,
  seriesFullName,
  seriesFamily,
  globalFamily,
  technical,
  embyDefault,
}

class EmbySourceCandidate {
  const EmbySourceCandidate({
    required this.source,
    required this.reason,
    required this.tracks,
  });

  final EmbyMediaSourceDescriptor source;
  final EmbySelectionReason reason;
  final EmbyResolvedTrackBundle tracks;
}

class EmbyResolutionPlan {
  const EmbyResolutionPlan({required this.candidates});

  final List<EmbySourceCandidate> candidates;
}

EmbyMediaSourceDescriptor describeEmbyMediaSource(
  PlaybackMediaSource source, {
  required int ordinal,
}) {
  final videoTracks = <EmbyVideoStreamDescriptor>[];
  final audioTracks = <EmbyAudioTrackDescriptor>[];
  final subtitleTracks = <EmbySubtitleTrackDescriptor>[];

  for (final stream in source.mediaStreams) {
    final index = _integer(stream['Index']);
    if (index == null) continue;

    switch (_text(stream['Type'])?.toLowerCase()) {
      case 'video':
        videoTracks.add(
          EmbyVideoStreamDescriptor(
            index: index,
            codec: _text(stream['Codec']),
            profile: _text(stream['Profile']),
            level: _text(stream['Level']),
            width: _integer(stream['Width']),
            height: _integer(stream['Height']),
            frameRate: _double(stream['RealFrameRate']) ??
                _double(stream['FrameRate']),
            bitDepth: _integer(stream['BitDepth']),
            hdr: _text(stream['VideoRange']),
            bitRate: _integer(stream['BitRate']),
          ),
        );
      case 'audio':
        final language = _text(stream['Language']);
        final title = _text(stream['Title']);
        final codec = _text(stream['Codec']);
        final channels = _integer(stream['Channels']);
        audioTracks.add(
          EmbyAudioTrackDescriptor(
            index: index,
            language: language,
            title: title,
            codec: codec,
            channels: channels,
            sampleRate: _integer(stream['SampleRate']),
            bitRate: _integer(stream['BitRate']),
            isDefault: stream['IsDefault'] == true,
            fingerprint: EmbyTrackFingerprint(
              language: language,
              normalizedTitle: _normalizeTitle(title),
              codec: codec,
              channels: channels,
              isExternal: _bool(stream['IsExternal']),
            ),
          ),
        );
      case 'subtitle':
        final language = _text(stream['Language']);
        final title = _text(stream['Title']);
        final codec = _text(stream['Codec']);
        final isExternal = stream['IsExternal'] == true;
        subtitleTracks.add(
          EmbySubtitleTrackDescriptor(
            index: index,
            language: language,
            title: title,
            codec: codec,
            isExternal: isExternal,
            isDefault: stream['IsDefault'] == true,
            isForced: stream['IsForced'] == true,
            fingerprint: EmbyTrackFingerprint(
              language: language,
              normalizedTitle: _normalizeTitle(title),
              codec: codec,
              channels: _integer(stream['Channels']),
              isExternal: isExternal,
            ),
          ),
        );
    }
  }

  final primaryVideo = videoTracks.isEmpty ? null : videoTracks.first;
  final summaryParts = <String>[
    if (primaryVideo?.height != null) '${primaryVideo!.height}p',
    if (source.size != null) _formatSize(source.size!),
    if (source.bitRate != null) _formatBitRate(source.bitRate!),
  ];

  return EmbyMediaSourceDescriptor(
    source: source,
    displayName: _sourceLabel(source, ordinal: ordinal),
    summary: summaryParts.join(' · '),
    technical: EmbyTechnicalFingerprint(
      height: primaryVideo?.height,
      videoCodec: primaryVideo?.codec,
      hdr: primaryVideo?.hdr,
      container: _text(source.container),
    ),
    videoTracks: videoTracks,
    audioTracks: audioTracks,
    subtitleTracks: subtitleTracks,
  );
}

String _sourceLabel(PlaybackMediaSource source, {required int ordinal}) {
  final name = _text(source.name);
  if (name != null) return name;

  final path = _text(source.path);
  if (path != null) {
    final normalizedPath = path.replaceAll('\\', '/');
    final basename =
        normalizedPath.substring(normalizedPath.lastIndexOf('/') + 1);
    if (basename.isNotEmpty) {
      try {
        return Uri.decodeComponent(basename);
      } on FormatException {
        return basename;
      }
    }
  }

  final container = _text(source.container)?.toUpperCase();
  return container == null
      ? '版本 ${ordinal + 1}'
      : '版本 ${ordinal + 1} · $container';
}

String _formatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final digits = value >= 100 || value == value.roundToDouble() ? 0 : 2;
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

String _formatBitRate(int bitsPerSecond) {
  final megabits = bitsPerSecond / 1000000;
  final digits =
      megabits >= 100 || megabits == megabits.roundToDouble() ? 0 : 1;
  return '${megabits.toStringAsFixed(digits)} Mbps';
}

int? _integer(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

bool? _bool(Object? value) {
  if (value is bool) return value;
  return switch (value?.toString().toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => null,
  };
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String? _normalizeTitle(String? value) => _text(value)?.toLowerCase();
