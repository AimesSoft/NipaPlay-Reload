import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/file_indexing.dart';
import 'package:nipaplay/next/media/media_capability.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/danmaku/store.dart';
import 'danmaku_test_support.dart';
import 'media_test_support.dart';

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Listing extends Action<_Json, _Json> {
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'fixture.list',
      title: 'List',
      description: 'Synthetic files',
      effect: Effect.read,
      input: ObjectSchema({}),
      output: ObjectSchema({}, additionalProperties: true));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async =>
      const Completed(_Json({
        'files': [
          {'path': '/fixture/listed.mkv'},
          {'path': 'smb://fixture/video.mkv'}
        ]
      }));
}

final class _Capability implements Capability {
  @override
  List<Action> get actions => [_Listing()];
}

void main() {
  late DanmakuFixture f;
  setUp(() async {
    f = DanmakuFixture();
    await f.open();
  });
  tearDown(() => f.close());
  test(
      'Classic listing indexes every returned location while preserving its public result',
      () async {
    final harness =
        Harness([FileIndexingCapability(_Capability(), f.identities)]);
    final result =
        await harness.invokeJson('fixture.list', {}, Invocation(origin: 'mcp'));
    expect(result, isA<Completed>());
    final db = f.jobs.database;
    expect((await db.query('media_entities')).map((e) => e['kind']),
        ['file', 'file']);
    expect((await db.query('media_locations')).map((e) => e['locator']),
        ['/fixture/listed.mkv', 'smb://fixture/video.mkv']);
    expect(await db.query('media_bindings'), isEmpty);
    expect((result as Completed).value.toJson()['files'], hasLength(2));
  });
  test('media identity resolves unindexed paths and the host current file',
      () async {
    final service = MediaService(
        store: f.identities,
        providers: [],
        classic: MemoryClassic(),
        authorizedRoots: () => []);
    service.currentPath = () => '/fixture/current.mkv';
    final harness = Harness([MediaCapability(service)]);
    for (final input in [
      {'path': '/fixture/direct.mkv'},
      {'current': true}
    ]) {
      final result = await harness.invokeJson(
          'media.identity.get', input, Invocation(origin: 'mcp'));
      expect(result, isA<Completed>(), reason: '${result.toEnvelope()}');
      final value = (result as Completed).value.toJson();
      expect(harness.lookup('media.identity.get')!.spec.output.validate(value),
          isEmpty);
    }
    expect(
        (await f.jobs.database.query('media_entities')).map((e) => e['kind']),
        ['file', 'file']);
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
  });

  test(
      'first identification hydrates the current file inside the task without a preceding scan',
      () async {
    final media = MediaFixture();
    await media.open();
    addTearDown(media.close);
    final video = await File('${media.media.path}/长安十二时辰 S01E01.mkv')
        .writeAsString('synthetic video');
    media.service.currentPath = () => video.path;
    await media.identities.importLegacy([
      {
        'filePath': video.path,
        'animeName': '',
        'episodeTitle': null,
        'animeId': null,
        'episodeId': null,
        'videoHash': null
      }
    ]);
    await media.call('media.identity.get', {'current': true});
    final fileId = await media.identities.ensureFile(video.path);
    final danmaku = DanmakuStore(media.identities);
    final binding = await danmaku.attach(
        fileId, biliVideo, '合成证据', null, Invocation(origin: 'mcp'));
    final started = await media.call('media.identification.start', {
      'current': true,
      'sources': ['tmdb']
    });
    final jobId = (started['job'] as JsonMap)['jobId'] as String;
    await waitForJob(media.engine, jobId, JobState.needsDecision);
    expect((await media.identities.entity(fileId))['revision'], 0);
    expect((await danmaku.binding(binding))['status'], 'accepted');
    expect(
        await media.jobs.database
            .query('media_entities', where: 'kind = ?', whereArgs: ['file']),
        hasLength(1));
    expect((await media.identities.entity(fileId))['attributes'],
        containsPair('probe', isNotEmpty));
  });
}
