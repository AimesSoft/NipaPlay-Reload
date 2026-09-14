import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/intro_skip/danmaku_intro_detector.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';

DanmakuTextEntry _e(double time, String text) =>
    DanmakuTextEntry(timeSeconds: time, text: text);

void main() {
  group('DanmakuIntroDetector.parseTimestamp', () {
    test('parses MM:SS variants', () {
      expect(DanmakuIntroDetector.parseTimestamp(' 02:12'), 132);
      expect(DanmakuIntroDetector.parseTimestamp(' 3:9'), 189);
      expect(DanmakuIntroDetector.parseTimestamp(' 1:23:45'), 5025);
    });

    test('normalizes full width colon and dot separator', () {
      expect(DanmakuIntroDetector.parseTimestamp(' 02：12'), 132);
      expect(DanmakuIntroDetector.parseTimestamp(' 2.21'), 141);
    });

    test('rejects decimal noise like 1.5', () {
      // 「跳伞1.5倍」不该被当成 90s。
      expect(DanmakuIntroDetector.parseTimestamp('1.5倍'), isNull);
      expect(DanmakuIntroDetector.parseTimestamp('1.5 '), isNull);
    });

    test('rejects fragments glued to digits', () {
      // 不能从 22:17 里截出 2:17。
      expect(DanmakuIntroDetector.parseTimestamp('122:17'), isNull);
      expect(DanmakuIntroDetector.parseTimestamp('2:173'), isNull);
    });

    test('rejects out of range minute/second', () {
      expect(DanmakuIntroDetector.parseTimestamp(' 75:10'), isNull);
      expect(DanmakuIntroDetector.parseTimestamp(' 10:75'), isNull);
    });
  });

  group('DanmakuIntroDetector.jumpTarget', () {
    test('finds target after keyword', () {
      expect(DanmakuIntroDetector.jumpTarget(text: '跳伞 02:12'), 132);
      expect(DanmakuIntroDetector.jumpTarget(text: '空降：02：12'), 132);
      expect(DanmakuIntroDetector.jumpTarget(text: '跳至1:30大家快'), 90);
    });

    test('returns null without keyword or timestamp', () {
      expect(DanmakuIntroDetector.jumpTarget(text: '前面高能'), isNull);
      expect(DanmakuIntroDetector.jumpTarget(text: '跳伞'), isNull);
    });
  });

  group('真实数据回归（起点估计）', () {
    // 这一组来自 2026-09-14 的线上问题：恶女不才 S1E6 的「跳过片头」按钮
    // 从视频第一帧就弹出。原因见下面各用例的注释。
    // 真值取自 AniSkip 社区标注：OP 80.2–170.2s。
    final realComments = [
      const DanmakuTextEntry(timeSeconds: 68.31, text: '空降2：50'),
      const DanmakuTextEntry(timeSeconds: 72.04, text: '跳伞02:50'),
      const DanmakuTextEntry(timeSeconds: 80.52, text: '跳伞02:50'),
      const DanmakuTextEntry(timeSeconds: 81.28, text: '跳伞2:50'),
      const DanmakuTextEntry(timeSeconds: 86.84, text: '跳伞02:50'),
      const DanmakuTextEntry(timeSeconds: 167.88, text: '感谢指挥部'),
      const DanmakuTextEntry(timeSeconds: 168.65, text: '空降成功 反手炸了指挥部'),
      const DanmakuTextEntry(timeSeconds: 170.47, text: '感谢指挥部'),
      const DanmakuTextEntry(timeSeconds: 171.52, text: '空降成功，感谢指挥部！'),
      const DanmakuTextEntry(timeSeconds: 172.84, text: '感谢指挥部'),
    ];

    test('报点目标值全部相同时依然成立（不再被 distinctCount 挡掉）', () {
      // 修复前：5 条报点的目标值全是 170，distinctCount == 1 < 2，
      // 主路径直接返回 null，回落到不估起点的仅着陆路径 → 起点塌成 0。
      final segment = DanmakuIntroDetector.detect(realComments);
      expect(segment, isNotNull, reason: '5 条一致报点 + 5 条着陆确认，证据充分');
    });

    test('起点不再塌成 0（真实片头 80.2s 才开始）', () {
      final segment = DanmakuIntroDetector.detect(realComments)!;
      // 真值 80.2。中位数法给出 78，容差放宽到 ±20s 以容忍不同实现细节，
      // 但必须远远好于修复前的 0。
      expect(segment.startSeconds, greaterThan(50),
          reason: '按钮不该在正片刚开始时就弹出（修复前是 0）');
      expect(segment.startSeconds, lessThan(100));
      expect((segment.startSeconds - 80.2).abs(), lessThan(20),
          reason: '应接近 AniSkip 真值 80.2');
    });

    test('结束点仍然准确（真值 170.2）', () {
      final segment = DanmakuIntroDetector.detect(realComments)!;
      expect((segment.endSeconds - 170.2).abs(), lessThan(5));
    });

    test('整批报点都是预告型时，改用典型 OP 长度反推', () {
      // 碧蓝之海 S3E10 的真实数据：六条报点全在 0~14s 发出（观众在开头预告
      // 落点，并不代表片头从 0 开始）。中位数 1.9s，若直接拿来当起点会被钳成 0。
      final preview = <DanmakuTextEntry>[
        const DanmakuTextEntry(timeSeconds: 0.00, text: '跳伞:1：35'),
        const DanmakuTextEntry(timeSeconds: 0.45, text: '跳伞01：30'),
        const DanmakuTextEntry(timeSeconds: 0.78, text: '空降01:35'),
        const DanmakuTextEntry(timeSeconds: 6.35, text: '空降01:33'),
        const DanmakuTextEntry(timeSeconds: 14.23, text: '空降01:33'),
        const DanmakuTextEntry(timeSeconds: 93.57, text: '感谢指挥部'),
        const DanmakuTextEntry(timeSeconds: 94.92, text: '感谢指挥部'),
        const DanmakuTextEntry(timeSeconds: 96.34, text: '感谢指挥部'),
        const DanmakuTextEntry(timeSeconds: 101.91, text: '感谢指挥部'),
      ];
      final segment = DanmakuIntroDetector.detect(preview);
      expect(segment, isNotNull);
      // end 约 94~96，反推起点应在 end-90 附近（很小的正数），
      // 关键是**不能因为预告弹幕就把整个区间当成"从 0 到 94 都是片头"**。
      expect(segment!.startSeconds, greaterThanOrEqualTo(0));
      expect(
          (segment.endSeconds - segment.startSeconds), lessThanOrEqualTo(240));
    });

    test('报点确实在片头内发出时，中位数法仍然生效', () {
      // 二十世纪电气目录 E7 的真实数据：报点出现在 44.7/47.3/48.9s（片头内），
      // 着陆确认聚在 130s 附近。实测这一集算出的区间是 45.0-130.0s。
      final normal = <DanmakuTextEntry>[
        const DanmakuTextEntry(timeSeconds: 44.7, text: '跳伞 02:10'),
        const DanmakuTextEntry(timeSeconds: 47.3, text: '空降 02:11'),
        const DanmakuTextEntry(timeSeconds: 48.9, text: '跳到 02:12'),
        const DanmakuTextEntry(timeSeconds: 129.9, text: '感谢指挥部'),
        const DanmakuTextEntry(timeSeconds: 130.2, text: '感谢指挥部'),
        const DanmakuTextEntry(timeSeconds: 131.6, text: '感谢指挥部'),
      ];
      final segment = DanmakuIntroDetector.detect(normal);
      expect(segment, isNotNull);
      // 中位数 47.3 → 起点 45，不应被预告型规则误伤成 end-90
      expect(segment!.startSeconds, greaterThan(40));
      expect((segment.startSeconds - 45).abs(), lessThan(10));
    });

    test('仅有着陆确认时起点也不能是 0', () {
      // 报点全部缺失的典型场景：着陆弹幕只说明片头何时结束，
      // 起点应退化为「按典型 OP 长度反推」，而不是 0。
      final landingOnly = realComments
          .where((c) => c.timeSeconds > 160)
          .toList(growable: false);
      final segment = DanmakuIntroDetector.detect(landingOnly);
      expect(segment, isNotNull);
      expect(segment!.startSeconds, greaterThan(0), reason: '起点至少不该是 0');
    });
  });

  group('DanmakuIntroDetector.detect', () {
    test('uses median of the largest cluster as intro end', () {
      final segment = DanmakuIntroDetector.detect([
        _e(4, '跳伞 01:30'),
        _e(6, '空降 01:32'),
        _e(8, '跳到 01:33'),
        _e(90, '空降成功'),
      ]);
      expect(segment, isNotNull);
      expect(segment!.endSeconds, 92);
      expect(segment.kind, SkipSegmentKind.opening);
      expect(segment.source, SkipSegmentSource.danmaku);
    });

    test('reports clustered near the start fall back to typical OP length', () {
      final segment = DanmakuIntroDetector.detect([
        _e(4, '跳伞 01:30'),
        _e(6, '空降 01:32'),
        _e(8, '跳到 01:33'),
      ]);
      // 报点集中在 4/6/8s，中位数 6 低于预告型阈值 30 → 认定起点信息不可信，
      // 改用「end(92) - 典型 OP 长度(90)」= 2s。
      // （若报点确实在片头内发出，中位数会明显大于 30，见下面那一条用例。）
      expect(segment?.endSeconds, 92);
      expect(segment?.startSeconds, 2);
    });

    test('needs three distinct targets without confirmation', () {
      // 只有 2 个不同目标值且无着陆确认 → 证据不足。
      expect(
        DanmakuIntroDetector.detect([
          _e(4, '跳伞 01:30'),
          _e(6, '空降 01:32'),
        ]),
        isNull,
      );
      // 补第三个不同目标值即可成立。
      expect(
        DanmakuIntroDetector.detect([
          _e(4, '跳伞 01:30'),
          _e(6, '空降 01:32'),
          _e(9, '跳到 01:35'),
        ]),
        isNotNull,
      );
    });

    test('ignores targets outside the plausible intro range', () {
      // 10s 太早、400s 已经是中段跳过，都不是片头。
      expect(
        DanmakuIntroDetector.detect([
          _e(2, '跳伞 00:10'),
          _e(3, '空降 00:12'),
          _e(5, '跳到 00:15'),
          _e(20, '跳伞 06:40'),
          _e(21, '空降 06:45'),
          _e(22, '跳到 06:50'),
        ]),
        isNull,
      );
    });

    test('prefers the largest cluster', () {
      final segment = DanmakuIntroDetector.detect([
        _e(4, '跳伞 01:30'),
        _e(6, '空降 01:32'),
        _e(20, '跳伞 03:20'),
        _e(22, '空降 03:21'),
        _e(24, '跳到 03:22'),
        _e(26, '跳至 03:23'),
      ]);
      // 第二簇有 4 条，胜出；中位数 (201+202)/2 = 201.5 → 202。
      expect(segment?.endSeconds, 202);
    });

    test('falls back to landing confirmations only', () {
      final segment = DanmakuIntroDetector.detect([
        _e(88, '空降成功'),
        _e(90, '着陆成功'),
        _e(91, '正片开始'),
      ]);
      expect(segment, isNotNull);
      expect(segment!.endSeconds, 90);
      // 着陆弹幕都发在片头末尾，起点无法估计 → 回落到 0。
      expect(segment.startSeconds, 0);
    });

    test('requires three landing confirmations', () {
      expect(
        DanmakuIntroDetector.detect([
          _e(88, '空降成功'),
          _e(90, '着陆成功'),
        ]),
        isNull,
      );
    });

    test('handles cold open with late intro start', () {
      final segment = DanmakuIntroDetector.detect([
        _e(150, '跳伞 03:20'),
        _e(152, '空降 03:21'),
        _e(154, '跳到 03:22'),
      ]);
      expect(segment?.endSeconds, 201);
      // 报点时刻 150/152/154 → 中位数 152，回退 2s → 150。
      expect(segment?.startSeconds, 150);
    });

    test('clamps end inside duration', () {
      final segment = DanmakuIntroDetector.detect(
        [
          _e(4, '跳伞 01:30'),
          _e(6, '空降 01:32'),
          _e(8, '跳到 01:33'),
        ],
        durationSeconds: 50,
      );
      // 片长只有 50s，落点 92s 越界 → 钳到 49.5s。
      expect(segment?.endSeconds, 49.5);
    });

    test('returns null on empty or noisy input', () {
      expect(DanmakuIntroDetector.detect(const []), isNull);
      expect(
        DanmakuIntroDetector.detect([
          _e(1, '哈哈哈哈'),
          _e(2, '前方高能'),
        ]),
        isNull,
      );
    });

    test('ignores invalid entries', () {
      expect(
        DanmakuIntroDetector.detect([
          const DanmakuTextEntry(timeSeconds: 0, text: ''),
          _e(4, '跳伞 01:30'),
          _e(6, '空降 01:32'),
          _e(8, '跳到 01:33'),
        ]),
        isNotNull,
      );
    });
  });

  group('DanmakuTextEntry.fromMap', () {
    test('reads time and content with fallbacks', () {
      final entry =
          DanmakuTextEntry.fromMap(const {'time': 12.5, 'c': '空降 02:12'});
      expect(entry.timeSeconds, 12.5);
      expect(entry.text, '空降 02:12');
      expect(entry.isValid, isTrue);
    });

    test('marks entries with unusable time invalid', () {
      expect(
        DanmakuTextEntry.fromMap(const {'t': 'oops', 'content': 'x'}).isValid,
        isFalse,
      );
    });
  });
}
