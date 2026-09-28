import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_menu/player_quick_controls.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class _FakeVideoPlayerState extends ChangeNotifier implements VideoPlayerState {
  bool _visible = false;

  @override
  bool get hasVideo => true;

  @override
  bool get showPlayerMenuQuickControls => _visible;

  @override
  double get playbackRate => 1.0;

  @override
  bool get supportsVolumeBoost => true;

  @override
  double get volumeBoost => 1.0;

  @override
  Future<void> setVolumeBoost(double value) async {}

  void showQuickControls(bool value) {
    _visible = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final cupertino in [false, true]) {
    testWidgets(
        'quick controls are hidden by default and can be shown '
        '(cupertino: $cupertino)', (tester) async {
      final videoState = _FakeVideoPlayerState();
      await tester.pumpWidget(
        ChangeNotifierProvider<VideoPlayerState>.value(
          value: videoState,
          child: MaterialApp(
            home: Scaffold(
              body: PlayerQuickControls(cupertino: cupertino),
            ),
          ),
        ),
      );

      expect(find.textContaining('播放倍速'), findsNothing);
      expect(find.text('音量增强'), findsNothing);

      videoState.showQuickControls(true);
      await tester.pump();
      expect(find.textContaining('播放倍速'), findsOneWidget);
      expect(find.text('音量增强'), findsOneWidget);
    });
  }
}
