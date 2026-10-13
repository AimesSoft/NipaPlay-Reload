part of 'mesh_integration_test.dart';

Future<void> x47HeadlessExperiment(_Rig rig) async {
  final mac = await rig.node('x47c-headless-reader');
  sqfliteFfiInit();
  final a = await x47Data(rig, mac);
  final root = await Directory('${rig.directory.path}/real-headless').create();
  final media = await Directory('${rig.directory.path}/real-media').create();
  await File('${root.path}/headless.json').writeAsString(jsonEncode({
    'format': 1,
    'host': 'nipaplay-headless',
    'mediaRoots': [media.path]
  }));
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  await File('${root.path}/mesh.json').writeAsString(jsonEncode({
    'coordinator': rig.base.toString(),
    'name': 'real-headless',
    'port': port,
    'broadcastDiscovery': false,
    'addresses': [
      {'kind': 'manual', 'host': '127.0.0.1', 'port': port}
    ]
  }));
  final args = [
    '--data',
    root.path,
    '--native-library',
    File('rust/headless/target/debug/libnipaplay_headless_native.dylib')
        .absolute
        .path,
    '--seed',
    Directory('assets/next/harness').absolute.path
  ];
  final enrollment = await Process.start(
      Platform.environment['NIPAPLAY_X47_HEADLESS_BINARY']!,
      ['--enroll-token-stdin', '--data', root.path]);
  enrollment.stdin.write(_jwt(424242));
  await enrollment.stdin.close();
  final enrollmentOut = enrollment.stdout.drain<void>(),
      enrollmentErr = enrollment.stderr.drain<void>();
  expect(await enrollment.exitCode, 0);
  await enrollmentOut;
  await enrollmentErr;
  final process = await Process.start(
      Platform.environment['NIPAPLAY_X47_HEADLESS_BINARY']!, args,
      environment: {
        'NIPAPLAY_MESH_DEV_CA': '${rig.caDirectory.path}/ca.pem',
        'HTTP_PROXY': '',
        'HTTPS_PROXY': '',
        'ALL_PROXY': '',
        'NO_PROXY': '127.0.0.1,localhost'
      });
  final logs = <String>[];
  process.stdout.transform(utf8.decoder).listen(logs.add);
  process.stderr.transform(utf8.decoder).listen(logs.add);
  try {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!await File('${root.path}/running.json').exists()) {
      if (DateTime.now().isAfter(deadline))
        fail('Isolated headless did not start: ${logs.join()}');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final owner =
        (jsonDecode(await File('${root.path}/device.json').readAsString())
            as Map)['deviceId'] as String;
    final identity = (jsonDecode(
            await File('${root.path}/mesh-identity.json').readAsString())
        as Map)['deviceId'] as String;
    final db = await databaseFactoryFfi.openDatabase('${root.path}/next.db');
    try {
      final store = IdentityStore(db, owner);
      final video = File('${media.path}/source.mp4');
      await video.writeAsBytes(List.generate(8193, (i) => i % 251));
      final fid = await store.ensureFile(video.path);
      await db.insert('media_entities',
          {'id': 'work', 'kind': 'work', 'attributes': '{"title":"真实无界面来源"}'});
      await db.insert('media_entities', {
        'id': 'release',
        'kind': 'release',
        'parent_id': 'work',
        'attributes': '{"season":1}'
      });
      await db.insert('media_entities', {
        'id': 'episode',
        'kind': 'episode',
        'parent_id': 'release',
        'attributes': '{"number":"1"}'
      });
      await db.insert('media_file_episodes', {
        'file_id': fid,
        'episode_id': 'episode',
        'relation': 'exact',
        'ordinal': 1
      });
      await mac.refreshDevices();
      await a.meshLibrary!.refresh();
      final work = (await a.library()).single;
      expect(work.title, '真实无界面来源');
      final episode = (await a.episodes(work.workId)).single;
      expect(episode.device!.name, 'real-headless');
      expect(episode.playable, true);
      final facts = await a.metadataFacts(work.workId);
      expect((facts['episodes'] as Map)['total'], 1);
      final readable = await a.meshLibrary!.files
          .call('readable', {'deviceId': identity, 'path': video.path});
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      try {
        final request =
            await client.getUrl(Uri.parse(readable['url'] as String));
        request.headers.set('Range', 'bytes=4096-4223');
        final response = await request.close();
        expect(response.statusCode, 206);
        expect(await response.fold<List<int>>([], (a, b) => a..addAll(b)),
            (await video.readAsBytes()).sublist(4096, 4224));
      } finally {
        client.close(force: true);
      }
      final destination = '${media.path}/pushed.srt';
      final upload = await a.meshLibrary!.files.call(
          'begin', {'deviceId': identity, 'path': destination, 'size': 8});
      await a.meshLibrary!.files.call('chunk', {
        'deviceId': identity,
        'transferId': upload['transferId'],
        'offset': 0,
        'data': base64Encode(utf8.encode('subtitle'))
      });
      await a.meshLibrary!.files.call(
          'finish', {'deviceId': identity, 'transferId': upload['transferId']});
      expect(await File(destination).readAsString(), 'subtitle');
      print(
          'X47c headless evidence: separate Dart AOT process + C ABI Rust library; authenticated catalogue contains one work/episode; canonical metadataFacts readable; direct TLS Range bytes4096-4223 match; subtitle pushed and published in source media directory. No GUI, keychain or workstation node involved.');
    } finally {
      await db.close();
    }
    await File('${root.path}/stop.request').writeAsString('${process.pid}');
    expect(await process.exitCode.timeout(const Duration(seconds: 15)), 0);
    expect(logs.any((line) => line.contains('"status":"stopped"')), true);
  } finally {
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(const Duration(seconds: 15));
  }
}
