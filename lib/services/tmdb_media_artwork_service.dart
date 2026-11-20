import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/tmdb_artwork.dart';
import 'package:nipaplay/models/tmdb_episode_stills.dart';
import 'package:nipaplay/models/tmdb_logo_brightness.dart';
import 'package:nipaplay/services/tmdb_logo_inspector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Port of Erika's anime/core/metadata.rs Evidence::of + resolve_source,
/// catalog/resolve.rs search_work and catalog/client.rs images/with_artwork.
/// This is artwork enrichment only: Dandanplay remains the page's metadata source.
class TmdbMediaArtworkService {
  TmdbMediaArtworkService(
      {http.Client? client,
      Uri? gateway,
      Future<BangumiAnime> Function(int)? loadDetails,
      Future<String> Function()? bangumiServer,
      Uri Function(Uri)? requestUri,
      Future<TmdbLogoBrightness?> Function(String)? logoBrightness})
      : _client = client ?? http.Client(),
        _gateway =
            gateway ?? Uri.parse('http://43.142.85.190/erika/metadata/v1/'),
        _loadDetails = loadDetails,
        _bangumiServer = bangumiServer,
        _requestUri = requestUri,
        _logoBrightness = logoBrightness ?? inspectCachedTmdbLogo;

  final http.Client _client;
  final Uri _gateway;
  final Future<BangumiAnime> Function(int)? _loadDetails;
  final Future<String> Function()? _bangumiServer;
  final Uri Function(Uri)? _requestUri;
  final Future<TmdbLogoBrightness?> Function(String) _logoBrightness;
  static const _logoSelectionVersion = 2;
  Map<String, TmdbLogoBrightness>? _logoScores;
  final Map<String, Future<TmdbLogoBrightness?>> _logoInspections = {};
  final Map<String, Future<TmdbMediaArtwork?>> _pending = {};
  final Map<String, TmdbMediaArtwork?> _memory = {};
  final Set<String> _uncertainSelections = {};
  final Map<String, Map<String, dynamic>> _works = {};
  TmdbImageConfiguration? _configuration;
  Future<TmdbImageConfiguration?>? _configurationRequest;
  final Map<String, Future<Map<String, dynamic>>> _seasonRequests = {};

  /// One metadata request per matched season, never one request per episode.
  /// Returned keys are Dandanplay IDs; playback and history keep their identity.
  Future<Map<int, String>> resolveEpisodeStills(
      BangumiAnime anime, TmdbReference reference) async {
    if (reference.kind != 'tv' || anime.episodeList?.isNotEmpty != true) {
      return const {};
    }
    String? requestKey;
    try {
      final work = await _work(reference);
      final season = selectTmdbStillSeason(anime,
          (work['seasons'] as List).whereType<Map<String, dynamic>>().toList());
      if (season == null) return const {};
      final number = season['season_number'] as int;
      final path = 'tmdb/${reference.key}/seasons/$number';
      requestKey = path;
      final body = await _seasonRequests.putIfAbsent(path, () async {
        final prefs = await SharedPreferences.getInstance();
        final key =
            'media_detail_tmdb_episode_stills_v1_${reference.id}_$number';
        Map<String, dynamic>? previous;
        try {
          final saved = jsonDecode(prefs.getString(key) ?? 'null');
          if (saved is Map<String, dynamic> &&
              saved['data'] is Map<String, dynamic>) {
            final data = saved['data'] as Map<String, dynamic>;
            if (data['id'] == season['id'] && data['season_number'] == number) {
              previous = data;
              final age = DateTime.now().millisecondsSinceEpoch -
                  (saved['fetchedAt'] as int);
              if (age >= 0 && age < const Duration(days: 1).inMilliseconds) {
                return data;
              }
            }
          }
        } catch (_) {/* Ignore obsolete or corrupt caches. */}
        try {
          final data = await _get(path, {'language': 'zh-CN'});
          if (data['id'] != season['id'] ||
              data['season_number'] != number ||
              data['episodes'] is! List) {
            throw const FormatException('TMDB season identity mismatch');
          }
          await prefs.setString(
              key,
              jsonEncode({
                'fetchedAt': DateTime.now().millisecondsSinceEpoch,
                'data': data
              }));
          return data;
        } catch (_) {
          if (previous != null) return previous;
          rethrow;
        }
      });
      final rows = (body['episodes'] as List)
          .whereType<Map<String, dynamic>>()
          .where((r) =>
              r['show_id'] == reference.id && r['season_number'] == number)
          .toList();
      final prefs = await SharedPreferences.getInstance();
      final configuration = await _imageConfiguration(prefs);
      return matchTmdbEpisodeStills(anime, rows, (path) {
        if (!validTmdbImagePath(path)) return null;
        return configuration?.url(
                TmdbImageAsset(kind: 'still', path: path), 520) ??
            'https://image.tmdb.org/t/p/w300$path';
      });
    } catch (_) {
      return const {}; // Missing artwork must never prevent browsing/playback.
    } finally {
      if (requestKey != null) _seasonRequests.remove(requestKey);
      _works.remove(reference.key);
    }
  }

