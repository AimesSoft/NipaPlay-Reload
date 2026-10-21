import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nipaplay/next/ui/widgets/artwork.dart';
import 'package:nipaplay/next/ui/widgets/poster_art.dart';
import 'package:nipaplay/next/ui/widgets/sheet_panels.dart';
import 'package:nipaplay/next/ui/widgets/still_mosaic.dart';

/// A poster that is a contact sheet (stills on white, gaps left over) is
/// laid out again from its stills: however many there are, the rows fill
/// the whole poster on dark, and no white shows.

/// A picture [width]×[height] of [background], with [boxes] of grainy
/// colour (never white) on it.
img.Image _picture(int width, int height,
    {List<(int, int, int, int)> boxes = const [],
    int background = 255,
    int seed = 1}) {
  final random = math.Random(seed);
  final picture = img.Image(width: width, height: height);
  img.fill(picture,
      color: img.ColorRgb8(background, background, background));
  for (final (i, (x, y, w, h)) in boxes.indexed) {
    final base = [40 + 30 * (i % 5), 60 + 25 * (i % 4), 90 + 20 * (i % 3)];
    for (var yy = y; yy < y + h; yy++) {
      for (var xx = x; xx < x + w; xx++) {
        picture.setPixelRgb(xx, yy, base[0] + random.nextInt(40),
            base[1] + random.nextInt(40), base[2] + random.nextInt(40));
      }
    }
  }
  return picture;
}

Uint8List _rgba(img.Image picture) => Uint8List.fromList(
    picture.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba));

/// The provider's sheet in the experiment: two stills, one large, two, one,
/// with a white gap where a seventh would be.
const _sheetBoxes = [
  (11, 9, 99, 74),
  (112, 9, 161, 74),
  (11, 85, 262, 149),
  (10, 236, 161, 75),
  (172, 236, 101, 75),
  (11, 312, 99, 73),
];

/// Colours that are nowhere near white, for stills.
const _colours = [
  (200, 60, 70),
  (40, 120, 200),
  (60, 170, 90),
  (220, 160, 40),
  (130, 70, 190),
  (30, 160, 170),
  (180, 90, 140),
];

