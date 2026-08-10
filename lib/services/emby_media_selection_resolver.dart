import '../models/emby_media_selection.dart';
import 'emby_release_name_parser.dart';

abstract interface class EmbyMediaSelectionResolver {
  EmbyResolutionPlan resolve({
    required List<EmbyMediaSourceDescriptor> sources,
    required EmbyPreferenceLayers preferences,
  });
}

class DefaultEmbyMediaSelectionResolver implements EmbyMediaSelectionResolver {
  @override
  EmbyResolutionPlan resolve({
    required List<EmbyMediaSourceDescriptor> sources,
    required EmbyPreferenceLayers preferences,
  }) {
    final identities = <EmbyMediaSourceDescriptor, EmbyReleaseIdentity>{
      for (final source in sources)
        source: parseEmbyReleaseIdentity(source.displayName),
    };
    final candidates = <EmbySourceCandidate>[];
    final includedIds = <String>{};

    void addMatching(EmbySelectionReason reason,
        bool Function(EmbyMediaSourceDescriptor source) matches,
        {bool rankBySimilarity = true,
        Set<String> preferredFamilies = const <String>{},
        Set<String> preferredFeatures = const <String>{},
        EmbyTechnicalFingerprint? preferredTechnical}) {
      final matchingSources = sources
          .asMap()
          .entries
          .where(
            (entry) => matches(entry.value),
          )
          .toList()
        ..sort((left, right) {
          if (!rankBySimilarity) return left.key.compareTo(right.key);
          final scoreDifference = _similarityScore(
            right.value,
            identities[right.value]!,
            preferredFamilies: preferredFamilies,
            preferredFeatures: preferredFeatures,
            preferredTechnical: preferredTechnical,
          ).compareTo(
            _similarityScore(
              left.value,
              identities[left.value]!,
              preferredFamilies: preferredFamilies,
              preferredFeatures: preferredFeatures,
              preferredTechnical: preferredTechnical,
            ),
          );
          return scoreDifference != 0
              ? scoreDifference
              : left.key.compareTo(right.key);
        });

      for (final entry in matchingSources) {
        final source = entry.value;
        if (!matches(source) || !includedIds.add(source.source.id)) continue;
        candidates.add(
          EmbySourceCandidate(
            source: source,
            reason: reason,
            tracks: _resolveTracks(source, preferences),
          ),
        );
      }
    }

    final episodeSourceId = preferences.episode?.mediaSourceId;
    if (episodeSourceId != null && episodeSourceId.isNotEmpty) {
      addMatching(
        EmbySelectionReason.episodeExact,
        (source) => source.source.id == episodeSourceId,
        rankBySimilarity: false,
      );
    }

    final globalFamilies = preferences.global?.families ?? const <String>{};
    if (globalFamilies.isNotEmpty) {
      addMatching(
        EmbySelectionReason.globalFamily,
        (source) => _sharesFamily(identities[source]!.families, globalFamilies),
        preferredFamilies: globalFamilies,
        preferredTechnical: preferences.global?.technical,
      );
    }

    final globalTechnical = preferences.global?.technical;
    if (globalTechnical != null && _hasTechnicalCriteria(globalTechnical)) {
      addMatching(
        EmbySelectionReason.technical,
        (source) => _technicalSimilarity(source.technical, globalTechnical) > 0,
        preferredFamilies: globalFamilies,
        preferredTechnical: globalTechnical,
      );
    }

    final seriesFullName = preferences.series?.normalizedFullName;
    if (seriesFullName != null && seriesFullName.isNotEmpty) {
      final normalized = _normalizeFullName(seriesFullName);
      addMatching(
        EmbySelectionReason.seriesFullName,
        (source) => identities[source]!.normalizedFullName == normalized,
        preferredFamilies: preferences.series?.families ?? const <String>{},
        preferredFeatures: preferences.series?.features ?? const <String>{},
        preferredTechnical: preferences.series?.technical,
      );
    }

    final seriesFamilies = preferences.series?.families ?? const <String>{};
    if (seriesFamilies.isNotEmpty) {
      addMatching(
        EmbySelectionReason.seriesFamily,
        (source) => _sharesFamily(identities[source]!.families, seriesFamilies),
        preferredFamilies: seriesFamilies,
        preferredFeatures: preferences.series?.features ?? const <String>{},
        preferredTechnical: preferences.series?.technical,
      );
    }

    final seriesTechnical = preferences.series?.technical;
    if (seriesTechnical != null && _hasTechnicalCriteria(seriesTechnical)) {
      addMatching(
        EmbySelectionReason.technical,
        (source) => _technicalSimilarity(source.technical, seriesTechnical) > 0,
        preferredFamilies: seriesFamilies,
        preferredFeatures: preferences.series?.features ?? const <String>{},
        preferredTechnical: seriesTechnical,
      );
    }

    addMatching(
      EmbySelectionReason.embyDefault,
      (_) => true,
      rankBySimilarity: false,
    );
    return EmbyResolutionPlan(candidates: candidates);
  }

