import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/danmaku/ass_kind.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';

void main() {
  group('ASS conversion events', () {
    test('match the classic ASS dialogue timing and style', () {
      const settings = AssExportSettings(
        fontSize: 24,
        scrollDurationSeconds: 8,
        timeOffsetSeconds: 1,
      );
      final result = convertDanmakuToAssWithEvents([
        {
          'time': 1.0,
          'content': 'scroll',
          'type': 'scroll',
          'color': 'rgb(255,0,0)',
        },
        {
          'time': 2.0,
          'content': 'top',
          'type': 'top',
          'color': 'rgb(0,255,0)',
        },
      ], settings);

      expect(result.events, hasLength(2));
      expect(result.events[0].content, 'scroll');
      expect(result.events[0].startSeconds, 2.0);
      expect(result.events[0].endSeconds, 10.0);
      expect(result.events[0].colorRgb, 0xFF0000);
      expect(result.events[0].type, DanmakuKind.scroll);
      expect(result.events[1].startSeconds, 3.0);
      expect(result.events[1].endSeconds, 8.0);
      expect(result.events[1].colorRgb, 0x00FF00);
      expect(result.events[1].type, DanmakuKind.top);
      expect(RegExp(r'^Dialogue:', multiLine: true).allMatches(result.ass), hasLength(2));
    });

    test('exclude merged and lane-filtered comments', () {
      const settings = AssExportSettings(
        fontSize: 96,
        displayArea: 0.1,
        mergeDuplicates: true,
      );
      final result = convertDanmakuToAssWithEvents([
        {'time': 1.0, 'content': 'same', 'type': 'scroll'},
        {'time': 1.5, 'content': 'same', 'type': 'scroll'},
        {'time': 1.0, 'content': 'another', 'type': 'scroll'},
      ], settings);

      expect(result.events, hasLength(1));
      expect(result.events.single.content, 'same');
      expect(RegExp(r'^Dialogue:', multiLine: true).allMatches(result.ass), hasLength(1));
    });

    test('match prepared ASS events and skip filtered entries', () {
      const settings = AssExportSettings(
        fontSize: 24,
        timeOffsetSeconds: 0.5,
      );
      final result = convertDanmakuToAssFromPreparedWithEvents([
        const PreparedDanmakuItem(
          timeSeconds: 1,
          text: 'visible',
          typeCode: 1,
          colorRgb: 0x123456,
          yPosition: 10,
          width: 100,
          scrollSpeed: 200,
          durationSeconds: 7,
          isScroll: true,
          centeredX: 0,
        ),
        const PreparedDanmakuItem(
          timeSeconds: 2,
          text: 'filtered',
          typeCode: 5,
          colorRgb: 0xFFFFFF,
          yPosition: 20,
          width: 80,
          scrollSpeed: 0,
          durationSeconds: 5,
          isScroll: false,
          centeredX: 920,
          isFiltered: true,
        ),
      ], playResX: 1920, playResY: 1080, settings: settings);

      expect(result.events, hasLength(1));
      expect(result.events.single.content, 'visible');
      expect(result.events.single.startSeconds, 1.5);
      expect(result.events.single.endSeconds, 8.5);
      expect(result.events.single.colorRgb, 0x123456);
    });
  });
}
