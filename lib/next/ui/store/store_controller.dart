import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/gui_calls.dart';
import '../data/rika_store.dart';

/// What the store page shows and does: the list (official, from npm, the
/// runtime's own extensions), what is being installed, what failed, and
/// whether something changed since 梨花 last started.
final class StoreController extends ChangeNotifier {
  StoreController(this.store);
  final NextRikaStore store;

  UiStore? data;
  Map codex = const {};
  String? failed;
  bool refreshing = false;

  /// Something changed since 梨花 started; it takes effect when she starts
  /// again.
  bool pending = false;
  bool applying = false;
  String? applyResult;
  final busy = <String>{};
  final errors = <String, String>{};
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load({bool refresh = false}) async {
    if (refresh) {
      refreshing = true;
      _notify();
    }
    try {
      final read = await store.read(refresh: refresh);
      final listed = await store
          .codexCatalog()
          .timeout(const Duration(seconds: 5))
          .catchError((Object _) => <String, Object?>{});
      data = read;
      codex = listed;
      failed = null;
    } catch (error) {
      failed = callFailure(error);
    }
    refreshing = false;
    _notify();
  }

  Future<void> run(String key, Future<void> Function() action) async {
    busy.add(key);
    errors.remove(key);
    _notify();
    try {
      await action();
      pending = true;
    } catch (error) {
      errors[key] = callFailure(error);
    }
    await load();
    busy.remove(key);
    _notify();
  }

  Future<void> install(UiStoreItem item) =>
      run(item.id, () => store.install(id: item.id, version: item.version));

  Future<void> remove(String id) => run(id, () => store.remove(id));

  Future<void> setEnabled(UiStoreItem item, bool on) =>
      run(item.id, () => store.setEnabled(item.id, on));

  Future<void> installWeb(String version) =>
      run('dsh-web', () => store.install(id: 'dsh-web', version: version));

  Future<void> addMarketplace(String source) =>
      run('codex-market', () => store.addMarketplace(source));

  Future<void> installCodex(String id, String marketplace, String plugin) =>
      run(id, () => store.installCodex(marketplace, plugin));

  Future<void> removeCodex(String id) => run(id, () => store.removeCodex(id));

  Future<JsonMapLike> resolveNpm(String spec) => store.resolveNpm(spec);

  Future<void> installNpm(
      {required String npm,
      required String version,
      required String kind,
      required String integrity}) async {
    busy.add('npm');
    errors.remove('npm');
    _notify();
    try {
      await store.install(
          npm: npm, version: version, kind: kind, integrity: integrity);
      pending = true;
    } catch (error) {
      errors['npm'] = callFailure(error);
    }
    await load();
    busy.remove('npm');
    _notify();
  }

  /// Restarts 梨花 so what changed takes effect.
  Future<void> apply() async {
    applying = true;
    applyResult = null;
    _notify();
    try {
      final result = await store.apply();
      if (result['restarted'] == true) {
        pending = false;
        final eventError = result['eventError'];
        if (eventError != null) applyResult = '已重启，但跟进事件发布失败：$eventError';
      } else {
        applyResult = result['status'] == 'notRun'
            ? '没有重启：${result['reason']}'
            : '重启失败：${result['error']}';
      }
    } catch (error) {
      applyResult = callFailure(error);
    }
    applying = false;
    _notify();
    await load();
  }
}

typedef JsonMapLike = Map<String, Object?>;
