import 'dart:convert';
import 'dart:isolate';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../events/signals.dart';
import '../../security/secret_redactor.dart';

const subscriptionLimit = 500;
const subscriptionReportLimit = 20;

/// Stores declarations and script-reported observations, never interprets rules.
final class SubscriptionStore {
  SubscriptionStore(this.db);
  final Database db;

  Future<String> _json(Object? value, int maxBytes) {
    final known = SecretRedactor.remembered();
    return Isolate.run(() {
      for (final entry in known.entries) {
        SecretRedactor.remember(entry.value, entry.key);
      }
      final encoded = jsonEncode(SecretRedactor.json(value));
      if (utf8.encode(encoded).length > maxBytes) {
        throw const Failure(
            FailureCode.invalidInput, 'JSON exceeds byte limit.');
      }
      return encoded;
    });
  }

  Future<List<JsonMap>> list(
      {String? state, int offset = 0, int limit = 100}) async {
    final rows = await db.rawQuery('''SELECT s.*,
      (SELECT payload FROM subscription_reports r WHERE r.subscription_id=s.id
       ORDER BY sequence DESC LIMIT 1) AS latest_report
      FROM subscriptions s ${state == null ? '' : 'WHERE state=?'}
      ORDER BY s.created_at,s.id LIMIT ? OFFSET ?''',
        [if (state != null) state, limit, offset]);
    return Isolate.run(() => [for (final row in rows) _decode(row)]);
  }

  static JsonMap _decode(Map<String, Object?> row) => {
        'id': row['id'],
        'title': row['title'],
        'kind': row['kind'],
        'workId': row['work_id'],
        'state': row['state'],
        'note': row['note'],
        'program': row['program'],
        'facts': jsonDecode(row['facts'] as String),
        'createdBy': row['created_by'],
        'createdAt': row['created_at'],
        'updatedAt': row['updated_at'],
        'revision': row['revision'],
        'latestReport': row['latest_report'] == null
            ? null
            : jsonDecode(row['latest_report'] as String),
        'latestDownloads':
            jsonDecode(row['latest_downloads'] as String? ?? '[]'),
      };

  Future<JsonMap> get(String id) async {
    final rows =
        await db.query('subscriptions', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) {
      throw const Failure(FailureCode.notFound, 'Subscription does not exist.');
    }
    final reports = await db.query('subscription_reports',
        where: 'subscription_id=?',
        whereArgs: [id],
        orderBy: 'sequence DESC',
        limit: subscriptionReportLimit);
    return Isolate.run(() => {
          ..._decode({
            ...rows.single,
            'latest_report': reports.firstOrNull?['payload']
          }),
          'reports': [
            for (final r in reports) jsonDecode(r['payload'] as String)
          ],
        });
  }

  /// Bounded display projection: never materializes private rules/facts.
  Future<List<JsonMap>> display() async {
    final rows = await db.rawQuery(
        '''SELECT id,title,kind,work_id,state,note,latest_downloads,
      (SELECT checked_at FROM subscription_reports r WHERE r.subscription_id=s.id ORDER BY sequence DESC LIMIT 1) AS checked_at,
      (SELECT json_extract(payload,'\$.errors') FROM subscription_reports r WHERE r.subscription_id=s.id ORDER BY sequence DESC LIMIT 1) AS errors
      FROM subscriptions s ORDER BY created_at,id LIMIT ?''',
        [subscriptionLimit]);
    return Isolate.run(() => [
          for (final r in rows)
            {
              'id': r['id'],
              'title': r['title'],
              'kind': r['kind'],
              'workId': r['work_id'],
              'state': r['state'],
              'note': r['note'],
              'lastCheckedAt': r['checked_at'],
              'downloads': jsonDecode(r['latest_downloads'] as String),
              'errors': jsonDecode(r['errors'] as String? ?? '[]'),
            }
        ]);
  }