void main() {
  group('the layout', () {
    const boxes = [
      Size(176, 264),
      Size(320, 480),
      Size(1280, 720),
      Size(40, 60),
    ];
    const aspects = [16 / 9, 1.34, 2.18, 1.76, 2.15, 1.35, 1.36, 1.6, 2.4];

    for (final n in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]) {
      test('$n pictures fill the box, rows edge to edge', () {
        for (final size in boxes) {
          for (final gap in [0.0, 2.0]) {
            final rects = mosaicLayout(
                [for (var i = 0; i < n; i++) aspects[i % aspects.length]],
                size,
                gap: gap,
                lead: n > 2 ? 2 : null);
            expect(rects, hasLength(n));
            if (n == 0) continue;
            _expectFilled(rects, size, gap, '$n in $size, gap $gap');
          }
        }
      });
    }

    test('the lead gets a row of its own', () {
      final rects = mosaicLayout(
          [1.34, 2.18, 1.76, 2.15, 1.35, 1.36], const Size(176, 264),
          lead: 2);
      expect(rects[2].width, closeTo(176, 0.01));
    });
  });

  group('a sheet', () {
    test("is cut into its stills, the gap where one is missing left out", () {
      final panels = sheetPanels(
          _rgba(_picture(283, 400, boxes: _sheetBoxes)), 283, 400);
      expect(panels, isNotNull);
      expect([for (final p in panels!) (p.x, p.y, p.width, p.height)],
          _sheetBoxes);
    });

    test('with gutters a pixel wide and greyed by JPEG', () {
      final picture = _picture(283, 400, boxes: [
        (8, 8, 130, 90),
        (139, 8, 136, 90),
        (8, 99, 267, 150),
        (8, 250, 130, 90),
      ]);
      // The gutters between rows, one pixel and not quite white.
      for (final y in [98, 249]) {
        for (var x = 8; x < 275; x++) {
          picture.setPixelRgb(x, y, 228, 230, 226);
        }
      }
      final panels = sheetPanels(_rgba(picture), 283, 400);
      expect(panels, hasLength(4));
    });

    test('a poster is not one, even on white', () {
      // Full bleed.
      expect(
          sheetPanels(
              _rgba(_picture(283, 400, boxes: [(0, 0, 283, 400)])), 283, 400),
          isNull);
      // A figure on a white ground: one box, taller than wide.
      expect(
          sheetPanels(
              _rgba(_picture(283, 400, boxes: [(60, 40, 160, 320)])), 283, 400),
          isNull);
      // A picture in a white frame.
      expect(
          sheetPanels(
              _rgba(_picture(283, 400, boxes: [(12, 12, 259, 376)])), 283, 400),
          isNull);
      // Two stills with a white corner the cut cannot part: a gap inside.
      final holed = _picture(283, 400, boxes: [
        (10, 10, 263, 150),
        (10, 170, 263, 110),
        (10, 280, 120, 110),
      ]);
      expect(sheetPanels(_rgba(holed), 283, 400), isNull);
    });
  });

  group('the mosaic', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('poster-mosaic-'));
    tearDown(() {
      PosterSheets.forget();
      dir.deleteSync(recursive: true);
    });

    List<MosaicPiece> stills(int n, {List<(int, int, int)> colours = _colours}) => [
          for (var i = 0; i < n; i++)
            () {
              final (r, g, b) = colours[i % colours.length];
              final picture = img.Image(width: 160, height: 90);
              img.fill(picture, color: img.ColorRgb8(r, g, b));
              final file = File('${dir.path}/still-$i.png')
                ..writeAsBytesSync(img.encodePng(picture));
              return MosaicPiece(file.path);
            }()
        ];

    /// [pieces] in a poster card's box, its pictures loaded.
    Future<GlobalKey> pump(WidgetTester tester, List<MosaicPiece> pieces,
        {int? lead}) async {
      final key = GlobalKey();
      await tester.pumpWidget(_Lookups(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 176,
                height: 264,
                // A tint taken from white paper.
                child: StillMosaic(pieces: pieces, lead: lead, tint: 0xfffdfdfd),
              ),
            ),
          ),
        ),
      ));
      return key;
    }

    testWidgets('the pixels are looked at: a white still shows', (tester) async {
      final key = await pump(
          tester, stills(2, colours: const [(255, 255, 255), (200, 60, 70)]));
      await _loadPictures(tester);
      expect(await _whitePixels(tester, key), greaterThan(176 * 264 / 4));
    });

    for (final n in [0, 1, 2, 3, 5, 7]) {
      testWidgets('$n stills: no hole, no white', (tester) async {
        final key = await pump(tester, stills(n), lead: n > 2 ? 2 : null);
        final tiles = find.descendant(
            of: find.byType(StillMosaic), matching: find.byType(ClipRect));
        expect(tiles, findsNWidgets(n));
        final origin = tester.getTopLeft(find.byType(StillMosaic));
        if (n > 0) {
          _expectFilled([
            for (final e in tiles.evaluate())
              (e.renderObject! as RenderBox).localToGlobal(Offset.zero) -
                      origin &
                  (e.renderObject! as RenderBox).size
          ], const Size(176, 264), StillMosaic.gapFor(const Size(176, 264)),
              '$n stills');
        }
        await _loadPictures(tester);
        final white = await _whitePixels(tester, key);
        expect(white, 0, reason: 'white pixels with $n stills');
      });
    }

    testWidgets('a small poster shows the lead alone', (tester) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
              width: 40,
              height: 60,
              child: StillMosaic(pieces: stills(6), lead: 2)),
        ),
      ));
      final tiles = find.descendant(
          of: find.byType(StillMosaic), matching: find.byType(ClipRect));
      expect(tiles, findsOneWidget);
      final image = tester.widget<NextImage>(
          find.descendant(of: tiles, matching: find.byType(NextImage)));
      expect(image.path, endsWith('still-2.png'));
    });

    testWidgets("a sheet poster shows its stills, another poster itself",
        (tester) async {
      final sheet = File('${dir.path}/sheet.png')
        ..writeAsBytesSync(img.encodePng(_picture(283, 400, boxes: _sheetBoxes)));
      final poster = File('${dir.path}/poster.png')
        ..writeAsBytesSync(
            img.encodePng(_picture(283, 400, boxes: [(0, 0, 283, 400)])));
      final read = await tester.runAsync(() async => [
            await PosterSheets.read(sheet.path),
            await PosterSheets.read(poster.path),
          ]);
      expect(read![0]?.pieces, hasLength(6));
      expect(read[0]?.lead, 2, reason: 'the largest still');
      expect(read[1], isNull);

      Widget at(String path) => Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                  width: 176, height: 264, child: PosterArt(path)),
            ),
          );
      await tester.pumpWidget(at(sheet.path));
      expect(find.byType(StillMosaic), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(StillMosaic), matching: find.byType(ClipRect)),
          findsNWidgets(6));

      await tester.pumpWidget(at(poster.path));
      expect(find.byType(StillMosaic), findsNothing);
      expect(
          tester
              .widgetList<NextImage>(find.byType(NextImage))
              .map((i) => i.path),
          contains(poster.path));
    });
  });
}

