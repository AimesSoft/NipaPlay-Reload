import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_next/danmaku_next_log.dart';

class MsdfFontAtlas {
  final double fontSize;
  final double renderScale;
  final double atlasScale;
  final int spread;
  final int padding;
  final VoidCallback? onAtlasUpdated;

  ui.Image? atlasTexture;
  final Map<String, _MsdfGlyph> _glyphs = {};
  final Set<String> _allChars = {};
  final Set<String> _pendingChars = {};
  bool _isUpdating = false;
  bool _disposed = false;

  MsdfFontAtlas({
    required this.fontSize,
    this.onAtlasUpdated,
    this.renderScale = 2.0,
    int? spread,
  })  : atlasScale = 1.0 / renderScale,
        spread = spread ?? max(6, (fontSize * 0.3).round()),
        padding = (spread ?? max(6, (fontSize * 0.3).round())) + 2;

  bool get isReady => atlasTexture != null;

  _MsdfGlyph? getGlyph(String char) => _glyphs[char];

  bool isTextReady(String text) {
    if (atlasTexture == null) return false;
    for (final rune in text.runes) {
      final charStr = String.fromCharCode(rune);
      if (!_glyphs.containsKey(charStr)) return false;
    }
    return true;
  }

  void addText(String text) {
    if (_disposed) return;
    bool hasNew = false;
    for (final rune in text.runes) {
      final charStr = String.fromCharCode(rune);
      if (!_allChars.contains(charStr)) {
        _pendingChars.add(charStr);
        hasNew = true;
      }
    }

    if (hasNew) {
      DanmakuNextLog.d(
        'MSDF',
        'addText new=${_pendingChars.length} total=${_allChars.length}',
        throttle: const Duration(seconds: 1),
      );
      _triggerUpdate();
    }
  }

  Future<void> prebuildFromTexts(List<String> texts) async {
    if (_disposed) return;
    bool hasNew = false;
    for (final text in texts) {
      for (final rune in text.runes) {
        final charStr = String.fromCharCode(rune);
        if (!_allChars.contains(charStr)) {
          _pendingChars.add(charStr);
          hasNew = true;
        }
      }
    }

    if (hasNew) {
      if (_isUpdating) return;
      DanmakuNextLog.d(
        'MSDF',
        'prebuild texts=${texts.length} new=${_pendingChars.length} total=${_allChars.length}',
        throttle: Duration.zero,
      );
      await _updateAtlas();
    }
  }

  void _triggerUpdate() {
    if (_disposed || _isUpdating) return;
    _isUpdating = true;

    Future.delayed(const Duration(milliseconds: 60), () async {
      if (_disposed) {
        _isUpdating = false;
        return;
      }
      try {
        DanmakuNextLog.d(
          'MSDF',
          'atlas update scheduled pending=${_pendingChars.length} total=${_allChars.length}',
          throttle: const Duration(seconds: 1),
        );
        await _updateAtlas();
      } finally {
        _isUpdating = false;
        if (!_disposed) {
          onAtlasUpdated?.call();
        }

        if (!_disposed && _pendingChars.isNotEmpty) {
          _triggerUpdate();
        }
      }
    });
  }

  Future<void> _updateAtlas() async {
    if (_disposed || _pendingChars.isEmpty) return;

    _allChars.addAll(_pendingChars);
    _pendingChars.clear();

    if (_disposed) return;
    DanmakuNextLog.d(
      'MSDF',
      'atlas update start glyphs=${_allChars.length}',
      throttle: Duration.zero,
    );
    await _regenerateAtlas();
    DanmakuNextLog.d(
      'MSDF',
      'atlas update done glyphs=${_allChars.length}',
      throttle: Duration.zero,
    );
  }

