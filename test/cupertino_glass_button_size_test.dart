import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_glass_button_group.dart';

void main() {
  testWidgets('fallback toolbar group matches native glass visual size', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: CupertinoGlassButtonGroup(
            buttonSize: 44,
            items: [
              CupertinoGlassButtonGroupItem(
                label: '更多',
                icon: CupertinoIcons.ellipsis,
                onPressed: () {},
              ),
              CupertinoGlassButtonGroupItem(
                label: '设置',
                icon: CupertinoIcons.gear,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(GlassButtonGroup)), const Size(100, 48));
  });

  testWidgets('fallback bottom sheet header button uses 44pt circle', (
    tester,
  ) async {
    final controller = CupertinoBottomSheetPageController(rootTitle: '菜单');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoBottomSheet(
          pageController: controller,
          child: const SizedBox.expand(),
        ),
      ),
    );

    expect(tester.getSize(find.byType(GlassButton)), const Size.square(44));
  });
}
