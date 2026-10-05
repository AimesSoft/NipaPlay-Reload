import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/danmaku_next/nipaplay_next_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NipaPlayNextEngine engine;
  setUp(() => engine = NipaPlayNextEngine());
  tearDown(() => engine.dispose());

  void configure(List<Map<String, dynamic>> comments,
      {int version = 0, double width = 800}) {
    engine.configure(
      danmakuList: comments,
      danmakuListVersion: version,
      size: Size(width, 450),
      fontSize: 24,
      displayArea: 1,
      scrollDurationSeconds: 10,
      allowStacking: false,
      mergeDanmaku: false,
    );
  }

  Map<String, dynamic> comment(String text) =>
      {'time': 0.0, 'content': text, 'type': 'scroll'};

  test('episode replacement at the same playback time drops the old frame', () {
    configure([comment('episode two')]);
    expect(engine.layout(1).single.content.text, 'episode two');

    configure([comment('episode three')]);
    expect(engine.layout(1).single.content.text, 'episode three');
  });

  test('clearing and reloading the same list respects its revision', () {
    final comments = [comment('old episode')];
    configure(comments, version: 1);
    expect(engine.layout(1), isNotEmpty);

    comments.clear();
    configure(comments, version: 2);
    expect(engine.layout(1), isEmpty);

    comments.add(comment('new episode'));
    configure(comments, version: 3);
    expect(engine.layout(1).single.content.text, 'new episode');
  });

  test('resizing a paused frame recalculates positions at its timestamp', () {
    final comments = [comment('paused')];
    configure(comments);
    final oldX = engine.layout(1).single.x;

    configure(comments, width: 1200);
    expect(engine.layout(1).single.x, isNot(oldX));
  });
}
