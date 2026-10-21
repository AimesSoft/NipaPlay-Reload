import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'artwork.dart';
import 'sheet_panels.dart';
import 'still_mosaic.dart';

/// The stills of a contact sheet (see [sheetPanels]), as pieces of the
/// picture, with the largest as the lead.
@immutable
class PosterSheet {
  const PosterSheet(this.pieces, this.lead);
  final List<MosaicPiece> pieces;
  final int lead;

  /// [panels] of a picture read at [width]×[height], each taken in a little
  /// so the gutters' fringe stays out.
  factory PosterSheet.of(
      String path, List<SheetPanel> panels, int width, int height) {
    final pieces = <MosaicPiece>[];
    var lead = 0, largest = 0;
    for (final (i, p) in panels.indexed) {
      final inset = math.max(1.0, math.min(p.width, p.height) * 0.02);
      final w = p.width - inset * 2, h = p.height - inset * 2;
      pieces.add(MosaicPiece(path,
          crop: Rect.fromLTWH(
              (p.x + inset) / width, (p.y + inset) / height, w / width, h / height),
          aspect: w / h,
          decode: PosterSheets.readWidth));
      if (p.width * p.height > largest) {
        largest = p.width * p.height;
        lead = i;
      }
    }
    return PosterSheet(pieces, lead);
  }
}

/// Which posters are contact sheets. Each picture is read once, at the
/// poster card's own decode so the two share it; what was found holds for
/// the session.
abstract final class PosterSheets {
  /// What a poster card decodes at on a 2× screen, rounded as [NextImage]
  /// rounds; a smaller picture is read whole.
  static const readWidth = 384;

  static final _known = <String, PosterSheet?>{};
  static final _reading = <String, Future<PosterSheet?>>{};

  /// Ticks when a picture turns out to be a sheet.
  static final changes = ValueNotifier<int>(0);

  static bool isKnown(String path) => _known.containsKey(path);

  /// The sheet [path] is, once known; null for any other picture.
  static PosterSheet? sheet(String path) => _known[path];

  /// Reads [path] (once). A picture that cannot be read is no sheet, and is
  /// tried again next time.
  static Future<PosterSheet?> read(String path) {
    if (_known.containsKey(path)) return SynchronousFuture(_known[path]);
    return _reading[path] ??= _read(path).then((sheet) {
      _reading.remove(path);
      _known[path] = sheet;
      if (sheet != null) changes.value++;
      return sheet;
    }, onError: (Object error) {
      _reading.remove(path);
      return null;
    });
  }

  @visibleForTesting
  static void forget() {
    _known.clear();
    _reading.clear();
  }

  static Future<PosterSheet?> _read(String path) async {
    final stream = ResizeImage.resizeIfNeeded(readWidth, null, artProvider(path))
        .resolve(ImageConfiguration.empty);
    final got = Completer<ImageInfo>();
    final listener = ImageStreamListener((info, _) {
      got.isCompleted ? info.dispose() : got.complete(info);
    }, onError: (error, stack) {
      if (!got.isCompleted) got.completeError(error, stack);
    });
    stream.addListener(listener);
    try {
      final info = await got.future;
      try {
        final image = info.image;
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return null;
        final panels = sheetPanels(
            data.buffer.asUint8List(), image.width, image.height);
        return panels == null
            ? null
            : PosterSheet.of(path, panels, image.width, image.height);
      } finally {
        info.dispose();
      }
    } finally {
      stream.removeListener(listener);
    }
  }
}

/// A work's poster. When the poster is a contact sheet (stills on white with
/// gaps, what some providers give a work without a key visual), its stills
/// are laid out again edge to edge on dark, so no white shows; any other
/// poster is shown as it is.
class PosterArt extends StatefulWidget {
  const PosterArt(this.path, {super.key, this.tint, this.read = true});
  final String? path;
  final int? tint;

  /// Whether to read the picture first. A thumbnail does not: it shows the
  /// picture straight away, and the sheet once a larger poster has found
  /// it.
  final bool read;

  @override
  State<PosterArt> createState() => _PosterArtState();
}

class _PosterArtState extends State<PosterArt> {
  /// The path whose reading ended here (read or not).
  String? _settled;

  /// Shown after a wait: fades in, as pictures do.
  bool _waited = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(PosterArt old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _read();
  }

  void _read() {
    final path = widget.path;
    if (!widget.read ||
        path == null ||
        path.isEmpty ||
        PosterSheets.isKnown(path)) {
      return;
    }
    _waited = true;
    PosterSheets.read(path).then((_) {
      if (mounted && widget.path == path) setState(() => _settled = path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.path, tint = widget.tint;
    final waiting = NextImage(null, shape: ArtShape.poster, tint: tint);
    if (path == null || path.isEmpty) return waiting;
    if (!widget.read) {
      return SheetBuilder(
        path: path,
        builder: (context, sheet) => sheet == null
            ? NextImage(path, shape: ArtShape.poster, tint: tint)
            : StillMosaic(pieces: sheet.pieces, lead: sheet.lead, tint: tint),
      );
    }
    final Widget art;
    if (PosterSheets.isKnown(path)) {
      final sheet = PosterSheets.sheet(path);
      art = sheet == null
          ? NextImage(path, shape: ArtShape.poster, tint: tint)
          : StillMosaic(pieces: sheet.pieces, lead: sheet.lead, tint: tint);
    } else if (_settled == path) {
      art = NextImage(path, shape: ArtShape.poster, tint: tint);
    } else {
      return waiting;
    }
    if (!_waited) return art;
    return Stack(fit: StackFit.expand, children: [
      waiting,
      TweenAnimationBuilder<double>(
        key: ValueKey(path),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        builder: (context, t, child) => Opacity(opacity: t, child: child),
        child: art,
      ),
    ]);
  }
}

/// A contact sheet's mosaic covering any box: laid out once in a poster's
/// shape and scaled to cover, so it keeps its arrangement while the box
/// changes shape (a picture flying into a page).
class SheetCover extends StatelessWidget {
  const SheetCover(this.sheet,
      {super.key, this.tint, this.alignment = Alignment.center});
  final PosterSheet sheet;
  final int? tint;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: alignment,
          child: SizedBox(
            width: 200,
            height: 300,
            child:
                StillMosaic(pieces: sheet.pieces, lead: sheet.lead, tint: tint),
          ),
        ),
      );
}

/// Builds with the sheet [path] is (null while unknown or for any other
/// picture), and again when that becomes known. It does not read the
/// picture itself.
class SheetBuilder extends StatelessWidget {
  const SheetBuilder({super.key, required this.path, required this.builder});
  final String? path;
  final Widget Function(BuildContext context, PosterSheet? sheet) builder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: PosterSheets.changes,
        builder: (context, _, __) {
          final path = this.path;
          return builder(context, path == null ? null : PosterSheets.sheet(path));
        },
      );
}
