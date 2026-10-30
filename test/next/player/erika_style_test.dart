import 'dart:io';

import 'package:erika_flutter/erika_flutter.dart' show kErikaSubtitleOverrideAll;
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/player/kernel/erika_driver.dart';
import 'package:nipaplay/next/player/subtitles/look.dart';

void main() {
  test('the shared subtitle look as Erika takes it', () async {
    final look = const SubtitleLook(
      color: 0xFFFFE000,
      borderColor: 0xFF000000,
      bold: true,
      borderSize: 2.5,
      shadowOffset: 1,
      alignX: 0,
      alignY: 0,
      marginX: 40,
      marginY: 30,
      overrideMode: 3,
      opacity: 0.5,
    ).kernelProperties();
    final style = await erikaSubtitleStyle(look);
    expect(style['primaryColorRgba'], 0xFFE00080);
    expect(style['outlineColorRgba'], 0x00000080);
    expect(style['bold'], true);
    expect(style['italic'], false);
    expect(style['outlineWidth'], 2.5);
    expect(style['shadowDepth'], 1.0);
    // Top left on the ASS numpad.
    expect(style['alignment'], 7);
    expect(style['marginLeft'], 40);
    expect(style['marginRight'], 40);
    expect(style['marginVertical'], 30);
    expect(style['overrideMask'], kErikaSubtitleOverrideAll);
    expect(style['fontFamily'], '');
    expect(style['fontFilePath'], '');

    final centred = await erikaSubtitleStyle(const SubtitleLook().kernelProperties());
    expect(centred['alignment'], 2);
    expect(centred['overrideMask'], 0);
  });

  test('a font of the library goes to Erika as its file', () async {
    final dir = await Directory.systemTemp.createTemp('erika-fonts');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}Noto.ttf');
    await file.writeAsBytes([0]);
    final style = await erikaSubtitleStyle(
        SubtitleLook(fontName: 'Noto', fontsDir: dir.path).kernelProperties());
    expect(style['fontFilePath'], file.path);
    expect(style['fontFamily'], '');
    final system = await erikaSubtitleStyle(
        SubtitleLook(fontName: 'PingFang SC', fontsDir: dir.path)
            .kernelProperties());
    expect(system['fontFamily'], 'PingFang SC');
    expect(system['fontFilePath'], '');
  });
}
