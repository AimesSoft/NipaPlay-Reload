import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/subtitle_parser.dart';
import 'package:nipaplay/utils/subtitle_timeline_index.dart';

SubtitleEntry cue(int start, int end, String text) =>
    SubtitleEntry(startTimeMs: start, endTimeMs: end, content: text);

String reference(List<SubtitleEntry> entries, int time) => entries
    .where((e) => e.startTimeMs <= time && e.endTimeMs >= time)
    .map((e) => e.content.trim())
    .where((text) => text.isNotEmpty)
    .toSet()
    .join('\n');

void main() {
  test('inclusive boundaries, overlaps, duplicates and backward seeks', () {
    final entries = [
      cue(20, 40, ' second '),
      cue(0, 100, 'long'),
      cue(10, 20, 'first'),
      cue(20, 30, 'second'),
      cue(2, 3, '  '),
      cue(50, 49, 'invalid'),
      cue(20, 20, 'instant')
    ];
    final index = SubtitleTimelineIndex(entries);
    for (final time in [-1, 0, 10, 19, 20, 21, 40, 41, 100, 101, 20, 0, -10]) {
      expect(index.textAt(time), reference(entries, time), reason: '$time');
    }
  });

  test('10000 unordered cues match a full scan through random seeks and ticks',
      () {
    final random = Random(42);
    final entries = List.generate(10000, (i) {
      final start = random.nextInt(100000);
      return cue(start, start + random.nextInt(500), 'line ${i % 150}');
    });
    entries.add(cue(-100, 100100, 'long overlap'));
    final index = SubtitleTimelineIndex(entries);
    for (var i = 0; i < 500; i++) {
      final time = random.nextInt(102000) - 1000;
      for (final tick in [time, time + 1, time + 8, time - 1]) {
        expect(index.textAt(tick), reference(entries, tick));
      }
    }
  });

  test('empty and single timelines remain correct across seeks', () {
    expect(SubtitleTimelineIndex([]).textAt(100), '');
    final index = SubtitleTimelineIndex([cue(10, 10, 'one')]);
    for (final time in [0, 10, 11, 10, 9]) {
      expect(index.textAt(time), time == 10 ? 'one' : '');
    }
  });
}
