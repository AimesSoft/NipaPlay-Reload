import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Nipa's face, cropped at runtime from the key visual that already ships
/// with the app (`assets/images/main_image.png`), so no new asset is needed.
/// The crop matches the concept's `img/nipa-avatar.jpg`.
@immutable
class NipaFaceImage extends ImageProvider<NipaFaceImage> {
  const NipaFaceImage();

  static const asset = 'assets/images/main_image.png';
  static const _left = 0.4958, _top = 0.1241, _side = 0.2604;
  static const _decodeWidth = 1280;
  static const _out = 256;

  @override
  Future<NipaFaceImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<NipaFaceImage>(this);

  @override
  ImageStreamCompleter loadImage(
          NipaFaceImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_load());

  static Future<ImageInfo> _load() async {
    final data = await rootBundle.load(asset);
    final buffer =
        await ui.ImmutableBuffer.fromUint8List(data.buffer.asUint8List());
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec(
        targetWidth: _decodeWidth,
        targetHeight:
            (descriptor.height * _decodeWidth / descriptor.width).round());
    final source = (await codec.getNextFrame()).image;
    final side = source.width * _side;
    final rect =
        Rect.fromLTWH(source.width * _left, source.height * _top, side, side);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
        source,
        rect,
        Rect.fromLTWH(0, 0, _out.toDouble(), _out.toDouble()),
        Paint()..filterQuality = FilterQuality.high);
    final picture = recorder.endRecording();
    final face = await picture.toImage(_out, _out);
    picture.dispose();
    source.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return ImageInfo(image: face);
  }

  @override
  bool operator ==(Object other) => other is NipaFaceImage;

  @override
  int get hashCode => (NipaFaceImage).hashCode;
}

/// What Nipa is doing. The avatar never writes; it shows this.
enum NipaMood { idle, thinking, acting, waiting }

class NipaAvatar extends StatelessWidget {
  const NipaAvatar({
    super.key,
    this.size = 30,
    this.mood = NipaMood.idle,
    this.hasNews = false,
    this.sentence,
  });

  final double size;
  final NipaMood mood;
  final bool hasNews;

  /// Shown on hover, e.g. “在想”, “在补弹幕”.
  final String? sentence;

  @override
  Widget build(BuildContext context) {
    final reduced = NextMotion.reduced(context);
    Widget avatar = SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NextColors.ink3,
                image: const DecorationImage(
                    image: NipaFaceImage(),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0x2EFFFFFF),
                      spreadRadius: size >= 26 ? 1.5 : 1),
                ],
              ),
            ),
          ),
          if (mood != NipaMood.idle)
            Positioned(
              left: -6,
              top: -6,
              right: -6,
              bottom: -6,
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: _Halo(mood: mood, size: size, reduced: reduced),
                ),
              ),
            ),
          if (hasNews)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: math.max(8, size * 0.27),
                height: math.max(8, size * 0.27),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NextColors.accent,
                  border: Border.all(color: NextColors.ink, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
    if (sentence case final text? when text.isNotEmpty) {
      avatar = Tooltip(
        message: text,
        waitDuration: const Duration(milliseconds: 250),
        preferBelow: true,
        verticalOffset: size / 2 + 10,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xF01C1C24),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: NextColors.line2),
        ),
        textStyle: NextText.sans(12, color: NextColors.p2),
        child: avatar,
      );
    }
    return avatar;
  }
}

class _Halo extends StatefulWidget {
  const _Halo({required this.mood, required this.size, required this.reduced});
  final NipaMood mood;
  final double size;
  final bool reduced;

  @override
  State<_Halo> createState() => _HaloState();
}

class _HaloState extends State<_Halo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Halo old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood || old.reduced != widget.reduced) _sync();
  }

  void _sync() {
    _c.stop();
    switch (widget.mood) {
      case NipaMood.thinking:
        _c.duration = const Duration(milliseconds: 2400);
        _c.repeat(reverse: true);
      case NipaMood.acting:
        _c.duration = const Duration(milliseconds: 1400);
        if (widget.reduced) {
          _c.value = 0.12;
        } else {
          _c.repeat();
        }
      case NipaMood.waiting:
        _c.duration = const Duration(milliseconds: 1000);
        _c.repeat(reverse: true);
      case NipaMood.idle:
        break;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.size / 2 + 3.5;
    switch (widget.mood) {
      case NipaMood.thinking:
        // Outer ring breathes: opacity, plus scale when motion is allowed.
        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_c.value);
            return Transform.scale(
              scale: widget.reduced ? 1 : 1 + 0.06 * t,
              child: Opacity(
                opacity: 0.22 + 0.55 * t,
                child: CustomPaint(
                    painter: _RingPainter(r, NextColors.paper, 1.4)),
              ),
            );
          },
        );
      case NipaMood.acting:
        return Stack(fit: StackFit.expand, children: [
          CustomPaint(painter: _RingPainter(r, const Color(0x1FFFFFFF), 1.4)),
          RotationTransition(
            turns: _c,
            child: CustomPaint(painter: _ArcPainter(r, NextColors.accent, 1.8)),
          ),
        ]);
      case NipaMood.waiting:
        final dot = math.max(6.0, widget.size * 0.22);
        return Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 4),
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_c.value);
                return widget.reduced
                    ? Opacity(opacity: 0.45 + 0.55 * t, child: child)
                    : Transform.translate(
                        offset: Offset(0, -3 * t), child: child);
              },
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NextColors.accent,
                  border: Border.all(color: NextColors.ink, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Color(0x99FF2E55), blurRadius: 8)
                  ],
                ),
              ),
            ),
          ),
        );
      case NipaMood.idle:
        return const SizedBox.shrink();
    }
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.radius, this.color, this.width);
  final double radius;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
        size.center(Offset.zero),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.radius != radius || old.color != color || old.width != width;
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.radius, this.color, this.width);
  final double radius;
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
        Rect.fromCircle(center: size.center(Offset.zero), radius: radius),
        -math.pi / 2,
        math.pi * 0.55,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..color = color);
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.radius != radius || old.color != color || old.width != width;
}
