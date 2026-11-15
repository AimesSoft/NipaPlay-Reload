import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/media_server_watch_history_sync.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/utils/playback_resume_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

WatchHistoryItem history(String id, {DateTime? watchedAt}) => WatchHistoryItem(
      filePath: 'jellyfin://$id',
      animeName: 'Anime',
      episodeTitle: 'Episode',
      animeId: 12,
      episodeId: 34,
      thumbnailPath: '/kept.png',
      videoHash: 'kept-hash',
      mediaKey: 'kept-key',
      lastPosition: 30000,
      duration: 120000,
      watchProgress: .25,
      lastWatchTime: watchedAt ?? DateTime.utc(2026, 11, 1),
    );

Map<String, Object> played(String id) => {
      'Id': id,
      'RunTimeTicks': 1200000000,
      'UserData': {
        'Played': true,
        'PlaybackPositionTicks': 0,
        'LastPlayedDate': '2026-11-15T00:00:00Z',
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'remote played mark clears continue position and preserves match metadata',
      () {
    final local = history('one');
    final merged = mergeMediaServerWatchHistory(
        local, (played('one')['UserData'] as Map).cast<String, dynamic>())!;
    expect(merged.watchProgress, 1);
    expect(merged.lastPosition, 0);
    expect(merged.animeId, 12);
    expect(merged.episodeId, 34);
    expect(merged.thumbnailPath, '/kept.png');
    expect(merged.videoHash, 'kept-hash');
    expect(merged.mediaKey, 'kept-key');
    expect(local.watchProgress, .25);
  });

  test(
      'manual played mark clears newer local progress without a new LastPlayedDate',
      () {
    final local = history('one', watchedAt: DateTime.utc(2026, 11, 16));
    final data = (played('one')['UserData'] as Map).cast<String, dynamic>();
    final merged = mergeMediaServerWatchHistory(local, data)!;
    expect(merged.watchProgress, 1);
    expect(merged.lastPosition, 0);
    expect(merged.lastWatchTime, local.lastWatchTime);
    expect(mergeMediaServerWatchHistory(merged, data), isNull);
    expect(
        mergeMediaServerWatchHistory(
            local, {...data}..remove('PlaybackPositionTicks')),
        isNull);
  });

  test(
      'remote resume progress recalculates fraction and preserves newer local play',
      () {
    final data = <String, dynamic>{
      'Played': false,
      'PlaybackPositionTicks': 600000000,
      'LastPlayedDate': '2026-11-15T00:00:00Z',
    };
    final merged = mergeMediaServerWatchHistory(history('one'), data)!;
    expect(merged.lastPosition, 60000);
    expect(merged.watchProgress, .5);
    expect(
        mergeMediaServerWatchHistory(
            history('one', watchedAt: DateTime.utc(2026, 11, 16)), data),
        isNull);
    expect(
        mergeMediaServerWatchHistory(history('one'), {'Played': true}), isNull);
  });

  test(
      'only histories bound to current server and user are requested, active item excluded',
      () async {
    var owner = 'profile-a/user-a';
    var session = 'session-a';
    final requests = <String>[];
    final sync = MediaServerWatchHistorySync(
      source: 'jellyfin',
      connection: () => MediaServerHistoryConnection(
          owner: owner, userId: 'user-a', session: session),
      request: (endpoint) async {
        requests.add(endpoint);
        return http.Response(
            jsonEncode({
              'Items': [played('mine')]
            }),
            200);
      },
    );
    await sync.bind('jellyfin://mine');
    await sync.bind('jellyfin://active');
    owner = 'profile-b/user-a';
    await sync.bind('jellyfin://other-server');
    owner = 'profile-a/user-b';
    await sync.bind('jellyfin://other-user');
    owner = 'profile-a/user-a';
    session =
        'new-address-and-token'; // Changing address does not change owner.
    final changes = await sync.refresh([
      history('mine'),
      history('active'),
      history('legacy-unbound'),
      history('other-server'),
      history('other-user'),
    ], activeItemId: () => 'active');
    expect(changes.map((item) => item.filePath), ['jellyfin://mine']);
    expect(requests, hasLength(1));
    final uri = Uri.parse(requests.single);
    expect(uri.path, '/Users/user-a/Items');
    expect(uri.queryParameters['Ids'], 'mine');
    expect(uri.queryParameters['Limit'], '100');
  });

  test('discard remote response when the connected account changes in flight',
      () async {
    var session = 'old';
    final response = Completer<http.Response>();
    final requested = Completer<void>();
    final sync = MediaServerWatchHistorySync(
      source: 'jellyfin',
      connection: () => MediaServerHistoryConnection(
          owner: 'profile/user', userId: 'user', session: session),
      request: (_) {
        requested.complete();
        return response.future;
      },
    );
    await sync.bind('jellyfin://one');
    final pending = sync.refresh([history('one')]);
    await requested.future;
    session = 'another-account';
    response.complete(http.Response(
        jsonEncode({
          'Items': [played('one')]
        }),
        200));
    expect(await pending, isEmpty);
  });

  test(
      'refresh uses one bounded batch and deleting history removes its binding',
      () async {
    final requests = <String>[];
    final sync = MediaServerWatchHistorySync(
      source: 'jellyfin',
      connection: () => const MediaServerHistoryConnection(
          owner: 'profile/user', userId: 'user', session: 'session'),
      request: (endpoint) async {
        requests.add(endpoint);
        return http.Response('{"Items":[]}', 200);
      },
    );
    final histories = List.generate(105, (i) => history('$i'));
    for (final item in histories) {
      await sync.bind(item.filePath);
    }
    await sync.refresh(histories);
    expect(requests, hasLength(1));
    expect(Uri.parse(requests.single).queryParameters['Ids']!.split(','),
        hasLength(100));
    await sync.forgetWhere((_) => true);
    await sync.refresh(histories);
    expect(requests, hasLength(1));
  });

  test(
      'legacy migration requires one saved matching account and never follows a new default',
      () async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, Object> profile(String id, String user) => {
          'id': id,
          'serverType': 'jellyfin',
          'userId': user,
        };
    await prefs.setString(
        'server_profiles', jsonEncode([profile('profile-a', 'user-a')]));
    await prefs.setString('jellyfin_current_profile_id', 'profile-a');
    var owner = 'profile-a/user-a';
    var profileId = 'profile-a';
    var userId = 'user-a';
    final ids = <String>[];
    final sync = MediaServerWatchHistorySync(
      source: 'jellyfin',
      connection: () => MediaServerHistoryConnection(
          owner: owner, userId: userId, session: owner, profileId: profileId),
      request: (endpoint) async {
        ids.add(Uri.parse(endpoint).queryParameters['Ids']!);
        return http.Response(
            jsonEncode({
              'Items': [played('legacy')]
            }),
            200);
      },
    );
    expect(await sync.refresh([history('legacy')]), hasLength(1));
    expect(prefs.getString('jellyfin_watch_history_owners_v1'),
        contains('legacy'));
    // The remaining old records must not be claimed when the default changes.
    owner = 'profile-b/user-b';
    profileId = 'profile-b';
    userId = 'user-b';
    await prefs.setString(
        'server_profiles', jsonEncode([profile('profile-b', 'user-b')]));
    await prefs.setString('jellyfin_current_profile_id', 'profile-b');
    expect(await sync.refresh([history('legacy'), history('still-unbound')]),
        isEmpty);
    expect(ids, hasLength(1));
    // Multiple saved profiles are ambiguous even with a selected default.
    await prefs.remove('jellyfin_watch_history_legacy_owner_v1');
    await prefs.setString(
        'server_profiles',
        jsonEncode(
            [profile('profile-a', 'user-a'), profile('profile-b', 'user-b')]));
    expect(await sync.refresh([history('still-unbound')]), isEmpty);
    expect(ids, hasLength(1));
  });

  test('completed local episodes restart at zero while incomplete ones resume',
      () {
    final local = history('episode');
    expect(local.resumePosition, 30000);
    expect(
        local
            .copyWith(watchProgress: 1, lastPosition: local.duration)
            .resumePosition,
        0);
    expect(
        local
            .copyWith(lastPosition: local.duration, watchProgress: .99)
            .resumePosition,
        0);
    expect(local.copyWith(watchProgress: 1, lastPosition: 0).resumePosition, 0);
  });

  test('new server rewatch position wins over an old completed route snapshot',
      () {
    final completedSnapshot =
        history('episode').copyWith(watchProgress: 1, lastPosition: 120000);
    final serverRewatch = mergeMediaServerWatchHistory(completedSnapshot, {
      'Played': false,
      'PlaybackPositionTicks': 600000000,
      'LastPlayedDate': '2026-11-16T00:00:00Z',
    })!;
    expect(
        historyResumePosition(
          path: serverRewatch.filePath,
          canonicalHistory: serverRewatch,
          initialHistory: completedSnapshot,
        ),
        60000);
    expect(
        historyResumePosition(
          path: completedSnapshot.filePath,
          canonicalHistory: completedSnapshot,
          initialHistory: history('episode'),
        ),
        0);
    expect(
        historyResumePosition(
          path: '/local.mp4',
          canonicalHistory: completedSnapshot.copyWith(filePath: '/local.mp4'),
        ),
        0);
  });

  test('server Played flag does not discard an in-progress rewatch position',
      () {
    final oldCompleted =
        history('episode').copyWith(watchProgress: 1, lastPosition: 0);
    final rewatch = mergeMediaServerWatchHistory(oldCompleted, {
      'Played': true,
      'PlaybackPositionTicks': 600000000,
      'LastPlayedDate': '2026-11-16T00:00:00Z',
    })!;
    expect(rewatch.watchProgress, .5);
    expect(rewatch.resumePosition, 60000);
  });

  test('a history opened while the server request runs is excluded on response',
      () async {
    String? active;
    final response = Completer<http.Response>();
    final requested = Completer<void>();
    final sync = MediaServerWatchHistorySync(
      source: 'jellyfin',
      connection: () => const MediaServerHistoryConnection(
          owner: 'profile/user', userId: 'user', session: 'session'),
      request: (_) {
        requested.complete();
        return response.future;
      },
    );
    await sync.bind('jellyfin://one');
    final pending = sync.refresh([history('one')], activeItemId: () => active);
    await requested.future;
    active = 'one';
    response.complete(http.Response(
        jsonEncode({
          'Items': [played('one')]
        }),
        200));
    expect(await pending, isEmpty);
  });

  test(
      'large ownership maps retain identities instead of evicting another account',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final owners = <String, String>{
      'jellyfin://foreign': 'other-account',
      for (var i = 0; i < 1000; i++) 'jellyfin://$i': 'current-account',
    };
    await prefs.setString(
        'jellyfin_watch_history_owners_v1', jsonEncode(owners));
    final sync = MediaServerWatchHistorySync(
      source: 'jellyfin',
      connection: () => const MediaServerHistoryConnection(
          owner: 'current-account', userId: 'user', session: 'session'),
      request: (_) async => http.Response('{"Items":[]}', 200),
    );
    await sync.bind('jellyfin://new');
    final persisted =
        jsonDecode(prefs.getString('jellyfin_watch_history_owners_v1')!) as Map;
    expect(persisted['jellyfin://foreign'], 'other-account');
    expect(persisted.length, 1002);
  });

  test('atomic remote write never overwrites progress saved during its request',
      () async {
    final root = await Directory.systemTemp.createTemp('remote-history-race-');
    StorageService.debugAppStorageDirectoryOverride = root;
    final database = WatchHistoryDatabase.instance;
    final db = await database.database;
    addTearDown(() async {
      await db.close();
      StorageService.debugAppStorageDirectoryOverride = null;
      await root.delete(recursive: true);
    });
    final original = history('one');
    await database.insertOrUpdateWatchHistory(original);
    final remote = mergeMediaServerWatchHistory(
        original, (played('one')['UserData'] as Map).cast<String, dynamic>())!;
    final newerLocal = original.copyWith(
        lastPosition: 90000,
        watchProgress: .75,
        lastWatchTime: DateTime.utc(2026, 11, 16));
    await database.insertOrUpdateWatchHistory(newerLocal);
    expect(await database.updateRemoteProgressIfUnchanged(original, remote),
        isFalse);
    expect(
        (await database.getHistoryByFilePath(original.filePath))!.lastPosition,
        90000);
    await database.insertOrUpdateWatchHistory(original);
    expect(await database.updateRemoteProgressIfUnchanged(original, remote),
        isTrue);
    final saved = (await database.getHistoryByFilePath(original.filePath))!;
    expect(saved.watchProgress, 1);
    expect(saved.episodeId, original.episodeId);
  });
}
