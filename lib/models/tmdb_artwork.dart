/// Dart port of Erika erika-catalog/src/{resolve,artwork}.rs.
/// Keep identity, language ranking and image rendition rules in sync.
class TmdbReference {
  const TmdbReference(this.kind, this.id);
  final String kind;
  final int id;
  String get key => '$kind/$id';

  static TmdbReference? fromUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        !['themoviedb.org', 'www.themoviedb.org'].contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        // url::Url normalizes explicit default ports away, as does Uri.port.
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (parts.length != 2 || !['tv', 'movie'].contains(parts[0])) return null;
    final id = int.tryParse(parts[1].split('-').first);
    return id != null && id > 0 ? TmdbReference(parts[0], id) : null;
  }
}

bool validTmdbImagePath(String path) =>
    path.length > 2 &&
    path.length <= 256 &&
    RegExp(r'^/[A-Za-z0-9._-]+$').hasMatch(path) &&
    !path.contains('..');

class TmdbImageAsset {
  const TmdbImageAsset(
      {required this.kind,
      required this.path,
      this.language,
      this.width = 0,
      this.height = 0,
      this.aspectRatio = 0,
      this.vote = 0,
      this.votes = 0});
  final String kind;
  final String path;
  final String? language;
  final int width;
  final int height;
  final double aspectRatio;
  final double vote;
  final int votes;

  static List<TmdbImageAsset> parse(
      TmdbReference owner, Map<String, dynamic> body) {
    if (body['id'] != owner.id) {
      throw const FormatException('TMDB artwork identity mismatch');
    }
    final result = <TmdbImageAsset>[];
    for (final kind in ['poster', 'backdrop', 'logo', 'still']) {
      final rows = body['${kind}s'];
      if (rows == null) continue;
      if (rows is! List || rows.length > 10000) {
        throw const FormatException('Invalid TMDB image list');
      }
      for (final row in rows.whereType<Map>()) {
        final path =
            row['file_path'] is String ? row['file_path'] as String : '';
        final aspect = (row['aspect_ratio'] as num?)?.toDouble() ?? 0;
        final vote = (row['vote_average'] as num?)?.toDouble() ?? 0;
        if (!validTmdbImagePath(path) ||
            !aspect.isFinite ||
            aspect < 0 ||
            !vote.isFinite) {
          continue;
        }
        int size(String key) {
          final value = row[key];
          return value is int && value >= 0 && value <= 0xffffffff ? value : 0;
        }

        final language = row['iso_639_1'] as String?;
        result.add(TmdbImageAsset(
            kind: kind,
            path: path,
            language: language?.isEmpty == true ? null : language,
            width: size('width'),
            height: size('height'),
            aspectRatio: aspect,
            vote: vote,
            votes: row['vote_count'] is int && row['vote_count'] >= 0
                ? row['vote_count'] as int
                : 0));
      }
    }
    return result;
  }
}

List<String> tmdbImageLanguages(String target, String original,
    {bool logo = false}) {
  final result = <String>[];
  for (final value in [
    ...(logo ? [original, target] : [target, original]),
    'en',
    'null'
  ]) {
    final tag = value.split(RegExp('[-_]')).first.toLowerCase();
    if ((tag == 'null' || RegExp(r'^[a-z]{2}$').hasMatch(tag)) &&
        !result.contains(tag)) {
      result.add(tag);
    }
  }
  return result;
}

TmdbImageAsset? chooseTmdbImage(List<TmdbImageAsset> assets, String kind,
    List<String> preferred, int targetWidth) {
  final ranked = rankTmdbImages(assets, kind, preferred, targetWidth);
  return ranked.isEmpty ? null : ranked.first;
}

