import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'concurrent initialization shares one future and failed initialization can retry',
      () async {
    SharedPreferences.setMockInitialValues(
        {SettingsKeys.torrentDownloadDirectory: '/downloads'});
    final gate = Completer<void>();
    var calls = 0;
    final service = TorrentDownloadService.forTesting(
      isIos: () => false,
      getDownloadsDirectory: () async => Directory('/downloads'),
      directoryExists: (_) async => true,
      initializeSession: (_) async {
        calls++;
        if (calls == 1) {
          await gate.future;
          throw StateError('initialization failed');
        }
      },
    );
    final first = expectLater(service.initialize(), throwsStateError);
    final second = expectLater(service.initialize(), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    gate.complete();
    await Future.wait([first, second]);
    await service.initialize();
    await service.initialize();
    expect(calls, 2);
  });

  group('TorrentDownloadService.getDownloadDirectory', () {
    const staleDirectory = '/old/Application/CONTAINER/Documents/downloads';
    const currentDirectory =
        '/current/Application/CONTAINER/Documents/downloads';

    test('repairs a stale saved iOS sandbox directory', () async {
      SharedPreferences.setMockInitialValues({
        SettingsKeys.torrentDownloadDirectory: staleDirectory,
        SettingsKeys.torrentRecentDownloadDirectories: <String>[
          staleDirectory,
          '/another/downloads',
        ],
        SettingsKeys.torrentRecentDownloadDirectoriesMigrated: true,
      });
      final service = TorrentDownloadService.forTesting(
        isIos: () => true,
        getDownloadsDirectory: () async => Directory(currentDirectory),
        directoryExists: (_) async => false,
      );

      final result = await service.getDownloadDirectory();

      expect(result, currentDirectory);
      expect(
        await SettingsStorage.loadString(
          SettingsKeys.torrentDownloadDirectory,
        ),
        currentDirectory,
      );
      expect(
        await SettingsStorage.loadStringList(
          SettingsKeys.torrentRecentDownloadDirectories,
        ),
        <String>[currentDirectory, '/another/downloads'],
      );
    });

    test('keeps an existing saved iOS directory', () async {
      SharedPreferences.setMockInitialValues({
        SettingsKeys.torrentDownloadDirectory: currentDirectory,
      });
      var requestedDefaultDirectory = false;
      final service = TorrentDownloadService.forTesting(
        isIos: () => true,
        getDownloadsDirectory: () async {
          requestedDefaultDirectory = true;
          return Directory('/unused');
        },
        directoryExists: (_) async => true,
      );

      expect(await service.getDownloadDirectory(), currentDirectory);
      expect(requestedDefaultDirectory, isFalse);
    });

    test('does not reset missing saved directories on other platforms',
        () async {
      SharedPreferences.setMockInitialValues({
        SettingsKeys.torrentDownloadDirectory: staleDirectory,
      });
      var checkedDirectory = false;
      final service = TorrentDownloadService.forTesting(
        isIos: () => false,
        getDownloadsDirectory: () async => Directory('/unused'),
        directoryExists: (_) async {
          checkedDirectory = true;
          return false;
        },
      );

      expect(await service.getDownloadDirectory(), staleDirectory);
      expect(checkedDirectory, isFalse);
    });
  });
}
