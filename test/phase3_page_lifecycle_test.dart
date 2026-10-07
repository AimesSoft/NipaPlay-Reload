import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/widgets/lazy_page_stack.dart';
import 'package:nipaplay/widgets/page_activity_mixin.dart';
import 'package:nipaplay/widgets/scroll_edge_builder.dart';

class _Probe extends StatefulWidget {
  const _Probe(this.id, this.events, this.focus);
  final String id;
  final List<String> events;
  final FocusNode focus;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with PageActivityMixin {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    widget.events.add('init:${widget.id}');
  }

  @override
  void onPageActivityChanged(bool active) {
    timer?.cancel();
    widget.events.add('active:${widget.id}:$active');
    if (active)
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        widget.events.add('tick:${widget.id}');
      });
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.events.add('dispose:${widget.id}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(focusNode: widget.focus);
}

void main() {
  testWidgets(
      'lazy pages retain state across reorder, isolate focus and stop hidden timers',
      (tester) async {
    final events = <String>[];
    final a = FocusNode();
    final b = FocusNode();
    Future<void> show(String selected,
        {List<String> ids = const ['a', 'b']}) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: LazyPageStack(
        pageIds: ids,
        selectedId: selected,
        builder: (_, id) => _Probe(id, events, id == 'a' ? a : b),
      ))));
      await tester.pump();
    }

    await show('a');
    expect(events.where((e) => e.startsWith('init:')), ['init:a']);
    a.requestFocus();
    await tester.pump();
    expect(a.hasFocus, isTrue);
    await tester.pump(const Duration(seconds: 2));
    await show('b');
    expect(a.hasFocus, isFalse);
    final aTicks = events.where((e) => e == 'tick:a').length;
    await tester.pump(const Duration(seconds: 3));
    expect(events.where((e) => e == 'tick:a').length, aTicks);
    expect(events, contains('tick:b'));
    await show('a', ids: ['b', 'a']);
    expect(events.where((e) => e == 'init:a').length, 1);
    expect(events.where((e) => e.startsWith('dispose:')), isEmpty);
    await show('a', ids: ['a']);
    expect(events, contains('dispose:b'));
    await tester.pumpWidget(const SizedBox());
    a.dispose();
    b.dispose();
  });

  testWidgets(
      'foreground polling stops without a frame and resumes only for visible pages',
      (tester) async {
    final events = <String>[];
    final focus = FocusNode();
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _Probe('a', events, focus))));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(events.last, 'active:a:false');
    final before = events.where((e) => e == 'tick:a').length;
    await tester.pump(const Duration(seconds: 5));
    expect(events.where((e) => e == 'tick:a').length, before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(events.where((e) => e == 'tick:a').length, before + 2);
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
  });

  testWidgets(
      'scroll controls rebuild only when their available directions change',
      (tester) async {
    final scroll = ScrollController();
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
        home: Column(children: [
      ScrollEdgeBuilder(
          controller: scroll,
          builder: (_, left, right) {
            builds++;
            return Text('$left/$right');
          }),
      Expanded(
          child: ListView.builder(
              controller: scroll,
              itemExtent: 50,
              itemCount: 100,
              itemBuilder: (_, i) => Text('row $i'))),
    ])));
    await tester.pump();
    expect(find.text('false/true'), findsOneWidget);
    scroll.jumpTo(50);
    await tester.pump();
    final middleBuilds = builds;
    for (var i = 2; i < 20; i++) {
      scroll.jumpTo(i * 50);
      await tester.pump();
    }
    expect(builds, middleBuilds);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(find.text('true/false'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
}