  EmbyResolvedTrackBundle _resolveTracks(
    EmbyMediaSourceDescriptor source,
    EmbyPreferenceLayers preferences,
  ) =>
      EmbyResolvedTrackBundle(
        audio: _resolveTrack(
          sourceId: source.source.id,
          tracks: source.audioTracks,
          preferences: <EmbyTrackPreference?>[
            preferences.episode?.audio,
            preferences.global?.audio,
            preferences.series?.audio,
          ],
          indexOf: (track) => track.index,
          fingerprintOf: (track) => track.fingerprint,
          allowTechnicalFallback: true,
          requireSubtitleKindAndCodec: false,
        ),
        subtitle: _resolveTrack(
          sourceId: source.source.id,
          tracks: source.subtitleTracks,
          preferences: <EmbyTrackPreference?>[
            preferences.episode?.subtitle,
            preferences.global?.subtitle,
            preferences.series?.subtitle,
          ],
          indexOf: (track) => track.index,
          fingerprintOf: (track) => track.fingerprint,
          allowTechnicalFallback: true,
          requireSubtitleKindAndCodec: true,
        ),
      );
}

EmbyResolvedTrackSelection _resolveTrack<T>({
  required String sourceId,
  required List<T> tracks,
  required List<EmbyTrackPreference?> preferences,
  required int Function(T track) indexOf,
  required EmbyTrackFingerprint Function(T track) fingerprintOf,
  required bool allowTechnicalFallback,
  required bool requireSubtitleKindAndCodec,
}) {
  for (final preference in preferences) {
    if (preference == null) continue;
    if (preference.mode == EmbyTrackPreferenceMode.followDefault) {
      return const EmbyResolvedTrackSelection.followDefault();
    }
    if (preference.mode == EmbyTrackPreferenceMode.disabled) {
      return const EmbyResolvedTrackSelection.disabled();
    }

    final exactIndex = preference.sourceIndex;
    T? matchedTrack;
    if (preference.mediaSourceId == sourceId && exactIndex != null) {
      for (final track in tracks) {
        if (indexOf(track) == exactIndex) {
          matchedTrack = track;
          break;
        }
      }
    }

    matchedTrack ??= _firstMatchingTrack(
      tracks,
      preference.fingerprint,
      fingerprintOf,
      allowTechnicalFallback: allowTechnicalFallback,
      requireSubtitleKindAndCodec: requireSubtitleKindAndCodec,
    );
    if (matchedTrack != null) {
      return EmbyResolvedTrackSelection.track(
        sourceIndex: indexOf(matchedTrack),
        fingerprint: fingerprintOf(matchedTrack),
      );
    }
  }
  return const EmbyResolvedTrackSelection.followDefault();
}

