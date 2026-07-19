import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/utils/danmaku_ass_converter.dart';

void main() {
  group('ASS conversion', () {
    test('writes the classic ASS dialogue timing and style', () {
      const settings = AssExportSettings(
        fontSize: 24,
        scrollDurationSeconds: 8,
        timeOffsetSeconds: 1,
      );
      final ass = convertDanmakuToAss([
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

      final dialogues = RegExp(r'^Dialogue:.*$', multiLine: true)
          .allMatches(ass)
          .map((match) => match.group(0)!)
          .toList();
      expect(dialogues, hasLength(2));
      expect(
        dialogues[0],
        startsWith('Dialogue: 0,0:00:02.00,0:00:10.00,Danmaku,'),
      );
      expect(dialogues[0], contains(r'\c&H0000FF&'));
      expect(dialogues[0], endsWith('scroll'));
      expect(
        dialogues[1],
        startsWith('Dialogue: 1,0:00:03.00,0:00:08.00,DanmakuTop,'),
      );
      expect(dialogues[1], contains(r'\c&H00FF00&'));
      expect(dialogues[1], endsWith('top'));
    });

    test('exclude merged and lane-filtered comments', () {
      const settings = AssExportSettings(
        fontSize: 96,
        displayArea: 0.1,
        mergeDuplicates: true,
      );
      final ass = convertDanmakuToAss([
        {'time': 1.0, 'content': 'same', 'type': 'scroll'},
        {'time': 1.5, 'content': 'same', 'type': 'scroll'},
        {'time': 1.0, 'content': 'another', 'type': 'scroll'},
      ], settings);

      final dialogues = RegExp(r'^Dialogue:.*$', multiLine: true)
          .allMatches(ass)
          .map((match) => match.group(0)!)
          .toList();
      expect(dialogues, hasLength(1));
      expect(dialogues.single, endsWith('same'));
      expect(ass, isNot(contains('another')));
    });

    test('typed danmaku no longer stores legacy visibility state', () {
      const settings = AssExportSettings(fontSize: 24);
      final legacyItem = DanmakuItem.fromMap({
        'time': 1,
        'content': 'legacy visibility value',
        'visible': false,
      });
      final item = DanmakuItem(
        time: const Duration(seconds: 2),
        content: 'kept comment',
      );

      final ass = convertDanmakuItemsToAss([legacyItem, item], settings);

      expect(ass, contains('legacy visibility value'));
      expect(ass, contains('kept comment'));
      expect(legacyItem.toMap(), isNot(contains('visible')));
      expect(legacyItem.extra, isNot(contains('visible')));
      expect(legacyItem.copyWith().toMap(), isNot(contains('visible')));
    });

    test('writes prepared ASS and skips filtered entries', () {
      const settings = AssExportSettings(
        fontSize: 24,
        timeOffsetSeconds: 0.5,
      );
      final ass = convertDanmakuToAssFromPrepared([
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

      final dialogues = RegExp(r'^Dialogue:.*$', multiLine: true)
          .allMatches(ass)
          .map((match) => match.group(0)!)
          .toList();
      expect(dialogues, hasLength(1));
      expect(
        dialogues.single,
        startsWith('Dialogue: 0,0:00:01.50,0:00:08.50,Danmaku,'),
      );
      expect(dialogues.single, contains(r'\c&H563412&'));
      expect(dialogues.single, endsWith('visible'));
      expect(ass, isNot(contains('filtered')));
    });
  });
}
