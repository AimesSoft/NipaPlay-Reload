import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';

import '../capabilities/family_descriptions.dart';
import '../util/slicer.dart';

/// Facts about how the capability catalogue differs from the one the previous
/// launch had. It states what changed; what to do about it is not its to say.
///
/// Per family (the part of an action id before the first dot) it keeps a hash
/// of the family description text and, for each action, a hash of its id,
/// effect, description and input schema. The snapshot and the latest change
/// records live in one small JSON file next to next.db, so nothing in the
/// database schema (and nothing Classic reads) is touched.
final class CapabilityCatalogChanges {
  CapabilityCatalogChanges(this.file, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final File file;
  final DateTime Function() _now;

  /// Called after a change record is stored, so a running conversation can be
  /// told its memory block is out of date.
  void Function()? onRecorded;

  static const keptRecords = 10;
  static const shownRecords = 2;
  static const shownWindow = Duration(days: 7);

  /// Compare [catalog] with the stored snapshot, store the new one, and return
  /// the change record if there is one. The first launch only stores.
  Future<JsonMap?> observe(Iterable<ActionSpec> catalog,
      {String? appVersion, String? build}) async {
    final snapshot = await _snapshot(catalog);
    final fingerprint = _hash(jsonEncode(_sorted(snapshot)));
    final stored = await _read();
    final previous = stored?['families'];
    if (previous is! Map) {
      await _write(fingerprint, snapshot, const []);
      return null;
    }
    if (stored!['fingerprint'] == fingerprint) return null;
    final families = _diff(previous.cast<String, Object?>(), snapshot);
    final records = [
      for (final r in (stored['changes'] as List? ?? const []))
        if (r is Map) r.cast<String, Object?>()
    ];
    JsonMap? record;
    if (families.isNotEmpty) {
      record = {
        'at': _now().toUtc().toIso8601String(),
        if (appVersion != null) 'appVersion': appVersion,
        if (build != null) 'build': build,
        'families': families,
      };
      records.add(record);
    }
    final kept = records.length > keptRecords
        ? records.sublist(records.length - keptRecords)
        : records;
    await _write(fingerprint, snapshot, kept);
    if (record != null) onRecorded?.call();
    return record;
  }

  /// The newest records, newest first, that are at most a week old.
  Future<List<JsonMap>> recent() async {
    final stored = await _read();
    final cutoff = _now().toUtc().subtract(shownWindow);
    final rows = [
      for (final r in (stored?['changes'] as List? ?? const []))
        if (r is Map &&
            DateTime.tryParse('${r['at']}')?.isAfter(cutoff) == true)
          r.cast<String, Object?>()
    ];
    return rows.reversed.take(shownRecords).toList();
  }

  /// One line per record for the memory block; only facts.
  static String describe(JsonMap record) {
    final at = '${record['at']}'.split('T').first;
    final version = [
      if (record['appVersion'] != null) '${record['appVersion']}',
      if (record['build'] != null) '+${record['build']}',
    ].join();
    final parts = <String>[];
    String ids(Object? value) {
      final list = (value as List).cast<String>();
      return list.length <= 8
          ? list.join('、')
          : '${list.take(8).join('、')} 等 ${list.length} 个';
    }

    (record['families'] as Map).forEach((family, raw) {
      final change = (raw as Map).cast<String, Object?>();
      final bits = <String>[
        if (change['familyAdded'] == true) '新增能力族',
        if (change['familyRemoved'] == true) '能力族已移除',
        if ((change['added'] as List).isNotEmpty) '新增动作 ${ids(change['added'])}',
        if ((change['removed'] as List).isNotEmpty)
          '移除动作 ${ids(change['removed'])}',
        if ((change['changed'] as List).isNotEmpty)
          '动作说明或输入有改动 ${ids(change['changed'])}',
        if (change['descriptionChanged'] == true) '族说明有改动',
      ];
      parts.add('$family 族：${bits.join('；')}');
    });
    return '$at${version.isEmpty ? '' : ' NipaPlay $version'}：${parts.join('；')}';
  }

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString().substring(0, 16);

  static Object? _sorted(Object? value) => switch (value) {
        Map() => {
            for (final key in (value.keys.map((k) => '$k').toList()..sort()))
              key: _sorted(value[key])
          },
        List() => [for (final item in value) _sorted(item)],
        _ => value,
      };

  /// {family: {description: hash, actions: {id: hash}}}
  ///
  /// Hashing every action's schema is a few hundred small pieces of work, done
  /// in turns so the interface keeps drawing while it starts.
  static Future<Map<String, Object?>> _snapshot(
      Iterable<ActionSpec> catalog) async {
    final byFamily = <String, Map<String, String>>{};
    final slice = Slicer();
    for (final spec in catalog) {
      await slice();
      final family = spec.id.split('.').first;
      byFamily.putIfAbsent(family, () => {})[spec.id] = _hash(jsonEncode(_sorted({
        'id': spec.id,
        'effect': spec.effect.name,
        'description': spec.description,
        'input': spec.input.toJsonSchema(),
      })));
    }
    return {
      for (final family in byFamily.keys)
        family: {
          'description': _hash([
            for (final key in (familyFacts.keys
                .where((k) => k == family || k.startsWith('$family.'))
                .toList()
              ..sort()))
              '$key\n${familyFacts[key]}'
          ].join('\n\n')),
          'actions': byFamily[family],
        }
    };
  }

  static Map<String, Object?> _diff(
      Map<String, Object?> before, Map<String, Object?> after) {
    final result = <String, Object?>{};
    for (final family in {...before.keys, ...after.keys}.toList()..sort()) {
      final old = (before[family] as Map?)?.cast<String, Object?>();
      final now = (after[family] as Map?)?.cast<String, Object?>();
      final oldActions = ((old?['actions'] as Map?) ?? const {}).cast<String, Object?>();
      final newActions = ((now?['actions'] as Map?) ?? const {}).cast<String, Object?>();
      final added = (newActions.keys.where((id) => !oldActions.containsKey(id)).toList()..sort());
      final removed = (oldActions.keys.where((id) => !newActions.containsKey(id)).toList()..sort());
      final changed = (newActions.keys
          .where((id) => oldActions.containsKey(id) && oldActions[id] != newActions[id])
          .toList()
        ..sort());
      final description =
          old != null && now != null && old['description'] != now['description'];
      if (added.isEmpty && removed.isEmpty && changed.isEmpty && !description) {
        continue;
      }
      result[family] = {
        if (old == null) 'familyAdded': true,
        if (now == null) 'familyRemoved': true,
        'added': added,
        'removed': removed,
        'changed': changed,
        'descriptionChanged': description,
      };
    }
    return result;
  }

  Future<Map<String, Object?>?> _read() async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } on Object {
      // Missing or damaged: treated like a first launch.
      return null;
    }
  }

  Future<void> _write(String fingerprint, Map<String, Object?> families,
      List<Object?> changes) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'fingerprint': fingerprint,
          'families': families,
          'changes': changes,
        }),
        flush: true);
    await temporary.rename(file.path);
  }
}
