import '../models/emby_media_selection.dart';
import '../player_abstraction/abstract_player.dart';
import '../player_abstraction/player_data_models.dart';
import '../player_abstraction/player_enums.dart';

export '../player_abstraction/abstract_player.dart'
    show AsyncExternalSubtitlePlayer;

enum EmbyExternalSubtitleActionKind { followDefault, disabled, select }

class EmbyExternalSubtitleAction {
  const EmbyExternalSubtitleAction.followDefault()
      : kind = EmbyExternalSubtitleActionKind.followDefault,
        streamIndex = null,
        codec = null,
        fingerprint = null;

  const EmbyExternalSubtitleAction.disabled()
      : kind = EmbyExternalSubtitleActionKind.disabled,
        streamIndex = null,
        codec = null,
        fingerprint = null;

  const EmbyExternalSubtitleAction.select({
    required this.streamIndex,
    required this.codec,
    required this.fingerprint,
  }) : kind = EmbyExternalSubtitleActionKind.select;

  final EmbyExternalSubtitleActionKind kind;
  final int? streamIndex;
  final String? codec;
  final EmbyTrackFingerprint? fingerprint;
}

class EmbyNativeTrackSelection {
  const EmbyNativeTrackSelection({
    this.audioIndex,
    this.subtitleIndex,
    required this.disableSubtitles,
    required this.externalSubtitle,
  });

  final int? audioIndex;
  final int? subtitleIndex;
  final bool disableSubtitles;
  final EmbyExternalSubtitleAction externalSubtitle;
}

typedef EmbyTrackIndexesSetter = void Function(List<int> indexes);
typedef EmbyExternalSubtitleClearer = Future<void> Function();
typedef EmbyExternalSubtitleLoader = Future<void> Function(
  EmbyExternalSubtitleAction action,
);

EmbyExternalSubtitleAction resolveExternalSubtitleAction(
  EmbyResolvedTrackSelection selection,
) {
  switch (selection.mode) {
    case EmbyResolvedTrackMode.followDefault:
      return const EmbyExternalSubtitleAction.followDefault();
    case EmbyResolvedTrackMode.disabled:
      return const EmbyExternalSubtitleAction.disabled();
    case EmbyResolvedTrackMode.track:
      final fingerprint = selection.fingerprint!;
      if (fingerprint.isExternal != true) {
        return const EmbyExternalSubtitleAction.disabled();
      }
      return EmbyExternalSubtitleAction.select(
        streamIndex: selection.sourceIndex!,
        codec: _normalizedText(fingerprint.codec) ?? 'srt',
        fingerprint: fingerprint,
      );
  }
}

EmbyNativeTrackSelection resolveNativeEmbyTracks(
  EmbyResolvedTrackBundle bundle,
  PlayerMediaInfo mediaInfo,
) {
  final audioIndex = bundle.audio.mode == EmbyResolvedTrackMode.track
      ? _matchNativeTrack(
          preferred: bundle.audio.fingerprint!,
          tracks: mediaInfo.audio ?? const <PlayerAudioStreamInfo>[],
          fingerprintOf: _audioFingerprint,
          allowTechnicalFallback: true,
        )
      : null;

  final subtitleSelection = bundle.subtitle;
  final externalSubtitle = resolveExternalSubtitleAction(subtitleSelection);
  final subtitleIndex = subtitleSelection.mode == EmbyResolvedTrackMode.track &&
          subtitleSelection.fingerprint!.isExternal != true
      ? _matchNativeTrack(
          preferred: subtitleSelection.fingerprint!,
          tracks: mediaInfo.subtitle ?? const <PlayerSubtitleStreamInfo>[],
          fingerprintOf: _subtitleFingerprint,
          allowTechnicalFallback: false,
        )
      : null;

  return EmbyNativeTrackSelection(
    audioIndex: audioIndex,
    subtitleIndex: subtitleIndex,
    disableSubtitles: subtitleSelection.mode == EmbyResolvedTrackMode.disabled,
    externalSubtitle: externalSubtitle,
  );
}

