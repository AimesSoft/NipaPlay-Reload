part of 'mesh_integration_test.dart';

Future<void> x47LibraryExperiment(_Rig rig) async {
  final mac = await rig.node('Mac'), source = await rig.node('workstation');
  await mac.refreshDevices();
  await source.refreshDevices();
  sqfliteFfiInit();
  final a = await x47Data(rig, mac), b = await x47Data(rig, source);
  final video = File('${source.root.path}/X47 CC0 S01E04.mp4');
  final encoded = await Process.run(ffmpegExecutable, [
    '-v',
    'error',
    '-f',
    'lavfi',
    '-i',
    'testsrc2=size=640x360:rate=24',
    '-t',
    '12',
    '-c:v',
    'libx264',
    '-crf',
    '8',
    '-g',
    '24',
    '-pix_fmt',
    'yuv420p',
    video.path
  ]);
  expect(encoded.exitCode, 0, reason: encoded.stderr.toString());
  expect(await video.length(), greaterThan(1048576));
  final first = File('${mac.root.path}/E01.mp4');
  await first.writeAsBytes([1, 2, 3, 4]);
  Future<void> work(UiDataService ui, String id, List<int> numbers,
      {String? duplicate}) async {
    await ui.db.insert('media_entities', {
      'id': id,
      'kind': 'work',
      'attributes': jsonEncode({'title': 'X47 开放视频'})
    });
    await ui.db.insert('media_entities', {
      'id': '$id-release',
      'kind': 'release',
      'parent_id': id,
      'attributes': '{"season":1}'
    });
    await ui.db.insert('media_external_objects', {
      'id': '$id-object',
      'provider': 'dandanplay',
      'object_type': 'work',
      'external_id': '4700',
      'scope': ''
    });
    await ui.db.insert('media_bindings', {
      'id': '$id-binding',
      'entity_id': id,
      'object_id': '$id-object',
      'relation': 'exact',
      'scope': '{}',
      'status': 'accepted',
      'source': 'fixture',
      'revision': 0,
      'created_at': '2026-10-13T00:00:00Z'
    });
    await ui.db.insert('media_snapshots', {
      'id': '$id-snapshot', 'object_id': '$id-object', 'language': 'zh-CN',
      'fetched_at': '2026-10-13T00:00:00Z',
      'fields': jsonEncode({'metadata': {'title': 'X47 开放视频',
        'originalTitle': 'Open Video', 'aliases': ['开放别名'], 'year': 2026}}),
    });
    for (final number in numbers) {
      final path = number == 1
          ? duplicate ?? first.path
          : number <= 3
              ? '${mac.root.path}/E0$number.mp4'
              : video.path;
      if (number > 1 && number <= 3) await File(path).writeAsBytes([number]);
      final fileId = await ui.media.store.ensureFile(path);
      final eid = '$id-episode-$number';
      await ui.db.insert('media_entities', {
        'id': eid,
        'kind': 'episode',
        'parent_id': '$id-release',
        'attributes': jsonEncode({'number': '$number', 'title': '第 $number 集'})
      });
      await ui.db.insert('media_file_episodes', {
        'file_id': fileId,
        'episode_id': eid,
        'relation': 'exact',
        'ordinal': number,
        'start_ms': number >= 4 ? (number - 4) * 1000 : 0,
        'end_ms': number >= 4 ? (number - 3) * 1000 : null
      });
    }
  }

  await work(a, 'mac-work', [1, 2, 3]);
  await work(b, 'source-work', [1, 4, 5, 6, 7, 8, 9, 10, 11, 12],
      duplicate: first.path);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xff4422aa), ui.BlendMode.src);
  final picture = recorder.endRecording(),
      artworkImage = await picture.toImage(32, 48);
  final png = (await artworkImage.toByteData(format: ui.ImageByteFormat.png))!;
  final poster = File('${source.root.path}/poster.png');
  await poster.writeAsBytes(png.buffer.asUint8List());
  await b.setArtwork({
    'entries': [
      {
        'entityId': 'source-work',
        'kind': 'poster',
        'file': poster.path,
        'source': {'label': 'CC0 fixture'}
      }
    ]
  }, Invocation(origin: 'fixture'));
  artworkImage.dispose();
  picture.dispose();
  await File(video.path.replaceFirst('.mp4', '.srt'))
      .writeAsString('1\n00:00:00,000 --> 00:00:02,000\nX47 CC0 subtitle\n');
  await File(video.path.replaceFirst('.mp4', '.xml')).writeAsString(
      '<i><d p="0.5,1,25,16777215,0,0,fixture,1">X47 同名弹幕</d></i>');
  final changed = a.changes.first;
  await a.meshLibrary!.refresh();
  await changed;
  final works = await a.library();
  expect(works, hasLength(1));
  final targets = ((await a.meshLibrary!.managementTargets([works.single.workId]))['entries'] as List).single as Map;
  final owners = (targets['targets'] as List).cast<Map>();
  expect(owners.map((o) => o['workId']).toSet(), {'mac-work', 'source-work'});
  final remoteOwner = owners.singleWhere((o) => o['workId'] == 'source-work');
  expect(remoteOwner['deviceId'], source.identity!.deviceId);
  expect((remoteOwner['episodes'] as List).map((e) => e['episodeId']), contains('source-work-episode-4'));
  expect(remoteOwner['online'], true);
  for (final query in ['Open Video', '开放别名', '2026']) {
    final result = await a.meshLibrary!.search(query);
    expect(((result['works'] as List).single as Map)['workId'], works.single.workId);
  }
  final eps = await a.episodes(works.single.workId);
  expect(eps.map((e) => e.number).toList(), List.generate(12, (i) => i + 1));
  expect(eps.take(3).every((e) => e.device == null), true);
  expect(
      eps.skip(3).every((e) => e.device?.name == 'workstation' && e.playable),
      true);
  final artworkDeadline = DateTime.now().add(const Duration(seconds: 10));
  while (!(a.meshLibrary!.refreshStatus['peers'] as List).cast<Map>().any(
      (p) => p['deviceId'] == source.identity!.deviceId && p['artwork'] == 'complete')) {
    if (DateTime.now().isAfter(artworkDeadline)) fail('Artwork did not settle: ${a.meshLibrary!.refreshStatus}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  final artworkWork = (await a.library()).single;
  expect(await File(artworkWork.artwork.poster!).exists(), true);
  expect(artworkWork.artwork.poster, startsWith(a.mediaRoot.path));
  final opened = (await a.meshLibrary!.open(eps[3].episodeId))!;
  final url = Uri.parse(opened['url'] as String);
  expect((opened['bundle'] as Map)['tracks'], hasLength(1));
  expect(
      ((opened['bundle'] as Map)['subtitles'] as List)
          .any((t) => (t as Map)['origin'] != 'embedded'),
      true);
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final request = await client.getUrl(url);
    request.headers.set('Range', 'bytes=1048576-1048703');
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    expect(response.statusCode, 206);
    final file = await video.open();
    await file.setPosition(1048576);
    expect(bytes, await file.read(128));
    await file.close();
    final suffix = await client.getUrl(url);
    suffix.headers.set('Range', 'bytes=-37');
    final suffixResponse = await suffix.close();
    expect(await suffixResponse.fold<List<int>>([], (a, b) => a..addAll(b)),
        (await video.readAsBytes()).sublist(await video.length() - 37));
    final head = await client.openUrl('HEAD', url);
    expect((await head.close()).contentLength, await video.length());
    final invalid = await client.getUrl(url);
    invalid.headers.set('Range', 'bytes=99999999-');
    final rejected = await invalid.close();
    expect(rejected.statusCode, 416);
    await rejected.drain<void>();
  } finally {
    client.close(force: true);
  }
  // A player abandoning a range must not make the bridge keep reading the
  // rest of the file. Stall one source block so the disconnect is deliberate.
  final beforeAbort = source.libraryRequest!;
  final enteredRead = Completer<void>(), releaseRead = Completer<void>();
  var abortedReads = 0;
  source.libraryRequest = (method, input, peer) async {
    if (method == 'mesh/library/read') {
      abortedReads++;
      if (!enteredRead.isCompleted) enteredRead.complete();
      await releaseRead.future;
    }
    return beforeAbort(method, input, peer);
  };
  final abandonedClient = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final request = await abandonedClient.getUrl(url);
    final pending = request.close()
        .then<void>((response) => response.drain<void>())
        .catchError((Object _) {});
    await enteredRead.future.timeout(const Duration(seconds: 3));
    abandonedClient.close(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    releaseRead.complete();
    await pending;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(abortedReads, 1, reason: 'no next block after the client disconnects');
    expect(source.status, 'online');
  } finally {
    if (!releaseRead.isCompleted) releaseRead.complete();
    abandonedClient.close(force: true);
    source.libraryRequest = beforeAbort;
  }
  final probed = await Process.run(ffprobeExecutable, [
    '-v',
    'error',
    '-show_entries',
    'format=duration:stream=width,height',
    '-of',
    'json',
    url.toString()
  ], environment: {
    'HTTP_PROXY': 'http://127.0.0.1:1',
    'http_proxy': 'http://127.0.0.1:1',
    'NO_PROXY': '127.0.0.1,localhost',
    'no_proxy': '127.0.0.1,localhost'
  });
  expect(probed.exitCode, 0, reason: probed.stderr.toString());
  final sought = await Process.run(ffmpegExecutable, [
    '-v',
    'error',
    '-ss',
    '8',
    '-i',
    url.toString(),
    '-frames:v',
    '1',
    '-f',
    'md5',
    '-'
  ], environment: {
    'HTTP_PROXY': 'http://127.0.0.1:1',
    'http_proxy': 'http://127.0.0.1:1',
    'NO_PROXY': '127.0.0.1,localhost',
    'no_proxy': '127.0.0.1,localhost'
  });
  expect(sought.exitCode, 0, reason: sought.stderr.toString());
  final local = await Process.run(ffmpegExecutable, [
    '-v',
    'error',
    '-ss',
    '8',
    '-i',
    video.path,
    '-frames:v',
    '1',
    '-f',
    'md5',
    '-'
  ]);
  expect(sought.stdout, local.stdout);
  await a.meshLibrary!.recordProgress(eps[3].episodeId, .75);
  await b.meshLibrary!.refresh();
  expect(
      (await b.episodes((await b.library()).single.workId))
          .singleWhere((e) => e.number == 4)
          .progress,
      .75);
  await b.meshLibrary!.recordProgress(
      (await b.episodes((await b.library()).single.workId))[3].episodeId, .25);
  await a.meshLibrary!.refresh();
  expect((await a.episodes(works.single.workId))[3].progress, .25);
  final before =
      await a.db.query('ui_cache', where: 'id=?', whereArgs: ['mesh:progress']);
  await expectLater(
      a.meshLibrary!.recordProgressBatch([
        {'episodeId': eps[3].episodeId, 'progress': 1.0},
        {'episodeId': 'missing', 'progress': 0.0}
      ]),
      throwsA(isA<Failure>()));
  expect(
      await a.db.query('ui_cache', where: 'id=?', whereArgs: ['mesh:progress']),
      before);
  final sourceRequest = source.libraryRequest!;
  for (final malformed in [false, true]) {
    source.libraryRequest = (method, input, peer) async {
      if (method == 'mesh/library/snapshot') {
        if (!malformed) {
          throw const Failure(FailureCode.conflict, 'Catalogue not ready.');
        }
        return {
          'version': 'bad-catalogue',
          'encoding': 'json-base64-v1',
          'data': 'invalid-base64!',
          'totalBytes': 1,
          'next': null
        };
      }
      return sourceRequest(method, input, peer);
    };
    await a.meshLibrary!.refresh();
    final status = (a.meshLibrary!.refreshStatus['peers'] as List)
        .cast<Map>()
        .singleWhere((p) => p['deviceId'] == source.identity!.deviceId);
    expect(status['online'], true);
    expect(status['error'], isNotNull);
    expect((await a.meshLibrary!.readable(eps[3].episodeId))['url'], isNotNull);
  }
  source.libraryRequest = sourceRequest;
  await a.meshLibrary!.refresh();
  final recovered = (a.meshLibrary!.refreshStatus['peers'] as List)
      .cast<Map>()
      .singleWhere((p) => p['deviceId'] == source.identity!.deviceId);
  expect(recovered['online'], true);
  expect(recovered['error'], isNull);
  await b.meshLibrary!.close();
  await source.close();
  rig.nodes.remove(source);
  await a.meshLibrary!.refresh();
  final offlineTargets = ((await a.meshLibrary!.managementTargets([works.single.workId]))['entries'] as List).single as Map;
  final offlineOwner = (offlineTargets['targets'] as List).cast<Map>().singleWhere((o) => o['workId'] == 'source-work');
  expect(offlineOwner['reason'], 'source_device_offline');
  expect(offlineOwner['online'], false);
  final offline = await a.library();
  expect(offline.single.devices.single.online, false);
  expect(
      (await a.episodes(offline.single.workId))
          .skip(3)
          .every((e) => !e.playable && e.device?.online == false),
      true);
  expect(await File(offline.single.artwork.poster!).exists(), true);
  final search = await a.meshLibrary!.search('第 4 集');
  final hit = (search['episodes'] as List).single as Map;
  expect((hit['work'] as Map)['workId'], offline.single.workId);
  expect((hit['episode'] as Map)['episodeId'], eps[3].episodeId);
  expect((hit['episode'] as Map)['playable'], false);
  expect(((hit['episode'] as Map)['device'] as Map)['online'], false);
  final acceptedIds = await a.meshLibrary!.searchWorkIds([
    const ExternalRef('dandanplay', 'work', '4700'),
    const ExternalRef('dandanplay', 'anime', '4700'),
    const ExternalRef('dandanplay', 'anime', 'unknown'),
  ]);
  expect(acceptedIds, [offline.single.workId, offline.single.workId, null]);
  print('X56 evidence: real authenticated Mesh search resolves canonical work/episode IDs; offline episode retains device and playable=false; accepted online identity resolves merged work, absent identity is null.');
  print(
      'X47 evidence: 1 merged work; 12 episodes; local duplicate preferred; ${await video.length()} real video bytes; Range 206 / suffix / HEAD / 416; ffprobe ${probed.stdout}; seek 8s decoded MD5 ${sought.stdout}; LWW .75 -> .25; rejected batch unchanged; offline retained artwork/catalogue.');
}

