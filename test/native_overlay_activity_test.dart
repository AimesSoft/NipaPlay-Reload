import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/widgets/macos_native_video_view.dart';

class _Player extends Fake implements Player {
  @override
  bool get prefersPlatformVideoSurface => true;
  @override
  Future<void> attachPlatformVideoSurface(
      {required int viewHandle,
      int? windowHandle,
      int? platformViewId}) async {}
}

class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({required this.read, required super.child});
  final VoidCallback read;
  @override
  RenderObject createRenderObject(BuildContext context) => _ProbeRender(read);
}

class _ProbeRender extends RenderProxyBox {
  _ProbeRender(this.read);
  final VoidCallback read;
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    read();
    super.applyPaintTransform(child, transform);
  }
}

void main() {
  testWidgets(
      'native overlay stops geometry polling offstage and in background',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const channel = MethodChannel('nipaplay/macos_native_video');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    var reads = 0;
    final player = _Player();
    Future<void> mount(bool active) async {
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: TickerMode(
              enabled: active,
              child: _Probe(
                  read: () => reads++,
                  child:
                      MacOSWindowNativeVideoOverlaySurface(player: player)))));
      await tester.pump();
    }

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await mount(true);
    final initial = reads;
    tester.binding.scheduleFrame();
    await tester.pump(const Duration(seconds: 1));
    expect(reads, greaterThan(initial));
    await mount(false);
    final hidden = reads;
    tester.binding.scheduleFrame();
    await tester.pump(const Duration(seconds: 1));
    expect(reads, hidden);
    await mount(true);
    expect(reads, greaterThan(hidden));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final background = reads;
    tester.binding.scheduleFrame();
    await tester.pump(const Duration(seconds: 1));
    expect(reads, background);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(reads, greaterThan(background));
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  }, skip: !Platform.isMacOS && !Platform.isWindows);
}
