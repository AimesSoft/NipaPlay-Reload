import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness_repository.dart';
import 'settings/registry.dart';
import 'repository_location.dart';

final class HarnessLocation extends ChangeNotifier implements RepositoryLocation {
  static const storageKey = 'next_harness_path';
  late final Future<void> ready = _load();
  String _path = defaultHarnessPath;
  String get path => _path;

  Future<void> _load() async {
    _path = (await SharedPreferences.getInstance()).getString(storageKey) ??
        defaultHarnessPath;
  }

  Future<void> setPath(Object? value) async {
    final path = expandHarnessPath(value as String);
    await ready;
    await (await SharedPreferences.getInstance()).setString(storageKey, path);
    _path = path;
    notifyListeners();
  }

  SettingEntry get setting => SettingEntry(
      key: 'next.harnessPath',
      title: 'Harness repository',
      description:
          'Absolute path to the user-owned harness. Creates a seed only when absent; existing files are never changed.',
      schema: const StringSchema(minLength: 1),
      defaultValue: defaultHarnessPath,
      scope: 'device',
      storageKey: storageKey,
      reader: 'HarnessLocation.path',
      writer: 'HarnessLocation.setPath',
      read: () async {
        await ready;
        return path;
      },
      write: setPath,
      validateValue: (value) {
        try {
          expandHarnessPath(value as String);
          return [];
        } on ArgumentError {
          return [
            const SchemaViolation('', 'Expected an absolute harness path.')
          ];
        }
      },
      decodeStorage: (value) => value ?? defaultHarnessPath);
}
