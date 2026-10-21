import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/accounts/collections.dart';
import 'package:nipaplay/next/capabilities/download_metadata_capability.dart';
import 'package:nipaplay/next/downloads/download_source.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/models/torrent_magnet_preview.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'media_test_support.dart';

class _Direct extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('history keyset continues after deleting the anchor and earlier records',
      () async {
    final rows = <JsonMap>[
      for (var i = 0; i < 7; i++)
        {'entryId': '$i', 'lastWatchedAt': '2026-10-${20 - i}'}
    ];
    final state = StateCapability([
      StateView(
          name: 'history',
          description: '',
          fields: const ObjectSchema(
              {'entryId': StringSchema(), 'lastWatchedAt': StringSchema()}),
          read: (offset, limit) async => rows.skip(offset).take(limit).toList(),
          cursorKey: 'entryId',
          cursorOrder: const [
            {'field': 'lastWatchedAt', 'direction': 'desc'}
          ])
    ]);
    final query = <String, Object?>{
      'view': 'history',
      'limit': 2,
      'select': ['entryId']
    };
    final first = await state.query(query);
    expect((first['rows'] as List).map((r) => r['entryId']), ['0', '1']);
    rows.removeWhere((r) => ['0', '1'].contains(r['entryId']));
    rows.insert(0, {'entryId': 'new', 'lastWatchedAt': '2026-10-30'});
    final second = await state.query({...query, 'cursor': first['nextCursor']});
    expect((second['rows'] as List).map((r) => r['entryId']), ['2', '3']);
    rows.removeWhere((r) => r['entryId'] == '3');
    final third = await state.query({...query, 'cursor': second['nextCursor']});
    expect((third['rows'] as List).map((r) => r['entryId']), ['4', '5']);
    await expectLater(
        state.query({...query, 'limit': 3, 'cursor': first['nextCursor']}),
        throwsA(isA<Failure>()));
  });

  test(
      'collection pages filter statuses with one request per page and retain unknown ratings',
      () async {
    var requests = 0;
    Future<JsonMap> bangumi(int offset, int limit) async {
      requests++;
      final all = [
        for (var i = 0; i < 5; i++)
          {'subject_id': i + 1, 'type': i.isEven ? 3 : 2, 'rate': i + 1}
      ];
      return {
        'data': all.skip(offset).take(limit).toList(),
        'total': all.length
      };
    }

    Future<List<JsonMap>> dandan() async => [
          {'animeId': 1, 'favoriteStatus': 'favorited'},
          {'animeId': 2, 'favoriteStatus': 'finished', 'userRating': 8},
        ];
    final input = <String, Object?>{
      'provider': 'bangumi',
      'statuses': ['doing'],
      'limit': 2
    };
    final first =
        await listCollections(input, bangumi: bangumi, dandanplay: dandan);
    final second = await listCollections(
        {...input, 'cursor': first['nextCursor']},
        bangumi: bangumi, dandanplay: dandan);
    final third = await listCollections(
        {...input, 'cursor': second['nextCursor']},
        bangumi: bangumi, dandanplay: dandan);
    expect(requests, 3);
    expect([
      for (final page in [first, second, third])
        ...(page['items'] as List).map((r) => r['workId'])
    ], [
      1,
      3,
      5
    ]);
    expect(third['nextCursor'], isNull);
    final dd = await listCollections({'provider': 'dandanplay', 'limit': 1},
        bangumi: bangumi, dandanplay: dandan);
    expect((dd['items'] as List).single['rating'], isNull);
    await expectLater(
        listCollections(
            {'provider': 'dandanplay', 'cursor': first['nextCursor']},
            bangumi: bangumi, dandanplay: dandan),
        throwsA(isA<Failure>()));
    expect(requests, 3);
  });

  test(
      'torrent file and loopback URL preview create only metadata cache, preserve file ordering and reject traversal',
      () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _Direct();
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final root = await Directory.systemTemp.createTemp('x60-preview-');
    final torrent = Uint8List.fromList(ascii.encode(
        'd4:infod5:filesld6:lengthi4e4:pathl5:a.mkveed6:lengthi6e4:pathl5:b.mkveee4:name6:series12:piece lengthi16e6:pieces20:${'p' * 20}ee'));
    final local =
        await File('${root.path}/sample.torrent').writeAsBytes(torrent);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.add(torrent);
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await root.delete(recursive: true);
    });
    final sources = DownloadSources(Directory('${root.path}/cache'),
        clientFactory: () => HttpClient()..findProxy = (_) => 'DIRECT');
    final api =
        Harness([DownloadMetadataCapability(sources, () async => true)]);
    JsonMap? previous;
    for (final source in [
      local.path,
      local.uri.toString(),
      'http://127.0.0.1:${server.port}/sample.torrent'
    ]) {
      final outcome = await api.invokeJson(
          'download.preview', {'source': source}, Invocation(origin: 'gui'));
      expect(outcome, isA<Completed>(),
          reason: jsonEncode(outcome.toEnvelope()));
      final result = (outcome as Completed).value.toJson();
      expect(result['totalSize'], 10);
      expect((result['files'] as List).map((f) => f['path']),
          ['series/a.mkv', 'series/b.mkv']);
      if (previous != null) expect(result, previous);
      previous = result;
    }
    expect(await root.list().map((f) => f.path.split('/').last).toList(),
        containsAll(['sample.torrent', 'cache']));
    final hostile = Uint8List.fromList(ascii.encode(
        'd4:infod6:lengthi4e4:name2:..12:piece lengthi16e6:pieces20:${'p' * 20}ee'));
    expect(() => torrentManifest(hostile), throwsA(isA<Failure>()));
  });

  test('a magnet preview without metadata stops at waitSeconds and says so',
      () async {
    final root = await Directory.systemTemp.createTemp('x60-magnet-');
    addTearDown(() => root.delete(recursive: true));
    final requests = <TorrentPreviewRequest>[];
    final api = Harness([
      DownloadMetadataCapability(
          DownloadSources(Directory('${root.path}/cache')), () async => true,
          previewMagnet: (source, {downloadDirectory, required request}) {
        requests.add(request);
        // Peers answer only for the second magnet; the first has none.
        return requests.length == 1
            ? Completer<TorrentMagnetPreview>().future
            : Future.value(const TorrentMagnetPreview(
                name: 'n', suggestedFolderName: 'n', totalSize: 1, files: []));
      })
    ]);
    final watch = Stopwatch()..start();
    final silent = await api.invokeJson(
        'download.preview',
        {'source': 'magnet:?xt=urn:btih:${'a' * 40}', 'waitSeconds': 1},
        Invocation(origin: 'agent'));
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(jsonEncode(silent.toEnvelope()), contains('No metadata arrived'));
    expect(requests.single.throwIfCancelled, throwsStateError,
        reason: 'the native preview is cancelled');
    final answered = await api.invokeJson('download.preview',
        {'source': 'magnet:?xt=urn:btih:${'b' * 40}'}, Invocation(origin: 'gui'));
    expect((answered as Completed).value.toJson()['name'], 'n');
  });

  test(
      'association preview is inert, stale edits fail, progress survives unmatch and rebuild',
      () async {
    final f = MediaFixture();
    await f.open();
    addTearDown(f.close);
    final file = await f.file('managed.mkv');
    final path =
        (await f.identities.locations(file)).single['locator'] as String;
    f.classic.rows[path] = {
      'filePath': path,
      'watchProgress': 0.4,
      'lastPosition': 400,
      'duration': 1000
    };
    final request = <String, Object?>{
      'requestId': 'x60-bind',
      'entries': [
        tmdbBinding(file, episodes: [1])
      ]
    };
    final before = await f.jobs.database.query('media_file_episodes');
    final preview = await f.call('media.management.bind_batch', request);
    expect(await f.jobs.database.query('media_file_episodes'), before);
    await f.call('media.identity.bind_batch', {...request, 'requestId': 'intervening-match'});
    final stale = await f.harness.invokeJson(
        'media.management.bind_batch',
        {...request, 'expectedPlan': preview['expectedPlan']},
        Invocation(origin: 'mcp'));
    expect(stale, isA<Failed>());
    final fresh = await f.call('media.management.bind_batch', request);
    await f.call('media.management.bind_batch',
        {...request, 'expectedPlan': fresh['expectedPlan']});
    final undo = <String, Object?>{
      'requestId': 'x60-unbind',
      'entries': [
        {'entityId': file, 'reason': 'user unmatched'}
      ]
    };
    final p = await f.call('media.management.unbind_batch', undo);
    f.classic.rows[path]!['watchProgress'] = 0.7;
    await f.call('media.management.unbind_batch',
        {...undo, 'expectedPlan': p['expectedPlan']});
    expect(await File(path).exists(), true);
    expect(f.classic.rows[path]!['watchProgress'], 0.7);
    final rebuild = {...request, 'requestId': 'x60-rebuild'};
    final b = await f.call('media.management.bind_batch', rebuild);
    await f.call('media.management.bind_batch',
        {...rebuild, 'expectedPlan': b['expectedPlan']});
    expect(f.classic.rows[path]!['watchProgress'], 0.7);
  });
}
