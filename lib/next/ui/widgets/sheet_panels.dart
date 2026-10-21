import 'dart:typed_data';

/// A screenshot cut out of a contact sheet, in the sheet's pixels.
typedef SheetPanel = ({int x, int y, int width, int height});

/// The screenshots of a contact sheet: stills laid out on white with white
/// margins and gutters, which some providers give as the poster of a work
/// without a key visual. Null for anything else (a real poster, even one on
/// a white ground). [rgba] is [width]×[height] pixels, four bytes each.
///
/// The sheet is cut along its white lines (rows first, then columns, and so
/// on); what is left must look like stills: wider than tall, hardly any
/// white inside, at least two of them.
List<SheetPanel>? sheetPanels(Uint8List rgba, int width, int height) {
  if (width < 48 || height < 48 || rgba.length < width * height * 4) {
    return null;
  }
  // The darkest channel of a pixel; transparent counts as white.
  int low(int p) {
    final i = p * 4;
    if (rgba[i + 3] < 128) return 255;
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    return r < g ? (r < b ? r : b) : (g < b ? g : b);
  }

  // A sheet has white margins all round; most pictures stop here, having
  // looked at their edges only.
  var edge = 0, edgeBlank = 0;
  for (var x = 0; x < width; x++) {
    if (low(x) >= _white) edgeBlank++;
    if (low((height - 1) * width + x) >= _white) edgeBlank++;
    edge += 2;
  }
  for (var y = 0; y < height; y++) {
    if (low(y * width) >= _white) edgeBlank++;
    if (low(y * width + width - 1) >= _white) edgeBlank++;
    edge += 2;
  }
  if (edgeBlank < edge * 0.97) return null;

  // White, and light: what a gutter a pixel or two wide becomes in a JPEG.
  final blank = Uint8List(width * height), light = Uint8List(width * height);
  for (var p = 0; p < blank.length; p++) {
    final l = low(p);
    if (l >= _white) blank[p] = 1;
    if (l >= _light) light[p] = 1;
  }

  bool rowBlank(int y, int x0, int x1) {
    var n = 0;
    for (var x = x0; x < x1; x++) {
      n += light[y * width + x];
    }
    return n >= (x1 - x0) * _line;
  }

  bool columnBlank(int x, int y0, int y1) {
    var n = 0;
    for (var y = y0; y < y1; y++) {
      n += light[y * width + x];
    }
    return n >= (y1 - y0) * _line;
  }

  final panels = <SheetPanel>[];
  final minWidth = width * 0.08, minHeight = height * 0.04;

  // Pieces of a box between its white lines, along one axis.
  List<(int, int)> pieces(int from, int to, bool Function(int) isBlank) {
    final found = <(int, int)>[];
    int? start;
    for (var i = from; i <= to; i++) {
      final open = i < to && !isBlank(i);
      if (open) {
        start ??= i;
      } else if (start != null) {
        found.add((start, i));
        start = null;
      }
    }
    return found;
  }

  bool cut(int x0, int y0, int x1, int y1, int depth) {
    if (depth > 10 || panels.length > 16) return false;
    final rows = pieces(y0, y1, (y) => rowBlank(y, x0, x1));
    if (rows.isEmpty) return true;
    if (rows.length > 1) {
      for (final (a, b) in rows) {
        if (!cut(x0, a, x1, b, depth + 1)) return false;
      }
      return true;
    }
    final (top, bottom) = rows.single;
    final columns = pieces(x0, x1, (x) => columnBlank(x, top, bottom));
    if (columns.isEmpty) return true;
    if (columns.length > 1) {
      for (final (a, b) in columns) {
        if (!cut(a, top, b, bottom, depth + 1)) return false;
      }
      return true;
    }
    final (left, right) = columns.single;
    // Specks between gutters are not stills.
    if (right - left < minWidth || bottom - top < minHeight) return true;
    // Trimmed: its own lines may part it further.
    if (left != x0 || right != x1 || top != y0 || bottom != y1) {
      return cut(left, top, right, bottom, depth + 1);
    }
    panels.add((x: left, y: top, width: right - left, height: bottom - top));
    return true;
  }

  if (!cut(0, 0, width, height, 0)) return null;
  if (panels.length < 2 || panels.length > 16) return null;
  double whiteIn(int x0, int y0, int x1, int y1) {
    var n = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        n += blank[y * width + x];
      }
    }
    return n / ((x1 - x0) * (y1 - y0));
  }

  for (final p in panels) {
    final aspect = p.width / p.height;
    if (aspect < 1 || aspect > 3.5) return null;
    final x1 = p.x + p.width, y1 = p.y + p.height;
    final mx = p.x + p.width ~/ 2, my = p.y + p.height ~/ 2;
    // Stills have little pure white; a white corner is a gap in the sheet
    // that the cut missed.
    if (whiteIn(p.x, p.y, x1, y1) > 0.2 ||
        whiteIn(p.x, p.y, mx, my) > 0.4 ||
        whiteIn(mx, p.y, x1, my) > 0.4 ||
        whiteIn(p.x, my, mx, y1) > 0.4 ||
        whiteIn(mx, my, x1, y1) > 0.4) {
      return null;
    }
  }
  return panels;
}

/// Near white in every channel, allowing for JPEG.
const _white = 236;

/// Light enough for a thin gutter.
const _light = 200;

/// A line is a gutter when this much of it is light.
const _line = 0.97;
