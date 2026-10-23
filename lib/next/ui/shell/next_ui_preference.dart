import 'package:flutter/foundation.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipa_harness/nipa_harness.dart';
import '../../settings/registry.dart';

/// “使用 Next 界面”. Only takes effect while NipaPlay Next is enabled in Labs.
class NextUiPreference extends ChangeNotifier {
  NextUiPreference() {
    attached = this;
    ready = _load();
  }

  static NextUiPreference? attached;
  static SettingEntry setting() => SettingEntry(
    key: key, title: '使用 Next 界面', description: '打开全新的首页与对话界面。',
    schema: const BooleanSchema(), defaultValue: false, storageKey: key,
    reader: 'lib/next/ui/shell/next_ui_preference.dart',
    writer: 'lib/next/ui/shell/next_ui_preference.dart#setEnabled',
    decodeStorage: (raw) => raw ?? false,
    read: () => SettingsStorage.loadBool(key),
    write: (value) async {
      final preference = attached;
      if (preference == null) {
        throw const Failure(FailureCode.unavailable, 'Interface preference is not attached.');
      }
      await preference.setEnabled(value as bool);
    },
  );

  static const key = 'labs_use_next_interface';

  /// Next's interface is what shows: on a desktop, with NipaPlay Next on in
  /// Labs ([nextEnabled]) and this [preference] on. Nipa runs only then;
  /// Classic has no Nipa (D1).
  static bool interfaceOpen(
          {required bool nextEnabled, required bool preference}) =>
      globals.isDesktop && nextEnabled && preference;

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
    await SettingsStorage.saveBool(key, enabled);
    _enabled = enabled;
    notifyListeners();
  }

  @override
  void dispose() {
    if (identical(attached, this)) attached = null;
    super.dispose();
  }
}
