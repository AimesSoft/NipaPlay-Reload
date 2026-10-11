import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/utils/dandanplay_comments.dart';
import 'danmaku_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DanmakuFixture f;
  setUp(() async {
    f = DanmakuFixture();
    await f.open();
    StorageService.debugAppStorageDirectoryOverride = f.root;
  });
  tearDown(() async {
    await DanmakuCacheManager.clearAllCache();
    StorageService.debugAppStorageDirectoryOverride = null;
    await f.close();
  });
  Future<Job> terminal(String id) async {
    var job = await f.engine.get(id);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!job.state.isTerminal && DateTime.now().isBefore(deadline)) {
      job = await f.engine.wait(id,
          afterRevision: job.revision, timeout: const Duration(seconds: 1));
    }
    expect(job.state.isTerminal, true);
    return job;
  }

  test(
      'failed refresh preserves assigned cache and reports existing playback without claiming acquisition',
      () async {
    final entity = await f.file();
    final attached = await f.call('danmaku.attach', {
      'entityId': entity,
      'video': ddpVideo.toJson(),
      'requestId': 'first',
      'reason': 'fixture'
    });
    expect((await terminal(attached['jobId'] as String)).state,
        JobState.succeeded);
    final binding =
        await f.service.store.binding(attached['bindingId'] as String);
    f.player.classicTracks.add({
      'trackId': 'dandanplay',
      'bindingId': binding['id'],
      'platform': 'dandanplay',
      'platformVideoId': ddpVideo.videoId,
      'count': 3
    });
    await DanmakuCacheManager.saveDanmakuToCache(
        ddpVideo.videoId,
        17864,
        ((jsonDecode(utf8.decode(f.host.responses['dandanplay.comments']!))
                as Map)['comments'] as List)
            .map((row) =>
                parseDandanplayComment(Map<String, dynamic>.from(row as Map)))
            .toList());
    f.host.failures['dandanplay.comments'] = const SourceFailure(
        SourceStatus.accessDenied,
        diagnostics: 'statusCode=302');
    final job = await f.service.fetch(ddpVideo,
        bindingId: binding['id'] as String,
        requestId: 'refresh-failed',
        refresh: true);
    final failed = await terminal(job.jobId);
    expect(failed.state, JobState.failed);
    final details = failed.receipt!.details;
    expect(details['acquisitionSucceeded'], false);
    expect(details['complete'], false);
    expect(details['loaded'], true);
    final available = details['available'] as Map;
    expect(available['classicCache']['count'], 3);
    expect(available['assignedCache']['count'], 3);
    expect(available['attemptedCache']['count'], 0);
    expect(available['player']['count'], 3);
    expect(
        (await f.service.store.binding(binding['id'] as String))['cache_key'],
        binding['cache_key']);
    expect(f.player.data[binding['id']], hasLength(3));
  });
  test('first fetch failure reports no cached or loaded comments', () async {
    f.host.failures['segmented.chunk:0'] = const SourceFailure(
        SourceStatus.accessDenied,
        diagnostics: 'statusCode=302');
    final result = await f.call('danmaku.fetch',
        {'video': segmentedVideo.toJson(), 'requestId': 'failed-empty'});
    final job = await terminal(result['jobId'] as String);
    expect(job.state, JobState.failed);
    final available = job.receipt!.details['available'] as Map;
    expect(available['classicCache'], {'present': false, 'count': 0});
    expect(available['attemptedCache']['count'], 0);
    expect(available['player']['loaded'], false);
  });
}
