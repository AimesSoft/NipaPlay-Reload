import 'dart:async';
import 'package:flutter/material.dart' show Material, MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/conversation/nipa_chat.dart';
import 'package:nipaplay/next/ui/home/home_page.dart';
import 'package:nipaplay/next/ui/home/hero_backdrop.dart';
import 'package:nipaplay/next/ui/shell/shell_controller.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'player_test_support.dart';

class _Data extends Fake implements NextUiData {
  Future<UiHome> Function() load = () async => const UiHome();
  final changesController = StreamController<void>.broadcast(sync: true);
  @override
  Future<UiHome> home() => load();
  @override
  Stream<void> get changes => changesController.stream;
  @override
  Stream<List<UiTask>> tasks() => Stream.value(const []);
  @override
  Future<List<UiCard>> cards(
          {required String threadId, String? turnId}) async =>
      [];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('saved hero wins over old chat cards and late homepage loads',
      (tester) async {
    const old = UiWork(workId: 'old', title: 'YUME∞MITA');
    const chosen = UiWork(workId: 'remote', title: '穹庐下的魔女');
    final data = _Data();
    data.load = () async => const UiHome(hero: UiHero(old));
    final shell =
        NextShellController(playerTestServices(data: data), onLeave: () {});
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Material(
            child: NextShellScope(
                controller: shell, child: const NextHomePage()))));
    await tester.pump();
    shell.chat.turns = [
      ChatTurn(id: 'previous')..cards = [const UiWorkCard(old)]
    ];
    shell.openChat();
    await tester.pump();
    final late = Completer<UiHome>();
    data.load = () => late.future;
    data.changesController.add(null);
    data.load = () async => const UiHome(hero: UiHero(chosen, pinned: true));
    data.changesController.add(null);
    await tester.pump();
    expect(tester.widget<HeroBackdrop>(find.byType(HeroBackdrop)).workId,
        chosen.workId);
    late.complete(const UiHome(hero: UiHero(old)));
    await tester.pump();
    shell.homeChatOpen.value = false;
    await tester.pump();
    expect(tester.widget<HeroBackdrop>(find.byType(HeroBackdrop)).workId,
        chosen.workId);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    shell.dispose();
    await data.changesController.close();
  });
}
