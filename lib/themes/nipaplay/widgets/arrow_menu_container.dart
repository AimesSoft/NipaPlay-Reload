import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class ArrowMenuContainer extends StatelessWidget {
  final Color backgroundColor;
  final Color borderColor;
  final double blurValue;
  final double borderRadius;
  final bool showPointer;
  final bool pointUp;
  final double pointerX;
  final double pointerWidth;
  final double pointerHeight;
  final EdgeInsetsGeometry contentPadding;
  final double borderWidth;
  final List<BoxShadow> shadows;
  final Widget child;

  const ArrowMenuContainer({
    super.key,
    required this.backgroundColor,
    required this.borderColor,
    required this.blurValue,
    required this.borderRadius,
    required this.showPointer,
    required this.pointUp,
    required this.pointerX,
    required this.pointerWidth,
    required this.pointerHeight,
    required this.contentPadding,
    required this.child,
    this.borderWidth = 0.5,
    this.shadows = const [
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.05),
        blurRadius: 8,
        offset: Offset(0, 4),
        spreadRadius: 0,
      ),
    ],
  });

  @override
  Widget build(BuildContext context) {
    final bool useSimpleClip = kIsWeb && !showPointer;
    final shape = ArrowMenuShape(
      radius: borderRadius,
      pointerWidth: showPointer ? pointerWidth : 0,
      pointerHeight: showPointer ? pointerHeight : 0,
      pointerX: pointerX,
      pointUp: pointUp,
      side: BorderSide.none,
    );
    final borderShape = ArrowMenuShape(
      radius: borderRadius,
      pointerWidth: showPointer ? pointerWidth : 0,
      pointerHeight: showPointer ? pointerHeight : 0,
      pointerX: pointerX,
      pointUp: pointUp,
      side: BorderSide(
        color: borderColor,
        width: borderWidth,
      ),
    );
    final borderRadiusValue = BorderRadius.circular(borderRadius);
    final backgroundDecoration = BoxDecoration(
      color: backgroundColor,
      borderRadius: borderRadiusValue,
      boxShadow: shadows,
    );
    final Widget blurredBody = useSimpleClip
        ? ClipRRect(
            borderRadius: borderRadiusValue,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue),
              child: DecoratedBox(
                decoration: backgroundDecoration,
                child: Padding(
                  padding: contentPadding,
                  child: child,
                ),
              ),
            ),
          )
        : ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: shape,
                  color: backgroundColor,
                  shadows: shadows,
                ),
                child: Padding(
                  padding: contentPadding,
                  child: child,
                ),
              ),
            ),
          );
    final ShapeBorder resolvedBorderShape =
        useSimpleClip ? RoundedRectangleBorder(borderRadius: borderRadiusValue) : borderShape;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        blurredBody,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: resolvedBorderShape,
                color: Colors.transparent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ArrowMenuShape extends ShapeBorder {
  final double radius;
  final double pointerWidth;
  final double pointerHeight;
  final double pointerX;
  final bool pointUp;
  final BorderSide side;

  const ArrowMenuShape({
    required this.radius,
    required this.pointerWidth,
    required this.pointerHeight,
    required this.pointerX,
    required this.pointUp,
    required this.side,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ShapeBorder scale(double t) {
    return ArrowMenuShape(
      radius: radius * t,
      pointerWidth: pointerWidth * t,
      pointerHeight: pointerHeight * t,
      pointerX: pointerX * t,
      pointUp: pointUp,
      side: side.scale(t),
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    if (side.width == 0) {
      return getOuterPath(rect, textDirection: textDirection);
    }
    return getOuterPath(rect.deflate(side.width), textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final double clampedRadius = radius.clamp(0.0, rect.shortestSide / 2);
    final bool hasPointer = pointerWidth > 0 && pointerHeight > 0;

    if (!hasPointer) {
      return Path()
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(clampedRadius)));
    }

    final double arrowHalf = pointerWidth / 2;
    final double arrowX = pointerX.clamp(
      clampedRadius + arrowHalf,
      rect.width - clampedRadius - arrowHalf,
    );
    final double top = rect.top + (pointUp ? pointerHeight : 0);
    final double bottom = rect.bottom - (pointUp ? 0 : pointerHeight);
    final Rect body = Rect.fromLTRB(rect.left, top, rect.right, bottom);
    final Radius r = Radius.circular(clampedRadius);
    final Path path = Path();

    if (pointUp) {
      path.moveTo(body.left + clampedRadius, body.top);
      path.lineTo(arrowX - arrowHalf, body.top);
      path.lineTo(arrowX, body.top - pointerHeight);
      path.lineTo(arrowX + arrowHalf, body.top);
      path.lineTo(body.right - clampedRadius, body.top);
      path.arcToPoint(Offset(body.right, body.top + clampedRadius), radius: r);
      path.lineTo(body.right, body.bottom - clampedRadius);
      path.arcToPoint(Offset(body.right - clampedRadius, body.bottom), radius: r);
      path.lineTo(body.left + clampedRadius, body.bottom);
      path.arcToPoint(Offset(body.left, body.bottom - clampedRadius), radius: r);
      path.lineTo(body.left, body.top + clampedRadius);
      path.arcToPoint(Offset(body.left + clampedRadius, body.top), radius: r);
    } else {
      path.moveTo(body.left + clampedRadius, body.top);
      path.lineTo(body.right - clampedRadius, body.top);
      path.arcToPoint(Offset(body.right, body.top + clampedRadius), radius: r);
      path.lineTo(body.right, body.bottom - clampedRadius);
      path.arcToPoint(Offset(body.right - clampedRadius, body.bottom), radius: r);
      path.lineTo(arrowX + arrowHalf, body.bottom);
      path.lineTo(arrowX, body.bottom + pointerHeight);
      path.lineTo(arrowX - arrowHalf, body.bottom);
      path.lineTo(body.left + clampedRadius, body.bottom);
      path.arcToPoint(Offset(body.left, body.bottom - clampedRadius), radius: r);
      path.lineTo(body.left, body.top + clampedRadius);
      path.arcToPoint(Offset(body.left + clampedRadius, body.top), radius: r);
    }

    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) {
      return;
    }
    final paint = side.toPaint()
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final path = getOuterPath(rect, textDirection: textDirection);
    canvas.drawPath(path, paint);
  }
}
