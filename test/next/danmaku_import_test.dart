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
import 'package:nipaplay/utils/danmaku_parser.dart';
import 'package:nipaplay/utils/danmaku_xml_utils.dart';
import 'package:nipaplay/utils/local_danmaku_file.dart';
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
    await core.danmaku.stopIndexing();
    final media = File('${root.path}/episode.mkv');
    await media.writeAsString('offline synthetic video');
    entityId = await core.media.service.index(media.path);
    video = _Video(await media.resolveSymbolicLinks());
    service = DanmakuService(
        store: core.danmaku.service.store, sources: [], player: video)
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

  test('Classic ARGB rows retain all entries and metadata after restoration',
      () async {
    final content =
        '<pool><chatserver>youku</chatserver><chatid>Xsynthetic</chatid>'
        '${List.generate(140, (i) => '<d p="${i / 10},${[
              1,
              4,
              5,
              6,
              7
            ][i % 5]},25,'
            '${i < 135 ? 0xff02cc92 : 0x02cc92},1700000000,0,synthetic-$i,'
            '${9007199254740993 + i}">合成弹幕 $i &amp; 内容</d>').join()}'
        '</pool>';
    await pool.writeAsString(content);
    final classicData = parseLocalDanmakuBytes(await pool.readAsBytes());
    final classic =
        parseDanmakuListInBackground(classicData['comments'] as List);
    final result = await call('danmaku.import', input());
    expect(result['count'], classic.length);
    expect(result['count'], 140);
    final binding = await service.store.binding(result['bindingId'] as String);
    final saved = await service.store.entries(binding['cache_key'] as String);
    for (var i = 0; i < saved.length; i++) {
      expect(saved[i].text, classic[i]['content']);
      expect(saved[i].sourceTimeMs, i * 100);
      expect(saved[i].colorRgb, parseDanmakuColorToInt(classic[i]['color']));
      expect(saved[i].platformId, '${9007199254740993 + i}');
      expect(saved[i].sender, 'synthetic-$i');
      expect(saved[i].fontSize, 25);
      expect(saved[i].sentAt, '1700000000');
      expect(saved[i].mode, [1, 4, 5, 6, 7][i % 5]);
      expect(saved[i].toPlayer()['type'], classic[i]['type']);
    }
    await pool.delete();
    video.danmakuTracks.clear();
    video.danmakuTrackEnabled.clear();
    await service.refreshCurrent();
    expect(video.danmakuTracks.values.single['count'], 140);
    expect(video.danmakuTracks.values.single['danmakuList'],
        saved.map((e) => e.toPlayer()).toList());
  });

  test('Classic JSON and byte encodings retain the same playable data',
      () async {
    const xmlText = '<i><d p="1.25,5,25,4278373522,1700000000,0,sender,42">'
        '合成弹幕 &amp; 内容</d></i>';
    final utf16 = [
      for (final littleEndian in [true, false])
        <int>[
          ...littleEndian ? [0xff, 0xfe] : [0xfe, 0xff],
          for (final unit in xmlText.codeUnits)
            ...littleEndian ? [unit & 255, unit >> 8] : [unit >> 8, unit & 255],
        ]
    ];
    final fixtures = [
      utf8.encode('\uFEFF$xmlText'),
      ...utf16,
      utf8.encode(jsonEncode([
        {'t': '1.25', 'c': '合成弹幕', 'y': 'top', 'r': '#ff02cc92'}
      ])),
      utf8.encode(jsonEncode([
        {'time': 1.25, 'content': '合成弹幕', 'color': 255},
        {'text': 'Classic 不作为弹幕加载的合成元数据', 'mode': 'metadata'},
      ])),
      utf8.encode(jsonEncode({
        'data': jsonEncode([
          {'time': 1.25, 'content': '合成弹幕', 'type': 5, 'color': 0xff02cc92}
        ])
      })),
      utf8.encode(jsonEncode({
        'comments': [
          {'p': '1.25,5,16711680,synthetic', 'm': '合成弹幕', 'cid': 42}
        ]
      })),
      // GBK bytes for a synthetic Chinese text node.
      [
        ...ascii.encode('<?xml version="1.0" encoding="GBK"?>'
            '<i><d p="1.25,5,25,255">'),
        0xba,
        0xcf,
        0xb3,
        0xc9,
        ...ascii.encode('</d></i>'),
      ],
    ];
    for (final bytes in fixtures) {
      await pool.writeAsBytes(bytes);
      final classicData = parseLocalDanmakuBytes(await pool.readAsBytes());
      final classic =
          parseDanmakuListInBackground(classicData['comments'] as List);
      final result = await call('danmaku.import', input());
      expect(result['count'], classic.length);
      final row = classic.single;
      final loaded = (video.danmakuTracks.values.single['danmakuList'] as List)
          .single as Map;
      expect(loaded['time'], row['time']);
      expect(loaded['content'], row['content']);
      expect(
          loaded['color'],
          'rgb(${(parseDanmakuColorToInt(row['color']) >> 16) & 255},'
          '${(parseDanmakuColorToInt(row['color']) >> 8) & 255},'
          '${parseDanmakuColorToInt(row['color']) & 255})');
    }
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
      '<i><d',
      '<i><d p="1,1">缺少必要字段</d></i>',
      '<i><d p="NaN,1,25,255">坏数据</d></i>',
      '{"data":"{}"}',
      '[{"time":"Infinity","content":"不可存储的时间"}]',
      '{"platform":42,"comments":[{"time":1,"content":"合成弹幕"}]}',
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
      'full episode files keep all 50000 entries and empty refresh cannot erase them',
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
    for (final content in ['[]', '<i/>', '{"data":[]}']) {
      await pool.writeAsString(content);
      expect(() => parseLocalDanmakuBytes(utf8.encode(content)),
          throwsFormatException,
          reason: 'Classic still rejects empty local pools');
      final empty = await api.invokeJson('danmaku.import',
          input(platform: 'custom-platform'), Invocation(origin: 'mcp'));
      expect(empty, isA<Failed>());
      expect(video.danmakuTracks.values.single['count'], 50000);
      final binding = await core.danmaku.service.store.binding(result['bindingId'] as String);
      expect(await core.danmaku.service.store.entries(binding['cache_key'] as String), hasLength(50000));
    }
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
    f.host.blockedKey = 'segmented.chunk:0';
    f.host.entered = Completer<void>();
    f.host.release = Completer<void>();
    final pending = await f.call('danmaku.attach', {
      'entityId': file,
      'video': segmentedVideo.toJson(),
      'reason': 'synthetic',
      'requestId': 'before-import'
    });
    await f.host.entered!.future;
    await xml('交入结果');
    final imported = await f.call('danmaku.import',
        {...input(platform: 'segmented', id: '101'), 'entityId': file});
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
      'video': segmentedVideo.toJson(),
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