  Future<void> _regenerateAtlas() async {
    if (_disposed || _allChars.isEmpty) return;

    final oldTexture = atlasTexture;
    final stopwatch = Stopwatch()..start();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    double x = 0;
    double y = 0;
    double maxRowHeight = 0;
    const atlasWidth = 2048.0;

    final Map<String, _MsdfGlyph> newGlyphs = {};

    bool aborted = false;
    for (final charStr in _allChars) {
      if (_disposed) {
        aborted = true;
        break;
      }
      final glyph = await _buildGlyph(charStr);

      if (x + glyph.pixelWidth > atlasWidth) {
        x = 0;
        y += maxRowHeight;
        maxRowHeight = 0;
      }

      canvas.drawImage(glyph.image, Offset(x, y), Paint());
      glyph.image.dispose();

      final rect = Rect.fromLTWH(x, y, glyph.pixelWidth, glyph.pixelHeight);
      newGlyphs[charStr] = _MsdfGlyph(
        atlasRect: rect,
        advance: glyph.advance,
        offsetX: glyph.offsetX,
        offsetY: glyph.offsetY,
      );

      x += glyph.pixelWidth;
      if (glyph.pixelHeight > maxRowHeight) {
        maxRowHeight = glyph.pixelHeight;
      }
    }

    final picture = recorder.endRecording();
    if (aborted || _disposed) {
      picture.dispose();
      stopwatch.stop();
      return;
    }

    final newTexture = await picture.toImage(
      atlasWidth.toInt(),
      max(1, (y + maxRowHeight).toInt()),
    );

    if (_disposed) {
      newTexture.dispose();
      stopwatch.stop();
      return;
    }

    atlasTexture = newTexture;

    _glyphs
      ..clear()
      ..addAll(newGlyphs);

    oldTexture?.dispose();
    stopwatch.stop();
    DanmakuNextLog.d(
      'MSDF',
      'atlas regenerated glyphs=${_allChars.length} size=${atlasTexture?.width}x${atlasTexture?.height} '
      'time=${stopwatch.elapsedMilliseconds}ms',
      throttle: Duration.zero,
    );
  }

  void dispose() {
    _disposed = true;
    _pendingChars.clear();
    _allChars.clear();
    _glyphs.clear();
    atlasTexture?.dispose();
  }