T? _firstMatchingTrack<T>(
  List<T> tracks,
  EmbyTrackFingerprint? preferred,
  EmbyTrackFingerprint Function(T track) fingerprintOf, {
  required bool allowTechnicalFallback,
  required bool requireSubtitleKindAndCodec,
}) {
  if (preferred == null) return null;

  T? find(bool Function(EmbyTrackFingerprint value) matches) {
    for (final track in tracks) {
      if (matches(fingerprintOf(track))) return track;
    }
    return null;
  }

  final language = _normalizedText(preferred.language);
  final title = _normalizedText(preferred.normalizedTitle);
  if (language != null && title != null) {
    final languageAndTitle = find(
      (value) =>
          _normalizedText(value.language) == language &&
          _normalizedText(value.normalizedTitle) == title,
    );
    if (languageAndTitle != null) return languageAndTitle;
  }
  if (language != null) {
    final languageMatch = find(
      (value) => _normalizedText(value.language) == language,
    );
    if (languageMatch != null) return languageMatch;
  }
  if (!allowTechnicalFallback) return null;

  final channels = preferred.channels;
  final codec = _normalizedText(preferred.codec);
  final isExternal = preferred.isExternal;
  if (requireSubtitleKindAndCodec) {
    if (codec == null || isExternal == null) return null;
    return find(
      (value) =>
          _normalizedText(value.codec) == codec &&
          value.isExternal == isExternal,
    );
  }
  if (channels == null && codec == null) return null;
  return find(
    (value) =>
        (channels == null || value.channels == channels) &&
        (codec == null || _normalizedText(value.codec) == codec),
  );
}

String _normalizeFullName(String value) =>
    parseEmbyReleaseIdentity(value).normalizedFullName;

bool _sharesFamily(Set<String> sourceFamilies, Set<String> preferredFamilies) {
  final normalizedPreferred = preferredFamilies
      .map((family) => family.trim().toLowerCase())
      .where((family) => family.isNotEmpty)
      .toSet();
  return sourceFamilies.any(normalizedPreferred.contains);
}

bool _hasTechnicalCriteria(EmbyTechnicalFingerprint technical) =>
    technical.height != null ||
    _hasText(technical.videoCodec) ||
    _hasText(technical.hdr) ||
    _hasText(technical.container);

bool _sameText(String? expected, String? actual) =>
    !_hasText(expected) ||
    expected!.trim().toLowerCase() == actual?.trim().toLowerCase();

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String? _normalizedText(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

int _similarityScore(
  EmbyMediaSourceDescriptor source,
  EmbyReleaseIdentity identity, {
  required Set<String> preferredFamilies,
  required Set<String> preferredFeatures,
  required EmbyTechnicalFingerprint? preferredTechnical,
}) {
  final normalizedFamilies =
      preferredFamilies.map(_normalizedText).whereType<String>().toSet();
  final normalizedFeatures =
      preferredFeatures.map(_normalizedText).whereType<String>().toSet();
  final featureMatches = identity.features
      .map(_normalizedText)
      .whereType<String>()
      .where(normalizedFeatures.contains)
      .length;
  final familyMatches = identity.families
      .map(_normalizedText)
      .whereType<String>()
      .where(normalizedFamilies.contains)
      .length;
  return familyMatches * 100 +
      featureMatches * 10 +
      _technicalSimilarity(
        source.technical,
        preferredTechnical,
      );
}

int _technicalSimilarity(
  EmbyTechnicalFingerprint source,
  EmbyTechnicalFingerprint? preferred,
) {
  if (preferred == null) return 0;
  var matches = 0;
  if (preferred.height != null && source.height == preferred.height) matches++;
  if (_hasText(preferred.videoCodec) &&
      _sameText(preferred.videoCodec, source.videoCodec)) {
    matches++;
  }
  if (_hasText(preferred.hdr) && _sameText(preferred.hdr, source.hdr)) {
    matches++;
  }
  if (_hasText(preferred.container) &&
      _sameText(preferred.container, source.container)) {
    matches++;
  }
  return matches;
}
