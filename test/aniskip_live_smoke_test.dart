// 真实网络端到端验证：用项目里的 SkipIdResolver + AniSkipService 打真接口。
//
// 为什么用环境变量而不是只靠 @Tags：package:test 对 tag 的语义是「过滤器」——
// 裸 `flutter test`（CI 的跑法）会运行**所有**测试，包括打过 tag 的；tag 只有
// 在显式传 `--tags` / `--exclude-tags` 时才起作用。本文件必须默认不跑（不能
// 依赖 CI 命令带参数），所以用 RUN_LIVE_TESTS 自守卫，全部用例默认 skip。
//
// 本地跑法（PowerShell: $env:RUN_LIVE_TESTS='1'; Bash: RUN_LIVE_TESTS=1）：
//   RUN_LIVE_TESTS=1 flutter test test/aniskip_live_smoke_test.dart
//
// 注意：本机走 TUN 代理，且必须清掉沙箱注入的 HTTP_PROXY，否则 flutter_tester
// 连不上（见项目记忆）。
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/intro_skip/aniskip_service.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';
import 'package:nipaplay/services/intro_skip/skip_id_resolver.dart';

/// 是否显式开启真实网络测试（见文件头注释）。
final bool _runLive = Platform.environment['RUN_LIVE_TESTS'] == '1';

void main() {
  group('AniSkip live smoke（真实网络，需 RUN_LIVE_TESTS=1）', skip: !_runLive, () {
    setUp(() {
      SkipIdResolver.clearCache();
      AniSkipService.instance.clearCache();
    });

    test('resolves MAL id for a well-known anime via AniList', () async {
      // ぐらんぶる（碧蓝之海 S1）的 MAL ID 实测是 37105。
      final malId = await SkipIdResolver.resolveMalIdFromTitles(['ぐらんぶる']);
      expect(malId, isNotNull);
      expect(malId, 37105);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('returns null for a title AniList cannot match', () async {
      // 中文标题 AniList 不认（实测 404），必须返回 null 而不是瞎猜。
      final malId =
          await SkipIdResolver.resolveMalIdFromTitles(['碧蓝之海中文名不存在xyz']);
      expect(malId, isNull);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('fetches real OP+ED segments from AniSkip', () async {
      final segments = await AniSkipService.instance.fetchSkipTimes(
        malId: 37105,
        episodeNumber: 1,
        episodeLengthSeconds: 1440,
      );
      expect(segments, isNotEmpty);

      final opening =
          segments.where((s) => s.kind == SkipSegmentKind.opening).toList();
      final ending =
          segments.where((s) => s.kind == SkipSegmentKind.ending).toList();
      expect(opening, isNotEmpty, reason: '第1集应当有 OP 标注');
      expect(ending, isNotEmpty, reason: '第1集应当有 ED 标注');

      for (final segment in segments) {
        expect(segment.source, SkipSegmentSource.aniskip);
        expect(segment.endSeconds, greaterThan(segment.startSeconds));
        // 区间必须落在合理范围内，否则说明解析错了字段
        expect(segment.startSeconds, greaterThanOrEqualTo(0));
        expect(segment.endSeconds, lessThan(3600));
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('caches results so a second call does not hit the network', () async {
      final first = await AniSkipService.instance.fetchSkipTimes(
        malId: 37105,
        episodeNumber: 1,
        episodeLengthSeconds: 1440,
      );
      final sw = Stopwatch()..start();
      final second = await AniSkipService.instance.fetchSkipTimes(
        malId: 37105,
        episodeNumber: 1,
        episodeLengthSeconds: 1440,
      );
      sw.stop();
      expect(second.length, first.length);
      // 命中缓存应当是「同步返回」级别，远快于一次网络往返。
      expect(sw.elapsedMilliseconds, lessThan(50));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('unknown episode yields empty list, not an exception', () async {
      // 一个不存在的集数：服务端 found=false 或返回空，总之不能抛。
      final segments = await AniSkipService.instance.fetchSkipTimes(
        malId: 37105,
        episodeNumber: 9999,
        episodeLengthSeconds: 1440,
      );
      expect(segments, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('invalid mal id is short-circuited without network', () async {
      final segments = await AniSkipService.instance.fetchSkipTimes(
        malId: 0,
        episodeNumber: 1,
      );
      expect(segments, isEmpty);
    });
  });
}
