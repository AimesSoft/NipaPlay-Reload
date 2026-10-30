import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/credential_vault.dart';
export 'package:nipaplay/security/credential_vault.dart';

/// Built-in names remain stable; new authorities use an origin, not a nickname.
String canonicalMetadataNamespace(String input) {
  final name = input.trim().toLowerCase();
  if (const {'tmdb', 'bangumi', 'dandanplay'}.contains(name)) return name;
  final uri = Uri.tryParse(name);
  if (uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      !uri.host.contains(RegExp(r'[\s%]')) &&
      uri.userInfo.isEmpty &&
      (uri.path.isEmpty || uri.path == '/') &&
      !uri.hasQuery &&
      !uri.hasFragment) {
    return Uri(
            scheme: 'https',
            host: uri.host.endsWith('.')
                ? uri.host.substring(0, uri.host.length - 1)
                : uri.host,
            port: uri.hasPort && uri.port != 443 ? uri.port : null)
        .toString();
  }
  throw const Failure(FailureCode.invalidInput,
      'New metadata namespaces must be HTTPS origins, e.g. https://movie.douban.com; reuse the returned canonical provider. Built-in names: tmdb, bangumi, dandanplay.');
}

ExternalRef canonicalExternalRef(JsonMap json) {
  final ref = ExternalRef.fromJson(json);
  if (ref.objectType.trim().isEmpty || ref.externalId.trim().isEmpty) {
    throw const Failure(FailureCode.invalidInput,
        'External object type and ID must not be blank.');
  }
  return ExternalRef(
      canonicalMetadataNamespace(ref.provider), ref.objectType, ref.externalId,
      scope: ref.scope);
}

final class ExternalRef implements JsonEncodable {
  const ExternalRef(this.provider, this.objectType, this.externalId,
      {this.scope = ''});
  final String provider, objectType, externalId, scope;
  factory ExternalRef.fromJson(JsonMap json) => ExternalRef(
      json['provider'] as String,
      json['objectType'] as String,
      json['externalId'] as String,
      scope: json['scope'] as String);
  @override
  JsonMap toJson() => {
        'provider': provider,
        'objectType': objectType,
        'externalId': externalId,
        'scope': scope
      };
}

final class MetadataRecord implements JsonEncodable {
  const MetadataRecord(
      {required this.ref,
      required this.title,
      required this.kind,
      this.originalTitle,
      this.overview,
      this.imageUrl,
      this.year,
      this.number,
      this.season,
      this.episodeType = 'regular',
      this.order = 'aired',
      this.episodes = const [],
      this.language = 'zh-CN',
      this.rating,
      this.episodeCount,
      this.details = const {},
      this.acquisition = const {},
      required this.fetchedAt});
  final ExternalRef ref;
  final String title, kind, episodeType, order, language;
  final String? originalTitle, overview, imageUrl, number;
  final int? year, season;
  final List<MetadataRecord> episodes;
  final DateTime fetchedAt;

  /// A work's score as the provider reports it: {value, max, count?}.
  final JsonMap? rating;

  /// A work's episode count as the provider reports it.
  final int? episodeCount;

  /// Provider facts beyond the common identity/title fields, retained on disk.
  final JsonMap details;

  /// What was requested and returned for this object, separate from its fields.
  /// Absent in old records and manually imported snapshots: coverage is unknown.
  final JsonMap acquisition;
  factory MetadataRecord.fromJson(JsonMap json) => MetadataRecord(
          ref: ExternalRef.fromJson(
              Map<String, Object?>.from(json['ref'] as Map)),
          title: json['title'] as String,
          kind: json['kind'] as String,
          originalTitle: json['originalTitle'] as String?,
          overview: json['overview'] as String?,
          imageUrl: json['imageUrl'] as String?,
          year: json['year'] as int?,
          number: json['number'] as String?,
          season: json['season'] as int?,
          episodeType: json['episodeType'] as String,
          order: json['order'] as String,
          language: json['language'] as String,
          fetchedAt: DateTime.parse(json['fetchedAt'] as String),
          rating: json['rating'] is Map
              ? Map<String, Object?>.from(json['rating'] as Map)
              : null,
          episodeCount: (json['episodeCount'] as num?)?.toInt(),
          details:
              Map<String, Object?>.from(json['details'] as Map? ?? const {}),
          acquisition: Map<String, Object?>.from(
              json['acquisition'] as Map? ?? const {}),
          episodes: [
            for (final item in json['episodes'] as List)
              MetadataRecord.fromJson(Map<String, Object?>.from(item as Map))
          ]);
  @override
  JsonMap toJson() => {
        'ref': ref.toJson(),
        'title': title,
        'kind': kind,
        'originalTitle': originalTitle,
        'overview': overview,
        'imageUrl': imageUrl,
        'year': year,
        'number': number,
        'season': season,
        'episodeType': episodeType,
        'order': order,
        'language': language,
        'fetchedAt': fetchedAt.toUtc().toIso8601String(),
        if (details.isNotEmpty) 'details': details,
        if (acquisition.isNotEmpty) 'acquisition': acquisition,
        if (rating != null) 'rating': rating,
        if (episodeCount != null) 'episodeCount': episodeCount,
        'episodes': [for (final episode in episodes) episode.toJson()]
      };
}

abstract interface class MetadataProvider {
  String get id;
  Future<List<MetadataRecord>> search(String query,
      {String kind = 'tv', int? year});
  Future<MetadataRecord> get(ExternalRef ref, {String language = 'zh-CN'});
}

abstract interface class HashMetadataProvider implements MetadataProvider {
  Future<List<MetadataRecord>> matchHash(
      String filename, String hash, int size);
}

abstract interface class CredentialResolver {
  Future<String> resolve(CredentialRef ref);
}

final class ProviderRetry implements Exception {
  const ProviderRetry(this.provider, this.at, this.reason);
  final String provider, reason;
  final DateTime at;
}
