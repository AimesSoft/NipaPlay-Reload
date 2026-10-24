import 'dart:async';

import 'package:file_selector/file_selector.dart' show openFile;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/file_picker_service.dart';

import '../../next_core.dart';
import '../../next_runtime.dart';
import '../../ui_data/host_settings.dart';
import 'login_requests.dart';
import 'settings_data.dart';

/// The real settings page data: the harness Actions as the person
/// (`origin: gui`), NextCore's memory, and [host] for what only this
/// device's person may change.
final class CoreSettingsData implements NextSettingsData {
  CoreSettingsData(this.core, this.runtime, this.logins,
      {NextHostSettings? host})
      : host = host ?? const UnavailableHostSettings();
  final NextCore core;
  final NextRuntime runtime;
  final LoginRequests logins;
  @override
  final NextHostSettings host;
  final _changes = StreamController<void>.broadcast();

  Invocation get _gui => Invocation(origin: 'gui');

  Future<JsonMap> _call(String action, JsonMap input) async {
    await core.ready;
    final outcome = await runtime.harness.invokeJson(action, input, _gui);
    return switch (outcome) {
      Completed(:final value) => value.toJson(),
      Failed(:final failure) => throw failure,
      NeedsDecision() => throw const Failure(
          FailureCode.unavailable, 'The action asked for a decision.'),
    };
  }

  @override
  Stream<void> get changes => _changes.stream;

  // —— 设置注册表 ——

  @override
  Future<List<UiSetting>> settings() async {
    final rows = <UiSetting>[];
    int? offset = 0;
    while (offset != null) {
      final page =
          await _call('settings.describe', {'offset': offset, 'limit': 500});
      rows.addAll([
        for (final row in (page['settings'] as List).cast<Map>())
          if (row['appliesNow'] != false) UiSetting.fromRow(row)
      ]);
      offset = (page['nextOffset'] as num?)?.toInt();
    }
    return rows;
  }

  @override
  Future<UiSetting> set(String key, Object? value) async {
    await _call('settings.set', {'key': key, 'value': value});
    return _one(key);
  }

  Future<UiSetting> _one(String key) async {
    final page = await _call('settings.describe', {
      'keys': [key]
    });
    return UiSetting.fromRow((page['settings'] as List).single as Map);
  }

  @override
  Future<void> reset(List<String> keys) async {
    if (keys.isEmpty) return;
    final result = await _call('settings.reset', {
      'changes': [
        for (final key in keys) {'key': key}
      ]
    });
    final failed = (result['results'] as List)
        .cast<Map>()
        .where((r) => r['status'] == 'failed');
    if (failed.isNotEmpty) {
      throw const Failure(FailureCode.unavailable, 'Some settings stayed.');
    }
  }

  @override
  Future<String?> pickPath({required bool directory}) async {
    if (directory) return FilePickerService().pickDirectory();
    return (await openFile())?.path;
  }

  // —— 账号 ——

  @override
  Future<List<UiAccount>> accounts() async {
    final result = await _call('accounts.status', {});
    return [
      for (final row in (result['accounts'] as List).cast<Map>())
        UiAccount(
          provider: row['provider'] as String,
          loggedIn: row['loggedIn'] == true,
          username: row['username'] as String?,
        )
    ];
  }

  @override
  Future<void> login(String provider) async {
    logins.expect(provider == 'dandanplay' ? '弹弹play' : 'Bangumi');
    await _call('accounts.login', {'provider': provider});
    unawaited(_watchJobs());
  }

  @override
  Future<void> logout(String provider) async {
    await _call('accounts.logout', {'provider': provider});
    _changes.add(null);
  }

  @override
  Future<UiBangumiSync> bangumiSync() async {
    final r = await _call('accounts.bangumi.sync_status', {});
    final status = r['lastSyncStatus'];
    return UiBangumiSync(
      last: DateTime.tryParse('${r['lastSyncTime']}')?.toLocal(),
      works: (r['syncedItemsCount'] as num?)?.toInt() ?? 0,
      failed: status is Map ? (status['errorCount'] as num?)?.toInt() ?? 0 : 0,
    );
  }

  @override
  Future<void> syncBangumi({bool full = false}) async {
    await _call('accounts.bangumi.sync', {if (full) 'full': true});
    unawaited(_watchJobs());
  }

  /// Logins and syncs run as tasks: the page hears when they end.
  Future<void> _watchJobs() async {
    for (var i = 0; i < 120; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final running = (await core.engine.list())
          .where((j) =>
              !j.state.isTerminal &&
              (j.type.startsWith('accounts.') ||
                  j.type.startsWith('media.sources.')))
          .isNotEmpty;
      if (!running) break;
    }
    _changes.add(null);
  }

  // —— 媒体来源 ——

  @override
  Future<List<UiMediaSource>> sources() async {
    final result = await _call('media.sources.list', {});
    return [
      for (final row in (result['sources'] as List).cast<Map>())
        UiMediaSource.fromRow(row)
    ];
  }

  @override
  Future<UiMediaSource> addSource(UiSourceDraft draft) async {
    final result = await _call(
        'media.sources.add', {'type': draft.type, ...draft.toJson()});
    _changes.add(null);
    return UiMediaSource.fromRow(result['source'] as Map);
  }