Future<void> applyEmbyResolvedTracksAfterOpen({
  required PlayerMediaInfo mediaInfo,
  required EmbyResolvedTrackBundle bundle,
  required EmbyTrackIndexesSetter setActiveAudio,
  required EmbyTrackIndexesSetter setActiveSubtitle,
  required EmbyExternalSubtitleClearer clearExternal,
  required EmbyExternalSubtitleLoader loadExternal,
}) async {
  final resolved = resolveNativeEmbyTracks(bundle, mediaInfo);
  if (resolved.audioIndex != null) {
    setActiveAudio(<int>[resolved.audioIndex!]);
  }

  switch (resolved.externalSubtitle.kind) {
    case EmbyExternalSubtitleActionKind.followDefault:
      await loadExternal(resolved.externalSubtitle);
    case EmbyExternalSubtitleActionKind.disabled:
      await clearExternal();
      if (resolved.disableSubtitles || resolved.subtitleIndex != null) {
        setActiveSubtitle(
          resolved.disableSubtitles
              ? const <int>[]
              : <int>[resolved.subtitleIndex!],
        );
      }
    case EmbyExternalSubtitleActionKind.select:
      setActiveSubtitle(const <int>[]);
      await clearExternal();
      await loadExternal(resolved.externalSubtitle);
  }
}

Future<void> applyEmbyExternalSubtitleAction({
  required EmbyExternalSubtitleAction action,
  required String videoPath,
  required String itemId,
  required String mediaSourceId,
  required Future<String?> Function(
    String itemId,
    String mediaSourceId,
    int streamIndex,
    String codec,
  ) download,
  required Future<bool> Function(
    String videoPath,
    String subtitlePath,
    int streamIndex,
    String codec,
  ) cache,
  required Future<void> Function(String subtitlePath, int streamIndex) activate,
  required Future<void> Function() followDefault,
}) async {
  switch (action.kind) {
    case EmbyExternalSubtitleActionKind.followDefault:
      await followDefault();
    case EmbyExternalSubtitleActionKind.disabled:
      return;
    case EmbyExternalSubtitleActionKind.select:
      final streamIndex = action.streamIndex!;
      final codec = _normalizedText(action.codec) ?? 'srt';
      final subtitlePath =
          await download(itemId, mediaSourceId, streamIndex, codec);
      if (subtitlePath == null || subtitlePath.trim().isEmpty) {
        throw StateError('The selected Emby subtitle could not be downloaded.');
      }
      final cached = await cache(
        videoPath,
        subtitlePath,
        streamIndex,
        codec,
      );
      if (!cached) {
        throw StateError('The selected Emby subtitle could not be cached.');
      }
      await activate(subtitlePath, streamIndex);
  }
}

Future<void> loadDefaultEmbyExternalSubtitles({
  required Future<List<Map<String, dynamic>>> Function() getTracks,
  required Future<String?> Function(int streamIndex, String codec) download,
  required Future<bool> Function(
    List<Map<String, dynamic>> downloaded,
    String? activePath,
  ) cache,
  required Future<void> Function(String subtitlePath, int streamIndex) activate,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) return;
  final tracks = await getTracks();
  if (!isCurrent()) return;

  final externalTracks = tracks
      .where((track) => track['type'] == 'external')
      .map((track) => Map<String, dynamic>.from(track))
      .toList();
  if (externalTracks.isEmpty) return;

  final preferred = _preferredExternalSubtitle(externalTracks);
  final preferredIndex = preferred['index'];
  final downloaded = <Map<String, dynamic>>[];
  String? activePath;
  int? activeIndex;

  for (final track in externalTracks) {
    if (!isCurrent()) return;
    final streamIndex = track['index'];
    if (streamIndex is! int) continue;
    final codec = _normalizedText(track['codec']?.toString()) ?? 'srt';
    final subtitlePath = await download(streamIndex, codec);
    if (!isCurrent()) return;
    if (subtitlePath == null || subtitlePath.trim().isEmpty) continue;

    downloaded.add(<String, dynamic>{
      ...track,
      'path': subtitlePath,
      'type': codec,
      'serverSubtitleIndex': streamIndex,
    });
    if (streamIndex == preferredIndex && activePath == null) {
      activePath = subtitlePath;
      activeIndex = streamIndex;
    }
  }

  if (downloaded.isEmpty || !isCurrent()) return;
  activePath ??= downloaded.first['path'] as String?;
  activeIndex ??= downloaded.first['serverSubtitleIndex'] as int?;
  if (activePath == null || activeIndex == null) return;

  if (!isCurrent()) return;
  final cached = await cache(downloaded, activePath);
  if (!isCurrent() || !cached) return;
  await activate(activePath, activeIndex);
}

Future<void> activateEmbyExternalSubtitle({
  required Object player,
  required String subtitlePath,
}) async {
  if (player is AsyncExternalSubtitlePlayer) {
    await player.setExternalSubtitleAsync(subtitlePath);
    return;
  }
  if (player is AbstractPlayer) {
    player.setMedia(subtitlePath, PlayerMediaType.subtitle);
    return;
  }
  throw ArgumentError.value(
    player,
    'player',
    'Player does not support external subtitles.',
  );
}

