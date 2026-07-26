import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/settings_storage.dart';

typedef MediaLibrarySectionOrderLoader = Future<List<String>> Function();
typedef MediaLibrarySectionOrderSaver = Future<void> Function(
  List<String> sectionIds,
);

class MediaLibrarySectionOrderStore {
  MediaLibrarySectionOrderStore({
    MediaLibrarySectionOrderLoader? load,
    MediaLibrarySectionOrderSaver? save,
  })  : _load = load ?? _loadFromSettings,
        _save = save ?? _saveToSettings;

  final MediaLibrarySectionOrderLoader _load;
  final MediaLibrarySectionOrderSaver _save;

  List<String> _sectionIds = const <String>[];
  int _revision = 0;
  Future<void> _saveQueue = Future<void>.value();
  Future<bool>? _pendingRestore;

  List<String> get sectionIds => List<String>.unmodifiable(_sectionIds);

  Future<bool> restore() {
    final pending = _pendingRestore;
    if (pending != null) return pending;

    late final Future<bool> restoreFuture;
    restoreFuture = _restore().whenComplete(() {
      if (identical(_pendingRestore, restoreFuture)) {
        _pendingRestore = null;
      }
    });
    _pendingRestore = restoreFuture;
    return restoreFuture;
  }

  Future<bool> _restore() async {
    final revisionAtStart = _revision;
    final saved = await _load();
    if (_revision != revisionAtStart) return false;

    _sectionIds = _normalize(saved);
    return true;
  }

  Future<void> update(List<String> sectionIds) {
    _revision++;
    _sectionIds = _normalize(sectionIds);
    final snapshot = List<String>.unmodifiable(_sectionIds);
    final persistence = _saveQueue.then((_) => _save(snapshot));
    _saveQueue = persistence.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return persistence;
  }

  Future<void> updateVisible(List<String> visibleSectionIds) async {
    await _pendingRestore;
    final visible = _normalize(visibleSectionIds);
    final visibleSet = visible.toSet();
    final orderedVisible = visible.iterator;
    final merged = <String>[];
    for (final id in _sectionIds) {
      if (!visibleSet.contains(id)) {
        merged.add(id);
      } else if (orderedVisible.moveNext()) {
        merged.add(orderedVisible.current);
      }
    }
    while (orderedVisible.moveNext()) {
      merged.add(orderedVisible.current);
    }
    await update(merged);
  }

  static List<String> _normalize(Iterable<String> sectionIds) {
    final normalized = <String>{};
    for (final id in sectionIds) {
      final value = id.trim();
      if (value.isNotEmpty) normalized.add(value);
    }
    return normalized.toList();
  }

  static Future<List<String>> _loadFromSettings() {
    return SettingsStorage.loadStringList(
      SettingsKeys.mediaLibrarySectionOrder,
    );
  }

  static Future<void> _saveToSettings(List<String> sectionIds) {
    return SettingsStorage.saveStringList(
      SettingsKeys.mediaLibrarySectionOrder,
      sectionIds,
    );
  }
}