  String _signature(BangumiAnime anime) => jsonEncode([
        anime.id,
        anime.nameCn,
        anime.name,
        anime.titles,
        anime.airDate,
        anime.sourceAirDates,
        anime.onlineDatabases,
        anime.dandanplayType
      ]);

  Future<TmdbMediaArtwork?> resolve(BangumiAnime anime) {
    final signature = _signature(anime);
    if (_memory.containsKey(signature)) return Future.value(_memory[signature]);
    return _pending.putIfAbsent(signature, () async {
      try {
        final result = await _resolve(anime, signature);
        // Failed lookups can be retried on the next page open.
        if (result != null && !_uncertainSelections.contains(signature)) {
          _memory[signature] = result;
        }
        if (_memory.length > 100) _memory.remove(_memory.keys.first);
        return result;
      } finally {
        _pending.remove(signature);
        _uncertainSelections.remove(signature);
      }
    });
  }

  Future<TmdbMediaArtwork?> _resolve(
      BangumiAnime anime, String signature) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'media_detail_tmdb_artwork_v1_${anime.id}';
    TmdbMediaArtwork? previous;
    try {
      final saved = jsonDecode(prefs.getString(key) ?? 'null');
      if (saved is Map<String, dynamic> &&
          (saved['signature'] == signature ||
              saved['sourceSignature'] == signature)) {
        previous =
            TmdbMediaArtwork.fromJson(saved['artwork'] as Map<String, dynamic>);
        if (saved['logoSelectionVersion'] != _logoSelectionVersion) {
          _uncertainSelections.add(signature);
        }
        final time = saved['fetchedAt'] as int;
        final age = DateTime.now().millisecondsSinceEpoch - time;
        if (age >= 0 &&
            age < const Duration(days: 1).inMilliseconds &&
            saved['logoSelectionVersion'] == _logoSelectionVersion) {
          return previous;
        }
      }
    } catch (_) {/* Invalid/older cache is not identity evidence. */}

