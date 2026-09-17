import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/fluent_icon_font_loader.dart';

class _InterruptedFontBundle extends CachingAssetBundle {
  bool failNextRead = true;
  final reads = <String, int>{};

  @override
  Future<ByteData> load(String key) async {
    reads.update(key, (count) => count + 1, ifAbsent: () => 1);
    if (failNextRead) {
      failNextRead = false;
      throw StateError('Temporary font asset read failure');
    }
    return rootBundle.load(key);
  }
}

Future<Uint8List> _rasterize(IconData icon, {String? familyOverride}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        inherit: false,
        fontFamily: familyOverride ?? icon.fontFamily,
        package: familyOverride == null ? icon.fontPackage : null,
        fontSize: 48,
        height: 1,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, const Offset(8, 8));
  final picture = recorder.endRecording();
  final image = await picture.toImage(80, 80);
  final bytes = await image.toByteData();
  final pixels = Uint8List.fromList(bytes!.buffer.asUint8List());
  painter.dispose();
  image.dispose();
  picture.dispose();
  return pixels;
}

void main() {
  testWidgets(
      'Fluent glyphs recover after a missing-font lookup and failed read',
      (tester) async {
    await tester.runAsync(() async {
      // Flutter widget tests disable automatic asset-font loading, reproducing
      // the missing-font lookup without replacing any Fluent IconData values.
      final missingGlyph = await _rasterize(fluent.FluentIcons.signin);
      final bundle = _InterruptedFontBundle();
      final loader = FluentIconFontLoader(bundle: bundle);
      await expectLater(loader.ensureLoaded(), throwsStateError);
      await loader.ensureLoaded();

      const icons = [
        fluent.FluentIcons.signin,
        fluent.FluentIcons.add_friend,
        fluent.FluentIcons.sign_out,
        fluent.FluentIcons.delete,
        fluent.FluentIcons.save,
        fluent.FluentIcons.link,
        fluent.FluentIcons.sync,
        fluent.FluentIcons.wifi,
        fluent.FluentIcons.clear,
        fluent.FluentIcons.account_management,
        fluent.FluentIcons.cloud_upload,
        fluent.FluentIcons.help,
        fluent.FluentIcons.accept,
        fluent.FluentIcons.cancel,
        fluent.FluentIcons.chrome_close,
      ];
      await (FontLoader('FluentGlyphReference')
            ..addFont(
                rootBundle.load('packages/fluent_ui/fonts/FluentIcons.ttf')))
          .load();
      for (final icon in icons) {
        final actual = await _rasterize(icon);
        final expected =
            await _rasterize(icon, familyOverride: 'FluentGlyphReference');
        expect(actual, orderedEquals(expected),
            reason: 'Fluent glyph U+${icon.codePoint.toRadixString(16)}');
        expect(actual, isNot(orderedEquals(missingGlyph)));
        expect(actual.any((value) => value != 0), isTrue);
      }

      await (FontLoader('SegoeGlyphReference')
            ..addFont(
                rootBundle.load('packages/fluent_ui/fonts/SegoeIcons.ttf')))
          .load();
      expect(
        await _rasterize(fluent.WindowsIcons.add),
        orderedEquals(await _rasterize(fluent.WindowsIcons.add,
            familyOverride: 'SegoeGlyphReference')),
      );
      await loader.ensureLoaded();
      expect(bundle.reads, {
        'packages/fluent_ui/fonts/FluentIcons.ttf': 2,
        'packages/fluent_ui/fonts/SegoeIcons.ttf': 1,
      });
    });
  });
}
