import '../models/emby_media_selection.dart';
import '../player_abstraction/player_data_models.dart';
import 'emby_media_preference_store.dart';
import 'emby_media_selection_resolver.dart';

enum MediaServerMenuSurface {
  nipaplaySource,
  nipaplayAudio,
  nipaplaySubtitle,
  cupertinoSource,
  cupertinoAudio,
  cupertinoSubtitle,
}

String? embySeriesIdFromSourceKey(String? sourceKey) {
  final parts = sourceKey?.split(':') ?? const <String>[];
  if (parts.length < 3 || parts.first != 'emby') return null;
  final seriesId = parts[1].trim();
  return seriesId.isEmpty ? null : seriesId;
}

EmbyTrackPreference? preferenceForEmbyServerAudio(
  EmbyMediaSourceDescriptor source,
  int sourceIndex,
) {
  for (final track in source.audioTracks) {
    if (track.index == sourceIndex) {
      return EmbyTrackPreference.track(
        track.fingerprint,
        sourceIndex: track.index,
        mediaSourceId: source.source.id,
      );
    }
  }
  return null;
}

EmbyTrackPreference? preferenceForEmbyServerSubtitle(
  EmbyMediaSourceDescriptor source,
  int sourceIndex,
) {
  for (final track in source.subtitleTracks) {
    if (track.index == sourceIndex) {
      return EmbyTrackPreference.track(
        track.fingerprint,
        sourceIndex: track.index,
        mediaSourceId: source.source.id,
      );
    }
  }
  return null;
}

EmbyTrackPreference preferenceForEmbyNativeAudio(
  PlayerAudioStreamInfo track,
) =>
    EmbyTrackPreference.track(
      EmbyTrackFingerprint(
        language: _firstText(track.language, track.metadata['language']),
        normalizedTitle:
            _firstText(track.title, track.metadata['title'])?.toLowerCase(),
        codec: _firstText(track.codec.name, track.metadata['codec']),
        channels: track.codec.channels ?? _integer(track.metadata['channels']),
        isExternal: track.isExternal,
      ),
    );

EmbyTrackPreference preferenceForEmbyNativeSubtitle(
  PlayerSubtitleStreamInfo track,
) =>
    EmbyTrackPreference.track(
      EmbyTrackFingerprint(
        language: _firstText(track.language, track.metadata['language']),
        normalizedTitle:
            _firstText(track.title, track.metadata['title'])?.toLowerCase(),
        codec: _text(track.metadata['codec']),
        isExternal: _boolean(track.metadata['isExternal']) ?? false,
      ),
    );

class EmbyPlayerMenuSelectionService {
  const EmbyPlayerMenuSelectionService({
    required EmbyMediaPreferenceStore store,
    required EmbyMediaSelectionResolver resolver,
  })  : _store = store,
        _resolver = resolver;

  final EmbyMediaPreferenceStore _store;
  final EmbyMediaSelectionResolver _resolver;

  Future<EmbyResolvedTrackBundle> resolveTracksForSource({
    required EmbySelectionContext? context,
    required EmbyMediaSourceDescriptor currentSource,
  }) async {
    final preferences = context == null
        ? const EmbyPreferenceLayers()
        : await _store.load(context);
    final plan = _resolver.resolve(
      sources: <EmbyMediaSourceDescriptor>[currentSource],
      preferences: preferences,
    );
    return plan.candidates.first.tracks;
  }

  Future<bool> persistCurrentManualPatch({
    required EmbySelectionContext? context,
    required EmbyMediaSourceDescriptor currentSource,
    required EmbyManualSelectionPatch patch,
  }) async {
    if (context == null) return false;
    await _store.saveManualPatch(context, currentSource, patch);
    return true;
  }
}

final Set<MediaServerMenuSurface> _activeMenuSelections =
    <MediaServerMenuSurface>{};

Future<bool> runMediaServerMenuSelection(
  MediaServerMenuSurface surface,
  bool isEmby,
  Future<void> Function() applySelection,
  Future<bool> Function() persistEmbySelection,
) async {
  if (!isEmby) {
    await applySelection();
    return false;
  }
  if (!_activeMenuSelections.add(surface)) return false;
  try {
    await applySelection();
    return await persistEmbySelection();
  } finally {
    _activeMenuSelections.remove(surface);
  }
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String? _firstText(Object? primary, Object? fallback) =>
    _text(primary) ?? _text(fallback);

int? _integer(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

bool? _boolean(Object? value) {
  if (value is bool) return value;
  return switch (value?.toString().trim().toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => null,
  };
}
