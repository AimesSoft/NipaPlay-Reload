@Tags(['performance'])
@Timeout(Duration(minutes: 15))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/service.dart';
import 'package:nipaplay/next/danmaku/store.dart';
import 'package:nipaplay/next/headless/ports.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/mesh/library_worker.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';
import 'support/big_profile.dart';
import 'support/platform.dart';

/// #1125: how long the first index build of a cold start takes, the time
/// the library page used to stay empty. Works with files on disk, their
/// episodes, provider bindings and metadata snapshots, as a real library.
/// `flutter test --no-pub --tags performance test/next/library_build_benchmark_test.dart`
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (works, episodes) in [(29, 15), (300, 12)]) {
    test('cold index build of $works works × $episodes episodes', () async {
      sqfliteFfiInit();
      final temp = await Directory.systemTemp.createTemp('library-bench-');
      addTearDown(() => deleteTestDirectory(temp));
      final profile = await buildBigProfile(Directory('${temp.path}/next'),
          spec: BigProfileSpec(
              works: works,
              episodesPerWork: episodes,
              danmakuEpisodes: 0,
              jobs: 10,
              followups: 10,
              waitingFollowups: 0,
              hookEvents: 10,
              historyItems: 10,
              calendarAnime: 10,
              journalBytes: 1 << 16,
              chatEventBytes: 0));
      final jobs =
          await SqliteJobStore.open(profile.root, factory: databaseFactoryFfi);
      final media = MediaService(
          store: IdentityStore(jobs.database, profile.deviceId),
          providers: const [],
          classic: NoClassic(),
          authorizedRoots: () => [profile.root.path]);
      final sources = StateSources()..history = () => [];
      final state = StateCapability(publicStateViews(
          media: media,
          settings: SettingsRegistry(jobs.database, const []),
          danmaku: DanmakuService(
              store: DanmakuStore(media.store),
              sources: const [],
              player: NoPlayer()),
          mesh: NoMesh(),
          sources: sources));
      final ui = UiDataService(
          media,
          TaskEngine(store: jobs, ownerDeviceId: profile.deviceId),
          state,
          sources,
          profile.root,
          MemoryVault());
      final worker =
          LibraryWorker(ui, subtitleProbe: (_) async => <String, Object?>{});
      addTearDown(() async {
        await worker.close();
        await ui.close();
        await ui.sources.close();
        await jobs.database.close();
      });
      final watch = Stopwatch()..start();
      final built = await worker.prepare(
          owner: profile.deviceId,
          peers: const {},
          peerRevision: 0,
          online: const {},
          onlineRevision: 0,
          account: null,
          composedStamp: null);
      watch.stop();
      expect(built.builds, 1);
      expect((await worker.works()).length, works);
      // ignore: avoid_print
      print('LIBRARY_BUILD works=$works episodes=$episodes '
          'files=${works * episodes} ms=${watch.elapsedMilliseconds}');
    });
  }
}
