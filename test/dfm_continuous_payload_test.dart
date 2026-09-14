import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/danmaku_next/next2_emoji_pipeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('continuous payload retains identity and future lifetime in media units',
      () async {
    final pipeline = Next2EmojiPipeline();
    final payload = await pipeline.buildPayload(
      items: [
        PositionedDanmakuItem(
          content: DanmakuContentItem('future', color: Colors.white),
          x: 1010,
          y: 20,
          offstageX: 1100,
          time: 10.1,
          motionId: 42,
          endMediaSeconds: 20.1,
          scrollSpeed: 100,
          typeCode: 1,
          width: 100,
        ),
        PositionedDanmakuItem(
          content: DanmakuContentItem('reverse', color: Colors.white),
          x: -110,
          y: 50,
          offstageX: -100,
          time: 10.1,
          motionId: 43,
          endMediaSeconds: 20.1,
          scrollSpeed: 100,
          typeCode: 6,
          width: 100,
        ),
      ],
      fontSize: 25, scaleX: 1.5, scaleY: 1.5, fontScale: 1.5,
      locale: null,
      // Continuous mode always sends base velocity. The Rust clock applies
      // playback rate; doubling it here would make 2x playback move at 4x.
      playbackRate: 1.0,
    );
    expect(payload.items[0]['motion_id'], 42);
    expect(payload.items[0]['start_media_s'], 10.1);
    expect(payload.items[0]['end_media_s'], 20.1);
    expect(payload.items[0]['x'], 1515);
    expect(payload.items[0]['scroll_speed'], -150);
    expect(payload.items[1]['motion_id'], 43);
    expect(payload.items[1]['scroll_speed'], 150);
  });
}