    try {
      if (anime.onlineDatabases == null &&
          anime.id > 0 &&
          _loadDetails != null) {
        final fresh = await _loadDetails(anime.id);
        if (fresh.id != anime.id) {
          throw const FormatException('Dandanplay identity mismatch');
        }
        anime = fresh;
      }
      final refs = <String, TmdbReference>{};
      for (final link in anime.onlineDatabases ?? <Map<String, String>>[]) {
        final ref = TmdbReference.fromUrl(link['url'] ?? '');
        if (ref != null) refs[ref.key] = ref;
      }
      // Conflicting provider links must never become a best-guess image.
      if (refs.length > 1) return previous;
      final titles = <String>[
        anime.nameCn,
        anime.name,
        ...?anime.titles?.map((t) => t['title'] ?? '')
      ];
      final dates = <String>[
        ...?anime.sourceAirDates,
        ...?anime.episodeList?.map((e) => e.airDate).whereType<String>()
      ];
      // airDate is the model's retained premiere date, not a guessed calendar year.
      if (anime.airDate != null) dates.add(anime.airDate!);
      if (refs.isEmpty || dates.every((d) => _year(d) == null)) {
        final subject = _bangumiSubject(anime);
        if (subject != null) {
          try {
            final base = Uri.parse(await (_bangumiServer?.call() ??
                Future.value('https://api.bgm.tv')));
            final body = await _request(base.replace(
                path: '${base.path}/v0/subjects/$subject'.replaceAll('//', '/'),
                query: null));
            // Erika's Bangumi adapter yields Chinese then original; inserting at
            // index 1 each time puts the original title before aliases.
            for (final title
                in [body['name_cn'], body['name']].whereType<String>()) {
              titles.insert(1, title);
            }
            if (body['date'] is String) dates.add(body['date'] as String);
          } catch (_) {/* Dandanplay evidence survives a Bangumi failure. */}
        }
      }
      final names = titles
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      final years = dates.map(_year).whereType<int>().toList()..sort();
      final reference = refs.isNotEmpty
          ? refs.values.single
          : years.isEmpty
              ? null
              : await _search(
                  names, years.first, _sourceKind(anime.dandanplayType));
      if (reference == null) return previous;
      final work = await _work(reference);
      final original = work['original_language'] as String? ?? '';
      final preferred = tmdbImageLanguages('zh-CN', original);
      List<TmdbImageAsset> assets = [];
      var imagesComplete = false;
      try {
        final path = 'tmdb/${reference.key}/images';
        assets = TmdbImageAsset.parse(
            reference,
            await _get(path, {
              'language': 'zh-CN',
              'include_image_language': preferred.join(',')
            }));
        // Retry unfiltered only when the entire parsed image response is empty,
        // exactly as catalog/client.rs::images (not just when a logo is absent).
        if (assets.isEmpty) {
          assets = TmdbImageAsset.parse(reference, await _get(path));
        }
        imagesComplete = true;
      } catch (_) {/* Work.backdrop_path is still valid same-work artwork. */}
      final configuration = await _imageConfiguration(prefs);
      String? url(TmdbImageAsset? asset, int width) {
        if (asset == null) return null;
        try {
          return configuration?.url(asset, width) ??
              'https://image.tmdb.org/t/p/original${asset.path}';
        } on FormatException {
          return null;
        }
      }

      final rootPath = work['backdrop_path'] as String? ?? '';
      final backdrop = chooseTmdbImage(assets, 'backdrop', preferred, 1920) ??
          (validTmdbImagePath(rootPath)
              ? TmdbImageAsset(kind: 'backdrop', path: rootPath)
              : null);
      final logoChoice = await _chooseReadableLogo(
          assets,
          tmdbImageLanguages('zh-CN', original, logo: true),
          (asset) => url(asset, 1000),
          prefs);
      final logo = logoChoice.asset;
      final logoVerified = imagesComplete && logoChoice.verified;
      if (logoVerified) {
        _uncertainSelections.remove(signature);
      } else {
        _uncertainSelections.add(signature);
      }
      final sameWork =
          previous?.reference.key == reference.key ? previous : null;
      final result = TmdbMediaArtwork(
          reference: reference,
          backdropUrl: url(backdrop, 1920) ?? sameWork?.backdropUrl,
          // Selection target is 640, the displayed rendition target is 1000,
          // matching catalog/client.rs and anime/core/content.rs respectively.
          logoUrl: url(logo, 1000) ?? sameWork?.logoUrl);
      if (result.backdropUrl != null || result.logoUrl != null) {
        await prefs.setString(
            key,
            jsonEncode({
              'signature': signature,
              'sourceSignature': _signature(anime),
              'fetchedAt': DateTime.now().millisecondsSinceEpoch,
              'logoSelectionVersion': logoVerified ? _logoSelectionVersion : 0,
              'artwork': result.toJson()
            }));
      }
      return result;
    } catch (_) {
      return previous; // A transient refresh failure must not erase artwork.
    } finally {
      _works.clear();
    }
  }

  Future<({TmdbImageAsset? asset, bool verified})> _chooseReadableLogo(
      List<TmdbImageAsset> assets,
      List<String> languages,
      String? Function(TmdbImageAsset) url,
      SharedPreferences prefs) async {
    final ranked = rankTmdbImages(assets, 'logo', languages, 640);
    if (ranked.isEmpty) return (asset: null, verified: true);
    _logoScores ??= _readLogoScores(prefs);
    var fallback = ranked.first;
    var bestLuminance = -1.0;
    var complete = true;
    var newInspections = 0;
    // A corrupt/huge response must not trigger thousands of image downloads.
    // Stop at the first bright candidate, preserving the existing ordering
    // between readable original-language, localized, color and white assets.
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    for (final asset in ranked) {
      final imageUrl = url(asset);
      if (imageUrl == null) {
        complete = false;
        continue;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        complete = false;
        break;
      }
      TmdbLogoBrightness? score = _logoScores![imageUrl];
      if (score == null) {
        if (newInspections >= 12) {
          complete = false;
          break;
        }
        newInspections++;
        try {
          final task = _logoInspections.putIfAbsent(
              imageUrl, () => _logoBrightness(imageUrl));
          score = await task.timeout(remaining < const Duration(seconds: 4)
              ? remaining
              : const Duration(seconds: 4));
          if (score != null) {
            _logoScores![imageUrl] = score;
            while (_logoScores!.length > 256) {
              _logoScores!.remove(_logoScores!.keys.first);
            }
            await prefs.setString(
                'media_detail_tmdb_logo_brightness_v1',
                jsonEncode(_logoScores!
                    .map((key, value) => MapEntry(key, value.toJson()))));
          }
        } catch (_) {
          // Unsupported/corrupt/unreachable images retain the normal fallback.
        } finally {
          _logoInspections.remove(imageUrl);
        }
      }
      if (score == null) {
        complete = false;
        continue;
      }
      if (score.isBright) return (asset: asset, verified: true);
      if (score.luminance > bestLuminance) {
        bestLuminance = score.luminance;
        fallback = asset;
      }
    }
    return (asset: fallback, verified: complete);
  }

  Map<String, TmdbLogoBrightness> _readLogoScores(SharedPreferences prefs) {
    try {
      final saved = jsonDecode(
          prefs.getString('media_detail_tmdb_logo_brightness_v1') ?? '{}');
      if (saved is Map<String, dynamic>) {
        return {
          for (final entry in saved.entries.take(256))
            if (TmdbLogoBrightness.fromJson(entry.value) case final score?)
              entry.key: score
        };
      }
    } catch (_) {/* Ignore an invalid analysis cache. */}
    return {};
  }

  Future<Map<String, dynamic>> _request(Uri uri) async {
    final response = await _client.get(_requestUri?.call(uri) ?? uri, headers: {
      'Accept': 'application/json'
    }).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException('Metadata HTTP ${response.statusCode}', uri);
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Invalid metadata response');
    }
    return body;
  }

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? query]) async {
    final body =
        await _request(_gateway.resolve(path).replace(queryParameters: query));
    if (body['schema_version'] != 1 || body['data'] is! Map<String, dynamic>) {
      throw const FormatException('Incompatible metadata gateway response');
    }
    return body['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _work(TmdbReference reference) async {
    final cached = _works[reference.key];
    if (cached != null) return cached;
    final work = await _get('tmdb/${reference.key}', {'language': 'zh-CN'});
    if (work['id'] != reference.id) {
      throw const FormatException('TMDB work identity mismatch');
    }
    if (reference.kind == 'tv' && work['seasons'] is! List) {
      throw const FormatException('Missing TMDB seasons');
    }
    _works[reference.key] = work;
    return work;
  }

  Future<TmdbImageConfiguration?> _imageConfiguration(
          SharedPreferences prefs) =>
      _configurationRequest ??= _loadImageConfiguration(prefs);

  Future<TmdbImageConfiguration?> _loadImageConfiguration(
      SharedPreferences prefs) async {
    if (_configuration != null) return _configuration;
    const key = 'media_detail_tmdb_images_v1';
    try {
      final saved = jsonDecode(prefs.getString(key) ?? 'null');
      if (saved is Map<String, dynamic>) {
        _configuration = TmdbImageConfiguration.parse(saved);
        final age =
            DateTime.now().millisecondsSinceEpoch - (saved['fetchedAt'] as int);
        if (age >= 0 && age < const Duration(days: 1).inMilliseconds) {
          return _configuration;
        }
      }
    } catch (_) {/* Fetch a new configuration. */}
    try {
      final body = await _get('tmdb/images/configuration');
      _configuration = TmdbImageConfiguration.parse(body);
      await prefs.setString(
          key,
          jsonEncode(
              {...body, 'fetchedAt': DateTime.now().millisecondsSinceEpoch}));
    } catch (_) {/* Use retained configuration or original rendition. */}
    return _configuration;
  }

  // catalog/resolve.rs: all queries must succeed and be complete before a
  // unique exact-title+year match (or verified continuing season) is accepted.
  Future<TmdbReference?> _search(
      List<String> titles, int year, String? kind) async {
    final bases = {
      for (final title in titles)
        if (_sequelBase(title) != null) title: _sequelBase(title)!
    };
    final queries = titles.map((t) => bases[t] ?? t).toSet().take(4);
    final candidates = <String, _Candidate>{};
    var complete = true;
    for (final query in queries) {
      for (final kind in kind == null ? ['tv', 'movie'] : [kind]) {
        try {
          final page = await _get('search', {
            'kind': kind,
            'query': query,
            'language': 'zh-CN',
            'page': '1',
            'year': '$year'
          });
          if (page['page'] != 1 ||
              page['total_pages'] is! int ||
              page['total_pages'] > 1 ||
              page['results'] is! List) {
            complete = false;
          }
          final rows = page['results'];
          if (rows is! List || rows.length > 10000) {
            throw const FormatException('Invalid TMDB search');
          }
          for (final row in rows.whereType<Map<String, dynamic>>()) {
            final id = row['id'];
            if (id is! int || id <= 0) {
              throw const FormatException('Missing TMDB search identity');
            }
            final ref = TmdbReference(kind, id);
            candidates.putIfAbsent(ref.key, () => _Candidate(ref, row));
          }
        } catch (_) {
          complete = false;
        }
      }
    }
    if (!complete) return null;
    TmdbReference? exact(List<String> names) {
      final found = candidates.values
          .where((c) => c.date.startsWith('$year-') && c.named(names))
          .toList();
      return found.length == 1 ? found.single.reference : null;
    }

    final direct =
        exact(titles) ?? (bases.isEmpty ? null : exact(bases.values.toList()));
    if (direct != null) return direct;
    for (final names in [titles, bases.values.toList()]) {
      final earlier = candidates.values
          .where((c) => c.reference.kind == 'tv' && c.named(names))
          .where((c) =>
              (int.tryParse(c.date.length >= 4 ? c.date.substring(0, 4) : '') ??
                  0) <
              year)
          .take(4);
      final found = <TmdbReference>[];
      for (final candidate in earlier) {
        final work = await _work(candidate.reference);
        final seasons = (work['seasons'] as List).whereType<Map>();
        final activeDates = [
          work['last_air_date'],
          if (work['last_episode_to_air'] is Map)
            work['last_episode_to_air']['air_date'],
          if (work['next_episode_to_air'] is Map)
            work['next_episode_to_air']['air_date'],
        ].whereType<String>();
        if (seasons.any((s) =>
                s['season_number'] is int &&
                s['season_number'] > 0 &&
                (s['air_date']?.toString() ?? '').startsWith('$year-')) ||
            activeDates.any((d) => d.startsWith('$year-'))) {
          found.add(candidate.reference);
        }
      }
      if (found.length == 1) return found.single;
      if (found.length > 1) return null;
    }
    return null;
  }
}

