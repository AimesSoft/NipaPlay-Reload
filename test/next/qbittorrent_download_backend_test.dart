import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/downloads/download_backend.dart';
import 'package:nipaplay/next/downloads/download_source.dart';
import 'package:nipaplay/next/downloads/qbittorrent_download_backend.dart';

import 'fake_qbittorrent.dart';

const hashA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late FakeQbittorrent fake;
  late Directory root;
  final backends = <QbittorrentDownloadBackend>[];

  QbittorrentDownloadBackend connect(
      {bool local = false,
      Future<QbittorrentLogin?> Function()? login,
      Duration metadataWait = const Duration(seconds: 5),
      Duration loginRetryDelay = const Duration(seconds: 30)}) {
    final backend = QbittorrentDownloadBackend(
        id: 'seedbox',
        name: 'Seedbox',
        address: fake.address,
        local: local,
        login: login ?? () async => QbittorrentLogin(fake.username, fake.password),
        metadataWait: metadataWait,
        pollInterval: const Duration(milliseconds: 20),
        loginRetryDelay: loginRetryDelay);
    backends.add(backend);
    return backend;
  }

  Future<DownloadRequest> magnet(String hash,
      {List<int>? indices,
      String? directory,
      String? category,
      bool? folder}) async {
    final prepared = await DownloadSources(Directory('${root.path}/cache'))
        .prepare('magnet:?xt=urn:btih:$hash&dn=Show');
    return DownloadRequest(
        source: prepared.source,
        infoHash: prepared.infoHash,
        title: prepared.title,
        fileIndices: indices,
        downloadDirectory: directory,
        category: category,
        createFolderForTask: folder);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('qbit-test-');
  });
  tearDown(() async {
    for (final backend in backends) {
      await backend.close();
    }
    backends.clear();
    await fake.stop();
    await root.delete(recursive: true);
  });

  for (final v5 in [false, true]) {
    group(v5 ? 'qBittorrent 5' : 'qBittorrent 4', () {
      setUp(() async {
        fake = FakeQbittorrent(v5: v5);
        await fake.start();
      });

      test('signs in once, reports the torrent and its files as qBittorrent says',
          () async {
        fake.torrents[hashA] = FakeTorrent(hashA, 'Show', '/seed/dl', [
          FakeFile('Show/ep1.mkv', 1000, progress: 1),
          FakeFile('Show/ep2.mkv', 2000, progress: 0.5),
          FakeFile('Show/readme.txt', 10, priority: 0),
        ]);
        final backend = connect();
        await backend.initialize();
        final listed = await backend.list();
        expect(listed.single.infoHash, hashA);
        expect(listed.single.files, isEmpty, reason: 'a listing is light');
        final task = await backend.read(listed.single.handle);
        expect(fake.logins, 1);
        expect(fake.origins.whereType<String>(), isNotEmpty,
            reason: 'qBittorrent refuses requests without its own Origin');
        expect(task.output.path, '/seed/dl');
        expect(task.output.isLocal, isFalse);
        expect(task.total, 3000, reason: 'only what is wanted');
        expect(task.completed, 2000);
        expect(task.finished, isFalse);
        expect(task.files.map((f) => f.location.path),
            ['/seed/dl/Show/ep1.mkv', '/seed/dl/Show/ep2.mkv', '/seed/dl/Show/readme.txt']);
        expect(task.files.map((f) => f.location.isLocal), everyElement(isFalse));
        expect(task.files.map((f) => f.included), [true, true, false]);
        expect(task.files.map((f) => f.isVideo), [true, true, false]);
        expect(task.files[0].complete, isTrue);
        expect(task.files[1].complete, isFalse);
        final json = task.toJson();
        expect((json['files'] as List).first['playable'], isFalse,
            reason: 'a file on another machine is never playable here');
        expect(json['local'], isFalse);
        expect(task.paused, isFalse);
        expect((task.health!['qbittorrent'] as Map)['backend'], 'seedbox');
      });

      test('pause and resume use the endpoints of this version', () async {
        fake.torrents[hashA] =
            FakeTorrent(hashA, 'Show', '/seed/dl', [FakeFile('a.mkv', 10)]);
        final backend = connect();
        await backend.pause(hashA);
        expect(fake.torrents[hashA]!.paused, isTrue);
        expect((await backend.read(hashA)).paused, isTrue);
        await backend.resume(hashA);
        expect(fake.torrents[hashA]!.paused, isFalse);
        final used = fake.requests
            .where((r) => r.contains('torrents/') && r.startsWith('POST'))
            .toSet();
        expect(
            used,
            v5
                ? {'POST /api/v2/torrents/stop', 'POST /api/v2/torrents/start'}
                : {
                    'POST /api/v2/torrents/stop', // tried first, a 404
                    'POST /api/v2/torrents/pause',
                    'POST /api/v2/torrents/resume'
                  });
        // After learning the style, only that style is used.
        fake.requests.clear();
        await backend.pause(hashA);
        await backend.resume(hashA);
        expect(fake.requests.where((r) => r.contains('stop') || r.contains('start')).length,
            v5 ? 2 : 0);
        expect(fake.requests.where((r) => r.contains('pause') || r.contains('resume')).length,
            v5 ? 0 : 2);
      });

      test('an initialized client picks the endpoint from the API version',
          () async {
        fake.torrents[hashA] =
            FakeTorrent(hashA, 'Show', '/seed/dl', [FakeFile('a.mkv', 10)]);
        final backend = connect();
        await backend.initialize();
        fake.requests.clear();
        await backend.pause(hashA);
        expect(fake.requests.where((r) => r.startsWith('POST /api/v2/torrents/')),
            [v5 ? 'POST /api/v2/torrents/stop' : 'POST /api/v2/torrents/pause']);
      });

      test('an expired session is opened again once and the call goes through',
          () async {
        fake.torrents[hashA] =
            FakeTorrent(hashA, 'Show', '/seed/dl', [FakeFile('a.mkv', 10)]);
        final backend = connect();
        expect(await backend.list(), hasLength(1));
        expect(fake.logins, 1);
        fake.expireSession();
        expect(await backend.list(), hasLength(1));
        expect(fake.logins, 2);
      });

      test('adds a magnet with directory, category and layout, then reports it',
          () async {
        fake.magnetContents[hashA] =
            (name: 'Show', files: [('Show/ep1.mkv', 100), ('Show/ep2.mkv', 200)]);
        final backend = connect();
        final task = await backend.add(await magnet(hashA,
            directory: '/seed/anime', category: 'anime', folder: true));
        expect(task.infoHash, hashA);
        expect(fake.torrents[hashA]!.savePath, '/seed/anime');
        expect(fake.torrents[hashA]!.category, 'anime');
        expect(fake.torrents[hashA]!.contentLayout, 'Subfolder');
        expect(task.files, hasLength(2), reason: 'the add waits for metadata');
        expect(task.output.path, '/seed/anime');
        // Added again, it is not added twice.
        fake.requests.clear();
        await backend.add(await magnet(hashA));
        expect(fake.requests.where((r) => r.contains('torrents/add')), isEmpty);
      });

      test('a .torrent with a selection is added stopped, selected, then run',
          () async {
        final bytes = testTorrent('Show', [('ep1.mkv', 100), ('ep2.mkv', 200)]);
        final file = await File('${root.path}/show.torrent').writeAsBytes(bytes);
        final hash = torrentInfoHash(bytes);
        final backend = connect();
        final task = await backend.add(DownloadRequest(
            source: file.path,
            infoHash: hash,
            title: 'Show',
            fileIndices: [1]));
        final torrent = fake.torrents[hash]!;
        expect(torrent.files.map((f) => f.priority), [0, 1]);
        expect(torrent.paused, isFalse);
        expect(task.files.map((f) => f.included), [false, true]);
        expect(task.paused, isFalse);
      });

      test('a magnet with a selection is selected as soon as metadata arrives',
          () async {
        fake.magnetContents[hashA] =
            (name: 'Show', files: [('Show/ep1.mkv', 100), ('Show/ep2.mkv', 200)]);
        final backend = connect();
        final task = await backend.add(await magnet(hashA, indices: [0]));
        expect(task.files.map((f) => f.included), [true, false]);
      });

      test('a magnet with a selection whose metadata never arrives is removed again, retryably',
          () async {
        fake.metadataDelay = null;
        final backend = connect(metadataWait: const Duration(milliseconds: 150));
        await expectLater(
            backend.add(await magnet(hashA, indices: [0])),
            throwsA(isA<Failure>()
                .having((f) => f.code, 'code', FailureCode.unavailable)
                .having((f) => f.retryable, 'retryable', isTrue)));
        expect(fake.torrents, isEmpty);
        expect(fake.deletions.single, 'false');
      });

      test('stopping an add that is waiting removes what it added', () async {
        fake.metadataDelay = null;
        final backend = connect();
        final stop = Completer<void>();
        final adding =
            backend.add(await magnet(hashA, indices: [0]), stopRequested: stop.future);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        stop.complete();
        await expectLater(adding, throwsA(isA<DownloadAddStopped>()));
        expect(fake.torrents, isEmpty);
      });

      test('selection changes priorities and keeps the files', () async {
        fake.torrents[hashA] = FakeTorrent(hashA, 'Show', '/seed/dl', [
          FakeFile('a.mkv', 10),
          FakeFile('b.mkv', 10),
          FakeFile('c.mkv', 10, priority: 0),
        ]);
        fake.torrents[hashA]!.files[0].priority = 7;
        final backend = connect();
        await backend.selectFiles(hashA, [0, 2]);
        expect(fake.torrents[hashA]!.files.map((f) => f.priority), [7, 0, 1],
            reason: 'a priority the owner set is not flattened');
        await expectLater(backend.selectFiles(hashA, [3]),
            throwsA(isA<Failure>().having((f) => f.code, 'code', FailureCode.invalidInput)));
      });

      test('remove keeps the data, delete takes it', () async {
        fake.torrents[hashA] =
            FakeTorrent(hashA, 'Show', '/seed/dl', [FakeFile('a.mkv', 10)]);
        final backend = connect();
        await backend.remove(hashA);
        expect(fake.deletions, ['false']);
        fake.torrents[hashA] =
            FakeTorrent(hashA, 'Show', '/seed/dl', [FakeFile('a.mkv', 10)]);
        await backend.delete(hashA);
        expect(fake.deletions, ['false', 'true']);
        expect(fake.torrents, isEmpty);
      });

      test('the size of a file on another machine is what qBittorrent holds',
          () async {
        fake.torrents[hashA] = FakeTorrent(hashA, 'Show', '/seed/dl', [
          FakeFile('a.mkv', 1000, progress: 1),
          FakeFile('b.mkv', 1000, progress: 0.25),
        ]);
        final backend = connect();
        final task = await backend.read(hashA);
        expect(await backend.readSize(task.files[0]), 1000);
        expect(await backend.readSize(task.files[1]), 250);
        await backend.delete(hashA);
        expect(await backend.readSize(task.files[0]), isNull);
      });

      test('speed limits are read back from qBittorrent', () async {
        final backend = connect();
        final set = await backend
            .bandwidth({'downloadBytesPerSecond': 500000, 'uploadBytesPerSecond': 0});
        expect(fake.downloadLimit, 500000);
        expect((set['actual'] as Map)['downloadBytesPerSecond'], 500000);
        expect(set['alternativeLimitsActive'], isFalse);
        final read = await backend.bandwidth({});
        expect(read['applied'], isFalse);
        expect((read['actual'] as Map)['uploadBytesPerSecond'], 0);
      });

      test('what qBittorrent says about itself, and nothing of the login',
          () async {
        final backend = connect(local: true);
        final status = await backend.status();
        expect(status, containsPair('online', true));
        expect(status['version'], v5 ? 'v5.0.4' : 'v4.6.7');
        expect(status['apiVersion'], v5 ? '2.11.2' : '2.9.3');
        expect(status['local'], isTrue);
        expect('$status', isNot(contains(fake.password)));
        expect('$status', isNot(contains(fake.username)));
        expect(backend.reference.toJson(), {'kind': 'qbittorrent', 'id': 'seedbox'});
      });
    });
  }

  group('connection', () {
    setUp(() async {
      fake = FakeQbittorrent();
      await fake.start();
    });

    test('a qBittorrent that is off is retryably unavailable, and said so',
        () async {
      final backend = connect();
      await backend.initialize();
      await fake.stop();
      await expectLater(
          backend.list(),
          throwsA(isA<Failure>()
              .having((f) => f.code, 'code', FailureCode.unavailable)
              .having((f) => f.retryable, 'retryable', isTrue)));
      final status = await backend.status();
      expect(status['online'], isFalse);
      expect(status['version'], isNull);
      expect(status['error'], 'unavailable');
    });

    test('a refused login is unavailable, retryable, and not hammered', () async {
      final backend = connect(
          login: () async => const QbittorrentLogin('nipa', 'hunter2-bad'));
      for (var i = 0; i < 3; i++) {
        await expectLater(
            backend.list(),
            throwsA(isA<Failure>()
                .having((f) => f.code, 'code', FailureCode.unavailable)
                .having((f) => f.retryable, 'retryable', isTrue)
                .having((f) => f.message, 'message', isNot(contains('hunter2-bad')))));
      }
      expect(fake.rejectedLogins, 1, reason: 'a banned address stays banned');
    });

    test('a login that fixes itself is tried again after the delay', () async {
      var password = 'hunter2-bad';
      final backend = connect(
          loginRetryDelay: const Duration(milliseconds: 50),
          login: () async => QbittorrentLogin('nipa', password));
      await expectLater(backend.list(), throwsA(isA<Failure>()));
      password = 'secret';
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(await backend.list(), isEmpty);
    });

    test('no saved login works against a qBittorrent that lets this client in',
        () async {
      fake.requireAuth = false;
      final backend = QbittorrentDownloadBackend(
          id: 'local', name: 'Local', address: fake.address, local: true);
      backends.add(backend);
      expect(await backend.list(), isEmpty);
      expect(fake.logins, 0);
    });

    test('with no login saved and one needed, the answer is retryably unavailable',
        () async {
      final backend = QbittorrentDownloadBackend(
          id: 'local', name: 'Local', address: fake.address, local: true);
      backends.add(backend);
      await expectLater(
          backend.list(),
          throwsA(isA<Failure>()
              .having((f) => f.code, 'code', FailureCode.unavailable)));
    });

    test('addresses are checked before anything is sent', () {
      expect(() => QbittorrentDownloadBackend.parseAddress('ftp://x'),
          throwsA(isA<Failure>()));
      expect(() => QbittorrentDownloadBackend.parseAddress('http://u:p@qbittorrent.example:1'),
          throwsA(isA<Failure>()),
          reason: 'the login is kept out of the address');
      expect(QbittorrentDownloadBackend.parseAddress('http://host:8080/').toString(),
          'http://host:8080');
      expect(QbittorrentDownloadBackend.isLoopback(Uri.parse('http://127.0.0.1:1')),
          isTrue);
      expect(QbittorrentDownloadBackend.isLoopback(Uri.parse('http://seedbox.lan:1')),
          isFalse);
    });
  });

  group('this machine', () {
    setUp(() async {
      fake = FakeQbittorrent();
      await fake.start();
    });

    test('paths are local, sizes come from disk, deleting is bounded', () async {
      final dir = await Directory('${root.path}/dl').create();
      final show = await Directory('${dir.path}/Show').create();
      await File('${show.path}/ep1.mkv').writeAsBytes(List.filled(100, 1));
      await File('${show.path}/ep2.mkv').writeAsBytes(List.filled(100, 1));
      fake.torrents[hashA] = FakeTorrent(hashA, 'Show', dir.path, [
        FakeFile('Show/ep1.mkv', 100, progress: 1),
        FakeFile('Show/ep2.mkv', 100, progress: 1),
      ]);
      final backend = connect(local: true);
      final task = await backend.read(hashA);
      expect(task.output.isLocal, isTrue);
      expect(task.files.map((f) => f.location.isLocal), everyElement(isTrue));
      expect(task.files.first.location.path, '${dir.path}/Show/ep1.mkv');
      expect(task.finished, isTrue);
      expect(await backend.readSize(task.files[0]), 100);
      expect((task.toJson()['files'] as List).first['playable'], isTrue);
      await backend.selectFiles(hashA, [1]);
      await backend.deleteFiles(hashA, [0]);
      expect(await File('${show.path}/ep1.mkv').exists(), isFalse);
      expect(await File('${show.path}/ep2.mkv').exists(), isTrue);
    });

    test('a listing that points outside the save path is refused before deleting',
        () async {
      final dir = await Directory('${root.path}/dl').create();
      fake.torrents[hashA] = FakeTorrent(
          hashA, 'Show', dir.path, [FakeFile('../outside.mkv', 100, progress: 1)]);
      final backend = connect(local: true);
      await expectLater(backend.delete(hashA), throwsA(isA<Failure>()));
      expect(fake.torrents, isNotEmpty);
    });

    test('files of a qBittorrent on another machine cannot be deleted here',
        () async {
      fake.torrents[hashA] =
          FakeTorrent(hashA, 'Show', '/seed/dl', [FakeFile('a.mkv', 10, progress: 1)]);
      final backend = connect();
      await expectLater(
          backend.deleteFiles(hashA, [0]),
          throwsA(isA<Failure>()
              .having((f) => f.code, 'code', FailureCode.invalidInput)));
    });
  });
}
