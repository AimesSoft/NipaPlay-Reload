import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/next/danmaku/capability.dart';
import 'package:nipaplay/next/danmaku/service.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/utils/danmaku_track_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'danmaku_test_support.dart';
import 'download_test_support.dart';
import 'media_test_support.dart';

class _Video extends MemoryDanmakuPlayer {
  _Video(this.currentVideoPath) {
    target = DanmakuPlaybackTarget(currentVideoPath, 1, durationMs: 3000000);
  }
  final String currentVideoPath;
  final danmakuTracks = <String, Map<String, dynamic>>{};
  final danmakuTrackEnabled = <String, bool>{};
  @override
  Set<String> get managedTracks => danmakuTracks.keys.toSet();
  @override
  JsonMap? loaded(String bindingId) =>
      danmakuTracks.containsKey(bindingId) ? super.loaded(bindingId) : null;
  @override
  List<JsonMap> get registry => [
        for (final t in danmakuTracks.entries)
          {
            'trackId': t.key,
            for (final e in t.value.entries)
              if (!['danmakuList', 'timeOffset'].contains(e.key))
                e.key: e.value,
            'enabled': danmakuTrackEnabled[t.key],
          }
      ];
  @override
  bool install(DanmakuPlaybackTarget expected, JsonMap binding,
      List<DanmakuEntry> entries,
      {int startMs = 0, int? endMs}) {
    if (!super
        .install(expected, binding, entries, startMs: startMs, endMs: endMs)) {
      return false;
    }
    final v = binding['video'] as Map;
    registerDanmakuSourceTrack(
        danmakuTracks,
        danmakuTrackEnabled,
        binding['id'] as String,
        {
          'bindingId': binding['id'],
          'entityId': binding['entity_id'],
          'source': v['sourceId'],
          'platform': v['sourceId'],
          'platformVideoId': v['videoId'],
          'origin':
              binding['bound_by'] == 'agent' ? 'agent_import' : 'manual_import',
          'provenance': binding['provenance'],
          'revision': binding['revision'],
          'deduplicate': binding['deduplicate'] == 1,
          'offsetMs': binding['offset_ms'],
          'timeOffset': (binding['offset_ms'] as int) / 1000,
          'danmakuList': [for (final e in entries) e.toPlayer()],
          'count': entries.length,
        },
        binding['enabled'] == 1);
    return true;
  }

