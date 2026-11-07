import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/next/ui/widgets/television_focus.dart';

void main() {
  testWidgets('directions ignore controls on a retained covered route',
      (tester) async {
    final original = TelevisionFocusable.isTelevision;
    TelevisionFocusable.isTelevision = () => true;
    addTearDown(() => TelevisionFocusable.isTelevision = original);
    final root = FocusNode();
    final top = FocusNode();
    final nav = GlobalKey<NavigatorState>();
    addTearDown(root.dispose);
    addTearDown(top.dispose);
    final opened = <String>[];
    Widget page(String label, double y) => Align(
        alignment: Alignment.topLeft,
        child: Padding(
            padding: EdgeInsets.only(top: y),
            child: NextButton(label: label, onTap: () => opened.add(label))));
    await tester.pumpWidget(MaterialApp(
        home: FocusTraversalGroup(
            policy: TelevisionTraversalPolicy(root),
            child: Focus(
                focusNode: root,
                child: Column(children: [
                  Focus(focusNode: top, child: const SizedBox(height: 40)),
                  Expanded(
                      child: Navigator(
                          key: nav,
                          onGenerateRoute: (_) => PageRouteBuilder<void>(
                              opaque: false,
                              pageBuilder: (_, __, ___) => page('covered', 20)))),
                ])))));
    nav.currentState!.push(PageRouteBuilder<void>(
        opaque: false, pageBuilder: (_, __, ___) => page('detail', 160)));
    await tester.pumpAndSettle();
    top.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, ['detail']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('directions cross between the top bar and navigator scope',
      (tester) async {
    final original = TelevisionFocusable.isTelevision;
    TelevisionFocusable.isTelevision = () => true;
    addTearDown(() => TelevisionFocusable.isTelevision = original);
    final root = FocusNode();
    addTearDown(root.dispose);
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: FocusTraversalGroup(
        policy: TelevisionTraversalPolicy(root),
        child: Focus(
            focusNode: root,
            child: Column(children: [
              Row(children: [
                NextButton(label: '首页', onTap: () => opened.add('home')),
                NextButton(label: '媒体库', onTap: () => opened.add('library')),
              ]),
              const SizedBox(height: 100),
              FocusScope(
                  child: Row(children: [
                NextButton(label: '播放', onTap: () => opened.add('play')),
                NextButton(label: '详情', onTap: () => opened.add('detail')),
              ])),
            ])),
      ),
    )));
    Focus.of(tester.element(find.text('播放'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(opened, ['home']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(opened, ['home', 'library']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(opened, ['home', 'library', 'detail']);
    await tester.pumpWidget(const SizedBox());
  });
}
