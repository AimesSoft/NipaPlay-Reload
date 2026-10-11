import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/settings_storage.dart';

/// “使用 Next 界面”. Only takes effect while NipaPlay Next is enabled in Labs.
class NextUiPreference extends ChangeNotifier {
  NextUiPreference() {
    ready = _load();
  }

  static const key = 'labs_use_next_interface';

  late final Future<void> ready;
  bool _enabled = false;
  bool get enabled => _enabled;

  Future<void> _load() async {
    _enabled = await SettingsStorage.loadBool(key, defaultValue: false);
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) async {
    await ready;
    if (_enabled == enabled) return;
    _enabled = enabled;
    notifyListeners();
    await SettingsStorage.saveBool(key, enabled);
  }
}
