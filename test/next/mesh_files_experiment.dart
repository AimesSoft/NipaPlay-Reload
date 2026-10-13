part of 'mesh_integration_test.dart';

Future<void> x47ProxyReview(_Rig rig) async {
  final mac = await rig.node('x47-review-reader'),
      source = await rig.node('x47-review-source');
  await mac.refreshDevices();
  await source.refreshDevices();
  sqfliteFfiInit();
  final a = await x47Data(rig, mac);
  await x47Data(rig, source);
  final peer = source.identity!.deviceId;
  final file = File('${source.root.path}/proxy-test.txt');
  await file.writeAsString('proxy review fixture');
  final selector = <String, Object?>{'path': file.path};
  Future<JsonMap> issue() => a.meshLibrary!.fileReadable(peer, selector);
  Future<int> fetch(Uri uri, {String? body}) async {
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final response = await (await client.getUrl(uri)).close();
      final content = await response.transform(utf8.decoder).join();
      if (body != null) expect(content, body);
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  Future<JsonMap> status() async {
    final outcome = await Harness([a.state]).invokeJson('state.query',
        {'view': 'mesh.file_proxy'}, Invocation(origin: 'review')) as Completed;
    return (outcome.value.toJson()['rows'] as List).single as JsonMap;
  }

  Future<void> restartProxy() async {
    await a.meshLibrary!.close();
    expect(a.meshLibrary!.fileProxyStatus['state'], 'closed');
    a.meshLibrary = MeshLibrary(a, mac);
    registerMergedLibrary(a.state, a.meshLibrary!);
    await a.meshLibrary!.start();
  }

  final first = await issue(), second = await issue();
  final uri = Uri.parse(first['url'] as String), token = uri.pathSegments.first;
  expect(uri.host, '127.0.0.1');
  expect(base64Url.decode(base64Url.normalize(token)), hasLength(32));
  expect(Uri.parse(second['url'] as String).pathSegments.first, isNot(token));
  final oldPredictable = sha256
      .convert(utf8.encode(jsonEncode([peer, selector, first['tag']])))
      .toString();
  expect(
      await fetch(uri
          .replace(pathSegments: [oldPredictable, file.uri.pathSegments.last])),
      404);
  expect(
      await fetch(uri.replace(pathSegments: [
        List.filled(43, 'A').join(),
        file.uri.pathSegments.last
      ])),
      404);
  expect(await fetch(uri, body: 'proxy review fixture'), 200);
  expect((await status())['state'], 'random');
  expect(jsonEncode(await status()), isNot(contains(token)));
  final reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final fixed = reservation.port;
  await reservation.close();
  mac.hostConfiguration['fileProxyPort'] = fixed;
  await restartProxy();
  final issued = await Future.wait([issue(), issue()]);
  final fixedUri = Uri.parse(issued.first['url'] as String);
  expect(issued.map((r) => Uri.parse(r['url'] as String).port),
      everyElement(fixed));
  expect((await status())['state'], 'fixed');
  expect((await status())['requestedPort'], fixed);
  expect(await fetch(fixedUri, body: 'proxy review fixture'), 200);
  await restartProxy();
  expect(Uri.parse((await issue())['url'] as String).port, fixed);
  expect(await fetch(fixedUri), 404);
  await a.meshLibrary!.close();
  final occupied = await ServerSocket.bind(InternetAddress.loopbackIPv4, fixed);
  try {
    await restartProxy();
    final fallback = Uri.parse((await issue())['url'] as String);
    expect(fallback.port, isNot(fixed));
    expect(fallback.host, '127.0.0.1');
    final observed = await status();
    expect(observed['requestedPort'], fixed);
    expect(observed['port'], fallback.port);
    expect(observed['state'], 'random_fallback');
    expect(observed['fallback'], true);
    expect(observed['reason'], 'requested_port_in_use');
    expect(await fetch(fallback, body: 'proxy review fixture'), 200);
  } finally {
    await occupied.close();
  }
  await a.meshLibrary!.close();
  final external = await Process.start('python3', [
    '-c',
    'import socket, sys\ns=socket.socket()\ns.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)\ns.bind(("127.0.0.1", $fixed))\ns.listen()\nprint(s.getsockname()[1], flush=True)\nsys.stdin.read()'
  ]);
  final errorOutput = external.stderr.transform(utf8.decoder).join();
  try {
    expect(
        await external.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 5)),
        '$fixed');
    await restartProxy();
    final fallback = Uri.parse((await issue())['url'] as String);
    expect(fallback.port, isNot(fixed));
    expect((await status())['reason'], 'requested_port_in_use');
    expect(await fetch(fallback, body: 'proxy review fixture'), 200);
  } finally {
    await external.stdin.close();
    expect(await external.exitCode.timeout(const Duration(seconds: 5)), 0,
        reason: await errorOutput);
  }
  final registry = SettingsRegistry(a.db, []);
  for (final key in [
    'fileProxyPort',
    'mesh.fileProxyPort',
    'mesh/fileProxyPort'
  ]) {
    expect(
        () => registry.register([
              SettingEntry(
                  key: key,
                  title: 'host',
                  description: 'host-only',
                  schema: const IntegerSchema(),
                  defaultValue: 0,
                  storageKey: key,
                  reader: 'host',
                  writer: 'host',
                  read: () async => 0,
                  write: (_) async {},
                  decodeStorage: (v) => v)
            ]),
        throwsArgumentError);
  }
  mac.hostConfiguration['fileProxyPort'] = 80;
  await restartProxy();
  await expectLater(
      issue(),
      throwsA(isA<Failure>()
          .having((f) => f.code, 'code', FailureCode.invalidInput)));
  expect((await status())['state'], 'invalid_configuration');
  print(
      'X47c review: 256-bit random grants; old derived address and unknown guess return404; valid address returns200; default random loopback; concurrent grants use one fixed listener; restart on same port rejects old token; Dart and separate-process occupied fixed port fall back to random with accurate state.query; invalid privileged port rejected; host configuration keys refused by SettingsRegistry.');
}

