import 'dart:async';
import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'denylist.dart';

final class SettingEntry {
  SettingEntry({
    required this.key,
    required this.title,
    required this.description,
    required Schema schema,
    this.dynamicSchema,
    this.validateValue,
    required Object? defaultValue,
    this.dynamicDefaultValue,
    required this.storageKey,
    required this.reader,
    required this.writer,
    required this.read,
    required this.write,
    required this.decodeStorage,
    this.additionalStorageKeys = const [],
    this.storageKind,
    this.scope = 'user',
    this.apply = 'immediate',
    bool Function()? visible,
    this.remote,
    this.step,
  })  : _schema = schema,
        _defaultValue = defaultValue,
        visible = visible ?? (() => true);

  final String key,
      title,
      description,
      scope,
      apply,
      storageKey,
      reader,
      writer;
  final Schema _schema;
  final Schema Function()? dynamicSchema;
  final List<SchemaViolation> Function(Object?)? validateValue;
  Schema get schema => dynamicSchema?.call() ?? _schema;
  final Object? _defaultValue;
  final Object? Function()? dynamicDefaultValue;
  Object? get defaultValue => dynamicDefaultValue?.call() ?? _defaultValue;
  final Future<Object?> Function() read;
  final Future<void> Function(Object?) write;
  final List<String> additionalStorageKeys;
  final String? storageKind;
  final Object? Function(Object?) decodeStorage;
  final bool Function() visible;
  final JsonMap? remote;
  final num? step;

  String get domain => key.split('.').first;
  JsonMap describe() => {
        'key': key,
        'title': title,
        'description': description,
        ...schema.toJsonSchema(),
        'default': defaultValue,
        'scope': scope,
        'apply': apply,
        'effect': 'write',
        if (step != null || remote?['step'] != null)
          'step': step ?? remote!['step'],
        if (key == 'danmaku.supersample') 'enum': [0.0, 1.5, 2.0],
        if (key == 'danmaku.outlineWidth') 'enum': [0.0, 1.0, 2.0],
        if (key == 'player.minimalProgressBarColor')
          'enum': [0xFFFF7274, 0xFF40C7FF, 0xFF6DFF69, 0xFF4CFFB1, 0xFFFFFFFF],
        if (key == 'appearance.blurPower')
          'enum': [0, 5, 15, 25, if ((_schema as NumberSchema).maximum! > 25) ...[50, 100]],
        if (key.startsWith('subtitle.') && key.toLowerCase().endsWith('color'))
          'pattern': r'^#[0-9A-Fa-f]{8}$',
        'storage': {
          'kind': storageKind ?? (storageKey.startsWith('@runtime:')
              ? 'runtime'
              : 'shared_preferences'),
          'key': storageKey,
          if (additionalStorageKeys.isNotEmpty) 'additionalKeys': additionalStorageKeys,
          if (key == 'danmaku.supersample')
            'legacyKeys': ['danmaku_supersample'],
          'reader': reader,
          'writer': writer,
        },
      };
}

final class SettingsRegistry {
  SettingsRegistry(this.database, Iterable<SettingEntry> entries) {
    register(entries);
  }

  void register(Iterable<SettingEntry> entries) {
    for (final entry in entries) {
      if (isSettingDenied(entry.key) || isSettingDenied(entry.storageKey)) {
        throw ArgumentError('Forbidden setting: ${entry.key}');
      }
      if (_entries.containsKey(entry.key)) {
        throw ArgumentError('Duplicate setting: ${entry.key}');
      }
      _entries[entry.key] = entry;
      for (final key in [entry.storageKey, ...entry.additionalStorageKeys]) {
        if (isSettingDenied(key)) throw ArgumentError('Forbidden storage key: $key');
        _storage.putIfAbsent(key, () => []).add(entry);
      }
    }
  }

  final Database database;
  final _entries = <String, SettingEntry>{};
  final _storage = <String, List<SettingEntry>>{};
  Future<void> _pending = Future.value();
  static final _operation = Object();

  Iterable<SettingEntry> get entries => _entries.values;
  bool contains(String key) => _entries[key]?.visible() ?? false;

  void replaceGroup(String prefix, Iterable<SettingEntry> entries) {
    final removed = _entries.values.where((e) => e.key.startsWith(prefix)).toList();
    for (final entry in removed) {
      _entries.remove(entry.key);
      for (final key in [entry.storageKey, ...entry.additionalStorageKeys]) {
        _storage[key]!.remove(entry);
        if (_storage[key]!.isEmpty) _storage.remove(key);
      }
    }
    register(entries);
  }

