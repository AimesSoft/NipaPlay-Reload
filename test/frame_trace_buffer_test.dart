import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/danmaku_next/next2_frame_trace.dart';

void main() {
  test('a stalled consumer retains newest events and reports lost samples', () {
    final buffer = FrameTraceBuffer(capacity: 3);
    for (var i = 0; i < 5; i++) {
      buffer.add({'frame': i});
    }
    final batch = buffer.drain();
    expect(batch['dropped'], 2);
    expect(batch['events'], [
      {'frame': 2},
      {'frame': 3},
      {'frame': 4}
    ]);
    expect(buffer.drain()['dropped'], 0);
    expect(buffer.drain()['events'], isEmpty);
  });
}
