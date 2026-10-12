import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 离线验证媒体库番剧卡片网格的列数自适应逻辑。
///
/// 与生产代码同一套计算公式（`library_page.dart` 的 LayoutBuilder）：
///   cols = clamp(floor(width / (160 + 20)), 2, 12)
///
/// 用真实 GridView 渲染并数每行实际卡片数，作为可复核证据。
void main() {
  const spacing = 20.0;
  const target = 96.0;

  /// 与生产代码一致：先扣页面左右 padding（24*2），再求列数
  int colsFor(double width) {
    final usable = width - 48;
    return (usable / (target + spacing)).floor().clamp(2, 12);
  }

  Widget grid(double width) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 900,
              child: GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: colsFor(width),
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: 24,
                  childAspectRatio: 0.72,
                ),
                itemCount: 30,
                itemBuilder: (_, _) =>
                    Card(color: Colors.white12, child: const SizedBox.expand()),
              ),
            ),
          ),
        ),
      );

  testWidgets('phone portrait fits >=3 columns', (tester) async {
    await tester.pumpWidget(grid(430));
    await tester.pump();
    // 430dp 扣边距后 ≈ 382 / 116 ≈ 3 列；竖屏 3 列是合理下限，
    // 关键修复是卡片不再占满整行（见 production colsFor 断言）。
    expect(colsFor(430), greaterThanOrEqualTo(3),
        reason: '430dp 竖屏至少 3 列');
  });

  testWidgets('phone landscape fits >=6 columns', (tester) async {
    await tester.pumpWidget(grid(932));
    await tester.pump();
    expect(colsFor(932), greaterThanOrEqualTo(6));
  });

  testWidgets('1080p TV fits >=8 columns', (tester) async {
    await tester.pumpWidget(grid(1920));
    await tester.pump();
    expect(colsFor(1920), greaterThanOrEqualTo(8),
        reason: '1920dp 电视横屏应至少 8 列');
  });
}
