import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/capability.dart';
import 'package:nipaplay/next/danmaku/executors.dart';
import 'package:nipaplay/next/danmaku/service.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/danmaku/sources.dart';
import 'package:nipaplay/next/danmaku/store.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Synthetic protocol responses, not recordings of platform content or accounts.
List<int> jsonBytes(Object value) => utf8.encode(jsonEncode(value));
List<int> varint(BigInt value) {
  final bytes = <int>[];
  do {
    var b = (value & BigInt.from(127)).toInt();
    value >>= 7;
    if (value != BigInt.zero) b |= 128;
    bytes.add(b);
  } while (value != BigInt.zero);
  return bytes;
}

List<int> numberField(int field, int value) =>
    [field << 3, ...varint(BigInt.from(value))];
List<int> bytesField(int field, List<int> value) =>
    [(field << 3) | 2, ...varint(BigInt.from(value.length)), ...value];
List<int> biliSegment(
        {String id = '9007199254740993',
        int timeMs = 1000,
        String text = '合成弹幕样本内容',
        String sender = 'sender-hash-fixture',
        int mode = 1}) =>
    bytesField(1, [
      ...numberField(2, timeMs),
      ...numberField(3, mode),
      ...numberField(4, 25),
      ...numberField(5, 16777215),
      ...bytesField(6, utf8.encode(sender)),
      ...bytesField(7, utf8.encode(text)),
      ...bytesField(12, utf8.encode(id))
    ]);
JsonMap youkuPayload(List<JsonMap> rows) => {
      'ret': ['SUCCESS::调用成功'],
      'data': {
        'result': jsonEncode({
          'data': {'result': rows}
        })
      }
    };
JsonMap youkuEntry({String id = 'entry-fixture', int time = 1000}) => {
      'id': id,
      'playat': time,
      'content': '优酷合成弹幕内容',
      'propertis': jsonEncode({'pos': 4, 'color': 16777215, 'size': 25})
    };

final class FixtureDanmakuHost implements DanmakuHost {
  final List<JsonMap> requests = [];
  final Map<String, List<int>> responses = {
    'dandanplay.comments': jsonBytes({
      'comments': [
        {
          'cid': 1,
          'p': '1,1,16777215,hash-a',
          'm': '合成弹幕样本内容',
          'source': 'bilibili',
          'sourceVideoId': '101',
          'originalId': '9007199254740993'
        },
        {'cid': 2, 'p': '2,5,255,hash-b', 'm': '来自其他平台', 'source': 'acfun'},
        {'cid': 3, 'p': '3,4,255,0', 'm': '没有来源证据'}
      ]
    }),
    'bilibili.view': jsonBytes({
      'code': 0,
      'data': {
        'title': '分 P 样本',
        'pages': [
          {'cid': 101, 'part': '第一段', 'duration': 360, 'page': 1},
          {'cid': 102, 'part': '第二段', 'duration': 420, 'page': 2}
        ]
      }
    }),
    'bilibili.segment:1': biliSegment(),
    'bilibili.segment:2': biliSegment(id: 'second-id', timeMs: 361000),
    'youku.video':
        jsonBytes({'id': 'Xfixture', 'title': '优酷样本', 'duration': 120}),
    'youku.episodes': jsonBytes({
      'total': 1,
      'videos': [
        {'id': 'Xfixture', 'title': '优酷样本', 'duration': 120}
      ]
    }),
    'youku.minute:0': jsonBytes(youkuPayload([youkuEntry()])),
    'youku.minute:1':
        jsonBytes(youkuPayload([youkuEntry(id: 'entry-two', time: 61000)])),
  };
  Completer<void>? entered, release;
  String? blockedKey;
  SourceFailure? failure;
  bool session = true;
  @override
  bool sessionAvailable(String sourceId) => sourceId == 'youku' && session;
  @override
  Future<List<int>> request(String profile, JsonMap parameters,
      DanmakuAccess? access, DanmakuCancellation cancel) async {
    cancel.check();
    final key = profile == 'youku.minute'
        ? '$profile:${parameters['minute']}'
        : profile == 'bilibili.segment'
            ? '$profile:${parameters['segmentIndex']}'
            : profile;
    requests.add({
      'profile': profile,
      'parameters': parameters,
      'accessRef': access?.credentialRef
    });
    if (blockedKey == key) {
      if (entered != null && !entered!.isCompleted) entered!.complete();
      await Future.any([release!.future, cancel.stopped]);
      cancel.check();
    }
    if (failure case final e?) {
      failure = null;
      throw e;
    }
    final result = responses[key];
    if (result == null) throw StateError('Unrecorded synthetic request $key');
    return result;
  }
}