class _Candidate {
  _Candidate(this.reference, this.body);
  final TmdbReference reference;
  final Map<String, dynamic> body;
  String get date =>
      body[reference.kind == 'movie' ? 'release_date' : 'first_air_date']
          as String? ??
      '';
  bool named(List<String> names) => names.any((name) {
        final normalized = _normal(name);
        return normalized.isNotEmpty &&
            (normalized ==
                    _normal((body['name'] ?? body['title']) as String? ?? '') ||
                normalized ==
                    _normal((body['original_name'] ?? body['original_title'])
                            as String? ??
                        ''));
      });
}

String _normal(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
String? _sourceKind(String? type) => switch (type) {
      'movie' || 'jpmovie' => 'movie',
      'tvseries' || 'web' || 'tvspecial' || 'jpdrama' => 'tv',
      _ => null,
    };
int? _year(String text) {
  final date = text.trim();
  if (date.length < 10 ||
      !RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}').hasMatch(date)) {
    return null;
  }
  final year = int.parse(date.substring(0, 4));
  final month = int.parse(date.substring(5, 7));
  final day = int.parse(date.substring(8, 10));
  final parsed = DateTime.utc(year, month, day);
  return year > 0 &&
          parsed.year == year &&
          parsed.month == month &&
          parsed.day == day
      ? year
      : null;
}