Future<void> x47LocalFilesConstraint(_Rig rig) async {
  final mesh = MeshRuntime(
      root: rig.directory, vault: rig.vault, token: () async => null);
  final files = MeshFiles(
      mesh,
      (peer, source) async => {...source, 'selectedDevice': peer},
      'local-task-owner');
  final observer = _Observer();
  final api = Harness([MeshFilesCapability(files)], observers: [observer]);
  final readable = await api.invokeJson(
      'media.mesh_files.readable',
      {
        'entries': [
          {'path': '${rig.directory.path}/plain.txt'}
        ]
      },
      Invocation(origin: 'test')) as Completed;
  expect(
      ((readable.value.toJson()['entries'] as List).single
          as Map)['selectedDevice'],
      'local-task-owner');
  final path = '${rig.directory.path}/local.txt';
  final beginning = await api.invokeJson('media.mesh_files.begin',
      {'path': path, 'size': 7}, Invocation(origin: 'test')) as Completed;
  final id = beginning.value.toJson()['transferId'];
  const payload = 'cHJpdmF0ZQ==';
  await api.invokeJson(
      'media.mesh_files.chunk',
      {'transferId': id, 'offset': 0, 'data': payload},
      Invocation(origin: 'test'));
  expect(jsonEncode(observer.records.map((r) => r.toJson()).toList()),
      isNot(contains(payload)));
  final finish = await api.invokeJson('media.mesh_files.finish',
      {'transferId': id}, Invocation(origin: 'test'));
  expect(finish, isA<Completed>());
  expect(await File(path).readAsString(), 'private');
  await files.close();
  await mesh.close();
}

Future<void> x47FileToolsExperiment(_Rig rig) async {
  final a = await rig.node('x47c-tool-a'),
      b = await rig.node('x47c-tool-b',
          authorize: (_, __) async => const Failure(
              FailureCode.unavailable, 'Classic receiver denied'));
  await a.refreshDevices();
  await b.refreshDevices();
  sqfliteFfiInit();
  final data = await x47Data(rig, b);
  b.attach(Harness([
    MeshFilesCapability(data.meshLibrary!.files),
    _Actions(rig.waitStarted, rig.waitRelease)
  ]));
  final path = File('${b.root.path}/test.txt');
  await path.writeAsString('temporary');
  final outcome = await a.invoke(
      b.identity!.deviceId,
      'media.mesh_files.delete',
      {
        'paths': [path.path]
      },
      destructive: false) as NeedsDecision;
  expect(await path.exists(), true);
  final choice = outcome.decision.options.single.call;
  expect(choice.actionId, 'mesh.invoke_destructive');
  expect(choice.input['deviceId'], b.identity!.deviceId);
  await Harness([MeshCapability(a)]).invokeJson(
      choice.actionId, choice.input, Invocation(origin: 'user-choice'));
  expect(await path.exists(), false);
  await expectLater(
      a.invoke(b.identity!.deviceId, 'download.echo', {}, destructive: false),
      throwsA(isA<Failure>()));
  print(
      'X47c tool routing: TLS-only file tool catalogue/call works with Classic receiver denied; NeedsDecision remains local mesh.invoke_destructive option; ordinary download action still denied.');
}

