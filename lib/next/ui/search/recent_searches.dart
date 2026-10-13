import 'package:nipaplay/utils/settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/registry.dart';

/// Where recent search terms are kept.
abstract interface class RecentSearchStore {
  Future<List<String>> load();
  Future<void> save(List<String> terms);

  /// Removes the record itself, not just its terms.
  Future<void> clear();
}

/// This device's preferences, as the interface keeps its own
/// (`next_ui_preference.dart`): across restarts, per lab profile.
final class PreferenceRecentSearches implements RecentSearchStore {
  const PreferenceRecentSearches();

  static const key = 'next_ui_recent_searches';

  @override
  Future<List<String>> load() => SettingsStorage.loadStringList(key);

  @override
  Future<void> save(List<String> terms) =>
      SettingsStorage.saveStringList(key, terms);

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await SettingsAccess.persist(key, () => prefs.remove(key));
  }
}