  Future<JsonMap> put(JsonMap input) async {
    final id = input['id'] as String? ?? 'sub-${const Uuid().v4()}';
    final facts = await _json(input['facts'] ?? <String, Object?>{}, 16384);
    final program = input['program'] as String;
    if (program.startsWith('/') ||
        program.contains('\\') ||
        program.contains(':') ||
        program.split('/').any((p) => p == '..' || p.isEmpty)) {
      throw const Failure(FailureCode.invalidInput,
          'program must be a relative harness path without traversal.');
    }
    await BodySignals.transaction(db, (txn) async {
      final old =
          await txn.query('subscriptions', where: 'id=?', whereArgs: [id]);
      if (old.isEmpty &&
          ((await txn.rawQuery('SELECT COUNT(*) AS n FROM subscriptions'))
                  .single['n'] as int) >=
              subscriptionLimit) {
        throw const Failure(
            FailureCode.invalidInput, 'At most 500 subscriptions per device.');
      }
      if (input['workId'] case final String workId) {
        if ((await txn.query('media_entities',
                columns: ['id'],
                where: "id=? AND kind='work'",
                whereArgs: [workId]))
            .isEmpty) {
          throw const Failure(FailureCode.invalidInput,
              'workId must name an existing Next work.');
        }
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final row = {
        'title': input['title'],
        'kind': input['kind'],
        'work_id': input['workId'],
        'state': input['state'] ?? 'active',
        'note': input['note'],
        'program': program,
        'facts': facts,
        'created_by': input['createdBy'],
        'updated_at': now,
        'revision': old.isEmpty ? 1 : (old.single['revision'] as int) + 1,
      };
      if (old.isEmpty) {
        await txn
            .insert('subscriptions', {...row, 'id': id, 'created_at': now});
      } else {
        await txn.update('subscriptions', row, where: 'id=?', whereArgs: [id]);
      }
      BodySignals.changed('subscription.changed', id,
          {'operation': 'put', 'revision': row['revision']});
    });
    return get(id);
  }

  Future<JsonMap> setState(String id, String state) async {
    await BodySignals.transaction(db, (txn) async {
      final count = await txn.rawUpdate(
          'UPDATE subscriptions SET state=?, updated_at=?, revision=revision+1 WHERE id=?',
          [state, DateTime.now().toUtc().toIso8601String(), id]);
      if (count == 0) {
        throw const Failure(
            FailureCode.notFound, 'Subscription does not exist.');
      }
      BodySignals.changed('subscription.changed', id,
          {'operation': 'set_state', 'state': state});
    });
    return get(id);
  }

  Future<JsonMap> remove(String id) => BodySignals.transaction(db, (txn) async {
        final count =
            await txn.delete('subscriptions', where: 'id=?', whereArgs: [id]);
        if (count > 0) {
          BodySignals.changed(
              'subscription.changed', id, {'operation': 'remove'});
        }
        return {'id': id, 'removed': count > 0};
      });

  Future<JsonMap> report(JsonMap input) async {
    final id = input['id'] as String;
    final at = DateTime.tryParse(input['checkedAt'] as String);
    if (at == null) {
      throw const Failure(
          FailureCode.invalidInput, 'checkedAt must be ISO-8601.');
    }
    final payload = await _json(
        {...input, 'checkedAt': at.toUtc().toIso8601String()}, 32768);
    await BodySignals.transaction(db, (txn) async {
      if ((await txn.query('subscriptions',
              columns: ['id'], where: 'id=?', whereArgs: [id]))
          .isEmpty) {
        throw const Failure(
            FailureCode.notFound, 'Subscription does not exist.');
      }
      final existing = await txn.query('subscription_reports',
          where: 'subscription_id=? AND report_id=?',
          whereArgs: [id, input['reportId']]);
      if (existing.isNotEmpty) {
        if (existing.single['payload'] != payload) {
          throw const Failure(FailureCode.conflict,
              'reportId already records another observation.');
        }
        return;
      }
      await txn.insert('subscription_reports', {
        'subscription_id': id,
        'report_id': input['reportId'],
        'checked_at': at.toUtc().toIso8601String(),
        'payload': payload
      });
      if ((input['downloads'] as List).isNotEmpty) {
        await txn.rawUpdate(
            "UPDATE subscriptions SET latest_downloads=json_extract(?, '\$.downloads') WHERE id=?",
            [payload, id]);
      }
      await txn.rawDelete(
          'DELETE FROM subscription_reports WHERE subscription_id=? AND sequence NOT IN (SELECT sequence FROM subscription_reports WHERE subscription_id=? ORDER BY sequence DESC LIMIT ?)',
          [id, id, subscriptionReportLimit]);
      await txn.rawUpdate(
          'UPDATE subscriptions SET updated_at=?,revision=revision+1 WHERE id=?',
          [DateTime.now().toUtc().toIso8601String(), id]);
      BodySignals.changed('subscription.changed', id,
          {'operation': 'report', 'reportId': input['reportId']});
    });
    return get(id);
  }
}
