import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/credential_key_policy.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../harness_redaction.dart';
import '../media/identity_store.dart' show newMediaId;
import 'denylist.dart';
import 'registry.dart';

/// Why a stored preference can or cannot be read and written here.
///
/// - `claimed`: a registry setting stores it; change it with `settings.set`.
/// - `credential`: a secret by name or policy; its value is never returned.
/// - `boundary`: an authorization boundary (remote access, remote control,
///   agent, model, mesh); its value is never returned (`app.runtime` gives the
///   non-secret facts) and it is never written here.
/// - `routing`: by name an address, proxy, server or certificate trust that no
///   setting claims; readable, never written here, because it decides where
///   keys or traffic go.
/// - `open`: anything else; readable and writable.
enum PrefClass { claimed, credential, boundary, routing, open }

final _routingName = RegExp(
    r'url|uri|server|proxy|host|endpoint|address|domain|cert|trust|gateway|origin|mirror|dns',
    caseSensitive: false);

/// Reads and writes the application preferences no registry setting claims.
/// Writes keep the previous state in settings_changes (under `prefs:<key>`),
/// so each can be listed and undone.
final class PrefsService {
  PrefsService(this.registry);
  final SettingsRegistry registry;
  final _previews = <String, JsonMap>{};
  Future<void> _pending = Future.value();

  Database get _db => registry.database;