  SettingEntry _entry(String key) {
    final entry = _entries[key];
    if (isSettingDenied(key) || entry == null || !entry.visible()) {
      throw Failure(FailureCode.notFound, 'Setting not found: $key');
    }
    return entry;
  }

  Future<T> _serial<T>(Future<T> Function() run) {
    final result = _pending.then((_) => run());
    // A failed caller must not poison the queue for subsequent callers.
    _pending =
        result.then<void>((_) {}, onError: (Object error, StackTrace s) {});
    return result;
  }

  Future<JsonMap?> _latest(String key) async {
    final rows = await database.query('settings_changes',
        where: 'key = ?', whereArgs: [key], orderBy: 'revision DESC', limit: 1);
    return rows.isEmpty ? null : _decodeRow(rows.first);
  }

  Future<JsonMap> get(String key) async {
    final entry = _entry(key);
    final latest = await _latest(key);
    return {
      'key': key,
      'value': await entry.read(),
      'revision': latest?['revision'] ?? 0,
      'scope': entry.scope,
      'apply': entry.apply,
      'provenance': latest,
    };
  }

  /// Current values and their latest provenance, rather than copied settings.
  Future<List<JsonMap>> preferences() async {
    await drain();
    final rows = <JsonMap>[];
    for (final entry in entries.where((e) => e.visible() && e.scope == 'user' && e.apply != 'runtime')) {
      final current = await get(entry.key);
      final provenance = current['provenance'] as Map?;
      if (provenance == null || provenance['changedBy'] == 'migration' ||
          provenance['origin'] == 'application') {
        continue;
      }
      rows.add({'key': entry.key, 'title': entry.title, 'value': current['value'],
        'changedAt': provenance['changedAt'], 'changedBy': provenance['changedBy'],
        'reason': provenance['reason']});
    }
    return rows;
  }

  Future<List<JsonMap>> describe(
      {String? domain,
      String? keyword,
      List<String>? keys,
      int offset = 0,
      int? limit}) async {
    final query = keyword?.toLowerCase();
    if (keys != null) {
      for (final key in keys) {
        _entry(key);
      }
    }
    final matched = entries.toList()
        .where((entry) =>
            entry.visible() &&
            (keys == null || keys.contains(entry.key)) &&
            (domain == null || entry.domain == domain) &&
            (query == null ||
                '${entry.key} ${entry.title} ${entry.description}'
                    .toLowerCase()
                    .contains(query)))
        .skip(offset);
    return [
      for (final entry in limit == null ? matched : matched.take(limit))
        {...entry.describe(), ...await get(entry.key)},
    ];
  }

  Future<JsonMap> set(String key, Object? value, Invocation invocation,
      {String? reason, int? expectedRevision, bool reset = false}) {
    final entry = _entry(key);
    if (reset) value = entry.defaultValue;
    final violations = entry.schema.validate(value);
    if (violations.isEmpty) {
      violations.addAll(entry.validateValue?.call(value) ?? []);
    }
    if (value is num && !value.isFinite) {
      violations
          .add(const SchemaViolation('/value', 'Expected a finite number.'));
    }
    if (violations.isNotEmpty) {
      throw Failure(FailureCode.invalidInput, 'Invalid setting value.',
          violations: violations);
    }
    if (entry.schema is NumberSchema) value = (value as num).toDouble();
    if (entry.schema is IntegerSchema) value = (value as num).toInt();
    return _serial(() async {
      final previous = await entry.read();
      final revision = (await _latest(key))?['revision'] ?? 0;
      if (expectedRevision != null && expectedRevision != revision) {
        throw const Failure(FailureCode.conflict, 'Setting revision changed.');
      }
      await runZoned(() => entry.write(value), zoneValues: {
        _operation: this,
        SettingsAccess.invocationKey: invocation,
        SettingsAccess.reasonKey: reason,
      });
      if (jsonEncode(previous) == jsonEncode(await entry.read()) &&
          jsonEncode(value) != jsonEncode(previous)) {
        throw const Failure(FailureCode.unavailable,
            'The Classic setter did not apply this value on the current player.');
      }
      // Some setters intentionally omit persistence when the value is unchanged.
      if (((await _latest(key))?['revision'] ?? 0) == revision) {
        await _append(entry, previous, await entry.read(), invocation, reason);
      }
      return get(key);
    });
  }

