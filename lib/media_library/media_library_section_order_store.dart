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

  List<String> get sectionIds => List<String>.unmodifiable(_sectionIds);

  Future<bool> restore() async {
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
