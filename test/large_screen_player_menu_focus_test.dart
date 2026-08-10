import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/services/large_screen_ui_sfx_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_danmaku_offset_pane.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/adaptive_player_menu_primitives.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_editable_slider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_player_menu_panel.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class _FakeVideoPlayerState extends ChangeNotifier implements VideoPlayerState {
  _FakeVideoPlayerState() : playerValue = _FakePlayer();

  final Player playerValue;
  bool danmakuVisibleValue = true;
  double manualDanmakuOffsetValue = 0;

  @override
  Player get player => playerValue;

  @override
  bool get hasVideo => true;

  @override
  String? get currentVideoPath => null;

  @override
  String? get currentExternalSubtitlePath => null;

  @override
  int? get animeId => null;

  @override
  bool get playerTopSendDanmakuButtonVisible => false;

  @override
  bool get danmakuVisible => danmakuVisibleValue;

  @override
  double get manualDanmakuOffset => manualDanmakuOffsetValue;

  @override
  void setManualDanmakuOffset(double value) {
    manualDanmakuOffsetValue = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayer implements Player {
  final PlayerMediaInfo mediaInfoValue = PlayerMediaInfo(
    duration: 0,
    subtitle: const [],
    audio: const [],
  );

  @override
  PlayerMediaInfo get mediaInfo => mediaInfoValue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _testApp({required Widget home}) {
  return ChangeNotifierProvider<LargeScreenUiSfxService>(
    create: (_) => LargeScreenUiSfxService(),
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: home,
    ),
  );
}

void main() {
  testWidgets('large screen player menu switch renders a Fluent UI toggle',
      (tester) async {
    var value = false;
    await tester.pumpWidget(
      _testApp(
        home: NipaplayLargeScreenModeScope(
          isActive: true,
          child: StatefulBuilder(
            builder: (context, setState) => AdaptivePlayerMenuSwitch(
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(fluent.ToggleSwitch), findsOneWidget);
    tester
        .widget<fluent.ToggleSwitch>(find.byType(fluent.ToggleSwitch))
        .onChanged!(true);
    await tester.pump();
    expect(value, isTrue);
  });

  testWidgets('right enters player content and left always returns to tabs',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final videoState = _FakeVideoPlayerState();
    final tabFocusNode = FocusNode(debugLabel: 'player-menu-tabs-test');
    addTearDown(videoState.dispose);
    addTearDown(tabFocusNode.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<VideoPlayerState>.value(
        value: videoState,
        child: _testApp(
          home: NipaplayLargeScreenModeScope(
            isActive: true,
            child: Align(
              alignment: Alignment.centerRight,
              child: NipaplayLargeScreenPlayerMenuPanel(
                initialFocusNode: tabFocusNode,
                onExitPlayback: () {},
                onSendDanmaku: () {},
                onRequestClose: () {},
              ),
            ),
          ),
        ),
      ),
    );

    tabFocusNode.requestFocus();
    await tester.pump();
    expect(tabFocusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.ancestors.any(
        (node) =>
            node.debugLabel == 'nipaplay_large_screen_player_menu_content',
      ),
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(tabFocusNode.hasFocus, isTrue);
  });

  testWidgets('focused Fluent slider owns left and right but releases up/down',
      (tester) async {
    final sliderFocusNode = FocusNode(debugLabel: 'slider-test');
    final nextFocusNode = FocusNode(debugLabel: 'next-control-test');
    addTearDown(sliderFocusNode.dispose);
    addTearDown(nextFocusNode.dispose);
    var value = 0.5;
    var horizontalBubbleCount = 0;

    await tester.pumpWidget(
      _testApp(
        home: NipaplayLargeScreenModeScope(
          isActive: true,
          child: StatefulBuilder(
            builder: (context, setState) {
              return Focus(
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) {
                    return KeyEventResult.ignored;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                      event.logicalKey == LogicalKeyboardKey.arrowRight) {
                    horizontalBubbleCount += 1;
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    nextFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Column(
                  children: [
                    NipaplayLargeScreenEditableSlider(
                      value: value,
                      min: 0,
                      max: 1,
                      divisions: 10,
                      focusNode: sliderFocusNode,
                      onChanged: (next) => setState(() => value = next),
                    ),
                    Focus(
                      focusNode: nextFocusNode,
                      child: const Text('下一个控件'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.byType(fluent.FluentTheme), findsOneWidget);
    final renderedSlider = tester.widget<fluent.Slider>(
      find.byType(fluent.Slider),
    );
    expect(
      renderedSlider.style?.trackHeight?.resolve(const <WidgetState>{}),
      4,
    );
    expect(
      renderedSlider.style?.activeColor?.resolve(const <WidgetState>{}),
      isNot(Colors.white),
    );

    sliderFocusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(value, closeTo(0.6, 0.0001));
    expect(sliderFocusNode.hasFocus, isTrue);
    expect(horizontalBubbleCount, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(value, closeTo(0.5, 0.0001));
    expect(sliderFocusNode.hasFocus, isTrue);
    expect(horizontalBubbleCount, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(nextFocusNode.hasFocus, isTrue);
  });

  testWidgets('zero danmaku offset keeps reset action focusable',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final videoState = _FakeVideoPlayerState();
    addTearDown(videoState.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<VideoPlayerState>.value(
        value: videoState,
        child: _testApp(
          home: const NipaplayLargeScreenModeScope(
            isActive: true,
            child: CupertinoDanmakuOffsetPane(),
          ),
        ),
      ),
    );
    await tester.pump();

    final resetAction = find.ancestor(
      of: find.text('重置偏移'),
      matching: find.byType(NipaplayLargeScreenFocusableAction),
    );
    expect(resetAction, findsOneWidget);
    expect(
      tester.widget<NipaplayLargeScreenFocusableAction>(resetAction).onActivate,
      isNotNull,
    );
  });
}
