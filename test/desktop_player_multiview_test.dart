import 'dart:io';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
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

    testWidgets('hosts transient popup views beside regular windows',
        (tester) async {
      final secondary = _FakeSecondaryView(tester.view);
      final owner = Object();
      late BuildContext popupSourceContext;

      await tester.pumpWidget(
        DesktopMultiWindowHost(
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                popupSourceContext = context;
                return const Text('main view');
              },
            ),
          ),
        ),
      );

      DesktopMultiWindow.attachTransientView(
        owner,
        View(
          view: secondary,
          child: DesktopMultiWindow.inheritTransientViewContext(
            popupSourceContext,
            const Icon(Icons.play_arrow, semanticLabel: 'popup view'),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      DesktopMultiWindow.detachTransientView(owner);
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsNothing);
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
      final transientHostSource = File(
        'lib/widgets/desktop_transient_overlay.dart',
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
      expect(
        forkSource,
        contains('supportsInteractivePopupWindows => false'),
      );
      expect(forkSource, contains('supportsTooltipWindows => false'));
      expect(
        RegExp(r'_PositiveViewSizeGate\(child: child\)')
            .allMatches(forkSource)
            .length,
        greaterThanOrEqualTo(2),
      );
      expect(forkSource, contains('WindowPositionerConstraintAdjustment'));
      expect(forkSource, contains("'width': size.width"));
      expect(forkSource, contains("'height': size.height"));
      expect(
          forkSource, contains('flutter_features.isWindowingEnabled = true'));
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
      expect(macOSRunnerSource, contains('nipaplayIsDetachedPlayerWindow'));
      expect(macOSRunnerSource, contains('replaceDetachedWindowBoolGetter'));
      expect(macOSRunnerSource, contains('replaceBoolGetter'));
      expect(macOSRunnerSource, isNot(contains('object_setClass')));
      expect(macOSRunnerSource, contains('.nonactivatingPanel'));
      expect(macOSRunnerSource, contains('configureTransientWindow'));
      expect(
        macOSRunnerSource,
        contains('applyPreferredContentSize(arguments, to: window)'),
      );
      expect(playerPageSource, contains('Icons.push_pin_rounded'));
      expect(detachedPlayerSource, contains('_DetachedWindowDragRegion'));
      expect(detachedPlayerSource, contains('controller.startDragging()'));
      expect(mainPlayerSlotSource, contains('VideoUploadUI('));
      expect(mainPlayerSlotSource, isNot(contains('FilledButton')));
      expect(tooltipSource, contains('createTooltipWindow'));
      expect(tooltipSource, contains('attachTransientView'));
      expect(transientHostSource, contains('attachTransientView'));
      expect(forkSource, contains('final transientViews'));
      expect(forkSource, contains('...transientViews'));
      expect(controlsSource, contains('DesktopTransientOverlay.showPopup'));
      expect(controlsSource, contains('Icons.open_in_new_rounded'));
      expect(controlsSource, contains('Icons.call_merge_rounded'));
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
