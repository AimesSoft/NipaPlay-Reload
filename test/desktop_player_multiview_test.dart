import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';

class _FakeSecondaryView extends TestFlutterView {
  _FakeSecondaryView(FlutterView view)
      : super(
          view: view,
          platformDispatcher: view.platformDispatcher as TestPlatformDispatcher,
          display: view.display as TestDisplay,
        );

  @override
  int get viewId => 706;

  @override
  void render(Scene scene, {Size? size}) {}

  @override
  void updateSemantics(SemanticsUpdate update) {}
}

class _StatefulPlayerSurface extends StatefulWidget {
  const _StatefulPlayerSurface({super.key});

  @override
  State<_StatefulPlayerSurface> createState() => _StatefulPlayerSurfaceState();
}

class _StatefulPlayerSurfaceState extends State<_StatefulPlayerSurface> {
  int transientControlState = 7;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Text('$transientControlState'),
      );
}

void main() {
  group('desktop player window mode', () {
    testWidgets('reparents the same State subtree across FlutterViews',
        (tester) async {
      final key = GlobalKey<_StatefulPlayerSurfaceState>();
      var detached = false;
      late StateSetter setHostState;
      final secondary = _FakeSecondaryView(tester.view);

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return Directionality(
              textDirection: TextDirection.ltr,
              child: ViewAnchor(
                view: detached
                    ? View(
                        view: secondary,
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: _StatefulPlayerSurface(key: key),
                        ),
                      )
                    : null,
                child: detached
                    ? const SizedBox()
                    : _StatefulPlayerSurface(key: key),
              ),
            );
          },
        ),
      );
      final originalState = key.currentState;
      setHostState(() => detached = true);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(key.currentState, same(originalState));
      expect(key.currentState?.transientControlState, 7);
    });

    test('normalizes invalid and extreme aspect ratios', () {
      expect(
          DesktopPlayerWindowService.normalizeAspectRatio(double.nan), 16 / 9);
      expect(DesktopPlayerWindowService.normalizeAspectRatio(0), 16 / 9);
      expect(DesktopPlayerWindowService.normalizeAspectRatio(0.1), 0.5);
      expect(DesktopPlayerWindowService.normalizeAspectRatio(8), 3);
    });

    test('keeps a video-shaped preferred window inside desktop bounds', () {
      expect(
        DesktopPlayerWindowService.preferredWindowSizeForAspect(16 / 9),
        const Size(960, 540),
      );
      expect(
        DesktopPlayerWindowService.minimumWindowSizeForAspect(16 / 9),
        const Size(640, 360),
      );
      expect(
        DesktopPlayerWindowService.preferredWindowSizeForAspect(9 / 16),
        const Size(540, 960),
      );
    });

    test('fork contract uses FlutterViews without a second engine or isolate',
        () {
      final forkSource = File(
        'packages/desktop_multi_window/lib/desktop_multi_window.dart',
      ).readAsStringSync();
      final serviceSource = File(
        'lib/services/desktop_player_window_service.dart',
      ).readAsStringSync();
      final mainSource = File('lib/main.dart').readAsStringSync();
      final macOSRunnerSource =
          File('macos/Runner/MainFlutterWindow.swift').readAsStringSync();
      final windowsVideoSource =
          File('windows/runner/windows_native_video.cpp').readAsStringSync();
      final nativeSurfaceSource =
          File('lib/widgets/macos_native_video_view.dart').readAsStringSync();
      final playerPageSource =
          File('lib/pages/play_video_page.dart').readAsStringSync();
      final detachedPlayerSource =
          File('lib/pages/desktop_player_window.dart').readAsStringSync();
      final mainPlayerSlotSource =
          File('lib/widgets/desktop_player_page_slot.dart').readAsStringSync();
      final tooltipSource = File(
        'lib/themes/nipaplay/widgets/tooltip_bubble.dart',
      ).readAsStringSync();
      final controlsSource = File(
        'lib/themes/nipaplay/widgets/modern_video_controls.dart',
      ).readAsStringSync();
      final contextMenuSource = File(
        'lib/widgets/context_menu/src/context_menu_controller.dart',
      ).readAsStringSync();

      expect(forkSource, contains('RegularWindowController'));
      expect(forkSource, contains('ViewCollection'));
      expect(forkSource, contains('controller.flutterView'));
      expect(forkSource, contains('runWidget(View(view: mainView'));
      expect(forkSource, contains('view.viewId != implicitView.viewId'));
      expect(forkSource, contains('nipaplay/desktop_multi_window_host'));
      expect(forkSource, contains("'startDragging'"));
      expect(forkSource, contains("'setAspectRatio'"));
      expect(forkSource, contains("'setAlwaysOnTop'"));
      expect(forkSource, contains('PopupWindowController'));
      expect(forkSource, contains('TooltipWindowController'));
      expect(forkSource, contains('WindowPositionerConstraintAdjustment'));
      expect(mainSource, contains('runDesktopMultiWindowApp('));
      expect(serviceSource, contains('final GlobalKey playerPageKey'));
      expect(serviceSource, isNot(contains('initializePlayer')));
      expect(macOSRunnerSource, contains('enableMultiView'));
      expect(
        macOSRunnerSource,
        contains('MultiviewPluginRegistrarCompatibility'),
      );
      expect(macOSRunnerSource, contains('requestedFlutterViewIdentifier'));
      expect(macOSRunnerSource, contains('DesktopMultiWindowHostPlugin'));
      expect(macOSRunnerSource, contains('contentAspectRatio'));
      expect(macOSRunnerSource, contains('canJoinAllSpaces'));
      expect(macOSRunnerSource, contains('NSEvent.mouseLocation'));
      expect(macOSRunnerSource, contains('DesktopWindowDragView'));
      expect(macOSRunnerSource, contains('mouseDownCanMoveWindow'));
      expect(macOSRunnerSource, contains('DesktopDetachedPlayerPanel'));
      expect(macOSRunnerSource, contains('DesktopInteractivePopupPanel'));
      expect(macOSRunnerSource, contains('.nonactivatingPanel'));
      expect(macOSRunnerSource, contains('configureTransientWindow'));
      final framelessImplementation = macOSRunnerSource.substring(
        macOSRunnerSource.indexOf('private func makeFrameless'),
        macOSRunnerSource.indexOf('private func makeInteractivePopup'),
      );
      expect(
        framelessImplementation.indexOf('window.styleMask = styleMask'),
        lessThan(
          framelessImplementation.indexOf(
            'object_setClass(window, DesktopDetachedPlayerPanel.self)',
          ),
        ),
        reason: 'AppKit must tear down its titlebar before the NSPanel class '
            'conversion to preserve private KVO registration ownership.',
      );
      expect(playerPageSource, contains('Icons.push_pin_rounded'));
      expect(detachedPlayerSource, isNot(contains('_WindowDragHandle')));
      expect(mainPlayerSlotSource, contains('VideoUploadUI('));
      expect(mainPlayerSlotSource, isNot(contains('FilledButton')));
      expect(tooltipSource, contains('createTooltipWindow'));
      expect(controlsSource, contains('DesktopTransientOverlay.showPopup'));
      expect(contextMenuSource, contains('DesktopTransientOverlay.showPopup'));
      expect(windowsVideoSource, contains('flutterViewId'));
      expect(windowsVideoSource, contains('FLUTTER_HOST_WINDOW'));
      expect(nativeSurfaceSource,
          contains("'flutterViewId': View.of(context).viewId"));
      expect(
          File('lib/pages/desktop_pip_window_app.dart').existsSync(), isFalse);
    });
  });
}