  Future<T> _serial<T>(Future<T> Function() run) {
    final result = _pending.then((_) => run());
    _pending = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  PrefClass classify(String key) {
    if (registry.claimOf(key).isNotEmpty) return PrefClass.claimed;
    if (CredentialKeyPolicy.isSecretKey(key) ||
        RegExp(r'(^|[._])(password|passwd|token|secret|api_?key|credential)([._]|$)')
            .hasMatch(key.toLowerCase())) {
      return PrefClass.credential;
    }
    if (isSettingDenied(key)) return PrefClass.boundary;
    if (_routingName.hasMatch(key)) return PrefClass.routing;
    return PrefClass.open;
  }

  static String typeOf(Object? value) => switch (value) {
        null => 'absent',
        bool() => 'bool',
        int() => 'int',
        double() => 'double',
        String() => 'string',
        List() => 'stringList',
        _ => 'unknown',
      };

  static int _size(Object? value) => switch (value) {
        String() => value.length,
        List() => value.length,
        _ => 0,
      };

  Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  /// A value as it may be shown: secrets masked, long text cut.
  Object? shown(Object? value, {int maxChars = 4000}) {
    Object? safe = redactHarnessJson(SecretRedactor.json(value));
    if (safe is String && safe.length > maxChars) {
      return {'truncated': true, 'length': safe.length, 'head': safe.substring(0, maxChars)};
    }
    if (safe is List && jsonEncode(safe).length > maxChars) {
      return {'truncated': true, 'length': safe.length, 'head': safe.take(20).toList()};
    }
    return safe;
  }

  Future<JsonMap> list(
      {String? prefix, String? keyword, String? klass, int offset = 0, int limit = 200}) async {
    final prefs = await _prefs();
    final counts = <String, int>{for (final c in PrefClass.values) c.name: 0};
    final rows = <JsonMap>[];
    final keys = prefs.getKeys().toList()..sort();
    for (final key in keys) {
      final c = classify(key);
      counts[c.name] = counts[c.name]! + 1;
      if (prefix != null && !key.startsWith(prefix)) continue;
      if (keyword != null && !key.toLowerCase().contains(keyword.toLowerCase())) continue;
      if (klass != null && klass != c.name) continue;
      final value = prefs.get(key);
      rows.add({
        'key': key,
        'class': c.name,
        'type': typeOf(value),
        'size': _size(value),
        if (c == PrefClass.claimed) 'claimedBy': registry.claimOf(key),
        'readable': c != PrefClass.credential && c != PrefClass.boundary,
        'writable': c == PrefClass.open,
      });
    }
    final page = rows.skip(offset).take(limit + 1).toList();
    return {
      'total': prefs.getKeys().length,
      'counts': counts,
      'matched': rows.length,
      'prefs': page.take(limit).toList(),
      'nextOffset': page.length > limit ? offset + limit : null,
    };
  }

  Future<JsonMap> get(List<String> keys) async {
    final prefs = await _prefs();
    return {
      'prefs': [
        for (final key in keys) () {
          final c = classify(key);
          final value = prefs.get(key);
          final base = {
            'key': key,
            'class': c.name,
            'present': value != null,
            'type': typeOf(value),
            if (c == PrefClass.claimed) 'claimedBy': registry.claimOf(key),
          };
          return switch (c) {
            PrefClass.credential => {
                ...base,
                'withheld': 'credential',
                'detail': 'A credential: its value is never returned.'
              },
            PrefClass.boundary => {
                ...base,
                'withheld': 'authorization_boundary',
                'detail': 'An authorization boundary: its value is not returned here. app.runtime reads the non-secret facts.'
              },
            _ => {...base, 'value': shown(value)},
          };
        }()
      ]
    };
  }

  Object? _coerce(Object? value, String? existing) {
    switch (existing) {
      case 'bool':
        if (value is bool) return value;
      case 'int':
        if (value is num && value == value.truncate()) return value.toInt();
      case 'double':
        if (value is num) return value.toDouble();
      case 'string':
        if (value is String) return value;
      case 'stringList':
        if (value is List && value.every((e) => e is String)) {
          return value.cast<String>();
        }
      case null:
        if (value is bool || value is String) return value;
        if (value is int) return value;
        if (value is num) return value.toDouble();
        if (value is List && value.every((e) => e is String)) {
          return value.cast<String>();
        }
    }
    throw Failure(
        FailureCode.invalidInput,
        existing == null
            ? 'Use a bool, number, string or array of strings.'
            : 'The preference holds a $existing; the value must be one too.');
  }

  JsonMap _state(Object? value) => value == null
      ? {'present': false}
      : {'present': true, 'type': typeOf(value), 'value': value};

  Object? _fromState(JsonMap state) =>
      state['present'] == true ? state['value'] : null;

  Future<JsonMap> _latest(String key) async {
    final rows = await _db.query('settings_changes',
        where: 'key = ?', whereArgs: ['prefs:$key'], orderBy: 'revision DESC', limit: 1);
    return rows.isEmpty ? {} : rows.first;
  }

  Future<Object?> _apply(SharedPreferences prefs, String key, Object? value) async {
    final ok = switch (value) {
      null => await prefs.remove(key),
      bool() => await prefs.setBool(key, value),
      int() => await prefs.setInt(key, value),
      double() => await prefs.setDouble(key, value),
      String() => await prefs.setString(key, value),
      List<String>() => await prefs.setStringList(key, value),
      _ => false,
    };
    if (!ok) {
      throw const Failure(FailureCode.unavailable, 'The preference could not be saved.');
    }
    await prefs.reload();
    return prefs.get(key);
  }

  void _requireWritable(String key) {
    switch (classify(key)) {
      case PrefClass.open:
        return;
      case PrefClass.claimed:
        throw Failure(FailureCode.invalidInput,
            '$key is the storage of ${registry.claimOf(key).join(', ')}; change it with settings.set, which validates it and applies it.');
      case PrefClass.credential:
        throw const Failure(FailureCode.invalidInput,
            'This preference is a credential; credentials are not written through Actions.');
      case PrefClass.boundary:
        throw const Failure(FailureCode.invalidInput,
            'This preference belongs to an authorization boundary (remote access, remote control, agent, model or mesh); only the user changes it.');
      case PrefClass.routing:
        throw const Failure(FailureCode.invalidInput,
            'By its name this preference sets an address, proxy, server or certificate trust, which decides where keys or traffic go; only the user changes it, or a setting that validates it.');
    }
  }

  /// Without [previewId] shows what writing would change; with it, writes
  /// exactly that preview.
  Future<JsonMap> set(JsonMap input, Invocation invocation) async {
    final unknown = input.keys.where((k) =>
        !const {'key', 'value', 'remove', 'previewId', 'reason'}.contains(k));
    if (unknown.isNotEmpty) {
      throw Failure(FailureCode.invalidInput, 'Unknown fields: ${unknown.join(', ')}');
    }
    final previewId = input['previewId'] as String?;
    if (previewId != null) return _commit(previewId, input, invocation);
    final key = input['key'] as String?;
    if (key == null) {
      throw const Failure(FailureCode.invalidInput,
          'Supply key and value (or remove:true) to preview, or previewId to commit a preview.');
    }
    final remove = input['remove'] == true;
    if (remove == input.containsKey('value')) {
      throw const Failure(FailureCode.invalidInput, 'Supply value, or remove:true, not both.');
    }
    _requireWritable(key);
    final prefs = await _prefs();
    final before = prefs.get(key);
    final Object? after;
    if (remove) {
      if (before == null) {
        throw const Failure(FailureCode.invalidInput, 'The preference is not set; there is nothing to remove.');
      }
      after = null;
    } else {
      after = _coerce(input['value'], before == null ? null : typeOf(before));
      if (jsonEncode(SecretRedactor.json(after)) != jsonEncode(after)) {
        throw const Failure(FailureCode.invalidInput,
            'The value looks like a credential; credentials are not written through Actions.');
      }
    }
    if (jsonEncode(before) == jsonEncode(after)) {
      throw const Failure(FailureCode.invalidInput, 'The preference already has this value.');
    }
    final id = newMediaId('prefs-preview');
    _previews[id] = {
      'key': key,
      'before': before,
      'after': after,
      'origin': invocation.origin,
    };
    if (_previews.length > 64) _previews.remove(_previews.keys.first);
    return {
      'committed': false,
      'previewId': id,
      'key': key,
      'before': _view(before),
      'after': _view(after),
      'note': 'Nothing is written until set is called again with this previewId. The value is not validated beyond its type.',
    };
  }

  JsonMap _view(Object? value) =>
      {...(_state(value)..remove('value')), if (value != null) 'value': shown(value)};

  Future<JsonMap> _commit(String previewId, JsonMap input, Invocation invocation) {
    final plan = _previews[previewId];
    if (plan == null || plan['origin'] != invocation.origin) {
      throw const Failure(FailureCode.conflict,
          'The preview is missing, used, or belongs to another caller; preview again.');
    }
    return _serial(() async {
      final key = plan['key'] as String;
      _requireWritable(key);
      final prefs = await _prefs();
      if (jsonEncode(prefs.get(key)) != jsonEncode(plan['before'])) {
        _previews.remove(previewId);
        throw const Failure(FailureCode.conflict,
            'The preference changed since the preview; nothing was written. Preview again.');
      }
      _previews.remove(previewId);
      final after = await _apply(prefs, key, plan['after']);
      return _record(key, plan['before'], after, invocation, input['reason'] as String?,
          undoOf: null);
    });
  }

  Future<JsonMap> _record(String key, Object? before, Object? after,
      Invocation invocation, String? reason, {String? undoOf}) async {
    final revision = ((await _latest(key))['revision'] as int? ?? 0) + 1;
    final origin = invocation.origin;
    final sequence = await _db.insert('settings_changes', {
      'key': 'prefs:$key',
      'previous_value': jsonEncode(_state(before)),
      'value': jsonEncode(_state(after)),
      'changed_at': DateTime.now().toUtc().toIso8601String(),
      'changed_by': origin == 'gui' ? 'user' : 'agent',
      'origin': origin,
      'reason': undoOf == null ? reason : 'undo of $undoOf${reason == null ? '' : ': $reason'}',
      'invocation_id': invocation.id,
      'revision': revision,
    });
    return {
      'committed': true,
      'commitId': 'prefs-$sequence',
      'key': key,
      'revision': revision,
      'before': _view(before),
      'after': _view(after),
      if (undoOf != null) 'undoOf': undoOf,
    };
  }

  Future<JsonMap> history({String? key, int offset = 0, int limit = 50}) async {
    final rows = await _db.query('settings_changes',
        where: key == null ? "key LIKE 'prefs:%'" : 'key = ?',
        whereArgs: key == null ? null : ['prefs:$key'],
        orderBy: 'sequence DESC',
        limit: limit + 1,
        offset: offset);
    JsonMap view(Map<String, Object?> row) {
      final before = jsonDecode(row['previous_value'] as String) as JsonMap;
      final after = jsonDecode(row['value'] as String) as JsonMap;
      return {
        'commitId': 'prefs-${row['sequence']}',
        'key': (row['key'] as String).substring(6),
        'revision': row['revision'],
        'changedAt': row['changed_at'],
        'changedBy': row['changed_by'],
        'origin': row['origin'],
        'reason': row['reason'],
        'invocationId': row['invocation_id'],
        'before': _view(_fromState(before)),
        'after': _view(_fromState(after)),
      };
    }

    return {
      'commits': [for (final row in rows.take(limit)) view(row)],
      'nextOffset': rows.length > limit ? offset + limit : null,
    };
  }

  /// Restores the state before commit [commitId], when the preference still
  /// has what that commit left.
  Future<JsonMap> undo(JsonMap input, Invocation invocation) {
    final commitId = input['commitId'] as String;
    final match = RegExp(r'^prefs-(\d+)$').firstMatch(commitId);
    if (match == null) {
      throw const Failure(FailureCode.invalidInput, 'commitId is a prefs-N id from settings.prefs.set.');
    }
    return _serial(() async {
      final rows = await _db.query('settings_changes',
          where: "sequence = ? AND key LIKE 'prefs:%'",
          whereArgs: [int.parse(match.group(1)!)]);
      if (rows.isEmpty) {
        throw const Failure(FailureCode.notFound, 'No such preference commit.');
      }
      final row = rows.single;
      final key = (row['key'] as String).substring(6);
      final restore = _fromState(jsonDecode(row['previous_value'] as String) as JsonMap);
      final left = _fromState(jsonDecode(row['value'] as String) as JsonMap);
      _requireWritable(key);
      final prefs = await _prefs();
      final current = prefs.get(key);
      if (jsonEncode(current) != jsonEncode(left)) {
        throw Failure(FailureCode.conflict,
            'The preference changed after this commit; nothing was undone.',
            violations: [
              SchemaViolation('/$key', 'now ${jsonEncode(shown(current))}, the commit left ${jsonEncode(shown(left))}')
            ]);
      }
      if (input['dryRun'] == true) {
        return {
          'committed': false,
          'dryRun': true,
          'key': key,
          'before': _view(current),
          'after': _view(restore),
        };
      }
      final after = await _apply(prefs, key, restore);
      return _record(key, current, after, invocation, input['reason'] as String?,
          undoOf: commitId);
    });
  }
}

/// `settings.prefs.*`.
final class PrefsCapability implements Capability {
  PrefsCapability(PrefsService service)
      : actions = [
          _action(
              'settings.prefs.list',
              'List stored application preferences',
              'List every key in the application preferences (SharedPreferences) with its class, type and size, never its value: claimed (a registry setting stores it; claimedBy names the settings), credential (a secret by name or policy), boundary (an authorization boundary: remote access, remote control, agent, model, mesh), routing (by name an address, proxy, server or certificate trust that no setting claims) and open. credential and boundary values are never returned by any action; app.runtime gives the non-secret facts of the boundary ones. readable and writable say what settings.prefs.get and settings.prefs.set do with the key. counts totals every class. Filter with prefix, keyword or class; page with offset/limit (default 200, max 1000). Use it to find a preference no setting covers.',
              Effect.read,
              const {
                'prefix': StringSchema(minLength: 1),
                'keyword': StringSchema(minLength: 1),
                'class': StringSchema(values: [
                  'claimed',
                  'credential',
                  'boundary',
                  'routing',
                  'open'
                ]),
                'offset': IntegerSchema(minimum: 0),
                'limit': IntegerSchema(minimum: 1, maximum: 1000),
              },
              const [],
              (input, _) => service.list(
                  prefix: input['prefix'] as String?,
                  keyword: input['keyword'] as String?,
                  klass: input['class'] as String?,
                  offset: (input['offset'] as num?)?.toInt() ?? 0,
                  limit: (input['limit'] as num?)?.toInt() ?? 200)),
          _action(
              'settings.prefs.get',
              'Read stored application preferences',
              'Read the values of up to 100 preference keys (see settings.prefs.list). Each result has key, class, present, type and value; strings and string lists that look like secrets are masked, text over 4000 characters is cut (truncated:true with the length and the head). credential and boundary keys return withheld and no value. A key that is not set returns present:false. Claimed keys return their stored value and claimedBy; settings.get also gives the effective value.',
              Effect.read,
              const {
                'keys': ArraySchema(StringSchema(minLength: 1),
                    minItems: 1, maxItems: 100),
              },
              const ['keys'],
              (input, _) => service.get((input['keys'] as List).cast<String>())),
          _action(
              'settings.prefs.set',
              'Write a stored application preference',
              'Fallback for a preference no setting covers. Only open keys can be written: not claimed ones (use settings.set), credentials, authorization boundaries, or addresses, proxies, servers and certificate trust (routing keys), which only the user changes. Supply key and value (bool, number, string or array of strings; an existing key keeps its type) or remove:true. Without previewId it only previews: before and after, and a previewId, valid for this caller and one commit. With previewId it writes exactly that preview, and refuses if the preference changed meanwhile or the value looks like a credential. The value is not validated beyond its type. Every commit is recorded (commitId prefs-N, origin, reason, before and after) and listed by settings.prefs.history; undo it with settings.prefs.undo.',
              Effect.write,
              const {
                'key': StringSchema(minLength: 1),
                'remove': BooleanSchema(),
                'previewId': StringSchema(minLength: 1),
                'reason': StringSchema(minLength: 1, maxLength: 500),
              },
              const [],
              service.set,
              additional: true),
          _action(
              'settings.prefs.undo',
              'Undo a preference write',
              'Restore the state before commit commitId (from settings.prefs.set or a previous undo). The preference must still have what that commit left; otherwise nothing is undone and the difference is reported. dryRun:true shows what would be restored. The undo is itself a commit with its own commitId, recorded and undoable. Keys that settings.prefs.set may not write cannot be undone either.',
              Effect.write,
              const {
                'commitId': StringSchema(minLength: 1),
                'dryRun': BooleanSchema(),
                'reason': StringSchema(minLength: 1, maxLength: 500),
              },
              const ['commitId'],
              service.undo),
          _action(
              'settings.prefs.history',
              'List preference writes',
              'Preference commits newest first (commitId, key, revision, changedAt, changedBy, origin, reason, invocationId, before and after), for one key or all. Values are masked as in settings.prefs.get. Registry settings have their own history in settings.history.',
              Effect.read,
              const {
                'key': StringSchema(minLength: 1),
                'offset': IntegerSchema(minimum: 0),
                'limit': IntegerSchema(minimum: 1, maximum: 1000),
              },
              const [],
              (input, _) => service.history(
                  key: input['key'] as String?,
                  offset: (input['offset'] as num?)?.toInt() ?? 0,
                  limit: (input['limit'] as num?)?.toInt() ?? 50)),
        ];
  @override
  final List<Action> actions;

  static Action _action(String id, String title, String description,
          Effect effect, Map<String, Schema> properties, List<String> required,
          Future<JsonMap> Function(JsonMap, Invocation) run,
          {bool additional = false}) =>
      _PrefsAction(
          ActionSpec(
              id: id,
              title: title,
              description: description,
              effect: effect,
              input: ObjectSchema(properties,
                  required: required, additionalProperties: additional),
              output: const ObjectSchema({}, additionalProperties: true)),
          run);
}

final class _PrefsData implements JsonEncodable {
  const _PrefsData(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _PrefsAction extends Action<_PrefsData, _PrefsData> {
  const _PrefsAction(this.spec, this.execute);
  @override
  final ActionSpec spec;
  final Future<JsonMap> Function(JsonMap, Invocation) execute;
  @override
  _PrefsData decodeInput(JsonMap json) => _PrefsData(json);
  @override
  Future<Outcome<_PrefsData>> run(_PrefsData input, Invocation invocation) async =>
      Completed(_PrefsData(await execute(input.value, invocation)));
}
