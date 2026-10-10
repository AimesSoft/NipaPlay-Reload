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

List<int> jsonBytes(Object value) => utf8.encode(jsonEncode(value));

/// Segmented synthetic source for storage/task tests; no platform protocol.
final class FixtureDanmakuSource implements DanmakuSource {
  const FixtureDanmakuSource(this.host, this.id, this.segmentMs);
  final DanmakuHost host;
  final String id;
  final int segmentMs;
  @override
  DanmakuDescriptor get describe => DanmakuDescriptor(
      id: id,
      platform: id,
      hosts: const ['fixture.invalid'],
      profiles: ['$id.chunk'],
      access: 'anonymous',
      segmentMs: segmentMs);
  DanmakuVideo video(String videoId) => DanmakuVideo(
      sourceId: id,
      videoId: videoId,
      title: videoId,
      durationMs: segmentMs * 2);
  @override
  Future<List<DanmakuVideo>> resolve(
          String locator, DanmakuCancellation cancel) async =>
      locator == 'ambiguous' ? [video('101'), video('102')] : [video(locator)];
  @override
  Future<List<DanmakuVideo>> listEpisodes(
          String workId, int page, DanmakuCancellation cancel) async =>
      [video('Xfixture')];
  @override
  Future<List<DanmakuVideo>> search(
          String query, DanmakuCancellation cancel) async =>
      [video('101')];
  @override
  List<DanmakuChunk> planFetch(DanmakuVideo video, int startMs, int endMs) => [
        for (var i = startMs ~/ segmentMs; i <= (endMs - 1) ~/ segmentMs; i++)
          DanmakuChunk(i, i * segmentMs, (i + 1) * segmentMs)
      ];
  @override
  bool validate(List<DanmakuChunk> plan, Set<int> completed) =>
      completed.length == plan.length &&
      plan.every((chunk) => completed.contains(chunk.index));
  @override
  Future<DanmakuChunkResult> fetchChunk(DanmakuVideo video, DanmakuChunk chunk,
      DanmakuCancellation cancel) async {
    final rows = jsonDecode(utf8.decode(
        await host.request('$id.chunk', {'index': chunk.index}, cancel)));
    if (rows is! List) throw const SourceFailure(SourceStatus.schemaChanged);
    return DanmakuChunkResult([
      for (final row in rows)
        DanmakuEntry.fromJson(Map<String, Object?>.from(row as Map))
    ]);
  }
}

List<int> fixtureChunk(
        {String source = 'segmented',
        String id = '9007199254740993',
        int timeMs = 1000,
        String text = '合成弹幕样本内容'}) =>
    jsonBytes([
      DanmakuEntry(
              sourceId: source,
              videoId: source == 'minutes' ? 'Xfixture' : '101',
              platform: source,
              originVideoId: source == 'minutes' ? 'Xfixture' : '101',
              platformId: id,
              sourceTimeMs: timeMs,
              text: text,
              mode: 1,
              colorRgb: 16777215)
          .toJson()
    ]);

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
    'segmented.chunk:0': fixtureChunk(),
    'segmented.chunk:1': fixtureChunk(id: 'second-id', timeMs: 361000),
    'minutes.chunk:0': fixtureChunk(source: 'minutes'),
    'minutes.chunk:1':
        fixtureChunk(source: 'minutes', id: 'entry-two', timeMs: 61000),
  };
  Completer<void>? entered, release;
  String? blockedKey;
  SourceFailure? failure;
  final Map<String, SourceFailure> failures = {};
  @override
  Future<List<int>> request(
      String profile, JsonMap parameters, DanmakuCancellation cancel) async {
    cancel.check();
    final key = parameters.containsKey('index')
        ? '$profile:${parameters['index']}'
        : profile;
    requests.add({'profile': profile, 'parameters': parameters});
    if (blockedKey == key) {
      if (entered != null && !entered!.isCompleted) entered!.complete();
      await Future.any([release!.future, cancel.stopped]);
      cancel.check();
    }
    if (failure case final e?) {
      failure = null;
      throw e;
    }
    if (failures[key] case final error?) {
      throw error;
    }
    final result = responses[key];
    if (result == null) throw StateError('Unrecorded synthetic request $key');
    return result;
  }
}

