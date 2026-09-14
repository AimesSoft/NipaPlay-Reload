import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/intro_skip/episode_number_extractor.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';
import 'package:nipaplay/services/intro_skip/skip_id_resolver.dart';

void main() {
  group('EpisodeNumberExtractor', () {
    test('prefers SxxExx over other patterns', () {
      expect(EpisodeNumberExtractor.extract('Grand.Blue.S01E12.1080p.mkv'), 12);
      expect(
          EpisodeNumberExtractor.extract('[Sub] Anime S3E07 [BDRip].mp4'), 7);
    });

    test('parses Chinese episode markers', () {
      expect(EpisodeNumberExtractor.extract('碧蓝之海 第10话.mp4'), 10);
      expect(EpisodeNumberExtractor.extract('动画 第3集.mkv'), 3);
    });

    test('parses EP / E prefixed numbers', () {
      expect(EpisodeNumberExtractor.extract('Show EP12.mkv'), 12);
      expect(EpisodeNumberExtractor.extract('Show E05.mkv'), 5);
    });

    test('parses bracketed numbers', () {
      expect(EpisodeNumberExtractor.extract('[12] Show.mkv'), 12);
      expect(EpisodeNumberExtractor.extract('【08】Show.mkv'), 8);
    });

    test('parses delimiter separated numbers', () {
      expect(EpisodeNumberExtractor.extract('Show -12- 1080p.mkv'), 12);
      expect(EpisodeNumberExtractor.extract('Show_04_BD.mkv'), 4);
    });

    test('parses space surrounded numbers', () {
      // 字幕组常见写法：`- 07 [`（分隔符与数字之间有空格）
      expect(
        EpisodeNumberExtractor.extract('[Sub] Grand Blue - 07 [1080p].mkv'),
        7,
      );
      expect(EpisodeNumberExtractor.extract('Anime - 12 - 1080p.mkv'), 12);
    });

    test('never mistakes resolution or codec digits for episode numbers', () {
      // 这几条是回归保护：`1080p` / `10bit` / `01v2` 里的数字紧贴字母，
      // 一旦被当成集数，AniSkip 会拉到完全错误的区间。
      expect(EpisodeNumberExtractor.extract('Show 1080p.mkv'), isNull);
      expect(EpisodeNumberExtractor.extract('Anime 10bit 1080p.mkv'), isNull);
      expect(EpisodeNumberExtractor.extract('Anime 01v2 1080p.mkv'), isNull);
      // 4 位年份超出 \d{1,3}，天然不命中
      expect(EpisodeNumberExtractor.extract('Show 2024 1080p.mkv'), isNull);
    });

    test('returns null when nothing matches', () {
      expect(EpisodeNumberExtractor.extract(null), isNull);
      expect(EpisodeNumberExtractor.extract(''), isNull);
      expect(EpisodeNumberExtractor.extract('Movie.mkv'), isNull);
    });

    test('never returns zero or negative', () {
      // 「第0话」这种标记在真实片源里不存在，解析到 0 只会把 AniSkip 带偏。
      expect(EpisodeNumberExtractor.extract('第0话.mkv'), isNull);
      expect(EpisodeNumberExtractor.extract('EP0.mkv'), isNull);
    });

    test('extractFromAny walks candidates in order', () {
      expect(
        EpisodeNumberExtractor.extractFromAny([
          '碧蓝之海',
          null,
          '[Sub] Grand Blue - 07 [1080p].mkv',
        ]),
        7,
      );
      expect(EpisodeNumberExtractor.extractFromAny(['碧蓝之海', null]), isNull);
    });

    test('seasonEpisode keeps raw digit forms for UI badges', () {
      final parts = EpisodeNumberExtractor.seasonEpisode(
          '[Sub] Grand Blue S02E07 [1080p]');
      expect(parts, isNotNull);
      expect(parts!.season, '02');
      expect(parts.episode, '07');
      expect(
          EpisodeNumberExtractor.seasonEpisode('Grand Blue S2E7'), isNotNull);
      expect(EpisodeNumberExtractor.seasonEpisode('第12话.mp4'), isNull);
      expect(EpisodeNumberExtractor.seasonEpisode(null), isNull);
    });

    test('extractSeason returns the season number', () {
      expect(EpisodeNumberExtractor.extractSeason('Show S01E12.mkv'), 1);
      expect(EpisodeNumberExtractor.extractSeason('Show S3E07.mkv'), 3);
      expect(EpisodeNumberExtractor.extractSeason('Show E07.mkv'), isNull);
    });
  });

  group('SkipIdResolver.extractBangumiIdFromDetails', () {
    test('reads bangumi id from bangumiUrl', () {
      final details = {
        'success': true,
        'bangumi': {'bangumiUrl': 'https://bangumi.tv/subject/235130'},
      };
      expect(SkipIdResolver.extractBangumiIdFromDetails(details), 235130);
    });

    test('falls back to direct bangumiId field', () {
      final details = {
        'success': true,
        'bangumi': {'bangumiId': 569116},
      };
      expect(SkipIdResolver.extractBangumiIdFromDetails(details), 569116);
    });

    test('treats zero bangumiId as absent', () {
      final details = {
        'success': true,
        'bangumi': {'bangumiId': '0'},
      };
      expect(SkipIdResolver.extractBangumiIdFromDetails(details), isNull);
    });

    test('returns null on failed or malformed payloads', () {
      expect(SkipIdResolver.extractBangumiIdFromDetails({}), isNull);
      expect(
        SkipIdResolver.extractBangumiIdFromDetails({'success': false}),
        isNull,
      );
      expect(
        SkipIdResolver.extractBangumiIdFromDetails(
            {'success': true, 'bangumi': 'oops'}),
        isNull,
      );
    });
  });

  group('SkipSegment', () {
    test('segment exposes seek-friendly durations', () {
      const segment = SkipSegment(
        kind: SkipSegmentKind.opening,
        source: SkipSegmentSource.aniskip,
        startSeconds: 124.417,
        endSeconds: 212.543,
      );
      expect(segment.start.inMilliseconds, 124417);
      expect(segment.end.inMilliseconds, 212543);
      expect(segment.containsSeconds(150), isTrue);
      expect(segment.containsSeconds(212.543), isFalse); // 右开区间
    });
  });

  group('mergeSkipSegmentSlot：AniSkip 有数据用 AniSkip，否则用弹幕', () {
    // 时序测试直接调用生产合并函数（applySkipSegment 用的就是它），
    // 合并规则改了这些断言会立刻失效——此前它们测的是测试内手抄的副本。
    SkipSegment? slot;
    SkipSegmentKind? slotKind;
    void apply(SkipSegment candidate) {
      if (slot != null && slotKind != candidate.kind) {
        throw StateError('本组测试只测单槽合并');
      }
      slot = mergeSkipSegmentSlot(slot, candidate).segment;
      slotKind = candidate.kind;
    }

    setUp(() {
      slot = null;
      slotKind = null;
    });

    test('完整优先级顺序 manual > mediaServer > aniskip > danmaku > chapter', () {
      expect(SkipSegmentSource.manual.rank, 100);
      expect(SkipSegmentSource.mediaServer.rank, 40);
      expect(SkipSegmentSource.aniskip.rank, 30);
      expect(SkipSegmentSource.danmaku.rank, 20);
      expect(SkipSegmentSource.chapterHeuristic.rank, 10);
    });

    test('弹幕先到、AniSkip 后到应覆盖', () {
      // 复刻真实时序：弹幕（本地，毫秒级）先写入，AniSkip（网络，数秒）后到。
      apply(const SkipSegment(
        kind: SkipSegmentKind.opening,
        source: SkipSegmentSource.danmaku,
        startSeconds: 0,
        endSeconds: 172,
      ));
      expect(slot!.source, SkipSegmentSource.danmaku);

      apply(const SkipSegment(
        kind: SkipSegmentKind.opening,
        source: SkipSegmentSource.aniskip,
        startSeconds: 80.2,
        endSeconds: 170.2,
      ));
      expect(slot!.source, SkipSegmentSource.aniskip,
          reason: 'AniSkip 后到且优先级更高，必须覆盖弹幕结果');
      expect(slot!.startSeconds, 80.2);
    });

    test('AniSkip 先到时，后到的弹幕不得覆盖', () {
      apply(const SkipSegment(
        kind: SkipSegmentKind.opening,
        source: SkipSegmentSource.aniskip,
        startSeconds: 80.2,
        endSeconds: 170.2,
      ));
      final merge = mergeSkipSegmentSlot(
        slot,
        const SkipSegment(
          kind: SkipSegmentKind.opening,
          source: SkipSegmentSource.danmaku,
          startSeconds: 0,
          endSeconds: 172,
        ),
      );
      expect(merge.accepted, isFalse, reason: '低优先级来源不能覆盖高优先级来源');
      expect(merge.segment.source, SkipSegmentSource.aniskip,
          reason: '被拒时槽位保持原值');
    });

    test('AniSkip 只给 ED 时，OP 仍保留弹幕结果（分槽互不干扰）', () {
      // AniSkip 一次返回 OP + ED 两段，必须按 kind 分槽存放；若共用单槽，
      // 后写入的 ED 会把先写入的 OP 挤掉（真实 bug：片头区间凭空消失）。
      final slots = <SkipSegmentKind, SkipSegment>{};
      void applyToSlot(SkipSegment candidate) {
        slots[candidate.kind] =
            mergeSkipSegmentSlot(slots[candidate.kind], candidate).segment;
      }

      applyToSlot(const SkipSegment(
        kind: SkipSegmentKind.opening,
        source: SkipSegmentSource.danmaku,
        startSeconds: 78,
        endSeconds: 170,
      ));
      applyToSlot(const SkipSegment(
        kind: SkipSegmentKind.ending,
        source: SkipSegmentSource.aniskip,
        startSeconds: 1270.9,
        endSeconds: 1360.9,
      ));

      expect(slots[SkipSegmentKind.opening]!.source, SkipSegmentSource.danmaku,
          reason: 'AniSkip 没有 OP 数据，不该清掉弹幕推导的 OP');
      expect(slots[SkipSegmentKind.ending]!.source, SkipSegmentSource.aniskip);
    });
  });
}
