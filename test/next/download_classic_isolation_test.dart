import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/next/downloads/download_library.dart';
import 'package:nipaplay/next/downloads/indexed_download_library.dart';
import 'package:nipaplay/next/headless/downloads.dart';
import 'package:nipaplay/next/ui/shell/next_ui_preference.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MediaFixture f;
  late ScanService scanner;
  late AppDownloadLibrary library;
  late TorrentDownloadService torrents;
  late String path;
  var classicScans = 0, classicReads = 0;
  final deviceHasNext = NextUiPreference.deviceHasNext;

  setUp(() async {
    NextUiPreference.deviceHasNext = () => true;
    SharedPreferences.setMockInitialValues({
      'labs_enable_agent_endpoint': true,
      'labs_use_next_interface': true,
    });
    classicScans = classicReads = 0;
    f = MediaFixture();
    await f.open();
    path = '${f.media.path}/completed.mkv';
    await File(path).writeAsString('verified download bytes');
    scanner = ScanService.forTesting(completedFilesProcessor: (_) async {
      classicScans++;
      return [];
    });
    torrents = TorrentDownloadService.forTesting(
      isIos: () => false,
      getDownloadsDirectory: () async => f.media,
      directoryExists: (_) async => true,
    );
    library = AppDownloadLibrary(torrents,
        media: () => f.service,
        scanner: scanner,
        refreshClassic: () async {},
        readClassic: (p) async {
          classicReads++;
          return WatchHistoryItem(
            filePath: p,
            animeName: 'Classic automatic guess',
            episodeTitle: 'Episode 1',
            animeId: 19566,
            episodeId: 7101,
            watchProgress: 0,
            lastPosition: 0,
            duration: 1000,
            lastWatchTime: DateTime.utc(2026, 10, 27),
          );
        });
  });
  tearDown(() async {
    scanner.dispose();
    await f.close();
    NextUiPreference.deviceHasNext = deviceHasNext;
  });

  test('Next registers downloads without Classic reads, matches or identities',
      () async {
    expect(await library.enabled, isTrue);
    expect(await library.registered(path), isNull);
    expect(await library.importFiles([path], f.media.path), isTrue);
    final entry = (await library.lookup(path))!;
    expect(entry['identificationPending'], isTrue);
    expect(entry['episodes'], isEmpty);
    expect(entry.containsKey('animeId'), isFalse);
    expect(classicScans, 0);
    expect(classicReads, 0);
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
    expect(await f.jobs.database.query('media_classic_observations'), isEmpty);
    expect(
        await f.jobs.database
            .query('media_entities', where: 'kind<>?', whereArgs: ['file']),
        isEmpty);
  });

  test('Next and Classic completion markers cannot suppress each other',
      () async {
    await library.markImported('next-task');
    await library.markImported('next-task');
    expect(await library.wasImported('next-task'), isTrue);
    expect(await torrents.loadAutoScannedCompletedTaskKeys(), isEmpty);
    await torrents.markAutoScannedCompletedTask('classic-task');
    expect(await library.wasImported('classic-task'), isFalse);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('labs_use_next_interface', false);
    expect(await library.wasImported('classic-task'), isTrue);
    expect(await library.wasImported('next-task'), isFalse);
    expect(await library.importFiles([path], f.media.path), isTrue);
    expect(classicScans, 1);
  });

  test('desktop and headless expose the real work ID after explicit binding',
      () async {
    final id = (await library.lookup(path))!['fileId'] as String;
    await f.call('media.identity.bind_batch', {
      'requestId': 'download-explicit-identity',
      'entries': [tmdbBinding(id)],
    });
    final desktop = (await library.lookup(path))!;
    final headless = (await HeadlessDownloadLibrary(f.service).lookup(path))!;
    expect(headless, desktop);
    final work = (desktop['workIds'] as List).single as String;
    expect((await f.identities.entity(work))['kind'], 'work');
    expect(desktop['identificationPending'], isFalse);
    expect(classicReads, 0);
    final indexed = IndexedDownloadLibrary(f.service);
    expect(await indexed.registered('${f.media.path}/absent.mkv'), isNull);
  });
}