  Future<_GlyphBitmap> _buildGlyph(String charStr) async {
    if (_disposed) {
      final fallback = await _imageFromMsdf(Uint8List.fromList([0, 0, 0]), 1, 1);
      return _GlyphBitmap(
        image: fallback,
        pixelWidth: 1.0,
        pixelHeight: 1.0,
        advance: 0.0,
        offsetX: 0.0,
        offsetY: 0.0,
      );
    }
    final sw = Stopwatch()..start();
    final double scaledFontSize = fontSize * renderScale;

    final textPainter = TextPainter(
      text: TextSpan(
        text: charStr,
        style: TextStyle(
          fontSize: scaledFontSize,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final glyphWidth = max(1, textPainter.width.ceil());
    final glyphHeight = max(1, textPainter.height.ceil());
    final pixelWidth = glyphWidth + padding * 2;
    final pixelHeight = glyphHeight + padding * 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.transparent, BlendMode.src);
    textPainter.paint(canvas, Offset(padding.toDouble(), padding.toDouble()));

    final picture = recorder.endRecording();
    final glyphImage = await picture.toImage(pixelWidth, pixelHeight);
    final byteData = await glyphImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    glyphImage.dispose();

    if (byteData == null) {
      DanmakuNextLog.d(
        'MSDF',
        'glyph "$charStr" pixel data missing',
        throttle: Duration.zero,
      );
      final fallback = await _imageFromMsdf(Uint8List.fromList([0, 0, 0]), 1, 1);
      return _GlyphBitmap(
        image: fallback,
        pixelWidth: 1.0,
        pixelHeight: 1.0,
        advance: 0.0,
        offsetX: 0.0,
        offsetY: 0.0,
      );
    }

    final pixels = byteData.buffer.asUint8List();
    final msdf = _generateMsdf(pixels, pixelWidth, pixelHeight);
    final msdfImage = await _imageFromMsdf(msdf, pixelWidth, pixelHeight);

    sw.stop();
    if (sw.elapsedMilliseconds >= 20) {
      DanmakuNextLog.d(
        'MSDF',
        'slow glyph "$charStr" ${sw.elapsedMilliseconds}ms size=${pixelWidth}x${pixelHeight}',
        throttle: Duration.zero,
      );
    }

    return _GlyphBitmap(
      image: msdfImage,
      pixelWidth: pixelWidth.toDouble(),
      pixelHeight: pixelHeight.toDouble(),
      advance: textPainter.width * atlasScale,
      offsetX: padding * atlasScale,
      offsetY: padding * atlasScale,
    );
  }

  Uint8List _generateMsdf(Uint8List rgba, int width, int height) {
    final int count = width * height;
    final Float32List alpha = Float32List(count);
    final Uint8List inside = Uint8List(count);

    for (int i = 0; i < count; i++) {
      final a = rgba[i * 4 + 3].toDouble() / 255.0;
      alpha[i] = a;
      inside[i] = a > 0.5 ? 1 : 0;
    }

    final segments = _buildSegments(alpha, width, height);
    if (segments.isEmpty) {
      return Uint8List(count * 3);
    }

    _colorSegments(segments);

    final Uint8List edgeAll = Uint8List(count);
    final Uint8List edgeR = Uint8List(count);
    final Uint8List edgeG = Uint8List(count);
    final Uint8List edgeB = Uint8List(count);

    bool hasEdgeR = false;
    bool hasEdgeG = false;
    bool hasEdgeB = false;

    for (final seg in segments) {
      if (seg.color == 0) {
        _rasterizeSegment(seg, edgeR, edgeAll, width, height);
        hasEdgeR = true;
      } else if (seg.color == 1) {
        _rasterizeSegment(seg, edgeG, edgeAll, width, height);
        hasEdgeG = true;
      } else {
        _rasterizeSegment(seg, edgeB, edgeAll, width, height);
        hasEdgeB = true;
      }
    }

    final distAll = _edt(edgeAll, width, height);
    final distR = hasEdgeR ? _edt(edgeR, width, height) : distAll;
    final distG = hasEdgeG ? _edt(edgeG, width, height) : distAll;
    final distB = hasEdgeB ? _edt(edgeB, width, height) : distAll;

    final Uint8List output = Uint8List(count * 3);
    final double spreadValue = spread.toDouble().clamp(1.0, 1e9);

    for (int i = 0; i < count; i++) {
      final double sign = inside[i] == 1 ? -1.0 : 1.0;

      final double dr = sqrt(distR[i]);
      final double dg = sqrt(distG[i]);
      final double db = sqrt(distB[i]);

      double r = 0.5 + sign * dr / spreadValue;
      double g = 0.5 + sign * dg / spreadValue;
      double b = 0.5 + sign * db / spreadValue;

      r = r.clamp(0.0, 1.0).toDouble();
      g = g.clamp(0.0, 1.0).toDouble();
      b = b.clamp(0.0, 1.0).toDouble();

      final int outIdx = i * 3;
      output[outIdx] = (r * 255).round();
      output[outIdx + 1] = (g * 255).round();
      output[outIdx + 2] = (b * 255).round();
    }

    return output;
  }

  List<_MsdfEdgeSegment> _buildSegments(Float32List alpha, int width, int height) {
    final int gridW = width + 1;
    final int gridH = height + 1;
    final Float32List corners = Float32List(gridW * gridH);

    for (int y = 0; y <= height; y++) {
      for (int x = 0; x <= width; x++) {
        double sum = 0.0;
        int count = 0;
        for (int dy = -1; dy <= 0; dy++) {
          final int py = y + dy;
          if (py < 0 || py >= height) continue;
          final int row = py * width;
          for (int dx = -1; dx <= 0; dx++) {
            final int px = x + dx;
            if (px < 0 || px >= width) continue;
            sum += alpha[row + px];
            count++;
          }
        }
        corners[y * gridW + x] = count == 0 ? 0.0 : sum / count;
      }
    }

    final List<_MsdfEdgeSegment> segments = [];
    const double iso = 0.5;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int cornerIndex = y * gridW + x;
        final double c0 = corners[cornerIndex];
        final double c1 = corners[cornerIndex + 1];
        final double c3 = corners[cornerIndex + gridW];
        final double c2 = corners[cornerIndex + gridW + 1];

        int mask = 0;
        if (c0 >= iso) mask |= 1;
        if (c1 >= iso) mask |= 2;
        if (c2 >= iso) mask |= 4;
        if (c3 >= iso) mask |= 8;

        if (mask == 0 || mask == 15) continue;

        final double center = (c0 + c1 + c2 + c3) * 0.25;

        Offset e0 = _edgePoint(x, y, c0, c1, iso, 0);
        Offset e1 = _edgePoint(x, y, c1, c2, iso, 1);
        Offset e2 = _edgePoint(x, y, c2, c3, iso, 2);
        Offset e3 = _edgePoint(x, y, c3, c0, iso, 3);

        void addSegment(Offset a, Offset b) {
          final double dx = a.dx - b.dx;
          final double dy = a.dy - b.dy;
          if ((dx * dx + dy * dy) < 1e-6) return;
          segments.add(_MsdfEdgeSegment(a, b));
        }

        switch (mask) {
          case 1:
            addSegment(e3, e0);
            break;
          case 2:
            addSegment(e0, e1);
            break;
          case 3:
            addSegment(e3, e1);
            break;
          case 4:
            addSegment(e1, e2);
            break;
          case 5:
            if (center >= iso) {
              addSegment(e0, e1);
              addSegment(e2, e3);
            } else {
              addSegment(e3, e0);
              addSegment(e1, e2);
            }
            break;
          case 6:
            addSegment(e0, e2);
            break;
          case 7:
            addSegment(e3, e2);
            break;
          case 8:
            addSegment(e2, e3);
            break;
          case 9:
            addSegment(e0, e2);
            break;
          case 10:
            if (center >= iso) {
              addSegment(e3, e0);
              addSegment(e1, e2);
            } else {
              addSegment(e0, e1);
              addSegment(e2, e3);
            }
            break;
          case 11:
            addSegment(e1, e2);
            break;
          case 12:
            addSegment(e1, e3);
            break;
          case 13:
            addSegment(e0, e1);
            break;
          case 14:
            addSegment(e0, e3);
            break;
        }
      }
    }

    return segments;
  }

