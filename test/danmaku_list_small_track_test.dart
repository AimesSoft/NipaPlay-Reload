import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/danmaku_list_window.dart';

void main() {
  for (final count in [0, 1, 8, 199, 200, 201, 500]) {
    test('initial window stays in bounds for $count comments', () {
      for (final center in [0, count ~/ 2, count > 0 ? count - 1 : 0]) {
        final start = danmakuListWindowStart(center, count, 200);
        final end = (start + 200).clamp(0, count);
        final items = List.generate(count, (index) => index);
        expect(items.sublist(start, end).length, count.clamp(0, 200));
        if (count <= 200) expect(start, 0);
      }
    });
  }
  test('long tracks center and clamp the window at both ends', () {
    expect(danmakuListWindowStart(0, 500, 200), 0);
    expect(danmakuListWindowStart(250, 500, 200), 150);
    expect(danmakuListWindowStart(499, 500, 200), 300);
  });
}
