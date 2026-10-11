import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// The detail page's big title, painted above the content. Undocked it sits
/// where the content keeps room for it ([top], scrolling with the page);
/// as [dock] runs it shrinks into the middle of the top bar and fades, and
/// the bar's small title takes over. Under reduced motion it only fades.
class DockingTitle extends SingleChildRenderObjectWidget {
  const DockingTitle({
    super.key,
    required this.scroll,
    required this.dock,
    required this.top,
    required this.left,
    required this.viewWidth,
    required this.reduced,
    super.child,
  });

  final ScrollController scroll;
  final Animation<double> dock;

  /// The title's top in the content at scroll offset 0, and the left edge
  /// this box is placed at, in page coordinates.
  final double top;
  final double left;
  final double viewWidth;
  final bool reduced;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderDockingTitle(scroll, dock, top, left, viewWidth, reduced);

  @override
  void updateRenderObject(
          BuildContext context, RenderDockingTitle renderObject) =>
      renderObject
        ..listen(scroll, dock)
        ..top = top
        ..left = left
        ..viewWidth = viewWidth
        ..reduced = reduced;
}

class RenderDockingTitle extends RenderProxyBox {
  RenderDockingTitle(this._scroll, this._dock, this._top, this._left,
      this._viewWidth, this._reduced);

  ScrollController _scroll;
  Animation<double> _dock;
  double _top, _left, _viewWidth;
  bool _reduced;

  /// Height of the docked title in the bar.
  static const _docked = 20.0;

  void listen(ScrollController scroll, Animation<double> dock) {
    if (identical(scroll, _scroll) && identical(dock, _dock)) return;
    if (attached) _unlisten();
    _scroll = scroll;
    _dock = dock;
    if (attached) _listen();
    markNeedsPaint();
  }

  set top(double v) => _set(_top != v, () => _top = v);
  set left(double v) => _set(_left != v, () => _left = v);
  set viewWidth(double v) => _set(_viewWidth != v, () => _viewWidth = v);
  set reduced(bool v) => _set(_reduced != v, () => _reduced = v);

  void _set(bool changed, VoidCallback apply) {
    if (!changed) return;
    apply();
    markNeedsPaint();
  }

  void _listen() {
    _scroll.addListener(markNeedsPaint);
    _dock.addListener(markNeedsPaint);
  }

  void _unlisten() {
    _scroll.removeListener(markNeedsPaint);
    _dock.removeListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
  }

  @override
  void detach() {
    _unlisten();
    super.detach();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final scrolled = _scroll.hasClients ? math.max(0.0, _scroll.offset) : 0.0;
    final d = _dock.value;
    final y0 = _top - scrolled;
    final Matrix4 transform;
    final double opacity;
    if (_reduced) {
      transform = Matrix4.translationValues(0, y0, 0);
      opacity = 1 - d;
    } else {
      final size = child.size;
      final s1 = math.min(1.0, _docked / size.height);
      final x1 = (_viewWidth - size.width * s1) / 2 - _left;
      final y1 = NextMetrics.chromeRow / 2 - size.height * s1 / 2;
      final s = 1 + (s1 - 1) * d;
      transform = Matrix4.translationValues(x1 * d, y0 + (y1 - y0) * d, 0)
        ..scaleByDouble(s, s, 1, 1);
      opacity = 1 - const Interval(0.55, 1).transform(d);
    }
    if (opacity <= 0) return;
    void paintChild(PaintingContext context, Offset offset) =>
        context.pushTransform(needsCompositing, offset, transform, super.paint);
    if (opacity >= 1) {
      paintChild(context, offset);
    } else {
      context.pushOpacity(offset, (opacity * 255).round(), paintChild);
    }
  }
}
