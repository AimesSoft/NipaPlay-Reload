import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HomeSectionType {
  todaySeries,
  randomRecommendations,
  continueWatching,
  remoteLibraries,
  localLibrary,
}

extension HomeSectionTypeExtension on HomeSectionType {
  String get storageKey {
    switch (this) {
      case HomeSectionType.todaySeries:
        return 'today_series';
      case HomeSectionType.randomRecommendations:
        return 'random_recommendations';
      case HomeSectionType.continueWatching:
        return 'continue_watching';
      case HomeSectionType.remoteLibraries:
        return 'remote_libraries';
      case HomeSectionType.localLibrary:
        return 'local_library';
    }
  }

  String get title {
    switch (this) {
      case HomeSectionType.todaySeries:
        return '今日新番';
      case HomeSectionType.randomRecommendations:
        return '随机推荐';
      case HomeSectionType.continueWatching:
        return '继续播放';
      case HomeSectionType.remoteLibraries:
        return '远程媒体库';
      case HomeSectionType.localLibrary:
        return '本地媒体库';
    }
  }

  static HomeSectionType? fromStorageKey(String key) {
    for (final value in HomeSectionType.values) {
      if (value.storageKey == key) {
        return value;
      }
    }
    return null;
  }
}

class HomeSectionsSettingsProvider extends ChangeNotifier {
  static const String _orderKey = 'home_sections_order';
  static const String _disabledKey = 'home_sections_disabled';

  static const List<HomeSectionType> defaultOrder = [
    HomeSectionType.todaySeries,
    HomeSectionType.randomRecommendations,
    HomeSectionType.continueWatching,
    HomeSectionType.remoteLibraries,
    HomeSectionType.localLibrary,
  ];

  late List<HomeSectionType> _order;
  late Map<HomeSectionType, bool> _enabled;

  HomeSectionsSettingsProvider() {
    _order = List<HomeSectionType>.from(defaultOrder);
    _enabled = {
      for (final type in defaultOrder) type: true,
    };
    _loadSettings();
  }

  List<HomeSectionType> get orderedSections => List.unmodifiable(_order);

  bool isSectionEnabled(HomeSectionType type) => _enabled[type] ?? true;

  Future<void> setSectionEnabled(HomeSectionType type, bool value) async {
    if (_enabled[type] == value) {
      return;
    }
    _enabled[type] = value;
    notifyListeners();
    await _saveEnabled();
  }

  Future<void> reorderSections(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _order.length) {
      return;
    }
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 || newIndex >= _order.length) {
      return;
    }
    final moved = _order.removeAt(oldIndex);
    _order.insert(newIndex, moved);
    notifyListeners();
    await _saveOrder();
  }

  Future<void> restoreDefaults() async {
    _order = List<HomeSectionType>.from(defaultOrder);
    _enabled = {
      for (final type in defaultOrder) type: true,
    };
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _orderKey,
      _order.map((type) => type.storageKey).toList(),
    );
    await prefs.setStringList(_disabledKey, const []);
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedOrder = prefs.getStringList(_orderKey);
      final storedDisabled = prefs.getStringList(_disabledKey) ?? const [];

      if (storedOrder != null && storedOrder.isNotEmpty) {
        final resolvedOrder = <HomeSectionType>[];
        for (final key in storedOrder) {
          final type = HomeSectionTypeExtension.fromStorageKey(key);
          if (type != null && !resolvedOrder.contains(type)) {
            resolvedOrder.add(type);
          }
        }
        for (final type in defaultOrder) {
          if (!resolvedOrder.contains(type)) {
            resolvedOrder.add(type);
          }
        }
        _order = resolvedOrder;
      }

      _enabled = {
        for (final type in defaultOrder)
          type: !storedDisabled.contains(type.storageKey),
      };
      notifyListeners();
    } catch (_) {
    }
  }

  Future<void> _saveOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _orderKey,
        _order.map((type) => type.storageKey).toList(),
      );
    } catch (_) {
    }
  }

  Future<void> _saveEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final disabled = _enabled.entries
          .where((entry) => entry.value == false)
          .map((entry) => entry.key.storageKey)
          .toList();
      await prefs.setStringList(_disabledKey, disabled);
    } catch (_) {
    }
  }
}