List<TmdbImageAsset> rankTmdbImages(List<TmdbImageAsset> assets, String kind,
    List<String> preferred, int targetWidth) {
  int rank(TmdbImageAsset asset) {
    if (kind == 'backdrop' && asset.language == null) return 0;
    final index = preferred.indexOf(asset.language ?? 'null');
    return (index < 0 ? preferred.length : index) + 1;
  }

  final valid = assets.where((a) => a.kind == kind).toList();
  valid.sort((a, b) {
    var order = rank(a).compareTo(rank(b));
    if (order == 0) {
      order = (b.width >= targetWidth ? 1 : 0)
          .compareTo(a.width >= targetWidth ? 1 : 0);
    }
    if (order == 0) order = b.vote.compareTo(a.vote);
    if (order == 0) order = b.votes.compareTo(a.votes);
    if (order == 0) order = b.width.compareTo(a.width);
    return order == 0 ? a.path.compareTo(b.path) : order;
  });
  return valid;
}

class TmdbImageConfiguration {
  const TmdbImageConfiguration(this.sizes);
  final Map<String, List<String>> sizes;

  static TmdbImageConfiguration parse(Map<String, dynamic> body) {
    final data = body['images'] is Map ? body['images'] as Map : body;
    if (data['secure_base_url'] != 'https://image.tmdb.org/t/p/') {
      throw const FormatException('Unsupported TMDB image host');
    }
    final sizes = <String, List<String>>{};
    for (final kind in ['poster', 'backdrop', 'logo', 'still']) {
      final rows = data['${kind}_sizes'];
      if (rows is! List) {
        throw const FormatException('Missing TMDB image sizes');
      }
      sizes[kind] = rows.whereType<String>().where((value) {
        if (value == 'original') return true;
        if (!RegExp(r'^[wh][0-9]+$').hasMatch(value)) return false;
        final n = int.parse(value.substring(1));
        return n > 0 && n <= 16384;
      }).toList();
      if (sizes[kind]!.isEmpty) {
        throw const FormatException('Invalid TMDB image sizes');
      }
    }
    return TmdbImageConfiguration(sizes);
  }

  String url(TmdbImageAsset asset, int targetWidth) {
    final options = sizes[asset.kind]!;
    final widths = options.where((s) => s.startsWith('w')).toList()
      ..sort((a, b) =>
          int.parse(a.substring(1)).compareTo(int.parse(b.substring(1))));
    String? size;
    if (asset.path.endsWith('.svg')) {
      if (options.contains('original')) size = 'original';
    } else if (widths.isNotEmpty) {
      size = widths.firstWhere((s) => int.parse(s.substring(1)) >= targetWidth,
          orElse: () => widths.last);
    } else if (options.contains('original')) {
      size = 'original';
    }
    if (size == null) throw const FormatException('No usable TMDB rendition');
    return 'https://image.tmdb.org/t/p/$size${asset.path}';
  }
}

class TmdbMediaArtwork {
  const TmdbMediaArtwork(
      {required this.reference, this.backdropUrl, this.logoUrl});
  final TmdbReference reference;
  final String? backdropUrl;
  final String? logoUrl;

  Map<String, dynamic> toJson() => {
        'kind': reference.kind,
        'id': reference.id,
        'backdropUrl': backdropUrl,
        'logoUrl': logoUrl
      };
  static TmdbMediaArtwork fromJson(Map<String, dynamic> json) {
    if (!['tv', 'movie'].contains(json['kind']) ||
        json['id'] is! int ||
        (json['id'] as int) <= 0) {
      throw const FormatException('Invalid cached TMDB identity');
    }
    String? image(String key) {
      final value = json[key];
      if (value == null) return null;
      final uri = value is String ? Uri.tryParse(value) : null;
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'image.tmdb.org' ||
          !uri.path.startsWith('/t/p/')) {
        throw const FormatException('Invalid cached TMDB artwork');
      }
      return value as String;
    }

    return TmdbMediaArtwork(
        reference: TmdbReference(json['kind'] as String, json['id'] as int),
        backdropUrl: image('backdropUrl'),
        logoUrl: image('logoUrl'));
  }
}

/// Product fallback order; custom artwork always takes priority over providers.
List<String> mediaDetailBackdropCandidates(
        {String? custom, String? tmdb, String? bangumiLarge, String? poster}) =>
    [custom, tmdb, bangumiLarge, poster]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