String? _bangumiSubject(BangumiAnime anime) {
  final ids = <String>{};
  for (final value in [
    anime.bangumiUrl,
    ...?anime.onlineDatabases?.map((r) => r['url'])
  ].whereType<String>()) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        ![
          'bgm.tv',
          'bangumi.tv',
          'chii.in',
          'www.bgm.tv',
          'www.bangumi.tv',
          'www.chii.in'
        ].contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      continue;
    }
    final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (parts.length == 2 &&
        parts[0] == 'subject' &&
        (int.tryParse(parts[1]) ?? 0) > 0) {
      ids.add(parts[1]);
    }
  }
  return ids.length == 1 ? ids.single : null;
}

// Exact sequel suffix alternatives and the three-pass stripping rule from
// erika-catalog/src/names.rs::SEQUEL_SUFFIX/sequel_base.
final _sequelSuffix = RegExp(
    r'(?:\s*第\s*([0-9０-９一二三四五六七八九十]{1,3})\s*(?:[季期]|部分?)'
    r'|\s*([0-9０-９]{1,2})\s*期|\s*\b(?:Season|S)\s*([0-9]{1,2})'
    r'|\s*([0-9]{1,2})(?:st|nd|rd|th)\s*(?:Season|シーズン)|\s*第\s*[0-9]{1,2}\s*クール'
    r'|\s*(?:最终|完结|最終|完結)季|\s*\bFinal\s*Season|\s*\bPart\.?\s*[0-9]{1,2}'
    r'|\s*[(（](?:19|20)[0-9]{2}[)）]|\s*(?:续篇|續篇|续集|續集|新作动画|新作動畫|新作アニメ)'
    r'|\s*[～~〜][^～~〜]+[～~〜])\s*$',
    caseSensitive: false);
String? _sequelBase(String title) {
  var base = title.trim();
  for (var i = 0; i < 3; i++) {
    final match = _sequelSuffix.firstMatch(base);
    if (match == null) break;
    base =
        base.substring(0, match.start).replaceFirst(RegExp(r'[ 　\-:：·]+$'), '');
  }
  return base.isNotEmpty && base != title.trim() ? base : null;
}