Future<void> applyEmbyTracksForVideoPath({
  required String videoPath,
  required bool isTranscoding,
  required Future<void> Function() applyEmby,
}) async {
  if (!videoPath.startsWith('emby://') || isTranscoding) return;
  await applyEmby();
}

Map<String, dynamic> _preferredExternalSubtitle(
  List<Map<String, dynamic>> tracks,
) {
  for (final track in tracks) {
    final language = _normalizedText(track['language']?.toString()) ?? '';
    final title = _normalizedText(track['title']?.toString()) ?? '';
    if (language.contains('chi') ||
        language.contains('zho') ||
        language.startsWith('zh') ||
        title.contains('chinese') ||
        title.contains('简体') ||
        title.contains('繁体') ||
        title.contains('中文')) {
      return track;
    }
  }
  for (final track in tracks) {
    if (track['isDefault'] == true) return track;
  }
  return tracks.first;
}

int? _matchNativeTrack<T>({
  required EmbyTrackFingerprint preferred,
  required List<T> tracks,
  required EmbyTrackFingerprint Function(T track) fingerprintOf,
  required bool allowTechnicalFallback,
}) {
  int? find(bool Function(EmbyTrackFingerprint candidate) matches) {
    for (var index = 0; index < tracks.length; index++) {
      if (matches(fingerprintOf(tracks[index]))) return index;
    }
    return null;
  }

  final exact = find((candidate) => _matchesAllDefined(preferred, candidate));
  if (exact != null) return exact;

  final language = _normalizedText(preferred.language);
  final title = _normalizedText(preferred.normalizedTitle);
  if (language != null && title != null) {
    final languageAndTitle = find(
      (candidate) =>
          _normalizedText(candidate.language) == language &&
          _normalizedText(candidate.normalizedTitle) == title,
    );
    if (languageAndTitle != null) return languageAndTitle;
  }

  if (language != null) {
    final languageMatch = find(
      (candidate) => _normalizedText(candidate.language) == language,
    );
    if (languageMatch != null) return languageMatch;
  }

  if (!allowTechnicalFallback) return null;
  final codec = _normalizedText(preferred.codec);
  final channels = preferred.channels;
  if (codec == null && channels == null) return null;
  return find(
    (candidate) {
      final candidateLanguage = _normalizedText(candidate.language);
      final languageDoesNotConflict = language == null ||
          candidateLanguage == null ||
          candidateLanguage == 'und';
      return languageDoesNotConflict &&
          (codec == null || _normalizedText(candidate.codec) == codec) &&
          (channels == null || candidate.channels == channels);
    },
  );
}

bool _matchesAllDefined(
  EmbyTrackFingerprint preferred,
  EmbyTrackFingerprint candidate,
) {
  final preferredLanguage = _normalizedText(preferred.language);
  final preferredTitle = _normalizedText(preferred.normalizedTitle);
  final preferredCodec = _normalizedText(preferred.codec);
  return (preferredLanguage == null ||
          _normalizedText(candidate.language) == preferredLanguage) &&
      (preferredTitle == null ||
          _normalizedText(candidate.normalizedTitle) == preferredTitle) &&
      (preferredCodec == null ||
          _normalizedText(candidate.codec) == preferredCodec) &&
      (preferred.channels == null ||
          candidate.channels == preferred.channels) &&
      (preferred.isExternal == null ||
          candidate.isExternal == preferred.isExternal);
}

EmbyTrackFingerprint _audioFingerprint(PlayerAudioStreamInfo track) {
  final metadata = track.metadata;
  return EmbyTrackFingerprint(
    language: track.language ?? metadata['language'],
    normalizedTitle: _normalizedText(track.title ?? metadata['title']),
    codec: track.codec.name ?? metadata['codec'],
    channels: track.codec.channels ?? int.tryParse(metadata['channels'] ?? ''),
    isExternal: track.isExternal || _boolFromText(metadata['isExternal']),
  );
}

EmbyTrackFingerprint _subtitleFingerprint(PlayerSubtitleStreamInfo track) {
  final metadata = track.metadata;
  return EmbyTrackFingerprint(
    language: track.language ?? metadata['language'],
    normalizedTitle: _normalizedText(track.title ?? metadata['title']),
    codec: metadata['codec'],
    channels: int.tryParse(metadata['channels'] ?? ''),
    isExternal: _boolFromText(metadata['isExternal']),
  );
}

bool _boolFromText(String? value) => value?.trim().toLowerCase() == 'true';

String? _normalizedText(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
