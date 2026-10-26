import 'ui_data.dart';

/// The provider object a found work is.
typedef FoundRef = ({String provider, String objectType, String externalId});

/// Works known from a metadata provider, outside the library. Their ID says
/// where they come from, so the agent can look them up; it is never shown.
abstract final class Found {
  static const _prefix = 'found:';

  /// The work-level objects a found work can be, by provider. A provider
  /// with a single kind leaves it out of the ID.
  static const kinds = {
    'dandanplay': ['anime'],
    'bangumi': ['subject'],
    'tmdb': ['tv', 'movie'],
  };

  /// `found:dandanplay:123`, `found:bangumi:456`, `found:tmdb:tv:789`.
  static String id(String provider, Object externalId, {String? objectType}) {
    final types = kinds[provider];
    return objectType == null ||
            types != null && types.length == 1 && types.single == objectType
        ? '$_prefix$provider:$externalId'
        : '$_prefix$provider:$objectType:$externalId';
  }

  static bool isFound(UiWork work) => isFoundId(work.workId);
  static bool isFoundId(String workId) => workId.startsWith(_prefix);

  /// The provider object [workId] names; null when it is not one NipaPlay
  /// reads.
  static FoundRef? ref(String workId) {
    if (!isFoundId(workId)) return null;
    final parts = workId.substring(_prefix.length).split(':');
    final types = kinds[parts.first];
    if (types == null || parts.length < 2) return null;
    if (types.length == 1) {
      return (
        provider: parts.first,
        objectType: types.single,
        externalId: parts.skip(1).join(':'),
      );
    }
    if (parts.length < 3 || !types.contains(parts[1])) return null;
    return (
      provider: parts.first,
      objectType: parts[1],
      externalId: parts.skip(2).join(':'),
    );
  }

  /// “弹弹play 作品 123”, “TMDB tv 789”, for the agent.
  static String describe(UiWork work) {
    final rest = work.workId.substring(_prefix.length);
    final found = ref(work.workId);
    final provider = found?.provider ?? rest.split(':').first;
    final external = found?.externalId ?? rest.substring(provider.length + 1);
    final kind = found != null && kinds[found.provider]!.length > 1
        ? found.objectType
        : '作品';
    return '${source(provider)} $kind $external';
  }

  /// A provider as people call it.
  static String source(String provider) => switch (provider) {
        'dandanplay' => '弹弹play',
        'bangumi' => 'Bangumi',
        'tmdb' => 'TMDB',
        _ => provider,
      };

  /// A found work as a provider record (`media.metadata.get`) describes it.
  static UiWork fromRecord(String workId, Map record, {UiArtwork? artwork}) {
    final provider = ref(workId)?.provider;
    final rating = _rating(record['rating']);
    return UiWork(
      workId: workId,
      title: _text(record['title']) ?? '',
      originalTitle: _text(record['originalTitle']),
      year: (record['year'] as num?)?.toInt(),
      episodeCount: episodeCount(record),
      // A TMDB movie is a film; the other objects say nothing of it.
      film: ref(workId)?.objectType == 'movie',
      overview: _text(record['overview']),
      details: {'sources': [{
        'provider': provider, 'objectType': ref(workId)?.objectType,
        'externalId': ref(workId)?.externalId,
        'fields': {...record, ...Map<String, Object?>.from(record['details'] as Map? ?? const {})},
      }]},
      ratings: [
        if (rating != null) UiRating(source(provider ?? ''), rating),
      ],
      artwork: artwork ?? UiArtwork(poster: _text(record['imageUrl'])),
    );
  }

  /// [work] as known so far, with what its provider record adds.
  static UiWork withRecord(UiWork work, Map record) {
    final more = fromRecord(work.workId, record);
    return UiWork(
      workId: work.workId,
      title: work.title.isEmpty ? more.title : work.title,
      originalTitle: more.originalTitle ?? work.originalTitle,
      year: more.year ?? work.year,
      genres: work.genres,
      episodeCount: more.episodeCount ?? work.episodeCount,
      film: work.film || more.film,
      runtime: work.runtime,
      overview: more.overview ?? work.overview,
      details: more.details,
      ratings: work.ratings.isEmpty ? more.ratings : work.ratings,
      artwork: UiArtwork(
        backdrop: work.artwork.backdrop,
        poster: work.artwork.poster ?? more.artwork.poster,
        logo: work.artwork.logo,
        tint: work.artwork.tint,
      ),
    );
  }

  /// The record's episode count, or its regular episodes when it lists
  /// them; a TMDB series lists seasons, which are not counted.
  static int? episodeCount(Map record) {
    if ((record['episodeCount'] as num?)?.toInt() case final n? when n > 0) {
      return n;
    }
    final episodes = record['episodes'];
    if (episodes is! List) return null;
    final regular = episodes
        .whereType<Map>()
        .where((e) =>
            e['kind'] == 'episode' &&
            (e['episodeType'] ?? 'regular') == 'regular')
        .length;
    return regular == 0 ? null : regular;
  }

  static double? _rating(Object? rating) {
    if (rating is! Map) return null;
    final value = rating['value'], max = rating['max'];
    if (value is! num || max is! num || max <= 0 || value <= 0) return null;
    return value * 10 / max;
  }

  static String? _text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;
}