Future<UiDataService> x47Data(_Rig rig, MeshRuntime node) async {
  final jobs =
      await SqliteJobStore.open(node.root, factory: databaseFactoryFfi);
  final identities = IdentityStore(jobs.database, node.identity!.deviceId);
  final media = MediaService(
      store: identities,
      providers: [],
      classic: MemoryClassic(),
      authorizedRoots: () => [rig.directory.path]);
  final engine = TaskEngine(
      store: jobs, ownerDeviceId: identities.ownerDeviceId, executors: []);
  await engine.start();
  final sources = StateSources();
  final danmaku = DanmakuService(
      store: DanmakuStore(identities), sources: [], player: NoPlayer());
  final state = StateCapability(publicStateViews(
      media: media,
      settings: SettingsRegistry(jobs.database, []),
      danmaku: danmaku,
      mesh: node,
      sources: sources));
  final ui = UiDataService(media, engine, state, sources, node.root, rig.vault);
  ui.subtitles = SubtitleLibrary(media, node.root,
      probe: (_) async => {'subtitles': <JsonMap>[]});
  ui.meshLibrary = MeshLibrary(ui, node);
  registerMergedLibrary(state, ui.meshLibrary!);
  await ui.meshLibrary!.start();
  await ui.start();
  addTearDown(() async {
    await ui.close();
    await engine.close();
  });
  return ui;
}