  Offset _edgePoint(int x, int y, double v0, double v1, double iso, int edge) {
    double t;
    final double denom = v1 - v0;
    if (denom.abs() < 1e-6) {
      t = 0.5;
    } else {
      t = ((iso - v0) / denom).clamp(0.0, 1.0).toDouble();
    }
    switch (edge) {
      case 0:
        return Offset(x + t, y.toDouble());
      case 1:
        return Offset(x + 1.0, y + t);
      case 2:
        return Offset(x + 1.0 - t, y + 1.0);
      case 3:
        return Offset(x.toDouble(), y + 1.0 - t);
      default:
        return Offset(x.toDouble(), y.toDouble());
    }
  }

  int _pointKey(Offset point) {
    final int qx = (point.dx * 1024).round();
    final int qy = (point.dy * 1024).round();
    return (qx << 32) ^ qy;
  }

  void _colorSegments(List<_MsdfEdgeSegment> segments) {
    final Map<int, List<int>> adjacency = {};
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final int keyA = _pointKey(seg.a);
      final int keyB = _pointKey(seg.b);
      adjacency.putIfAbsent(keyA, () => []).add(i);
      adjacency.putIfAbsent(keyB, () => []).add(i);
    }

    final List<bool> visited = List<bool>.filled(segments.length, false);
    for (int i = 0; i < segments.length; i++) {
      if (visited[i]) continue;
      final contour = _traceContour(i, segments, adjacency, visited);
      _assignContourColors(contour, segments);
    }
  }

  _Contour _traceContour(
    int startIndex,
    List<_MsdfEdgeSegment> segments,
    Map<int, List<int>> adjacency,
    List<bool> visited,
  ) {
    final List<_ContourEdge> edges = [];

    final startSeg = segments[startIndex];
    visited[startIndex] = true;
    edges.add(_ContourEdge(startIndex, false));

    final int startKey = _pointKey(startSeg.a);
    int currentKey = _pointKey(startSeg.b);
    bool closed = false;

    while (true) {
      if (currentKey == startKey) {
        closed = true;
        break;
      }

      final candidates = adjacency[currentKey];
      if (candidates == null) break;

      int? nextIndex;
      for (final idx in candidates) {
        if (!visited[idx]) {
          nextIndex = idx;
          break;
        }
      }

      if (nextIndex == null) break;

      final nextSeg = segments[nextIndex];
      final int keyA = _pointKey(nextSeg.a);
      final int keyB = _pointKey(nextSeg.b);
      bool reversed;
      int nextKey;
      if (keyA == currentKey) {
        reversed = false;
        nextKey = keyB;
      } else if (keyB == currentKey) {
        reversed = true;
        nextKey = keyA;
      } else {
        break;
      }

      visited[nextIndex] = true;
      edges.add(_ContourEdge(nextIndex, reversed));
      currentKey = nextKey;
    }

    return _Contour(edges, closed);
  }

  void _assignContourColors(_Contour contour, List<_MsdfEdgeSegment> segments) {
    if (contour.edges.isEmpty) return;

    const double cornerThreshold = pi / 3.0;

    final List<Offset> dirs = [];
    for (final edge in contour.edges) {
      final seg = segments[edge.index];
      final Offset dir = edge.reversed ? seg.a - seg.b : seg.b - seg.a;
      dirs.add(dir);
    }

    List<int> bestColors = [];
    int bestConflicts = 1 << 30;

    for (int startColor = 0; startColor < 3; startColor++) {
      final colors = _assignColors(dirs, cornerThreshold, startColor);
      final conflicts = _countConflicts(colors, dirs, cornerThreshold, contour.closed);
      if (conflicts < bestConflicts) {
        bestConflicts = conflicts;
        bestColors = colors;
      }
    }

    if (bestColors.isEmpty) {
      bestColors = _assignColors(dirs, cornerThreshold, 0);
    }

    for (int i = 0; i < contour.edges.length; i++) {
      segments[contour.edges[i].index].color = bestColors[i];
    }
  }

  List<int> _assignColors(List<Offset> dirs, double threshold, int startColor) {
    final List<int> colors = List<int>.filled(dirs.length, startColor);
    int color = startColor;
    for (int i = 1; i < dirs.length; i++) {
      if (_angleBetween(dirs[i - 1], dirs[i]) > threshold) {
        color = (color + 1) % 3;
      }
      colors[i] = color;
    }
    return colors;
  }

  int _countConflicts(
    List<int> colors,
    List<Offset> dirs,
    double threshold,
    bool closed,
  ) {
    int conflicts = 0;
    for (int i = 1; i < dirs.length; i++) {
      if (_angleBetween(dirs[i - 1], dirs[i]) > threshold && colors[i] == colors[i - 1]) {
        conflicts++;
      }
    }
    if (closed && dirs.length > 1) {
      if (_angleBetween(dirs.last, dirs.first) > threshold && colors.last == colors.first) {
        conflicts++;
      }
    }
    return conflicts;
  }

  double _angleBetween(Offset a, Offset b) {
    final double ax = a.dx;
    final double ay = a.dy;
    final double bx = b.dx;
    final double by = b.dy;

    final double magA = sqrt(ax * ax + ay * ay);
    final double magB = sqrt(bx * bx + by * by);
    if (magA == 0.0 || magB == 0.0) return 0.0;

    final double dot = (ax * bx + ay * by) / (magA * magB);
    final double clamped = dot.clamp(-1.0, 1.0).toDouble();
    return acos(clamped);
  }

  void _rasterizeSegment(
    _MsdfEdgeSegment seg,
    Uint8List map,
    Uint8List all,
    int width,
    int height,
  ) {
    final double ax = seg.a.dx;
    final double ay = seg.a.dy;
    final double bx = seg.b.dx;
    final double by = seg.b.dy;

    final double dx = bx - ax;
    final double dy = by - ay;
    final int steps = max(dx.abs(), dy.abs()).ceil();

    void mark(double px, double py) {
      final int ix = px.round();
      final int iy = py.round();
      if (ix < 0 || iy < 0 || ix >= width || iy >= height) return;
      final int idx = iy * width + ix;
      map[idx] = 1;
      all[idx] = 1;
    }

    if (steps <= 0) {
      mark(ax, ay);
      return;
    }

    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      mark(ax + dx * t, ay + dy * t);
    }
  }

  Float32List _edt(Uint8List binary, int width, int height) {
    final int count = width * height;
    final Float32List data = Float32List(count);
    const double inf = 1e20;

    for (int i = 0; i < count; i++) {
      data[i] = binary[i] == 1 ? 0.0 : inf;
    }

    final Float32List f = Float32List(max(width, height));
    final Float32List d = Float32List(max(width, height));

    for (int x = 0; x < width; x++) {
      for (int y = 0; y < height; y++) {
        f[y] = data[y * width + x];
      }
      _edt1d(f, height, d);
      for (int y = 0; y < height; y++) {
        data[y * width + x] = d[y];
      }
    }

    for (int y = 0; y < height; y++) {
      final rowOffset = y * width;
      for (int x = 0; x < width; x++) {
        f[x] = data[rowOffset + x];
      }
      _edt1d(f, width, d);
      for (int x = 0; x < width; x++) {
        data[rowOffset + x] = d[x];
      }
    }

    return data;
  }

  void _edt1d(Float32List f, int n, Float32List d) {
    final List<int> v = List<int>.filled(n, 0);
    final Float32List z = Float32List(n + 1);

    int k = 0;
    v[0] = 0;
    z[0] = -1e20;
    z[1] = 1e20;

    for (int q = 1; q < n; q++) {
      double s;
      while (true) {
        final int p = v[k];
        s = ((f[q] + q * q) - (f[p] + p * p)) / (2 * (q - p));
        if (s > z[k]) {
          break;
        }
        k--;
      }
      k++;
      v[k] = q;
      z[k] = s;
      z[k + 1] = 1e20;
    }

    k = 0;
    for (int q = 0; q < n; q++) {
      while (z[k + 1] < q) {
        k++;
      }
      final int p = v[k];
      final double val = (q - p) * (q - p) + f[p];
      d[q] = val.toDouble();
    }
  }

  Future<ui.Image> _imageFromMsdf(Uint8List rgb, int width, int height) async {
    final Uint8List pixels = Uint8List(width * height * 4);
    for (int i = 0; i < width * height; i++) {
      final int src = i * 3;
      final int dst = i * 4;
      pixels[dst] = rgb[src];
      pixels[dst + 1] = rgb[src + 1];
      pixels[dst + 2] = rgb[src + 2];
      pixels[dst + 3] = 255;
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (ui.Image img) {
        completer.complete(img);
      },
    );
    return completer.future;
  }
}

class _MsdfEdgeSegment {
  Offset a;
  Offset b;
  int color;

  _MsdfEdgeSegment(this.a, this.b, {this.color = 0});
}

class _ContourEdge {
  final int index;
  final bool reversed;

  _ContourEdge(this.index, this.reversed);
}

class _Contour {
  final List<_ContourEdge> edges;
  final bool closed;

  _Contour(this.edges, this.closed);
}

class _MsdfGlyph {
  final Rect atlasRect;
  final double advance;
  final double offsetX;
  final double offsetY;

  _MsdfGlyph({
    required this.atlasRect,
    required this.advance,
    required this.offsetX,
    required this.offsetY,
  });
}

class _GlyphBitmap {
  final ui.Image image;
  final double pixelWidth;
  final double pixelHeight;
  final double advance;
  final double offsetX;
  final double offsetY;

  _GlyphBitmap({
    required this.image,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.advance,
    required this.offsetX,
    required this.offsetY,
  });

  // no empty factory; fallback handled in builder
}
