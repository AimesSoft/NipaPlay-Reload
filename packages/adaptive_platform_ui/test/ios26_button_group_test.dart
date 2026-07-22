import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reserves room for native Liquid Glass chrome', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: IOS26ButtonGroup(
            height: 44,
            itemWidth: 44,
            items: const [
              IOS26ButtonGroupItem(label: 'More', sfSymbol: 'ellipsis'),
              IOS26ButtonGroupItem(label: 'Theme', sfSymbol: 'moon.fill'),
              IOS26ButtonGroupItem(
                label: 'Settings',
                sfSymbol: 'gearshape.fill',
              ),
            ],
            onPressed: (_) {},
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(IOS26ButtonGroup)),
      const Size((44 * 3) + 24, 44),
    );
  });

  testWidgets('empty groups remain collapsed', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: IOS26ButtonGroup(items: const [], onPressed: (_) {}),
        ),
      ),
    );

    expect(tester.getSize(find.byType(IOS26ButtonGroup)), Size.zero);
  });
}
