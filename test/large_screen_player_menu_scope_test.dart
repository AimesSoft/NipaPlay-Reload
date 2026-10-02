import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_player_menu_scope.dart';

void main() {
  testWidgets('back uses the back callback without opening the menu',
      (tester) async {
    var backPresses = 0;
    var menuPresses = 0;
    late BuildContext playerContext;
    await tester.pumpWidget(NipaplayLargeScreenPlayerMenuScope(
      onMenuPressed: () => menuPresses++,
      onBackPressed: () => backPresses++,
      child: Builder(builder: (context) {
        playerContext = context;
        return const SizedBox.shrink();
      }),
    ));

    expect(
        NipaplayLargeScreenPlayerMenuScope.maybeHandleBackPress(playerContext),
        isTrue);
    expect(backPresses, 1);
    expect(menuPresses, 0);
  });

  testWidgets('menu uses the menu callback without exiting playback',
      (tester) async {
    var backPresses = 0;
    var menuPresses = 0;
    late BuildContext playerContext;
    await tester.pumpWidget(NipaplayLargeScreenPlayerMenuScope(
      onMenuPressed: () => menuPresses++,
      onBackPressed: () => backPresses++,
      child: Builder(builder: (context) {
        playerContext = context;
        return const SizedBox.shrink();
      }),
    ));

    expect(
        NipaplayLargeScreenPlayerMenuScope.maybeHandleMenuPress(playerContext),
        isTrue);
    expect(menuPresses, 1);
    expect(backPresses, 0);
  });

  testWidgets('missing player scope leaves back to its caller', (tester) async {
    late BuildContext playerContext;
    await tester.pumpWidget(Builder(builder: (context) {
      playerContext = context;
      return const SizedBox.shrink();
    }));

    expect(
        NipaplayLargeScreenPlayerMenuScope.maybeHandleBackPress(playerContext),
        isFalse);
  });
}
