import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/lab_profile.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

void main() {
  test('profile names cannot escape their directory or namespace', () {
    expect(LabProfile.parseName(null), isNull);
    expect(LabProfile.parseName('x11test'), 'x11test');
    for (final name in [
      '',
      '../real',
      'a/b',
      'a:b',
      'a b',
      '.hidden',
      'X11test',
      '測試',
      'a' * 65
    ]) {
      expect(() => LabProfile.parseName(name), throwsArgumentError);
    }
  });

  test('concurrent preference updates persist without changing other files',
      () async {
    final root = await Directory.systemTemp.createTemp('nipa-lab-prefs-');
    addTearDown(() => root.delete(recursive: true));
    final real = File('${root.path}/real.json');
    await real.writeAsString('{"flutter.download_directory":"/Volumes/Media"}');
    final before = await real.readAsBytes();
    final store = LabPreferences(File('${root.path}/lab.json'));
    await Future.wait([
      store.setValue(
          'String', 'flutter.download_directory', '${root.path}/downloads'),
      store.setValue('Int', 'flutter.history_count', 12),
      store.setValue('StringList', 'flutter.folders', ['read-only']),
      store.setValue('String', 'native.window', 'keep'),
    ]);
    final reopened = LabPreferences(store.file);
    expect(await reopened.getAll(), {
      'flutter.download_directory': '${root.path}/downloads',
      'flutter.history_count': 12,
      'flutter.folders': ['read-only'],
    });
    await reopened.clearWithParameters(ClearParameters(
        filter: PreferencesFilter(
            prefix: 'flutter.', allowList: {'flutter.history_count'})));
    expect((await reopened.getAll()).containsKey('flutter.history_count'),
        isFalse);
    await reopened.clear();
    expect(await reopened.getAll(), isEmpty);
    expect(
        await reopened.getAllWithParameters(
            GetAllParameters(filter: PreferencesFilter(prefix: 'native.'))),
        {'native.window': 'keep'});
    expect(await real.readAsBytes(), before);
  });

  test('all path provider storage categories use the lab root', () async {
    final root = await Directory.systemTemp.createTemp('nipa-lab-paths-');
    addTearDown(() => root.delete(recursive: true));
    final paths = LabPaths(root.path);
    for (final path in await Future.wait([
      paths.getTemporaryPath(),
      paths.getApplicationSupportPath(),
      paths.getApplicationDocumentsPath(),
      paths.getApplicationCachePath(),
      paths.getLibraryPath(),
      paths.getDownloadsPath(),
    ])) {
      expect(path, startsWith('${root.path}/'));
      expect(Directory(path!).existsSync(), isTrue);
    }
  });
}
