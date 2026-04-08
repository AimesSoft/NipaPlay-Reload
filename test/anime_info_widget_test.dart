import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/anime_info_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/control_shadow.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class _FakeVideoPlayerState extends ChangeNotifier implements VideoPlayerState {
  _FakeVideoPlayerState({
    required this.hasVideoValue,
    required this.showControlsValue,
    this.animeTitleValue,
    this.episodeTitleValue,
  });

  final bool hasVideoValue;
  final bool showControlsValue;
  final String? animeTitleValue;
  final String? episodeTitleValue;

  @override
  bool get hasVideo => hasVideoValue;

  @override
  bool get showControls => showControlsValue;

  @override
  String? get animeTitle => animeTitleValue;

  @override
  String? get episodeTitle => episodeTitleValue;

  @override
  String? get currentVideoPath => null;

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
        animeTitleValue: 'Sousou no Frieren',
        episodeTitleValue: 'TV Special',
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

      expect(find.text('Sousou no Frieren'), findsOneWidget);
      expect(find.text('TV Special'), findsOneWidget);
      expect(find.byType(AnimatedSlide), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AnimeInfoWidget),
          matching: find.byType(AnimatedOpacity),
        ),
        findsNothing,
      );
      expect(find.byType(ControlTextShadow), findsNWidgets(2));
    },
  );
}
