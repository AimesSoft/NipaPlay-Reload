import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('deferred startup migrates legacy history before opening a new database',
      () async {
    SharedPreferences.setMockInitialValues({});
    final root =
        await Directory.systemTemp.createTemp('history-legacy-startup-');
    StorageService.debugAppStorageDirectoryOverride = root;
    final item = WatchHistoryItem(
      filePath: 'https://example.invalid/episode.mp4',
      animeName: 'Legacy history',
      watchProgress: .5,
      lastPosition: 500,
      duration: 1000,
      lastWatchTime: DateTime(2026, 1, 1),
    );
    await File('${root.path}/watch_history.json')
        .writeAsString(jsonEncode([item.toJson()]));
    final database = WatchHistoryDatabase.instance;
    addTearDown(() async {
      await (await database.database).close();
      StorageService.debugAppStorageDirectoryOverride = null;
      await root.delete(recursive: true);
    });
    await database.migrateFromJson();
    final history = await database.getAllWatchHistory();
    expect(history, hasLength(1));
    expect(history.single.filePath, item.filePath);
    expect(history.single.lastPosition, 500);
  });
}