Future<void> x47FilesExperiment(_Rig rig) async {
  final mac = await rig.node('x47c-reader'),
      source = await rig.node('x47c-source');
  await mac.refreshDevices();
  await source.refreshDevices();
  sqfliteFfiInit();
  final a = await x47Data(rig, mac), b = await x47Data(rig, source);
  final peer = source.identity!.deviceId;
  final actions = MeshFilesCapability(a.meshLibrary!.files).actions;
  Future<Outcome<MeshJson>> run(String op, JsonMap input) =>
      (actions.singleWhere((action) => action.spec.id == 'media.mesh_files.$op')
              as Action<MeshJson, MeshJson>)
          .run(MeshJson({'deviceId': peer, ...input}),
              Invocation(origin: 'x47c experiment'));
  JsonMap completed(Outcome<MeshJson> result) =>
      (result as Completed<MeshJson>).value.json;
  final arbitrary = File('${source.root.path}/outside-library.txt');
  await arbitrary.writeAsString('not indexed');
  final urls = completed(await run('readable', {
    'entries': [
      {'path': arbitrary.path}
    ]
  }));
  final url =
      Uri.parse(((urls['entries'] as List).single as JsonMap)['url'] as String);
  expect(url.host, '127.0.0.1');
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    final response = await (await client.getUrl(url)).close();
    expect(await response.transform(utf8.decoder).join(), 'not indexed');
  } finally {
    client.close(force: true);
  }
  final bytes = List<int>.generate(1048576 + 79, (i) => i % 251);
  final target = File('${source.root.path}/transferred.srt');
  Future<String> stage() async {
    final upload = completed(
        await run('begin', {'path': target.path, 'size': bytes.length}));
    final id = upload['transferId'] as String;
    for (var offset = 0; offset < bytes.length; offset += 524288) {
      final chunk = bytes.sublist(offset,
          offset + 524288 < bytes.length ? offset + 524288 : bytes.length);
      final input = {
        'transferId': id,
        'offset': offset,
        'data': base64Encode(chunk)
      };
      await run('chunk', input);
      if (offset == 0) {
        expect(completed(await run('chunk', input))['received'], 524288);
        await expectLater(
            run('chunk', {
              ...input,
              'data': base64Encode([9])
            }),
            throwsA(isA<Failure>()));
      }
    }
    return id;
  }

  final first = await stage();
  await expectLater(run('finish', {'transferId': first, 'sha256': 'wrong'}),
      throwsA(isA<Failure>()));
  expect(await target.exists(), false);
  await run('finish',
      {'transferId': first, 'sha256': sha256.convert(bytes).toString()});
  expect(await target.readAsBytes(), bytes);
  final replacement = await stage();
  final decision = await run('finish', {'transferId': replacement});
  expect(decision, isA<NeedsDecision<MeshJson>>());
  expect(await target.readAsBytes(), bytes);
  final call =
      (decision as NeedsDecision<MeshJson>).decision.options.single.call;
  await target.writeAsString('changed after preview');
  await expectLater(run('confirm', call.input), throwsA(isA<Failure>()));
  expect(await target.readAsString(), 'changed after preview');
  final second = await run('finish', {'transferId': replacement})
      as NeedsDecision<MeshJson>;
  await run('confirm', second.decision.options.single.call.input);
  expect(await target.readAsBytes(), bytes);
  final deletion = await run('delete', {
    'paths': [target.path, arbitrary.path]
  }) as NeedsDecision<MeshJson>;
  expect(await target.exists(), true);
  expect(await arbitrary.exists(), true);
  await expectLater(
      b.meshLibrary!.files.request('confirm',
          deletion.decision.options.single.call.input, 'different-peer'),
      throwsA(isA<Failure>()));
  await run('confirm', deletion.decision.options.single.call.input);
  expect(await target.exists(), false);
  expect(await arbitrary.exists(), false);
  await expectLater(run('confirm', deletion.decision.options.single.call.input),
      throwsA(isA<Failure>()));
  print(
      'X47c evidence: authenticated TLS read of unindexed file via loopback; 1048655 bytes uploaded in 3 bounded chunks; identical retry accepted, conflicting retry rejected; SHA256 verified; overwrite and batch delete NeedsDecision; changed preview refused; other peer cannot confirm; decision replay refused.');
}