  @override
  void remove(String bindingId) {
    super.remove(bindingId);
    danmakuTracks.remove(bindingId);
    danmakuTrackEnabled.remove(bindingId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late NextCore core;
  late Harness api;
  late _Video video;
  late DanmakuService service;
  late String entityId;
  late File pool;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('next-import-');
    core = NextCore(
        root: root,
        databaseFactory: databaseFactoryFfi,
        downloadBackend: FakeDownloadBackend(root),
        downloadLibrary: FakeDownloadLibrary(),
        isDownloaderEnabled: () async => false,
        loadImportedKeys: () async => {},
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path],
        mediaProviders: [],
        mediaDurationProbe: (_) async => 3000000);
    await core.ready;
    final media = File('${root.path}/episode.mkv');
    await media.writeAsString('offline synthetic video');
    entityId = await core.media.service.index(media.path);
    video = _Video(await media.resolveSymbolicLinks());
    service = DanmakuService(
        store: core.danmaku.service.store,
        sources: [],
        host: FixtureDanmakuHost(),
        player: video)
      ..engine = core.engine;
    api = Harness([
      DanmakuCapability(service),
      StateCapability(publicStateViews(
          media: core.media.service,
          settings: core.settings,
          danmaku: service,
          mesh: core.mesh,
          sources: core.stateSources))
    ]);
    pool = File('${root.path}/pool.xml');
  });
  tearDown(() async {
    await core.close();
    await root.delete(recursive: true);
  });

  Future<JsonMap> call(String id, JsonMap input,
      {String origin = 'mcp'}) async {
    final outcome = await api.invokeJson(id, input, Invocation(origin: origin));
    expect(outcome, isA<Completed>(), reason: jsonEncode(outcome.toEnvelope()));
    final result = (outcome as Completed).value.toJson();
    expect(api.lookup(id)!.spec.output.validate(result), isEmpty,
        reason: '$id: ${jsonEncode(result)}');
    return result;
  }

  JsonMap input({String platform = 'youku', String id = 'Xfixture'}) => {
        'filePath': pool.path,
        'platform': platform,
        'platformVideoId': id,
      };
  Future<void> xml(String text) => pool.writeAsString(
      '<i><d p="1.25,5,25,255,1700000000,0,sender,9007199254740993">$text</d></i>');

  test(
      'imports without a host session, mounts immediately and exposes provenance',
      () async {
    await xml('浏览器取得的弹幕 &amp; 内容');
    final before = DateTime.now().toUtc();
    final result = await call(
        'danmaku.import', {...input(), 'note': 'browser acquisition'});
    expect(result['loaded'], true);
    expect(result['count'], 1);
    final provenance = result['provenance'] as Map;
    expect(provenance['platform'], 'youku');
    expect(provenance['platformVideoId'], 'Xfixture');
    expect(provenance['actor'], 'agent');
    expect(provenance['origin'], 'mcp');
    expect(provenance['note'], 'browser acquisition');
    expect(DateTime.parse(provenance['importedAt'] as String).isBefore(before),
        false);
    final entry = (video.danmakuTracks.values.single['danmakuList'] as List)
        .single as Map;
    expect(entry['time'], 1.25);
    expect(entry['content'], '浏览器取得的弹幕 & 内容');
    expect(entry['type'], 'top');
    expect(entry['platformDanmakuId'], '9007199254740993');
    expect(entry['source'], 'youku');
    final tracks = (await call('danmaku.tracks', {}))['tracks'] as List;
    expect(tracks.single['provenance'], provenance);
    expect(tracks.single['origin'], 'agent_import');
    for (final view in ['danmaku.tracks', 'danmaku.bindings']) {
      final rows = (await call('state.query', {'view': view}))['rows'] as List;
      expect(rows.single['provenance'], provenance);
      if (view == 'danmaku.bindings') {
        expect(rows.single['loaded'], true);
      } else {
        expect(rows.single['count'], 1);
      }
    }
    expect(await core.engine.list(type: 'danmaku.fetch'), isEmpty);
  });

  test('reimport replaces one platform video and preserves display settings',
      () async {
    await xml('旧弹幕');
    final first = await call('danmaku.import', input());
    await call('danmaku.update', {
      'changes': [
        {
          'bindingId': first['bindingId'],
          'expectedRevision': first['revision'],
          'enabled': false,
          'offsetMs': 250,
          'displayFold': false,
        }
      ]
    });
    await xml('新弹幕');
    final refreshed = await call('danmaku.import', input());
    expect(refreshed['bindingId'], first['bindingId']);
    expect(refreshed['revision'], 2);
    expect(video.danmakuTracks, hasLength(1));
    expect(video.danmakuTrackEnabled.values.single, false);
    final track = video.danmakuTracks.values.single;
    expect(track['deduplicate'], false);
    expect(track['timeOffset'], 0.25);
    expect((track['danmakuList'] as List).single['content'], '新弹幕');
    await call('danmaku.import', input(platform: 'bilibili', id: 'Xfixture'));
    expect(video.danmakuTracks, hasLength(2));
    video.danmakuTracks.clear();
    video.danmakuTrackEnabled.clear();
    await service.refreshCurrent();
    expect(video.danmakuTracks, hasLength(2));
    final restored =
        video.danmakuTracks.values.singleWhere((t) => t['platform'] == 'youku');
    expect((restored['danmakuList'] as List).single['content'], '新弹幕');
  });

  test(
      'a malformed file or transaction failure leaves the previous pool unchanged',
      () async {
    await xml('旧弹幕');
    final first = await call('danmaku.import', input());
    final store = core.danmaku.service.store;
    final before = await store.binding(first['bindingId'] as String);
    final track = video.danmakuTracks.values.single;
    for (final content in [
      '{',
      '<html/>',
      '<i><d p="NaN,1,25,255">坏数据</d></i>',
      jsonEncode([
        {'sourceTimeMs': 1000, 'text': 'valid', 'mode': 1, 'colorRgb': 255},
        {'sourceTimeMs': -1, 'text': 'invalid', 'mode': 1, 'colorRgb': 255}
      ])
    ]) {
      await pool.writeAsString(content);
      final outcome = await api.invokeJson(
          'danmaku.import', input(), Invocation(origin: 'mcp'));
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).failure.code, FailureCode.invalidInput);
      expect(await store.binding(first['bindingId'] as String), before);
      expect(video.danmakuTracks.values.single, same(track));
    }
    await xml('新弹幕');
    final db = store.db;
    final chunks = await db.query('danmaku_cache_chunks');
    await db.execute(
        "CREATE TRIGGER fail_import BEFORE UPDATE ON danmaku_bindings BEGIN SELECT RAISE(ABORT,'synthetic write failure'); END");
    expect(
        await api.invokeJson(
            'danmaku.import', input(), Invocation(origin: 'mcp')),
        isA<Failed>());
    expect(await store.binding(first['bindingId'] as String), before);
    expect(await db.query('danmaku_cache_chunks'), chunks);
    expect(video.danmakuTracks.values.single, same(track));
  });

  test(
      'full episode files keep all 50000 entries and allow an explicitly empty refresh',
      () async {
    final data = [
      for (var i = 0; i < 50000; i++)
        {
          'sourceTimeMs': i * 10,
          'text': '合成弹幕 $i',
          'mode': 1,
          'colorRgb': 0xffffff,
          'platformId': '$i',
        }
    ];
    await pool.writeAsString(jsonEncode({'comments': data}));
    expect(await pool.length(), greaterThan(4000000));
    final result =
        await call('danmaku.import', input(platform: 'custom-platform'));
    expect(result['count'], 50000);
    expect(result['loaded'], true);
    expect(video.danmakuTracks.values.single['count'], 50000);
    expect(
        (video.danmakuTracks.values.single['danmakuList'] as List)
            .last['content'],
        '合成弹幕 49999');
    await pool.writeAsString('[]');
    final empty =
        await call('danmaku.import', input(platform: 'custom-platform'));
    expect(empty['bindingId'], result['bindingId']);
    expect(empty['count'], 0);
    expect(video.danmakuTracks.values.single['count'], 0);
  });

  test(
      'episode imports replace a loaded file track and survive playback restoration',
      () async {
    final db = core.danmaku.service.store.db;
    await db.insert('media_entities', {
      'id': 'episode-fixture',
      'kind': 'episode',
      'revision': 0,
      'attributes': '{}'
    });
    await db.insert('media_file_episodes', {
      'file_id': entityId,
      'episode_id': 'episode-fixture',
      'relation': 'episode',
      'ordinal': 1
    });
    await xml('文件轨道');
    await call('danmaku.import', {...input(), 'path': video.currentVideoPath});
    await xml('集轨道');
    final episode = await call(
        'danmaku.import', {...input(), 'entityId': 'episode-fixture'},
        origin: 'gui');
    expect((episode['provenance'] as Map)['actor'], 'user');
    expect((episode['provenance'] as Map)['origin'], 'gui');
    expect(video.danmakuTracks, hasLength(1));
    expect(
        (video.danmakuTracks.values.single['danmakuList'] as List)
            .single['content'],
        '集轨道',
        reason: jsonEncode({
          'result': episode,
          'tracks': video.danmakuTracks,
          'links': await db.query('media_file_episodes'),
          'bindings': await db.query('danmaku_bindings')
        }));
    video.danmakuTracks.clear();
    video.danmakuTrackEnabled.clear();
    await service.refreshCurrent();
    expect(video.danmakuTracks, hasLength(1));
    expect(
        video.danmakuTracks.values.single['bindingId'], episode['bindingId']);
  });

  test('an import does not allow an earlier in-flight fetch to overwrite it',
      () async {
    final f = DanmakuFixture();
    await f.open();
    addTearDown(f.close);
    final file = await f.file();
    f.host.blockedKey = 'bilibili.segment:1';
    f.host.entered = Completer<void>();
    f.host.release = Completer<void>();
    final pending = await f.call('danmaku.attach', {
      'entityId': file,
      'video': biliVideo.toJson(),
      'reason': 'synthetic',
      'requestId': 'before-import'
    });
    await f.host.entered!.future;
    await xml('交入结果');
    final imported = await f.call('danmaku.import',
        {...input(platform: 'bilibili', id: '101'), 'entityId': file});
    f.host.release!.complete();
    await f.wait(pending['jobId'] as String, JobState.failed);
    final binding =
        await f.service.store.binding(imported['bindingId'] as String);
    expect(
        (await f.service.store.entries(binding['cache_key'] as String))
            .single
            .text,
        '交入结果');
    expect(f.player.data[imported['bindingId']]!.single.text, '交入结果');
    final refresh = await f.call('danmaku.attach', {
      'entityId': file,
      'video': biliVideo.toJson(),
      'reason': 'fresh host acquisition',
      'requestId': 'after-import',
      'refresh': true,
    });
    await f.wait(refresh['jobId'] as String, JobState.succeeded);
    expect(
        (await f.service.store
            .binding(imported['bindingId'] as String))['provenance'],
        isNull);
  });
}
