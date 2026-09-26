import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Supplies the page title and source selector to the active media view so all
/// controls can share one height budget, including the view's search/filter bar.
class TelevisionMediaLibraryHeaderScope extends InheritedWidget {
  const TelevisionMediaLibraryHeaderScope({
    super.key,
    required this.header,
    required super.child,
  });

  final Widget header;

  static TelevisionMediaLibraryHeaderScope? maybeOf(
    BuildContext context,
  ) =>
      context.dependOnInheritedWidgetOfExactType<
          TelevisionMediaLibraryHeaderScope>();

  @override
  bool updateShouldNotify(TelevisionMediaLibraryHeaderScope oldWidget) =>
      header != oldWidget.header;
}

/// Keeps media at its original size while fitting the complete TV control area
/// into at most one third of the available page height. Without the TV scope,
/// this is the usual unscaled controls/expanded-content column.
class MediaLibraryBody extends StatelessWidget {
  const MediaLibraryBody({
    super.key,
    this.controls = const <Widget>[],
    required this.child,
  });

  final List<Widget> controls;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pageHeader = TelevisionMediaLibraryHeaderScope.maybeOf(context);
    if (pageHeader == null) {
      if (controls.isEmpty) return child;
      return Column(
        children: [
          ...controls,
          Expanded(child: child),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              key: const ValueKey('television-media-library-controls'),
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 3),
              child: _ScaledMediaLibraryControls(
                minimumLayoutWidth:
                    1280 * MediaQuery.textScalerOf(context).scale(1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [pageHeader.header, ...controls],
                ),
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

/// Uses the existing render transform for painting, hit testing, semantics and
/// directional focus geometry. Only this header's layout is scaled, never media.
class _ScaledMediaLibraryControls extends SingleChildRenderObjectWidget {
  const _ScaledMediaLibraryControls({
    required this.minimumLayoutWidth,
    required super.child,
  });

  final double minimumLayoutWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScaledMediaLibraryControls(minimumLayoutWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScaledMediaLibraryControls renderObject,
  ) {
    renderObject.minimumLayoutWidth = minimumLayoutWidth;
  }
}

class _RenderScaledMediaLibraryControls extends RenderTransform {
  _RenderScaledMediaLibraryControls(this._minimumLayoutWidth)
      : super(transform: Matrix4.identity());

  double _minimumLayoutWidth;

  set minimumLayoutWidth(double value) {
    if (_minimumLayoutWidth == value) return;
    _minimumLayoutWidth = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final content = child!;
    final width = constraints.maxWidth;
    if (width <= 0 || constraints.maxHeight <= 0) {
      content.layout(BoxConstraints.tightFor(width: _minimumLayoutWidth));
      size = constraints.smallest;
      transform = Matrix4.diagonal3Values(0, 0, 1);
      return;
    }

    // Measure at a width that accommodates TV action rows even with large text.
    final layoutWidth = math.max(width, _minimumLayoutWidth);
    content.layout(BoxConstraints.tightFor(width: layoutWidth),
        parentUsesSize: true);
    var scale = math.min(1.0, width / layoutWidth);
    if (content.size.height > 0) {
      scale = math.min(scale, constraints.maxHeight / content.size.height);
    }

    // Widen the logical header before applying the uniform scale so its search
    // field and source strip still span the page instead of clustering left.
    content.layout(BoxConstraints.tightFor(width: width / scale),
        parentUsesSize: true);
    if (content.size.height > 0) {
      scale = math.min(scale, constraints.maxHeight / content.size.height);
    }
    size = constraints.constrain(Size(width, content.size.height * scale));
    transform = Matrix4.diagonal3Values(scale, scale, 1);
  }
}
