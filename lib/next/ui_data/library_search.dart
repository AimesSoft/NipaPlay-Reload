import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import '../media/metadata_provider.dart';

/// Rebuilt with X48's disposable projection, never on a search keystroke.
final class LibrarySearchIndex {
  final _documents = <int, _Document>{};
  final _ids = <String, int>{};
  int _serial = 0;
  final _postings = <String, Set<int>>{};
  final _identities = <String, String>{};
  bool ready = false;

  void replace(List<JsonMap> rows) {
    _identities.clear();
    final retained = <String>{};
    var order = 0;
    rows = rows.toList()
      ..sort((a, b) {
        final added = (b['added'] as int).compareTo(a['added'] as int);
        return added != 0
            ? added
            : (a['id'] as String).compareTo(b['id'] as String);
      });
    for (final row in rows) {
      final work = row['payload'] as JsonMap, facts = row['facts'] as JsonMap;
      final titles = <String>{
        work['title'] as String,
        if (work['originalTitle'] case final String title) title,
        ...(facts['searchTitles'] as List? ?? []).cast<String>(),
      };
      final episodes = (facts['searchEpisodes'] as List? ?? []).cast<JsonMap>();
      final summary = <String, Object?>{
        ...work,
        'aliases': titles
            .where((t) => t != work['title'] && t != work['originalTitle'])
            .toList(),
        'playable':
            episodes.any((e) => (e['episode'] as Map)['playable'] == true),
      };
      final workKey = 'work:${work['workId']}';
      retained.add(workKey);
      _add(workKey, order++, summary, null, [
        ...titles,
        if (work['year'] != null) '${work['year']}',
        ...(facts['searchYears'] as List? ?? []).map((y) => '$y'),
      ]);
      for (final item in episodes) {
        final episode = item['episode'] as JsonMap;
        final key = 'episode:${episode['episodeId']}';
        retained.add(key);
        _add(key, order++, summary, episode, [
          if (episode['title'] case final String title) title,
          ...(item['titles'] as List? ?? []).cast<String>(),
        ]);
      }
      for (final key in (facts['identityKeys'] as List? ?? []).cast<String>()) {
        _identities[key] = work['workId'] as String;
      }
    }
    for (final key in _ids.keys.where((k) => !retained.contains(k)).toList()) {
      final id = _ids.remove(key)!;
      _removeTokens(id, _documents.remove(id)!.fields);
    }
    ready = true;
  }

  String? workId(ExternalRef ref) => _identities[jsonEncode([
        ref.provider,
        ref.objectType == 'anime' ? 'work' : ref.objectType,
        ref.scope,
        ref.externalId
      ])];

  void _add(String key, int order, JsonMap work, JsonMap? episode,
      List<String> fields) {
    final normalized =
        fields.map(_normalize).where((s) => s.isNotEmpty).toSet().toList();
    final id = _ids.putIfAbsent(key, () => _serial++), old = _documents[id];
    _documents[id] = _Document(order, work, episode, normalized);
    if (old != null &&
        old.fields.length == normalized.length &&
        Iterable<int>.generate(normalized.length)
            .every((i) => old.fields[i] == normalized[i])) return;
    if (old != null) _removeTokens(id, old.fields);
    for (final token in _tokens(normalized)) {
      (_postings[token] ??= {}).add(id);
    }
  }

  void _removeTokens(int id, List<String> fields) {
    for (final token in _tokens(fields).toSet()) {
      final posting = _postings[token]!;
      posting.remove(id);
      if (posting.isEmpty) _postings.remove(token);
    }
  }

  Iterable<String> _tokens(List<String> fields) sync* {
    for (final field in fields) {
      final chars = field.runes.toList();
      for (var n = 1; n <= 3; n++) {
        for (var i = 0; i + n <= chars.length; i++) {
          yield String.fromCharCodes(chars.sublist(i, i + n));
        }
      }
    }
  }

  JsonMap search(String query, {int limit = 12, int? episodeLimit}) {
    final terms =
        _normalize(query).split(' ').where((s) => s.isNotEmpty).toList();
    if (terms.isEmpty) {
      throw const Failure(
          FailureCode.invalidInput, 'Search query must not be blank.');
    }
    final lists = <Set<int>>[];
    for (final term in terms) {
      final chars = term.runes.toList(), n = term.runes.length.clamp(1, 3);
      for (var i = 0; i + n <= chars.length; i++) {
        final posting =
            _postings[String.fromCharCodes(chars.sublist(i, i + n))];
        if (posting == null) return _result([], [], 0, 0);
        lists.add(posting);
      }
    }
    lists.sort((a, b) => a.length.compareTo(b.length));
    final matched = lists.first
        .where((id) =>
            lists.skip(1).every((p) => p.contains(id)) &&
            terms
                .every((t) => _documents[id]!.fields.any((f) => f.contains(t))))
        .toList();
    final normalized = _normalize(query);
    int rank(int id) {
      final fields = _documents[id]!.fields;
      return fields.contains(normalized)
          ? 0
          : fields.any((f) => f.startsWith(normalized))
              ? 1
              : 2;
    }

    matched.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : _documents[a]!.order.compareTo(_documents[b]!.order);
    });
    final works = <JsonMap>[], episodes = <JsonMap>[];
    var workTotal = 0, episodeTotal = 0;
    for (final id in matched) {
      final d = _documents[id]!;
      if (d.episode == null) {
        workTotal++;
        if (works.length < limit) works.add(d.work);
      } else {
        episodeTotal++;
        if (episodes.length < (episodeLimit ?? limit)) {
          episodes.add({'work': d.work, 'episode': d.episode});
        }
      }
    }
    return _result(works, episodes, workTotal, episodeTotal);
  }

  JsonMap _result(List<JsonMap> works, List<JsonMap> episodes, int workTotal,
          int episodeTotal) =>
      {
        'works': works,
        'episodes': episodes,
        'workTotal': workTotal,
        'episodeTotal': episodeTotal,
      };
}

final _spaces = RegExp(r'\s+');
String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(_spaces, ' ');

final class _Document {
  const _Document(this.order, this.work, this.episode, this.fields);
  final int order;
  final JsonMap work;
  final JsonMap? episode;
  final List<String> fields;
}

/// Only title facts and declared aliases, never descriptions or guessed identities.
List<String> librarySearchTitles(Map fields) => [
      for (final key in ['title', 'originalTitle'])
        if (fields[key] case final String text) text,
      for (final key in ['aliases', 'alternativeTitles'])
        if (fields[key] case final List values)
          for (final value in values)
            if (value is String) value,
    ];
