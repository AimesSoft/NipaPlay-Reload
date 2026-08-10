import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/services/large_screen_ui_sfx_service.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/settings_entries.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_settings_panel.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:provider/provider.dart';

Widget _testApp({ThemeData? theme, required Widget home}) {
  return ChangeNotifierProvider<LargeScreenUiSfxService>(
    create: (_) => LargeScreenUiSfxService(),
    child: MaterialApp(theme: theme, home: home),
  );
}

void main() {
  testWidgets('moving from settings content to tabs releases content focus',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final command =
        ValueNotifier<NipaplayLargeScreenSettingsPanelCommand?>(null);
    addTearDown(command.dispose);
    var contentActivationCount = 0;

    await tester.pumpWidget(
      _testApp(
        home: Scaffold(
          body: SizedBox(
            width: kNipaplayLargeScreenSettingsPanelWidth,
            child: NipaplayLargeScreenSettingsPanel(
              isDarkMode: true,
              commandNotifier: command,
              entriesOverride: <NipaplaySettingEntry>[
                NipaplaySettingEntry(
                  id: 'focus-test',
                  title: '测试 Tab',
                  icon: Icons.settings,
                  pageTitle: '测试设置',
                  page: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => contentActivationCount += 1,
                        child: const Text('右侧控件'),
                      ),
                      TextButton(
                        onPressed: () => contentActivationCount += 1,
                        child: const Text('水平相邻控件'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    command.value = NipaplayLargeScreenSettingsPanelCommand.navigateRight;
    await tester.pump();
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.ancestors.any(
        (node) => node.debugLabel == 'nipaplay_large_screen_settings_content',
      ),
      isTrue,
    );

    final initialContentFocus = FocusManager.instance.primaryFocus;
    command.value = null;
    command.value = NipaplayLargeScreenSettingsPanelCommand.navigateRight;
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(initialContentFocus));

    command.value = null;
    command.value = NipaplayLargeScreenSettingsPanelCommand.navigateLeft;
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'nipaplay_large_screen_settings_menu',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(contentActivationCount, 0);
  });

  testWidgets('settings slider owns horizontal keys and releases vertical keys',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final command =
        ValueNotifier<NipaplayLargeScreenSettingsPanelCommand?>(null);
    final nextFocusNode = FocusNode(debugLabel: 'settings-after-slider');
    addTearDown(command.dispose);
    addTearDown(nextFocusNode.dispose);
    var sliderValue = 0.5;

    await tester.pumpWidget(
      _testApp(
        theme: ThemeData.dark(),
        home: NipaplayLargeScreenModeScope(
          isActive: true,
          child: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                width: kNipaplayLargeScreenSettingsPanelWidth,
                child: NipaplayLargeScreenSettingsPanel(
                  isDarkMode: true,
                  commandNotifier: command,
                  entriesOverride: <NipaplaySettingEntry>[
                    NipaplaySettingEntry(
                      id: 'slider-test',
                      title: '滑块 Tab',
                      icon: Icons.tune,
                      pageTitle: '滑块设置',
                      page: Column(
                        children: [
                          SettingsItem.slider(
                            title: '精确滑块',
                            value: sliderValue,
                            min: 0,
                            max: 1,
                            divisions: 10,
                            onChanged: (value) {
                              setState(() => sliderValue = value);
                            },
                          ),
                          TextButton(
                            focusNode: nextFocusNode,
                            onPressed: () {},
                            child: const Text('下一个控件'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    command.value = NipaplayLargeScreenSettingsPanelCommand.navigateRight;
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(sliderValue, closeTo(0.6, 0.0001));
    expect(
      FocusManager.instance.primaryFocus?.ancestors.any(
        (node) => node.debugLabel == 'nipaplay_large_screen_settings_content',
      ),
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(sliderValue, closeTo(0.5, 0.0001));
    expect(
      FocusManager.instance.primaryFocus?.ancestors.any(
        (node) => node.debugLabel == 'nipaplay_large_screen_settings_content',
      ),
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(nextFocusNode.hasFocus, isTrue);
  });

  testWidgets('large-screen color swatches can receive focus and activate',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final command =
        ValueNotifier<NipaplayLargeScreenSettingsPanelCommand?>(null);
    addTearDown(command.dispose);
    var selectedColor = 0;

    await tester.pumpWidget(
      _testApp(
        theme: ThemeData.dark(),
        home: NipaplayLargeScreenModeScope(
          isActive: true,
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SizedBox(
                  width: kNipaplayLargeScreenSettingsPanelWidth,
                  child: NipaplayLargeScreenSettingsPanel(
                    isDarkMode: true,
                    commandNotifier: command,
                    entriesOverride: <NipaplaySettingEntry>[
                      NipaplaySettingEntry(
                        id: 'color-test',
                        title: '颜色 Tab',
                        icon: Icons.palette,
                        pageTitle: '颜色设置',
                        page: AdaptiveSettingsColorTile<int>(
                          title: '主题色',
                          value: selectedColor,
                          options: const <AdaptiveSettingsColorOption<int>>[
                            AdaptiveSettingsColorOption<int>(
                              title: '红色',
                              value: 1,
                              color: Colors.red,
                            ),
                            AdaptiveSettingsColorOption<int>(
                              title: '蓝色',
                              value: 2,
                              color: Colors.blue,
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => selectedColor = value);
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    command.value = NipaplayLargeScreenSettingsPanelCommand.navigateRight;
    await tester.pump();
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.ancestors.any(
        (node) => node.debugLabel == 'nipaplay_large_screen_settings_content',
      ),
      isTrue,
    );

    command.value = null;
    command.value = NipaplayLargeScreenSettingsPanelCommand.activateFocused;
    await tester.pump();
    expect(selectedColor, 1);
  });
}