class MemoryDanmakuPlayer
    implements DanmakuPlayerPort, DanmakuTrackRegistry, DanmakuTrackUpdater {
  final List<JsonMap> classicTracks = [];
  final Map<String, JsonMap> classicCache = {};
  int reuseCount = 0;
  int installCount = 0;
  @override
  Future<bool> restoreClassic(
      DanmakuPlaybackTarget target, JsonMap binding) async {
    final video = binding['video'] as JsonMap;
    final cached = classicCache[video['videoId']];
    if (cached != null && classicTracks.isEmpty) classicTracks.add({...cached});
    return reuse(target, binding);
  }

  @override
  List<JsonMap> get registry => classicTracks;
  @override
  bool updateTrack(
      DanmakuPlaybackTarget expected, String id, JsonMap properties) {
    if (target?.path != expected.path ||
        target?.generation != expected.generation) {
      return false;
    }
    final track = classicTracks.where((t) => t['trackId'] == id).firstOrNull;
    if (track == null || track['bindingId'] != null) return false;
    track.addAll({
      ...properties,
      if (properties.containsKey('displayFold'))
        'deduplicate': properties['displayFold']
    });
    return true;
  }

  @override
  bool reuse(DanmakuPlaybackTarget expected, JsonMap binding) {
    if (target?.path != expected.path ||
        target?.generation != expected.generation) {
      return false;
    }
    final video = binding['video'] as JsonMap;
    final track = classicTracks
        .where((t) =>
            t['platform'] == video['sourceId'] &&
            t['platformVideoId'] == video['videoId'])
        .firstOrNull;
    if (track == null) return false;
    reuseCount++;
    track['bindingId'] = binding['id'];
    track.addAll({
      'revision': binding['revision'],
      'enabled': binding['enabled'] == 1,
      'offsetMs': binding['offset_ms'],
      'deduplicate': binding['deduplicate'] == 1
    });
    tracks[binding['id'] as String] = {
      'revision': binding['revision'],
      'cacheRevision': binding['cache_revision'],
      'cacheKey': binding['cache_key'],
      'startMs': 0,
      'endMs': null
    };
    return true;
  }

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
    installCount++;
    tracks[id] = {
      'revision': binding['revision'],
      'cacheKey': binding['cache_key'],
      'cacheRevision': binding['cache_revision'],
      'startMs': startMs,
      'endMs': endMs,
      'enabled': binding['enabled'] == 1,
      'deduplicate': binding['deduplicate'] == 1,
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
        player: player,
        sources: [
          DandanplayDanmakuSource(host,
              allowedHosts: const ['fixture.invalid']),
          FixtureDanmakuSource(host, 'segmented', 360000),
          FixtureDanmakuSource(host, 'minutes', 60000)
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

  Future<JsonMap> legacyAlignment(JsonMap input,
      {JobState state = JobState.needsDecision,
      String? choice,
      String candidateState = 'proposed'}) async {
    final id = input['bindingId'] as String;
    final binding = await service.store.binding(id);
    final anchors = input['anchors'] as List;
    final offsets = [
      for (final a in anchors)
        ((a as Map)['sourceTimeMs'] as int) - (a['mediaTimeMs'] as int)
    ]..sort();
    final offset = offsets.isEmpty ? null : offsets[offsets.length ~/ 2];
    final jobId =
        stableMediaId('danmaku-align', [input['requestId'], id, anchors]);
    final proposal = {
      'method': 'manualAnchors',
      'offsetMs': offset,
      'anchors': anchors,
      'maxResidualMs': offset == null
          ? null
          : offsets
              .map((n) => (n - offset).abs())
              .reduce((a, b) => a > b ? a : b),
      'confidence': 'insufficientEvidence',
      'confirmed': false,
      'applicableRange': 'requested media version',
      'autoApply': false
    };
    final date = DateTime.now().toUtc();
    final job = Job(
        jobId: jobId,
        type: 'danmaku.align',
        title: 'Persisted legacy alignment',
        state: state,
        phase: 'estimate',
        progress: JobProgress(completed: 0, unit: 'anchors'),
        createdAt: date,
        updatedAt: date,
        ownerDeviceId: 'fixture-device',
        revision: 0,
        sideEffectCommitted: true,
        checkpoint: {
          if (choice != null) ...{
            'choice': choice,
            'invocationId': 'legacy-invocation',
            'boundBy': 'agent'
          }
        },
        input: {...input, 'bindingRevision': binding['revision']},
        decision: state == JobState.needsDecision
            ? Decision(prompt: 'Persisted legacy choice', options: [
                if (offset != null)
                  DecisionOption(
                      label: 'Apply',
                      call: ActionCall('danmaku.align_apply',
                          {'jobId': jobId, 'revision': 0})),
                DecisionOption(
                    label: 'Keep',
                    call: ActionCall(
                        'danmaku.align_keep', {'jobId': jobId, 'revision': 0}))
              ])
            : null);
    await jobs.commit(
        job,
        JobEvent(
            jobId: jobId,
            revision: 0,
            kind: 'needs_decision',
            at: date,
            snapshot: job.toJson()),
        expectedRevision: null);
    await jobs.database.insert('danmaku_alignment_candidates', {
      'job_id': jobId,
      'binding_id': id,
      'binding_revision': binding['revision'],
      'payload': jsonEncode(proposal),
      'state': candidateState
    });
    return {'jobId': jobId};
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

const segmentedVideo = DanmakuVideo(
    sourceId: 'segmented', videoId: '101', title: '分段测试', durationMs: 720000);
const minuteVideo = DanmakuVideo(
    sourceId: 'minutes',
    videoId: 'Xfixture',
    title: '测试剧集',
    durationMs: 120000);
const ddpVideo = DanmakuVideo(
    sourceId: 'dandanplay',
    videoId: '7101',
    title: '测试动画',
    durationMs: 720000,
    objectType: 'episode');
