import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/danmaku_matching_service.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('danmaku matching access', () {
    test('logged-out users are rejected before a match request is created',
        () async {
      SharedPreferences.setMockInitialValues({});
      await expectLater(
        DanmakuMatchingService.instance.matchVideo(
          fileName: 'episode.mkv',
          fileHash: '00000000000000000000000000000000',
          fileSize: 1024,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('third-party matching is accessible without a Dandanplay account',
        () async {
      SharedPreferences.setMockInitialValues({
        'dandanplay_server_url': 'https://third-party.example/danmaku',
      });
      await DanmakuMatchingService.instance.ensureAccess();
      expect(await DanmakuMatchingService.instance.canAccess(), isTrue);
    });

    test('all app matching callers use the shared matching facade', () {
      final directMatchImplementations = <String>[];
      final directVideoInfoCallers = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        if (source.contains('/api/v2/match')) {
          directMatchImplementations.add(entity.path);
        }
        if (source.contains('DandanplayService.getVideoInfo(') &&
            !entity.path.endsWith('danmaku_matching_service.dart')) {
          directVideoInfoCallers.add(entity.path);
        }
      }

      expect(
        directMatchImplementations.map((path) => path.split('/').last).toSet(),
        {
          'dandanplay_service_io.dart',
          'dandanplay_service_stub.dart',
        },
      );
      expect(directVideoInfoCallers, isEmpty);

      for (final path in [
        'lib/services/emby_dandanplay_matcher.dart',
        'lib/services/jellyfin_dandanplay_matcher.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(source, contains('DanmakuMatchingService.instance'));
        expect(source, isNot(contains('DandanplayService.matchVideo(')));
        expect(source, isNot(contains('DandanplayService.searchAnime(')));
        expect(source, isNot(contains('/api/v2/search/episodes')));
      }
    });
  });

  group('Dandanplay gateway migration', () {
    test('only the guarded gateway is offered as a built-in server', () {
      expect(
        NetworkSettings.getAvailableServers().map((server) => server['url']),
        [NetworkSettings.primaryServer],
      );
    });

    test('uses the NipaPlay gateway by default', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        await NetworkSettings.getDandanplayServer(),
        NetworkSettings.primaryServer,
      );
    });

    for (final legacyUrl in [
      'https://api.dandanplay.net',
      'https://api.dandanplay.net/',
      'http://139.224.252.88:16001',
      'http://139.224.252.88:16001/',
    ]) {
      test('migrates legacy server $legacyUrl to the gateway', () async {
        SharedPreferences.setMockInitialValues({
          'dandanplay_server_url': legacyUrl,
        });
        expect(
          await NetworkSettings.getDandanplayServer(),
          NetworkSettings.primaryServer,
        );
      });
    }
  });
}
