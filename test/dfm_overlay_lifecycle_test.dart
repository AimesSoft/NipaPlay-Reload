import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/danmaku_dfm/dfm_plus_layout_bridge.dart';
import 'package:nipaplay/danmaku_dfm/dfm_plus_overlay.dart';
import 'package:nipaplay/danmaku_next/next2_texture_bridge.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/utils/danmaku/style.dart';
import 'package:provider/provider.dart';

class _Layout extends Fake implements DfmPlusLayoutBridge {
  int configurations = 0, layouts = 0, prefetches = 0, disposals = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #configure:
        configurations++;
        return Future<void>.value();
      case #layout:
        layouts++;
        final time = invocation.positionalArguments.first as double;
        return <PositionedDanmakuItem>[
          PositionedDanmakuItem(
            content: DanmakuContentItem('test', color: Colors.white),
            offstageX: 500,
            x: 100,
            y: 20,
            time: time,
            width: 40,
            endMediaSeconds: time + 10,
            scrollSpeed: 10,
            typeCode: 1,
          ),
        ];
      case #prefetchChars:
        prefetches++;
        return null;
      case #dispose:
        disposals++;
        return null;
    }
    return super.noSuchMethod(invocation);
  }
}

class _Texture extends Fake implements Next2TextureBridge {
  int acquisitions = 0, disposals = 0;
  final frames = <Map<String, dynamic>>[];
  @override
  bool signalVsync(int elapsedUs) => false;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #ensureTexture:
        acquisitions++;
        return Future<Next2TextureInfo?>.value(Next2TextureInfo(
          textureId: 7,
          engineHandle: 1,
          width: invocation.namedArguments[#width] as int,
          height: invocation.namedArguments[#height] as int,
          isNewEngine: true,
        ));
      case #setFrame:
        frames.add(
            invocation.namedArguments[#framePayload] as Map<String, dynamic>);
        return Future<bool>.value(true);
      case #disposeSurface:
        disposals++;
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class _Settings extends ChangeNotifier implements SettingsProvider {
  @override
  double get danmakuSupersample => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'DFM retains texture and layout, stops hidden work and releases on exit',
      (tester) async {
    final clock = ValueNotifier<double>(10000);
    final layout = _Layout();
    final texture = _Texture();
    final settings = _Settings();
    Future<void> show(
        {bool visible = true, bool playing = false, int version = 1}) async {
      await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
            home: DfmPlusOverlay(
          layoutBridge: layout,
          textureBridge: texture,
          danmakuList: const [],
          danmakuListVersion: version,
          playbackTimeMs: clock,
          currentTimeSeconds: clock.value / 1000,
          fontSize: 25,
          isVisible: visible,
          opacity: 1,
          displayArea: 1,
          timeOffset: 0,
          scrollDurationSeconds: 10,
          allowStacking: false,
          mergeDanmaku: true,
          customFontFamily: '',
          customFontFilePath: '',
          outlineWidth: 0,
          shadowStyle: DanmakuShadowStyle.none,
          trackGapRatio: .15,
          isPlaying: playing,
          playbackRate: 1,
        )),
      ));
      await tester.pump();
    }

    await show();
    final overlayState = tester.state(find.byType(DfmPlusOverlay));
    final textureElement = tester.element(find.byType(Texture));
    expect(layout.configurations, 1);
    expect(texture.acquisitions, 1);

    await show(playing: true);
    await show(visible: false, playing: true);
    final hiddenFrames = texture.frames.length;
    final hiddenLayouts = layout.layouts;
    final hiddenPrefetches = layout.prefetches;
    expect(texture.frames.last['items'], isEmpty);
    expect(texture.frames.last['motion_clock']['playing'], false);
    for (var i = 0; i < 5; i++) {
      clock.value += 1000;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(texture.frames.length, hiddenFrames);
    expect(layout.layouts, hiddenLayouts);
    expect(layout.prefetches, hiddenPrefetches);
    expect(tester.binding.hasScheduledFrame, false);
    expect(texture.disposals, 0);

    await show();
    expect(tester.state(find.byType(DfmPlusOverlay)), same(overlayState));
    expect(tester.element(find.byType(Texture)), same(textureElement));
    expect(texture.acquisitions, 1);
    expect(layout.configurations, 1);
    expect(texture.frames.last['motion_clock']['media_s'], 15.0);
    expect(texture.frames.last['motion_clock']['playing'], false);

    await show(visible: false, version: 2);
    expect(layout.configurations, 1);
    await show(version: 2);
    expect(layout.configurations, 2);
    expect(texture.acquisitions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(layout.disposals, 1);
    expect(texture.disposals, 1);
    clock.dispose();
    settings.dispose();
  });
}