  @override
  Future<UiMediaSource> updateSource(
      String sourceId, UiSourceDraft draft) async {
    final result = await _call(
        'media.sources.update', {'sourceId': sourceId, ...draft.toJson()});
    _changes.add(null);
    return UiMediaSource.fromRow(result['source'] as Map);
  }

  @override
  Future<void> removeSource(String sourceId) async {
    await _call('media.sources.remove', {'sourceId': sourceId});
    _changes.add(null);
  }

  @override
  Future<UiSourceLogin> loginSource(String sourceId) async {
    final source =
        (await sources()).where((s) => s.sourceId == sourceId).firstOrNull;
    if (source != null) logins.expect(source.name);
    final r = await _call(
        'media.sources.login', {'sourceId': sourceId, 'method': 'auto'});
    unawaited(_watchJobs());
    final approval = r['approval'];
    return UiSourceLogin(
      code: (approval is Map ? approval['code'] : r['code']) as String?,
      connected: r['connected'] == true,
    );
  }

  @override
  Future<UiSourceCheck> checkSource(String sourceId) async {
    try {
      final r = await _call('media.sources.check', {'sourceId': sourceId});
      _changes.add(null);
      final ok = r['connected'] == true && r['authenticated'] != false;
      return UiSourceCheck(
          ok: ok,
          message: ok
              ? null
              : r['connected'] == true
                  ? '需要登录'
                  : '连不上');
    } on Failure {
      return const UiSourceCheck(ok: false, message: '连不上');
    }
  }

  @override
  Future<List<UiSourceLibrary>> libraries(String sourceId) async {
    final r = await _call('media.sources.libraries', {'sourceId': sourceId});
    return [
      for (final row in (r['libraries'] as List).cast<Map>())
        UiSourceLibrary(
            id: '${row['id']}',
            name: '${row['name']}',
            kind: row['kind'] as String?)
    ];
  }

  @override
  Future<void> selectLibraries(String sourceId, List<String> ids) async {
    await _call(
        'media.sources.select', {'sourceId': sourceId, 'libraries': ids});
    _changes.add(null);
  }

  // —— 记忆 ——

  @override
  Future<List<UiMemoryFile>> memories() async {
    await core.ready;
    final files = <UiMemoryFile>[];
    for (final row in await core.memory.list()) {
      final path = row['path'] as String;
      String? title;
      if (path != 'preferences.md' && path != 'MEMORY.md') {
        final content = (await core.memory.read(path))['content'] as String;
        title = memoryHeading(content);
      }
      files.add(UiMemoryFile(
          path: path,
          bytes: (row['bytes'] as num?)?.toInt() ?? 0,
          revision: row['revision'] as String?,
          title: title));
    }
    return files;
  }

  @override
  Future<UiMemoryDoc> memory(String path) async {
    await core.ready;
    final r = await core.memory.read(path);
    return UiMemoryDoc(
        path: path,
        content: r['content'] as String,
        revision: r['revision'] as String);
  }

  @override
  Future<void> editMemory(UiMemoryDoc doc, String content) async {
    await core.memory.edit(doc.path, content, doc.revision, _gui);
    _changes.add(null);
  }

  @override
  Future<void> forgetMemory(UiMemoryDoc doc) async {
    await core.memory.delete(doc.path, doc.revision, _gui);
    _changes.add(null);
  }

  /// Nipa's memory writes are recorded in the same database the UI data
  /// watches.
  @override
  Stream<void> get memoryChanges =>
      Stream.fromFuture(core.ready).asyncExpand((_) => core.uiData.changes);

  // —— 关于 ——

  @override
  Future<UiAbout> about() async {
    try {
      final r = await _call('app.instance', {});
      return UiAbout(version: r['version'] as String?);
    } on Failure {
      return const UiAbout();
    }
  }

  void dispose() => _changes.close();
}

/// The first Markdown heading of a memory note, if it has one.
String? memoryHeading(String content) {
  for (final line in content.split('\n')) {
    final match = RegExp(r'^#{1,3}\s+(.+?)\s*$').firstMatch(line);
    if (match != null) return match.group(1);
    if (line.trim().isNotEmpty) return null;
  }
  return null;
}

/// Until the host's own settings arrive (X52): nothing can be read or
/// changed from here.
final class UnavailableHostSettings implements NextHostSettings {
  const UnavailableHostSettings();

  static const _problem = '暂不可用';

  @override
  Future<UiModelSetup> model() async =>
      const UiModelSetup(source: UiModelSource.codex, problem: _problem);

  @override
  Future<void> setModel(UiModelChoice choice) async =>
      throw const Failure(FailureCode.unavailable, _problem);

  @override
  Future<UiModelCheck> checkModel() async =>
      const UiModelCheck(ok: false, message: _problem);

  @override
  Future<UiModelChoice?> codexModel() async => null;

  @override
  Future<void> importCodexModel() async =>
      throw const Failure(FailureCode.unavailable, _problem);

  @override
  Future<UiMeshSetup> mesh() async =>
      const UiMeshSetup(available: false, problem: _problem);

  @override
  Future<void> setMesh(UiMeshChoice choice) async =>
      throw const Failure(FailureCode.unavailable, _problem);

  @override
  Future<bool> remotePrograms() async => false;

  @override
  Future<void> setRemotePrograms(bool allowed) async =>
      throw const Failure(FailureCode.unavailable, _problem);

  @override
  Stream<void> get changes => const Stream.empty();
}
