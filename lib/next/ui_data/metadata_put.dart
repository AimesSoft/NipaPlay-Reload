import 'dart:async';
import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';

import '../events/signals.dart';
import '../media/identity_store.dart';
import 'metadata_facts.dart';
import 'service.dart';

/// One value as a set of override rows on one entity. Text fields travel
/// with their language row; the unit is written, or left alone, as a whole.
final class _Unit {
  _Unit(this.path, this.entityId, this.name, this.rows, {this.sourced = false});
  final String path, entityId, name;
  final List<(String, Object?)> rows;
  final bool sourced;
  bool changed = true;
}

final class _Target {
  _Target(this.index, this.entityId, this.season, this.number, this.created);
  final int index;
  final String entityId;
  final int? season;
  final String? number;
  final bool created;
  final units = <_Unit>[];

  /// An explicit write of the episode's season and number, when the item
  /// names the episode by episodeId and gives season or number.
  _Numbering? numbering;
}

final class _Numbering {
  _Numbering(this.beforeSeason, this.beforeNumber, this.afterSeason,
      this.afterNumber, this.changed);
  final int? beforeSeason, afterSeason;
  final String? beforeNumber, afterNumber;
  final bool changed;
}

bool _sameNumber(String? a, String? b) {
  if (a == null || b == null) return a == b;
  final x = num.tryParse(a), y = num.tryParse(b);
  return x != null && y != null ? x == y : a.trim() == b.trim();
}

