import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/credential_vault.dart';
export 'package:nipaplay/security/credential_vault.dart';

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
      required this.fetchedAt});
  final ExternalRef ref;
  final String title, kind, episodeType, order, language;
  final String? originalTitle, overview, imageUrl, number;
  final int? year, season;
  final List<MetadataRecord> episodes;
  final DateTime fetchedAt;
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