  Future<bool> persist(String storageKey, Future<bool> Function() perform,
      Invocation invocation, String? reason) async {
    final affected = _storage[storageKey]?.toList();
    if (affected == null) return perform();
    Future<bool> run() async {
      final before = [for (final entry in affected) await entry.read()];
      final saved = await perform();
      if (!saved) return false;
      for (var i = 0; i < affected.length; i++) {
        final entry = affected[i];
        final after = await entry.read();
        if (jsonEncode(before[i]) != jsonEncode(after)) {
          await _append(entry, before[i], after, invocation, reason);
        }
      }
      return saved;
    }

    return identical(Zone.current[_operation], this) ? run() : _serial(run);
  }

  Future<void> _append(SettingEntry entry, Object? previous, Object? value,
      Invocation invocation, String? reason) async {
    final revision = ((await _latest(entry.key))?['revision'] as int? ?? 0) + 1;
    final origin = invocation.origin;
    final changedBy = switch (origin) {
      'gui' => 'user',
      'mcp' => 'agent',
      'migration' => 'migration',
      _ => origin,
    };
    await database.insert('settings_changes', {
      'key': entry.key,
      'previous_value': jsonEncode(previous),
      'value': jsonEncode(value),
      'changed_at': DateTime.now().toUtc().toIso8601String(),
      'changed_by': changedBy,
      'origin': origin,
      'reason': reason,
      'invocation_id': invocation.id,
      'revision': revision,
    });
  }

  Future<List<JsonMap>> history(
      {String? key,
      List<String>? keys,
      DateTime? from,
      DateTime? to,
      int offset = 0,
      int limit = 50}) async {
    if (key != null) _entry(key);
    if (keys != null) {
      for (final key in keys) {
        _entry(key);
      }
    }
    if (limit < 1 || limit > 1000) {
      throw const Failure(FailureCode.invalidInput, 'Limit must be 1–1000.');
    }
    final visibleKeys = entries
        .where((entry) =>
            entry.visible() &&
            (key == null || key == entry.key) &&
            (keys == null || keys.contains(entry.key)))
        .map((entry) => entry.key)
        .toList();
    if (visibleKeys.isEmpty) return [];
    final rows = await database.query('settings_changes',
        where: [
          'key IN (${List.filled(visibleKeys.length, '?').join(',')})',
          if (from != null) 'changed_at >= ?',
          if (to != null) 'changed_at <= ?',
        ].join(' AND '),
        whereArgs: [
          ...visibleKeys,
          if (from != null) from.toUtc().toIso8601String(),
          if (to != null) to.toUtc().toIso8601String()
        ],
        orderBy: 'sequence DESC',
        limit: limit,
        offset: offset);
    return [
      for (final row in rows)
        if (_entries[row['key']]?.visible() ?? false) _decodeRow(row),
    ];
  }

  JsonMap _decodeRow(Map<String, Object?> row) => {
        'key': row['key'],
        'previousValue': jsonDecode(row['previous_value'] as String),
        'value': jsonDecode(row['value'] as String),
        'changedAt': row['changed_at'],
        'changedBy': row['changed_by'],
        'origin': row['origin'],
        'reason': row['reason'],
        'invocationId': row['invocation_id'],
        'revision': row['revision'],
      };

  Future<void> recordRuntime(String key, Object? previous, Object? value) {
    if (identical(Zone.current[_operation], this)) return Future.value();
    final invocation =
        Zone.current[SettingsAccess.invocationKey] as Invocation? ??
            Invocation(origin: 'gui');
    return _serial(() => _append(_entry(key), previous, value, invocation,
        Zone.current[SettingsAccess.reasonKey] as String?));
  }

  Future<void> drain() => _pending;
}

/// Classic persistence boundary. Absent on Web and in standalone Classic tests.
abstract final class SettingsAccess {
  static SettingsRegistry? registry;
  static final invocationKey = Object();
  static final reasonKey = Object();
  static bool get deferReload => Zone.current[invocationKey] != null;

  static Future<void> recordRuntime(
          String key, Object? previous, Object? value) =>
      registry?.recordRuntime(key, previous, value) ?? Future.value();

  static Future<void> recordRegisteredRuntime(String key, Object? previous, Object? value) =>
      registry?.contains(key) == true
          ? registry!.recordRuntime(key, previous, value)
          : Future.value();

  static Future<bool> persist(
      String storageKey, Future<bool> Function() perform,
      {bool migration = false}) {
    final current = registry;
    if (current == null) return perform();
    return current.persist(
        storageKey,
        perform,
        Zone.current[invocationKey] as Invocation? ??
            Invocation(origin: migration ? 'migration' : 'gui'),
        Zone.current[reasonKey] as String?);
  }
}
