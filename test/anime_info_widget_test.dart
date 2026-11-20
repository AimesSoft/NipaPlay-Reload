import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/anime_info_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/control_shadow.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class _FakeVideoPlayerState extends ChangeNotifier implements VideoPlayerState {
  _FakeVideoPlayerState({
    required this.hasVideoValue,
    required this.showControlsValue,
    this.animeTitleValue,
    this.episodeTitleValue,
    this.currentVideoPathValue,
  });

  final bool hasVideoValue;
  final bool showControlsValue;
  final String? animeTitleValue;
  final String? episodeTitleValue;
  final String? currentVideoPathValue;

  @override
  bool get hasVideo => hasVideoValue;

  @override
  bool get showControls => showControlsValue;

  @override
  String? get animeTitle => animeTitleValue;

  @override
  String? get episodeTitle => episodeTitleValue;

  @override
  String? get currentVideoPath => currentVideoPathValue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'renders title text without an inner AnimatedOpacity clip layer',
    (tester) async {
      final videoState = _FakeVideoPlayerState(
        hasVideoValue: true,
        showControlsValue: true,
        animeTitleValue: '关于邻家的天使大人不知不觉把我惯成了废人这档子事 第二季',
        episodeTitleValue: '第4话',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 480,
                child: AnimeInfoWidget(videoState: videoState),
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('...'), findsOneWidget);
      expect(find.text('第4话'), findsOneWidget);
      expect(find.byType(AnimatedSlide), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AnimeInfoWidget),
          matching: find.byType(AnimatedOpacity),
        ),
        findsNothing,
      );
      expect(find.byType(ControlTextShadow), findsNWidgets(2));

      final titleRect = tester.getRect(find.textContaining('...'));
      final episodeRect = tester.getRect(find.text('第4话'));
      expect(episodeRect.left, greaterThan(titleRect.right));
    },
  );

  group('iPhone Duo outer display in landscape', () {
    // 678x466 pt, with the side column on the left (84 pt inset) and the
    // AirPlay, screenshot and share buttons on the right.
    const windowSize = Size(678, 466);
    const leftInset = 84.0;
    const rightInset = 24.0;
    const fileTitle = 'Happy! Lucky! Dochy!';

    double titleMaxWidth() => playerTopBarTitleMaxWidth(
          windowWidth: windowSize.width,
          leftInset: leftInset,
          rightInset: rightInset,
          rightButtonCount: 3,
          isPictureInPicture: false,
          isMobilePlatform: true,
        );

    Future<void> pumpTopBarTitle(
      WidgetTester tester,
      _FakeVideoPlayerState videoState,
    ) async {
      tester.view.physicalSize = windowSize * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      // Same positioning as the player top bar: an unbounded row after the
      // back and send-danmaku buttons.
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned(
                top: 10,
                left: 16,
                child: Padding(
                  padding: const EdgeInsets.only(left: leftInset, top: 6),
                  child: Row(
                    children: [
                      const SizedBox(width: 28 + 12 + 44 + 8 + 4),
                      // A fresh render object per pump: each one reports
                      // an overflow only once.
                      AnimeInfoWidget(
                        key: UniqueKey(),
                        videoState: videoState,
                        maxWidth: titleMaxWidth(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('truncates a long file title instead of overflowing',
        (tester) async {
      expect(titleMaxWidth(), 156);

      await pumpTopBarTitle(
        tester,
        _FakeVideoPlayerState(
          hasVideoValue: true,
          showControlsValue: true,
          currentVideoPathValue: '/Documents/$fileTitle.mp4',
        ),
      );

      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(
        find.descendant(
          of: find.byType(AnimeInfoWidget),
          matching: find.byType(Text),
        ),
      );
      expect(title.data, endsWith('...'));
      expect(
        tester.getSize(find.byType(AnimeInfoWidget)).width,
        lessThanOrEqualTo(titleMaxWidth()),
      );
    });

    testWidgets('fits titles of every length, with and without an episode',
        (tester) async {
      for (var length = 1; length <= fileTitle.length; length++) {
        for (final episodeTitle in [null, '第12话 最终回']) {
          await pumpTopBarTitle(
            tester,
            _FakeVideoPlayerState(
              hasVideoValue: true,
              showControlsValue: true,
              animeTitleValue: fileTitle.substring(0, length),
              episodeTitleValue: episodeTitle,
            ),
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'title of $length characters, episode $episodeTitle',
          );
        }
      }
    });
  });
}