extension UiMetadataPut on UiDataService {
  /// `media.metadata.put`: one work's data, in one atomic commit, on the
  /// existing override and artwork-override storage.
  Future<JsonMap> putMetadata(JsonMap input, Invocation invocation) =>
      media.mutate(() async {
        final store = media.store, db = store.database;
        final workId = input['workId'] as String;
        final key = stableMediaId(
            'media.metadata.put', [invocation.origin, input['requestId']]);
        final fingerprint = stableMediaId('input', input);
        final saved = await store.operation(key, fingerprint);
        if (saved != null) {
          return {
            ...saved,
            'replayed': true,
            'uiFacts': await metadataSummary(workId)
          };
        }

        final workRows = await db.query('media_entities',
            where: "id=? AND kind='work'", whereArgs: [workId]);
        if (workRows.isEmpty ||
            decodeMediaJson(workRows.single['attributes'])['removed'] == true) {
          throw const Failure(
              FailureCode.notFound, 'workId must identify a library work.');
        }
        final workTitle =
            decodeMediaJson(workRows.single['attributes'])['title'];
        final family = await store.metadataFamily(workId);

        final problems = <JsonMap>[];
        void problem(String path, String error, [FailureCode? code]) =>
            problems.add({'path': path, 'error': error, 'code': (code ?? FailureCode.invalidInput).wireName});

        final source = <String, Object?>{
          for (final e in (input['source'] as Map).entries)
            if (e.value != null) e.key as String: e.value
        };
        final language = input['language'] as String?;

        final prepared = <String, Future<JsonMap>>{};
        Future<JsonMap?> image(String path, Object? raw) async {
          final text = (raw as String).trim();
          if (text.startsWith('http://')) {
            problem(path, 'Image URLs must be HTTPS.');
            return null;
          }
          final remote = text.startsWith('https://');
          try {
            final value = await prepared.putIfAbsent(
                text,
                () => artwork.prepare(
                    url: remote ? text : null, file: remote ? null : text));
            return {...value, 'source': source};
          } on Failure catch (e) {
            problem(path, e.message, e.code);
          } on Object catch (e) {
            problem(path, 'Image could not be fetched or decoded: $e',
                FailureCode.unavailable);
          }
          return null;
        }

        // What each entity's own fields would become.
        Future<List<_Unit>> units(String path, String entityId, JsonMap data,
            {required Set<String> images}) async {
          final result = <_Unit>[];
          for (final field in ['title', 'originalTitle', 'overview']) {
            if (!data.containsKey(field)) continue;
            final text = (data[field] as String).trim();
            if (text.isEmpty) {
              problem('$path.$field', '$field must not be empty.');
              continue;
            }
            result.add(_Unit('$path.$field', entityId, field, [
              (field, text),
              if (field != 'originalTitle') ('${field}Language', language)
            ], sourced: true));
          }
          if (data['year'] != null) {
            result.add(_Unit('$path.year', entityId, 'year',
                [('year', data['year'])], sourced: true));
          }
          if (data['genres'] != null) {
            final genres = [
              for (final g in (data['genres'] as List)) (g as String).trim()
            ];
            if (genres.isEmpty || genres.any((g) => g.isEmpty)) {
              problem('$path.genres', 'genres must be non-empty names.');
            } else {
              result.add(_Unit('$path.genres', entityId, 'genres',
                  [('genres', genres)], sourced: true));
            }
          }
          if (data['airDate'] != null) {
            final date = data['airDate'] as String;
            if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
                DateTime.tryParse(date) == null) {
              problem('$path.airDate', 'airDate must be YYYY-MM-DD.');
            } else {
              result.add(_Unit('$path.airDate', entityId, 'airDate',
                  [('airDate', date)], sourced: true));
            }
          }
          if (data['runtime'] != null) {
            result.add(_Unit('$path.runtime', entityId, 'runtime',
                [('runtimeMs', (data['runtime'] as int) * 60000)],
                sourced: true));
          }
          for (final kind in images) {
            if (data[kind] == null) continue;
            final value = await image('$path.$kind', data[kind]);
            if (value != null) {
              result.add(_Unit('$path.$kind', entityId, kind,
                  [('artwork.$kind', value)]));
            }
          }
          return result;
        }

        final work = (input['work'] as Map?)?.cast<String, Object?>() ?? {};
        final workUnits = await units('work', workId, work,
            images: {'poster', 'backdrop', 'logo'});

        // Which episodes the items mean, and which do not exist yet.
        final catalogue = await db.rawQuery(
            "SELECT e.id,e.attributes,r.id AS release_id,r.attributes AS release_attributes "
            "FROM media_entities e JOIN media_entities r ON r.id=e.parent_id "
            "WHERE e.kind='episode' AND r.kind='release' AND r.parent_id=?",
            [workId]);
        final existing = <({String id, String? number, int? season, String releaseId})>[
          for (final row in catalogue)
            if (decodeMediaJson(row['attributes'])['removed'] != true &&
                decodeMediaJson(row['release_attributes'])['removed'] != true)
              (
                id: row['id'] as String,
                number: decodeMediaJson(row['attributes'])['number']?.toString(),
                season: decodeMediaJson(row['attributes'])['season'] as int? ??
                    decodeMediaJson(row['release_attributes'])['season'] as int?,
                releaseId: row['release_id'] as String
              )
        ];
        final releases = <({String id, int? season})>[
          for (final row in await db.query('media_entities',
              where: "kind='release' AND parent_id=?", whereArgs: [workId]))
            if (decodeMediaJson(row['attributes'])['removed'] != true)
              (
                id: row['id'] as String,
                season: decodeMediaJson(row['attributes'])['season'] as int?
              )
        ];
        final newReleases = <int?, String>{};
        final newReleaseRows = <JsonMap>[];
        final newEpisodeRows = <JsonMap>[];
        final targets = <_Target>[];
        final claimed = <String>{};
        final numberings = <String, _Numbering>{};
        final items = (input['episodes'] as List? ?? const []).cast<Map>();
        for (var i = 0; i < items.length; i++) {
          final item = items[i].cast<String, Object?>();
          final path = 'episodes[$i]';
          final season = item['season'] as int?;
          final number = (item['number'] as String?)?.trim();
          final id = item['episodeId'] as String?;
          if (id == null && (number == null || number.isEmpty)) {
            problem(path, 'Give episodeId, or number (with season when the episode has one).');
            continue;
          }
          String? episodeId;
          var created = false;
          if (id != null) {
            final match = existing.where((e) => e.id == id).toList();
            if (match.isEmpty) {
              problem(path, 'episodeId is not an episode of this work.',
                  FailureCode.notFound);
              continue;
            }
            if (item.containsKey('number') && (number == null || number.isEmpty)) {
              problem('$path.number', 'number must not be empty.');
              continue;
            }
            if (number != null || season != null) {
              final cur = match.single;
              final afterSeason = season ?? cur.season;
              final afterNumber = number ?? cur.number;
              numberings[id] = _Numbering(
                  cur.season,
                  cur.number,
                  afterSeason,
                  afterNumber,
                  afterSeason != cur.season ||
                      !_sameNumber(afterNumber, cur.number));
            }
            episodeId = id;
          } else {
            final match = existing
                .where((e) => e.season == season && _sameNumber(e.number, number))
                .toList();
            if (match.length > 1) {
              problem(path,
                  'Season/number matches several episodes (${match.map((e) => e.id).join(', ')}); address by episodeId.',
                  FailureCode.conflict);
              continue;
            }
            if (match.isNotEmpty) {
              episodeId = match.single.id;
            } else {
              final seasonReleases =
                  releases.where((r) => r.season == season).toList();
              if (seasonReleases.length > 1) {
                problem(path,
                    'Several releases carry season ${season ?? 'none'}; the episode cannot be placed without a choice.',
                    FailureCode.conflict);
                continue;
              }
              final releaseId = seasonReleases.isNotEmpty
                  ? seasonReleases.single.id
                  : newReleases.putIfAbsent(season, () {
                      final rid = newMediaId('release');
                      newReleaseRows.add({
                        'id': rid,
                        'kind': 'release',
                        'parent_id': workId,
                        'revision': 0,
                        'attributes': jsonEncode({
                          'localOnly': true,
                          'removed': false,
                          'title': workTitle,
                          if (season != null) 'season': season
                        })
                      });
                      return rid;
                    });
              episodeId = newMediaId('episode');
              created = true;
              newEpisodeRows.add({
                'id': episodeId,
                'kind': 'episode',
                'parent_id': releaseId,
                'revision': 0,
                'attributes': jsonEncode({
                  'localOnly': true,
                  'removed': false,
                  'type': 'regular',
                  'order': 'unspecified',
                  'title': (item['title'] as String?)?.trim() ?? '',
                  'number': number,
                  if (season != null) 'season': season
                })
              });
              // Later items with the same season/number mean this one.
              existing.add((
                id: episodeId,
                number: number,
                season: season,
                releaseId: releaseId
              ));
            }
          }
          if (!claimed.add(episodeId)) {
            problem(path, 'Another item in this batch already names this episode.',
                FailureCode.conflict);
            continue;
          }
          final target = _Target(i, episodeId, season, number, created);
          target.numbering = numberings[episodeId];
          target.units.addAll(await units(path, episodeId, item,
              images: {'still'}));
          targets.add(target);
        }

        // One release never holds two episodes with the same season and
        // number, judged on what the batch would leave behind.
        final after = {
          for (final e in existing)
            e.id: (season: numberings[e.id]?.afterSeason ?? e.season,
                number: numberings[e.id]?.afterNumber ?? e.number)
        };
        for (final t in targets) {
          final n = t.numbering;
          if (n == null || !n.changed || n.afterNumber == null) continue;
          final releaseId =
              existing.firstWhere((e) => e.id == t.entityId).releaseId;
          final clash = [
            for (final e in existing)
              if (e.releaseId == releaseId &&
                  e.id != t.entityId &&
                  after[e.id]!.season == n.afterSeason &&
                  _sameNumber(after[e.id]!.number, n.afterNumber))
                e.id
          ];
          if (clash.isNotEmpty) {
            problem(
                'episodes[${t.index}]',
                'Season ${n.afterSeason ?? 'none'} number ${n.afterNumber} is already held by ${clash.join(', ')} in the same release.',
                FailureCode.conflict);
          }
        }

        if (problems.isNotEmpty) {
          throw Failure(
              problems.every((p) => p['code'] == 'unavailable')
                  ? FailureCode.unavailable
                  : FailureCode.invalidInput,
              'Nothing was written. ${problems.length} item(s) failed: '
              '${[for (final p in problems) '${p['path']}: ${p['error']}'].join('; ')}',
              retryable: problems.every((p) => p['code'] == 'unavailable'),
              details: {'items': problems});
        }

        // Already what she says? Then the unit stays as it is.
        Future<({Object? value, bool found})> current(
            List<String> ids, String field) async {
          final rows = await db.query('media_overrides',
              where:
                  'entity_id IN (${List.filled(ids.length, '?').join(',')}) AND field=?',
              whereArgs: [...ids, field],
              orderBy: 'changed_at DESC',
              limit: 1);
          if (rows.isEmpty || rows.single['mode'] != 'persistent') {
            return (value: null, found: false);
          }
          return (value: jsonDecode(rows.single['value'] as String), found: true);
        }

        final groups = <String, List<_Unit>>{};
        for (final unit in [
          ...workUnits,
          for (final t in targets) ...t.units
        ]) {
          groups.putIfAbsent(unit.entityId, () => []).add(unit);
        }
        final sources = <String, JsonMap>{};
        for (final entry in groups.entries) {
          final ids = entry.key == workId
              ? family
              : newEpisodeRows.any((r) => r['id'] == entry.key)
                  ? <String>[]
                  : [entry.key];
          final recorded = ids.isEmpty
              ? null
              : (await current(ids, 'fieldSources')).value;
          sources[entry.key] = {
            if (recorded is Map) ...recorded.cast<String, Object?>()
          };
          for (final unit in entry.value) {
            if (ids.isEmpty) continue;
            var same = true;
            for (final (field, value) in unit.rows) {
              final now = await current(ids, field);
              same &= now.found
                  ? stableMediaId('v', [now.value]) ==
                      stableMediaId('v', [value])
                  : value == null;
            }
            if (unit.sourced) {
              same &= stableMediaId('v', [sources[entry.key]![unit.name]]) ==
                  stableMediaId('v', [source]);
            }
            unit.changed = !same;
          }
        }

        final entries = <JsonMap>[];
        for (final entry in groups.entries) {
          var sourcesChanged = false;
          for (final unit in entry.value.where((u) => u.changed)) {
            for (final (field, value) in unit.rows) {
              entries.add({'entityId': entry.key, 'field': field, 'value': value});
            }
            if (unit.sourced) {
              sources[entry.key]![unit.name] = source;
              sourcesChanged = true;
            }
          }
          if (sourcesChanged) {
            entries.add({
              'entityId': entry.key,
              'field': 'fieldSources',
              'value': sources[entry.key]
            });
          }
        }
        final edits = await store.overrideEdits(entries, invocation,
            created: {for (final r in newEpisodeRows) r['id'] as String});

        JsonMap outcome(Iterable<_Unit> list) =>
            {for (final u in list) u.name: u.changed ? 'written' : 'unchanged'};
        final result = <String, Object?>{
          'requestId': input['requestId'],
          'workId': workId,
          if (workUnits.isNotEmpty) 'work': outcome(workUnits),
          'episodes': [
            for (final t in targets)
              {
                'index': t.index,
                'episodeId': t.entityId,
                'created': t.created,
                'fields': outcome(t.units),
                if (t.numbering != null)
                  'numbering': {
                    'written': t.numbering!.changed,
                    'before': {
                      'season': t.numbering!.beforeSeason,
                      'number': t.numbering!.beforeNumber
                    },
                    'after': {
                      'season': t.numbering!.afterSeason,
                      'number': t.numbering!.afterNumber
                    }
                  }
              }
          ],
          'created': {
            'releases': [for (final r in newReleaseRows) r['id']],
            'episodes': [for (final r in newEpisodeRows) r['id']]
          },
          'written': [
            ...workUnits,
            for (final t in targets) ...t.units
          ].where((u) => u.changed).length +
              targets.where((t) => t.numbering?.changed == true).length,
          'unchanged': [
            ...workUnits,
            for (final t in targets) ...t.units
          ].where((u) => !u.changed).length +
              targets.where((t) => t.numbering?.changed == false).length,
        };

        await BodySignals.transaction(db, (tx) async {
          for (final row in [...newReleaseRows, ...newEpisodeRows]) {
            await tx.insert('media_entities', row);
          }
          for (final t in targets) {
            final n = t.numbering;
            if (n == null || !n.changed) continue;
            final row = await tx.query('media_entities',
                where: 'id=?', whereArgs: [t.entityId]);
            final attrs = decodeMediaJson(row.single['attributes']);
            await tx.update(
                'media_entities',
                {
                  'revision': (row.single['revision'] as int) + 1,
                  'attributes': jsonEncode({
                    ...attrs,
                    if (n.afterNumber != null) 'number': n.afterNumber,
                    if (n.afterSeason != null) 'season': n.afterSeason
                  })
                },
                where: 'id=?',
                whereArgs: [t.entityId]);
          }
          await store.writeOverrides(tx, edits);
          await tx.insert('media_binding_operations', {
            'id': key,
            'fingerprint': fingerprint,
            'result': jsonEncode(result)
          });
          await tx.insert('body_changes', {
            'at': DateTime.now().toUtc().toIso8601String(),
            'type': 'media.metadata.put',
            'subject_id': workId,
            'actor': invocation.origin == 'gui' ? 'user' : 'agent',
            'origin': invocation.origin,
            'invocation_id': invocation.id,
            'facts': jsonEncode({'source': source, ...result})
          });
        });
        store.announceOverrides(edits, invocation);
        return {...result, 'uiFacts': await metadataSummary(workId)};
      });
}
