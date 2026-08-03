import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:adaptive_platform_ui/src/widgets/ios26/ios26_popup_menu_button.dart'
    show IOS26PopupMenuButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';

void main() {
  testWidgets('phone settings page provides a Material ancestor',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdaptiveSettingsScope(
          style: AdaptiveSettingsStyle.phone,
          child: AdaptiveSettingsPage(
            children: [
              Chip(label: Text('Selected library')),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Selected library'), findsOneWidget);
  });

  testWidgets('every iOS 26 dropdown uses the native menu and shared trigger',
      (tester) async {
    String? selectedValue;
    PlatformInfo.setPlatformOverride(PlatformOverride.ios, iosVersion: 26);
    addTearDown(PlatformInfo.clearPlatformOverride);

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveSettingsScope(
          style: AdaptiveSettingsStyle.phone,
          child: AdaptiveSettingsTile<String>.dropdown(
            title: 'Kernel',
            items: [
              DropdownMenuItemData(
                title: 'MDK',
                value: 'mdk',
                isSelected: true,
              ),
              DropdownMenuItemData(title: 'MediaKit', value: 'media-kit'),
            ],
            onChanged: (value) => selectedValue = value,
          ),
        ),
      ),
    );

    final popupFinder = find.byWidgetPredicate(
      (widget) => widget is IOS26PopupMenuButton<String>,
    );
    expect(popupFinder, findsOneWidget);

    final popup = tester.widget<IOS26PopupMenuButton<String>>(popupFinder);
    expect(popup.child, isNotNull);
    expect(popup.buttonLabel, isNull);
    expect(find.text('MDK'), findsOneWidget);
    expect(
      (popup.items.first as AdaptivePopupMenuItem<String>).icon,
      'checkmark',
    );

    popup.onSelected(
      1,
      popup.items[1] as AdaptivePopupMenuItem<String>,
    );
    expect(selectedValue, 'media-kit');
  });

  testWidgets('iOS 18 dropdown uses the NipaPlay menu with shared trigger',
      (tester) async {
    String? selectedValue;
    PlatformInfo.setPlatformOverride(PlatformOverride.ios, iosVersion: 18);
    addTearDown(PlatformInfo.clearPlatformOverride);

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveSettingsScope(
          style: AdaptiveSettingsStyle.phone,
          child: AdaptiveSettingsTile<String>.dropdown(
            title: 'Kernel',
            items: [
              DropdownMenuItemData(
                title: 'MDK',
                value: 'mdk',
                isSelected: true,
              ),
              DropdownMenuItemData(title: 'MediaKit', value: 'media-kit'),
            ],
            onChanged: (value) => selectedValue = value,
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) => widget is IOS26PopupMenuButton<String>,
      ),
      findsNothing,
    );
    expect(find.byType(BlurDropdown<String>), findsOneWidget);
    expect(find.text('MDK'), findsOneWidget);
    expect(find.text('MediaKit'), findsNothing);

    await tester.tap(find.text('MDK'));
    await tester.pumpAndSettle();
    expect(find.text('MediaKit'), findsOneWidget);

    await tester.tap(find.text('MediaKit'));
    await tester.pumpAndSettle();
    expect(selectedValue, 'media-kit');
  });
}
