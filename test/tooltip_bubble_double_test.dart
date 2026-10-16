import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tooltip_bubble.dart';

const String _kAspectTooltip = '画面比例（适应/填充/拉伸/16:9/4:3）';

void main() {
  Future<TestGesture> _startMouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 7,
    );
    await gesture.addPointer(location: Offset.zero);
    return gesture;
  }

  testWidgets('TooltipBubble shows exactly one bubble on plain hover',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: TooltipBubble(
            text: _kAspectTooltip,
            showOnTop: true,
            child: const SizedBox(width: 48, height: 48),
          ),
        ),
      ),
    ));
    await tester.pump();

    final gesture = await _startMouse(tester);
    await gesture.moveTo(tester.getCenter(find.byType(TooltipBubble)));
    await tester.pump(const Duration(milliseconds: 120));

    final bubbles = find.text(_kAspectTooltip).evaluate().length;
    expect(bubbles, 1, reason: 'plain hover should render exactly one bubble');
    await gesture.removePointer();
  });

  testWidgets('TooltipBubble stays single under Windows-style enter/exit churn',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: TooltipBubble(
            text: _kAspectTooltip,
            showOnTop: true,
            child: const SizedBox(width: 48, height: 48),
          ),
        ),
      ),
    ));
    await tester.pump();

    final gesture = await _startMouse(tester);
    final center = tester.getCenter(find.byType(TooltipBubble));

    // 模拟 Windows 上 hover 期间 pointer 抖动产生的成对 enter/exit。
    for (var i = 0; i < 6; i++) {
      await gesture.moveTo(center + Offset(i * 3.0, 0));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveTo(center + const Offset(400, 400));
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveTo(center);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 200));

    final bubbles = find.text(_kAspectTooltip).evaluate().length;
    expect(bubbles, lessThanOrEqualTo(1),
        reason: 'churned hover should never leave more than one bubble');
    await gesture.removePointer();
  });

  testWidgets('blanking tooltip text hides the bubble while menu is open',
      (tester) async {
    final controller = MenuController();
    Widget buildMenuButton({required bool suppressTooltip}) {
      return MenuAnchor(
        controller: controller,
        alignmentOffset: const Offset(-120, 8),
        style: MenuStyle(
          alignment: Alignment.bottomCenter,
          backgroundColor: const WidgetStatePropertyAll(Colors.white),
        ),
        menuChildren: [
          MenuItemButton(
            onPressed: () {},
            child: const Text('适应'),
          ),
        ],
        builder: (buttonContext, menuController, _) {
          return TooltipBubble(
            // 修复后的按钮行为：菜单打开期间传空文本隐藏气泡。
            text: suppressTooltip ? '' : _kAspectTooltip,
            showOnTop: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => menuController.open(),
                child: const SizedBox(width: 48, height: 48),
              ),
            ),
          );
        },
      );
    }

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: buildMenuButton(suppressTooltip: false),
        ),
      ),
    ));
    await tester.pump();

    final gesture = await _startMouse(tester);
    await gesture.moveTo(tester.getCenter(find.byType(TooltipBubble)));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text(_kAspectTooltip), findsOneWidget);

    // 按钮被点击（菜单打开）时指针没有离开按钮，tooltip 仍处于 hover 状态：
    // 未修复时气泡与菜单面板叠成"两层气泡"。
    await tester.tap(find.byType(TooltipBubble));
    await tester.pumpAndSettle();
    expect(find.text('适应'), findsOneWidget, reason: 'menu should be open');
    expect(find.text(_kAspectTooltip), findsOneWidget,
        reason: 'documents the pre-fix two-layer state');

    // 修复后：菜单打开时按钮把 tooltip 文本置空 → 气泡收起。
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: buildMenuButton(suppressTooltip: true),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text(_kAspectTooltip), findsNothing,
        reason: 'blanking the tooltip text must hide the bubble');
    expect(find.text('适应'), findsOneWidget,
        reason: 'menu must stay open and clickable');

    await gesture.removePointer();
  });
}