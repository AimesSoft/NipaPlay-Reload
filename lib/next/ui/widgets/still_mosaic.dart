import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'artwork.dart';

/// One picture in a [StillMosaic]: a still, or the part of a picture that is
/// one ([crop], in fractions of the picture).
@immutable
class MosaicPiece {
  const MosaicPiece(
    this.path, {
    this.crop = const Rect.fromLTWH(0, 0, 1, 1),
    this.aspect = 16 / 9,
    this.decode,
  });

  final String path;
  final Rect crop;

  /// The crop's own width over its height.
  final double aspect;

  /// Decoded at this width when set: pieces of one picture share a decode.
  final int? decode;

  /// The whole picture's width over its height.
  double get pictureAspect => aspect * crop.height / crop.width;

  @override
  bool operator ==(Object other) =>
      other is MosaicPiece &&
      other.path == path &&
      other.crop == crop &&
      other.aspect == aspect &&
      other.decode == decode;

  @override
  int get hashCode => Object.hash(path, crop, aspect, decode);
}

/// Where each picture of [aspects] (width over height) goes in [size]: in
/// rows of one to three, every row as wide as the box and the rows together
/// as tall as it, [gap] between them, so nothing is left over. Each picture
/// is cropped as little as the box allows. With [lead], that picture gets a
/// row of its own when one of the rows holds one.
List<Rect> mosaicLayout(List<double> aspects, Size size,
    {double gap = 0, int? lead}) {
  final n = aspects.length;
  if (n == 0 || size.isEmpty) return const [];
  if (n == 1) return [Offset.zero & size];

  List<List<int>>? best;
  var bestCost = double.infinity, bestScale = 1.0;
  for (final rows in _rowSizes(n, math.min(n, 6))) {
    final order = _assign(rows, n, lead);
    final usable = size.height - gap * (rows.length - 1);
    if (usable <= 0) continue;
    var natural = 0.0;
    for (final row in order) {
      final width = size.width - gap * (row.length - 1);
      if (width <= 0) break;
      natural += width / row.fold(0.0, (sum, i) => sum + aspects[i]);
    }
    if (natural <= 0) continue;
    // Above 1 the rows are stretched taller than the pictures are, and
    // their sides are cropped; below, their tops and bottoms.
    final scale = usable / natural;
    var cost = math.log(scale).abs() + 0.02 * rows.length;
    for (final row in order) {
      // Three to a row is small on a poster card.
      if (row.length == 3) cost += 0.2;
      for (final i in row) {
        final shown = aspects[i] / scale;
        if (shown < 0.75 || shown > 3.2) cost += 1;
      }
    }
    final single = rows.indexOf(1);
    if (n >= 3) cost += single < 0 ? 0.12 : 0.01 * single;
    if (cost < bestCost) {
      bestCost = cost;
      best = order;
      bestScale = scale;
    }
  }
  if (best == null) return [for (var i = 0; i < n; i++) Rect.zero];

  final rects = List<Rect>.filled(n, Rect.zero);
  var y = 0.0;
  for (final (r, row) in best.indexed) {
    final width = size.width - gap * (row.length - 1);
    final sum = row.fold(0.0, (s, i) => s + aspects[i]);
    final last = r == best.length - 1;
    final height = last ? size.height - y : width / sum * bestScale;
    var x = 0.0;
    for (final (j, i) in row.indexed) {
      final w = j == row.length - 1 ? size.width - x : width * aspects[i] / sum;
      rects[i] = Rect.fromLTWH(x, y, w, height);
      x += w + gap;
    }
    y += height + gap;
  }
  return rects;
}

/// Every way to split [n] into rows of one to three, at most [most] rows.
Iterable<List<int>> _rowSizes(int n, int most) sync* {
  if (n == 0) {
    yield const [];
    return;
  }
  if (most == 0) return;
  for (var k = 1; k <= math.min(3, n); k++) {
    for (final rest in _rowSizes(n - k, most - 1)) {
      yield [k, ...rest];
    }
  }
}

/// The pictures row by row in their order, [lead] moved to the first row of
/// one.
List<List<int>> _assign(List<int> rows, int n, int? lead) {
  final single = lead == null ? -1 : rows.indexOf(1);
  final rest = [
    for (var i = 0; i < n; i++)
      if (single < 0 || i != lead) i
  ];
  var next = 0;
  return [
    for (final (r, k) in rows.indexed)
      r == single ? [lead!] : [for (var j = 0; j < k; j++) rest[next++]]
  ];
}

/// Stills laid edge to edge on dark: rows that fill the whole box whatever
/// their number, each still cropped to its place. A small box shows fewer
/// (only [lead] in the smallest); none shows the tint.
class StillMosaic extends StatelessWidget {
  const StillMosaic({super.key, required this.pieces, this.lead, this.tint});

  final List<MosaicPiece> pieces;

  /// The piece that matters most: kept in a small box, given a row of its
  /// own in a large one.
  final int? lead;
  final int? tint;

  /// How many fit a box this wide.
  static int most(double width) => width < 72
      ? 1
      : width < 128
          ? 3
          : 7;

  static double gapFor(Size size) =>
      (size.shortestSide * 0.01).clamp(1.0, 3.0).toDouble();

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final size = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : 200,
          constraints.hasBoundedHeight ? constraints.maxHeight : 300,
        );
        if (pieces.isEmpty || size.isEmpty) {
          return NextImage(null, shape: ArtShape.poster, tint: tint);
        }
        final shown = _shown(most(size.width));
        final at = shown.indexWhere((p) => p.$2 == lead);
        final rects = mosaicLayout(
            [for (final (piece, _) in shown) piece.aspect], size,
            gap: gapFor(size), lead: at < 0 ? null : at);
        return ColoredBox(
          color: NextColors.ink,
          child: Stack(children: [
            for (final (i, (piece, _)) in shown.indexed)
              Positioned.fromRect(
                rect: rects[i],
                child: _Crop(piece, tint: tint),
              ),
          ]),
        );
      });

  /// At most [count] pieces with their indices: the lead first kept, the
  /// rest in order.
  List<(MosaicPiece, int)> _shown(int count) {
    final all = [for (final (i, p) in pieces.indexed) (p, i)];
    if (all.length <= count) return all;
    final first = lead != null && lead! < all.length ? lead! : 0;
    final picked = <int>{first};
    for (var i = 0; picked.length < count && i < all.length; i++) {
      picked.add(i);
    }
    return [for (final e in all) if (picked.contains(e.$2)) e];
  }
}

/// A piece covering its box: the crop scaled to cover, centred.
class _Crop extends StatelessWidget {
  const _Crop(this.piece, {this.tint});
  final MosaicPiece piece;
  final int? tint;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth, h = constraints.maxHeight;
        final crop = piece.crop, aspect = piece.pictureAspect;
        // The whole picture at the size where its crop covers the box.
        final scale = math.max(w / (crop.width * aspect), h / crop.height);
        final pw = aspect * scale, ph = scale;
        final left = -crop.left * pw - (crop.width * pw - w) / 2;
        final top = -crop.top * ph - (crop.height * ph - h) / 2;
        return ClipRect(
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: left,
              top: top,
              width: pw,
              height: ph,
              child: NextImage(piece.path,
                  fit: BoxFit.fill, tint: tint, decode: piece.decode),
            ),
          ]),
        );
      });
}