final class MemoryDanmakuPlayer implements DanmakuPlayerPort {
  @override
  DanmakuPlaybackTarget? target;
  final Map<String, JsonMap> tracks = {};
  final Map<String, List<DanmakuEntry>> data = {};
  @override
  Set<String> get managedTracks => tracks.keys.toSet();
  @override
  JsonMap? loaded(String bindingId) => tracks[bindingId];
  @override
  bool install(DanmakuPlaybackTarget expected, JsonMap binding,
      List<DanmakuEntry> entries,
      {int startMs = 0, int? endMs}) {
    if (target?.path != expected.path ||
        target?.generation != expected.generation) {
      return false;
    }
    final id = binding['id'] as String;
    tracks[id] = {
      'revision': binding['revision'],
      'cacheKey': binding['cache_key'],
      'cacheRevision': binding['cache_revision'],
      'startMs': startMs,
      'endMs': endMs,
      'enabled': binding['enabled'] == 1,
      'offsetMs': binding['offset_ms']
    };
    data[id] = entries;
    return true;
  }

  @override
  void remove(String bindingId) {
    tracks.remove(bindingId);
    data.remove(bindingId);
  }
}

final class DanmakuFixture {
  late Directory root;
  late SqliteJobStore jobs;
  late IdentityStore identities;
  late DanmakuService service;
  late TaskEngine engine;
  late Harness harness;
  final host = FixtureDanmakuHost();
  final player = MemoryDanmakuPlayer();
  Future<void> open() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('next-danmaku-');
    await connect();
  }

  Future<void> connect() async {
    jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    identities = IdentityStore(jobs.database, 'fixture-device');
    service = DanmakuService(
        store: DanmakuStore(identities),
        host: host,
        player: player,
        sources: [
          DandanplayDanmakuSource(host),
          BilibiliDanmakuSource(host),
          YoukuDanmakuSource(host)
        ]);
    engine = TaskEngine(
        store: jobs,
        ownerDeviceId: 'fixture-device',
        executors: danmakuExecutors(service));
    service.engine = engine;
    harness = Harness([DanmakuCapability(service), TaskCapability(engine)]);
    await engine.start();
  }

  Future<String> file(
      {String path = '/fixture/video.mkv', int size = 1}) async {
    final id = await identities.registerFile(
        path, {'size': size, 'modifiedAt': 'fixture', 'headMd5': 'fixture'});
    player.target = DanmakuPlaybackTarget(path, 1);
    return id;
  }

  Future<JsonMap> call(String id, JsonMap input,
      {String origin = 'mcp'}) async {
    final outcome =
        await harness.invokeJson(id, input, Invocation(origin: origin));
    final envelope = outcome.toEnvelope();
    expect(envelope['status'], 'completed', reason: jsonEncode(envelope));
    final result = Map<String, Object?>.from(envelope['result'] as Map);
    expect(harness.lookup(id)!.spec.output.validate(result), isEmpty,
        reason: id);
    return result;
  }

  Future<Job> wait(String id, JobState state) async {
    for (var i = 0; i < 100; i++) {
      final job = await engine.get(id);
      if (job.state == state) return job;
      if (job.state.isTerminal) {
        fail('Expected $state: ${jsonEncode(job.toJson())}');
      }
      await engine.wait(id,
          afterRevision: job.revision,
          timeout: const Duration(milliseconds: 100));
    }
    throw StateError('Timed out');
  }

  Future<void> reopen() async {
    await engine.close();
    player.tracks.clear();
    player.data.clear();
    await connect();
  }

  Future<void> close() async {
    await engine.close();
    await root.delete(recursive: true);
  }
}

const biliVideo = DanmakuVideo(
    sourceId: 'bilibili',
    videoId: '101',
    title: '测试分 P',
    durationMs: 720000,
    objectType: 'cid');
const youkuVideo = DanmakuVideo(
    sourceId: 'youku', videoId: 'Xfixture', title: '测试剧集', durationMs: 120000);
const ddpVideo = DanmakuVideo(
    sourceId: 'dandanplay',
    videoId: '7101',
    title: '测试动画',
    durationMs: 720000,
    objectType: 'episode');
