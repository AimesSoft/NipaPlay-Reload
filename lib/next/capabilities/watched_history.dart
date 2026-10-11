import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../media/media_service.dart';

final class WatchedHistory {
  WatchedHistory(this._media, this.historyDatabase, this.changed);
  final MediaService Function() _media;
  MediaService get media => _media();
  final Future<Database> Function() historyDatabase;
  final Future<void> Function() changed;

  Future<JsonMap> set(List<JsonMap> entries, Invocation invocation) =>
      media.mutate(() async {
        if (entries.isEmpty)
          throw const Failure(
              FailureCode.invalidInput, 'Supply at least one episode or file.');
        final desired = <String, bool>{};
        for (final entry in entries) {
          final fileId = entry['fileId'] as String?,
              episodeId = entry['episodeId'] as String?;
          if ((fileId == null) == (episodeId == null))
            throw const Failure(FailureCode.invalidInput,
                'Each entry needs exactly one fileId or episodeId.');
          final ids = fileId != null
              ? [fileId]
              : [
                  for (final row in await media.store.database.query(
                      'media_file_episodes',
                      where: 'episode_id=?',
                      whereArgs: [episodeId]))
                    row['file_id'] as String
                ];
          if (ids.isEmpty)
            throw const Failure(
                FailureCode.notFound, 'Episode has no recorded file.');
          for (final id in ids) {
            final entity = await media.store.entity(id);
            if (entity['kind'] != 'file')
              throw const Failure(FailureCode.invalidInput,
                  'Use a file or episode from library.files or library.episodes.');
            final canonical = entity['id'] as String;
            final links = await media.store.database.query(
                'media_file_episodes',
                where: 'file_id=?',
                whereArgs: [canonical]);
            if (links.length > 1)
              throw const Failure(FailureCode.conflict,
                  'This file contains multiple episodes; its whole-file Classic progress cannot mark one episode.');
            for (final location in await media.store.locations(canonical)) {
              final path = location['locator'] as String;
              final watched = entry['watched'] as bool;
              if (desired.containsKey(path) && desired[path] != watched)
                throw const Failure(FailureCode.invalidInput,
                    'The same file has conflicting states in this batch.');
              desired[path] = watched;
            }
          }
        }
        final db = await historyDatabase();
        final changes = <JsonMap>[];
        await db.transaction((tx) async {
          for (final entry in desired.entries) {
            final rows = await tx.query('watch_history',
                where: 'file_path=?', whereArgs: [entry.key]);
            if (rows.isEmpty)
              throw const Failure(FailureCode.notFound,
                  'File has no Classic watch history; scan or play it first.');
            final before = rows.single;
            final position = entry.value ? before['duration'] as int : 0;
            final progress = entry.value ? 1.0 : 0.0;
            if (before['watch_progress'] == progress &&
                before['last_position'] == position) continue;
            final after = {
              'watch_progress': progress,
              'last_position': position,
              'last_watch_time': DateTime.now().toIso8601String()
            };
            await tx.update('watch_history', after,
                where: 'id=?', whereArgs: [before['id']]);
            changes.add({
              'path': entry.key,
              'before': before,
              'after': {...before, ...after}
            });
          }
        });
        if (changes.isNotEmpty) {
          await media.store.database.insert('body_changes', {
            'at': DateTime.now().toUtc().toIso8601String(),
            'type': 'history.watched',
            'subject_id': 'watch_history',
            'actor': invocation.origin == 'gui' ? 'user' : 'agent',
            'origin': invocation.origin,
            'invocation_id': invocation.id,
            'facts': jsonEncode({'title': '已更新观看状态', 'changes': changes})
          });
          await changed();
        }
        return {'changed': changes.length, 'files': desired.length};
      });
}

final class WatchedHistoryCapability implements Capability {
  WatchedHistoryCapability(WatchedHistory service)
      : actions = [_MarkWatched(service)];
  @override
  final List<Action> actions;
}

final class _Value implements JsonEncodable {
  const _Value(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _MarkWatched extends Action<_Value, _Value> {
  const _MarkWatched(this.service);
  final WatchedHistory service;
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'history.mark_watched_batch',
      title: '标记本地观看状态',
      description:
          'Atomically mark recorded Classic files/episodes watched or unwatched. entries:[{episodeId OR fileId,watched}]. IDs come from library.episodes/library.files. Existing matching, duration and other history fields are preserved. Does not update remote account collections. Multi-episode files are rejected because Classic progress is whole-file.',
      effect: Effect.write,
      input: ObjectSchema({
        'entries': ArraySchema(ObjectSchema({
          'episodeId': StringSchema(minLength: 1),
          'fileId': StringSchema(minLength: 1),
          'watched': BooleanSchema()
        }, required: [
          'watched'
        ]))
      }, required: [
        'entries'
      ]),
      output: ObjectSchema({}, additionalProperties: true));
  @override
  _Value decodeInput(JsonMap json) => _Value(json);
  @override
  Future<Outcome<_Value>> run(_Value input, Invocation invocation) async =>
      Completed(_Value(await service.set(
          (input.value['entries'] as List).cast<JsonMap>(), invocation)));
}
