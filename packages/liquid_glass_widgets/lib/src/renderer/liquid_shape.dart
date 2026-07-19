import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'liquid_glass_renderer.dart';

/// Represents a shape that can be used by a [LiquidGlass] widget.
// ignore: deprecated_member_use
sealed class LiquidShape extends OutlinedBorder with EquatableMixin {
  const LiquidShape({super.side = BorderSide.none});

  @protected
  OutlinedBorder get _equivalentOutlinedBorder;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _equivalentOutlinedBorder.getInnerPath(
      rect,
      textDirection: textDirection,
    );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _equivalentOutlinedBorder.getOuterPath(
      rect,
      textDirection: textDirection,
    );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    _equivalentOutlinedBorder.paint(canvas, rect, textDirection: textDirection);
  }

  @override
  List<Object?> get props => [side];
}

/// Represents a squircle shape that can be used by a [LiquidGlass] widget.
///
/// Works like a [RoundedSuperellipseBorder].
class LiquidRoundedSuperellipse extends LiquidShape {
  /// Creates a new [LiquidRoundedSuperellipse] with the given [borderRadius].
  const LiquidRoundedSuperellipse({
    required this.borderRadius,
    super.side = BorderSide.none,
  });

  /// The radius of the squircle.
  ///
  /// This is the radius of the corners of the squircle.
  final double borderRadius;

  @override
  OutlinedBorder get _equivalentOutlinedBorder => RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
        side: side,
      );

  @override
  LiquidRoundedSuperellipse copyWith({
    BorderSide? side,
    double? borderRadius,
  }) {
    return LiquidRoundedSuperellipse(
      side: side ?? this.side,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidRoundedSuperellipse(
      borderRadius: borderRadius * t,
      side: side.scale(t),
    );
  }

  @override
  List<Object?> get props => [...super.props, borderRadius];
}

/// Represents an ellipse shape that can be used by a [LiquidGlass] widget.
///
/// Works like an [OvalBorder].
class LiquidOval extends LiquidShape {
  /// Creates a new [LiquidOval] with the given [side].
  const LiquidOval({super.side = BorderSide.none});

  @override
  OutlinedBorder get _equivalentOutlinedBorder => const OvalBorder();

  @override
  OutlinedBorder copyWith({BorderSide? side}) {
    return LiquidOval(
      side: side ?? this.side,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidOval(
      side: side.scale(t),
    );
  }
}

/// Represents a rounded rectangle shape that can be used by a [LiquidGlass]
/// widget.
///
/// Works like a [RoundedRectangleBorder].
class LiquidRoundedRectangle extends LiquidShape {
  /// Creates a new [LiquidRoundedRectangle] with the given [borderRadius].
  const LiquidRoundedRectangle({
    required this.borderRadius,
    super.side = BorderSide.none,
  });

  /// The radius of the rounded rectangle.
  ///
  /// This is the radius of the corners of the rounded rectangle.
  final double borderRadius;

  @override
  OutlinedBorder get _equivalentOutlinedBorder => RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
        side: side,
      );

  @override
  LiquidRoundedRectangle copyWith({
    BorderSide? side,
    double? borderRadius,
  }) {
    return LiquidRoundedRectangle(
      side: side ?? this.side,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidRoundedRectangle(
      borderRadius: borderRadius * t,
      side: side.scale(t),
    );
  }

  @override
  List<Object?> get props => [...super.props, borderRadius];
}

/// Represents a rounded rectangle shape with different radii for top and bottom.
class LiquidVerticalRoundedRectangle extends LiquidShape {
  /// Creates a new [LiquidVerticalRoundedRectangle].
  const LiquidVerticalRoundedRectangle({
    required this.topRadius,
    required this.bottomRadius,
    super.side = BorderSide.none,
  });

  /// The radius of the top corners.
  final double topRadius;

  /// The radius of the bottom corners.
  final double bottomRadius;

  @override
  OutlinedBorder get _equivalentOutlinedBorder => RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(topRadius),
          bottom: Radius.circular(bottomRadius),
        ),
        side: side,
      );

  @override
  LiquidVerticalRoundedRectangle copyWith({
    BorderSide? side,
    double? topRadius,
    double? bottomRadius,
  }) {
    return LiquidVerticalRoundedRectangle(
      side: side ?? this.side,
      topRadius: topRadius ?? this.topRadius,
      bottomRadius: bottomRadius ?? this.bottomRadius,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidVerticalRoundedRectangle(
      topRadius: topRadius * t,
      bottomRadius: bottomRadius * t,
      side: side.scale(t),
    );
  }

  @override
  List<Object?> get props => [...super.props, topRadius, bottomRadius];
}

/// Represents a squircle shape with different radii for top and bottom.
///
/// Works like a [RoundedSuperellipseBorder] with vertical border radii.
class LiquidVerticalRoundedSuperellipse extends LiquidShape {
  /// Creates a new [LiquidVerticalRoundedSuperellipse].
  const LiquidVerticalRoundedSuperellipse({
    required this.topRadius,
    required this.bottomRadius,
    super.side = BorderSide.none,
  });

  /// The radius of the top corners.
  final double topRadius;

  /// The radius of the bottom corners.
  final double bottomRadius;

  @override
  OutlinedBorder get _equivalentOutlinedBorder => RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(topRadius),
          bottom: Radius.circular(bottomRadius),
        ),
        side: side,
      );

  @override
  LiquidVerticalRoundedSuperellipse copyWith({
    BorderSide? side,
    double? topRadius,
    double? bottomRadius,
  }) {
    return LiquidVerticalRoundedSuperellipse(
      side: side ?? this.side,
      topRadius: topRadius ?? this.topRadius,
      bottomRadius: bottomRadius ?? this.bottomRadius,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidVerticalRoundedSuperellipse(
      topRadius: topRadius * t,
      bottomRadius: bottomRadius * t,
      side: side.scale(t),
    );
  }

  @override
  List<Object?> get props => [...super.props, topRadius, bottomRadius];
}