Future<void> x47CatalogueEvolution(_Rig rig) async {
  final mac = await rig.node('x47c-catalogue-a'),
      source = await rig.node('x47c-catalogue-b');
  await mac.refreshDevices();
  await source.refreshDevices();
  sqfliteFfiInit();
  final a = await x47Data(rig, mac), b = await x47Data(rig, source);
  for (final data in [a, b]) {
    await data.db.insert('media_entities', {
      'id': 'work',
      'kind': 'work',
      'attributes': '{"title":"X47c catalogue"}'
    });
    await data.db.insert('media_entities', {
      'id': 'release',
      'kind': 'release',
      'parent_id': 'work',
      'attributes': '{"season":1}'
    });
    await data.db.insert('media_entities', {
      'id': 'episode',
      'kind': 'episode',
      'parent_id': 'release',
      'attributes': '{"number":"1","title":"One"}'
    });
    final file = File('${data.mediaRoot.path}/unique.bin');
    await file.writeAsBytes([data == a ? 3 : 4]);
    final fid = await data.media.store.ensureFile(file.path);
    await data.db.insert('media_file_episodes', {
      'file_id': fid,
      'episode_id': 'episode',
      'relation': 'exact',
      'ordinal': 1
    });
  }
  await a.meshLibrary!.refresh();
  expect(await a.library(), hasLength(2));
  final oldWorks = await a.library();
  final oldEpisodes = [
    for (final w in oldWorks) (await a.episodes(w.workId)).single.episodeId
  ];
  for (final data in [a, b]) {
    await data.db.insert('media_external_objects', {
      'id': 'identity',
      'provider': 'tmdb',
      'object_type': 'tv',
      'external_id': '47',
      'scope': ''
    });
    await data.db.insert('media_bindings', {
      'id': 'accepted',
      'entity_id': 'work',
      'object_id': 'identity',
      'relation': 'exact',
      'scope': '{}',
      'status': 'accepted',
      'source': 'fixture',
      'revision': 0,
      'created_at': '2026-10-13T00:00:00Z'
    });
  }
  await b.meshLibrary!.refresh();
  await a.meshLibrary!.refresh();
  final merged = (await a.library()).single;
  expect(await a.episodes(merged.workId), hasLength(1));
  for (final old in oldWorks)
    expect((await a.work(old.workId))!.workId, merged.workId);
  for (final old in oldEpisodes)
    expect(await a.meshLibrary!.parent(old), merged.workId);
  final facts = await a.metadataFacts(merged.workId);
  expect((facts['episodes'] as Map)['total'], 1);
  final before =
      await a.db.query('ui_cache', where: 'id=?', whereArgs: ['mesh:progress']);
  await expectLater(
      a.meshLibrary!.recordProgress(oldEpisodes.first, double.nan),
      throwsA(isA<Failure>()));
  expect(
      await a.db.query('ui_cache', where: 'id=?', whereArgs: ['mesh:progress']),
      before);
  await a.meshLibrary!.close();
  a.meshLibrary = MeshLibrary(a, mac);
  await a.meshLibrary!.start();
  await a.meshLibrary!.refresh();
  for (final old in oldWorks)
    expect((await a.work(old.workId))!.workId, merged.workId);
  await File('${source.root.path}/unique.bin').delete();
  await b.meshLibrary!.refresh();
  await a.meshLibrary!.refresh();
  expect((await a.episodes(merged.workId)).single.device, null);
  print(
      'X47c catalogue: two works became one after accepted TMDB identity; old work/episode IDs survive identity change and cache restart; merged metadataFacts reads canonical IDs; NaN progress leaves cache unchanged; removed peer file does not replace local playable source.');
}