/// Rows of rects that fill [size] edge to edge, [gap] apart, and nothing
/// overlaps: no holes but the gaps.
void _expectFilled(List<Rect> rects, Size size, double gap, String label) {
  const e = 0.01;
  final rows = <double, List<Rect>>{};
  for (final r in rects) {
    expect(r.width, greaterThan(size.shortestSide * 0.08), reason: label);
    expect(r.height, greaterThan(size.shortestSide * 0.08), reason: label);
    final key = rows.keys.firstWhere((t) => (t - r.top).abs() < e,
        orElse: () => r.top);
    (rows[key] ??= []).add(r);
  }
  final tops = rows.keys.toList()..sort();
  var y = 0.0;
  for (final top in tops) {
    final row = rows[top]!..sort((a, b) => a.left.compareTo(b.left));
    expect(top, closeTo(y, e), reason: '$label: row at $top');
    final height = row.first.height;
    var x = 0.0;
    for (final r in row) {
      expect(r.left, closeTo(x, e), reason: '$label: $r');
      expect(r.height, closeTo(height, e), reason: '$label: $r');
      x = r.right + gap;
    }
    expect(row.last.right, closeTo(size.width, e), reason: '$label: $row');
    y = top + height + gap;
  }
  expect(y - gap, closeTo(size.height, e), reason: '$label: bottom');
}

/// Pictures asked for under the test's fake clock never arrive: each is
/// dropped, read again outside it, and looked up anew.
Future<void> _loadPictures(WidgetTester tester) async {
  final images = [
    for (final e in find.byType(Image).evaluate()) ((e.widget as Image).image, e)
  ];
  await tester.runAsync(() async {
    for (final (provider, element) in images) {
      final key =
          await provider.obtainKey(createLocalImageConfiguration(element));
      imageCache.evict(key);
      await precacheImage(provider, element);
    }
  });
  // Looked up again, the pictures are there at once.
  _lookups.value = false;
  await tester.pump();
  _lookups.value = true;
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Turned off and on, every picture under [_Lookups] is looked up again.
final _lookups = ValueNotifier(true);

class _Lookups extends StatelessWidget {
  const _Lookups({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: _lookups,
        builder: (context, on, child) =>
            TickerMode(enabled: on, child: child!),
        child: child,
      );
}

Future<int> _whitePixels(WidgetTester tester, GlobalKey key) async {
  final count = await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var white = 0;
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      final r = data.getUint8(i), g = data.getUint8(i + 1);
      final b = data.getUint8(i + 2), a = data.getUint8(i + 3);
      if (a > 0 && r > 230 && g > 230 && b > 230) white++;
    }
    image.dispose();
    return white;
  });
  return count!;
}
