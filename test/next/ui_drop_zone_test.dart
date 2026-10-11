import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/conversation/chat_context.dart';
import 'package:nipaplay/next/ui/widgets/drop_zone.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

/// Classic plays a video dropped anywhere on the window; Next only takes
/// the drops that land on its own drop places while it is on screen. And
/// what the interface adds to a message (files, the work it was about) is
/// read back from Codex's history exactly.
void main() {
  Widget zone({required bool onScreen}) => Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: onScreen,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              height: 100,
              child: NextDropZone(
                onDrop: (_) {},
                builder: (context, over) => const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );

  testWidgets('drops outside Next, or with Next hidden, stay Classic\'s',
      (tester) async {
    await tester.pumpWidget(zone(onScreen: true));
    expect(NextDropZones.claims(const Offset(100, 50)), isTrue);
    expect(NextDropZones.claims(const Offset(300, 50)), isFalse);

    // Next behind Classic's player (its subtree's tickers are off).
    await tester.pumpWidget(zone(onScreen: false));
    expect(NextDropZones.claims(const Offset(100, 50)), isFalse);

    // Next gone altogether.
    await tester.pumpWidget(const SizedBox());
    expect(NextDropZones.claims(const Offset(100, 50)), isFalse);
  });

  test('files and the work asked about read back from what was sent', () {
    const paths = [
      '/Users/x/Desktop/截屏 2026-10-12 21.03.17.png',
      '/Users/x/Downloads/[Group] Title - 14 [1080p].torrent',
    ];
    const work = UiWork(workId: 'work-1', title: '迷宫饭');
    final sent =
        ChatContext.about(ChatContext.withFiles('这是哪一集？', paths), work);
    expect(ChatContext.strip(sent), '这是哪一集？');
    expect(ChatContext.files(sent), paths);
    expect(ChatContext.aboutTitle(sent), '迷宫饭');

    final filesOnly = ChatContext.withFiles('', paths.take(1).toList());
    expect(ChatContext.strip(filesOnly), '');
    expect(ChatContext.files(filesOnly), paths.take(1).toList());
    expect(ChatContext.aboutTitle(filesOnly), isNull);
  });
}
