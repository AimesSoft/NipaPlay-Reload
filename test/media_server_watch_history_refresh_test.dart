import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/jellyfin_playback_sync_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This integration uses a loopback server; bypass the widget binding's
  // intentional HTTP-400 stub so the production transport is exercised.
  HttpOverrides.global = null;

  test(
      'computer 50% history disappears from continue watching after tablet completes and app resumes',
      () async {
    final root =
        await Directory.systemTemp.createTemp('remote-history-resume-');
    StorageService.debugAppStorageDirectoryOverride = root;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${server.address.address}:${server.port}';
    final profile = ServerProfile(
      id: 'only-profile',
      serverName: 'Test',
      serverType: 'jellyfin',
      userId: 'the-user',
      accessToken: 'token',
      username: 'Test',
      addresses: [ServerAddress(id: 'lan', url: baseUrl, name: 'LAN')],
    );
    SharedPreferences.setMockInitialValues({
      'server_profiles': jsonEncode([profile.toJson()]),
      'jellyfin_current_profile_id': profile.id,
      // Reproduce the old per-device position cache too: canonical DB wins.
      'video_positions': jsonEncode({'jellyfin://episode-a': 60000}),
    });
    var played = false;
    var batches = 0;
    server.listen((request) async {
      if (request.uri.path != '/Users/the-user/Items') {
        request.response.statusCode = 404;
      } else {
        batches++;
        expect(request.uri.queryParameters['Ids'], 'episode-a');
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'Items': [
            {
              'Id': 'episode-a',
              'RunTimeTicks': 1200000000,
              'UserData': {
                'Played': played,
                'PlaybackPositionTicks': played ? 0 : 600000000,
                // Real Jellyfin retains this date when PlayedItems marks it
                // completed, even though the local exit is more recent.
                'LastPlayedDate': '2026-11-01T00:00:00Z',
              },
            }
          ],
        }));
      }
      await request.response.close();
    });
    final service = JellyfinService.instance
      ..isConnected = true
      ..currentProfile = profile
      ..userId = 'the-user'
      ..accessToken = 'token'
      ..serverUrl = baseUrl;
    final database = WatchHistoryDatabase.instance;
    final db = await database.database;
    final provider = WatchHistoryProvider();
    var resumedDuringInitialLoad = false;
    provider.addListener(() {
      if (provider.isLoaded && !resumedDuringInitialLoad) {
        resumedDuringInitialLoad = true;
        provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      }
    });
    addTearDown(() async {
      provider.dispose();
      JellyfinPlaybackSyncService().dispose();
      service
        ..isConnected = false
        ..currentProfile = null
        ..userId = null
        ..accessToken = null
        ..serverUrl = null;
      await server.close(force: true);
      await db.close();
      StorageService.debugAppStorageDirectoryOverride = null;
      await root.delete(recursive: true);
    });
    await database.insertOrUpdateWatchHistory(WatchHistoryItem(
      filePath: 'jellyfin://episode-a',
      animeName: 'Anime',
      watchProgress: .5,
      lastPosition: 60000,
      duration: 120000,
      lastWatchTime: DateTime.utc(2026, 11, 16),
    ));
    await provider.loadHistory();
    await _until(() => batches == 1);
    // Wait for the initial unchanged response to settle before simulating resume.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(provider.continueWatchingItems, hasLength(1));
    expect(
        (await SharedPreferences.getInstance())
            .getString('jellyfin_watch_history_owners_v1'),
        contains('episode-a'));
    played = true; // Tablet completed the episode on the same server account.
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _until(() => provider.history.single.watchProgress == 1);
    expect(provider.continueWatchingItems, isEmpty);
    final completed =
        (await database.getHistoryByFilePath('jellyfin://episode-a'))!;
    expect(completed.resumePosition, 0);
    expect(completed.lastPosition, 0);
    expect(batches, 2);
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline))
      fail('Timed out waiting for remote refresh');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
