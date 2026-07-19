import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

@internal
mixin TransformTrackingRepaintBoundaryMixin on RenderProxyBox {
  @override
  GeometryTransformTrackingLayer? get layer =>
      super.layer as GeometryTransformTrackingLayer?;

  @override
  bool get isRepaintBoundary => true;

  @override
  OffsetLayer updateCompositedLayer({
    covariant GeometryTransformTrackingLayer? oldLayer,
  }) {
    final layer = oldLayer ??= GeometryTransformTrackingLayer();

    // ignore: cascade_invocations
    layer
      ..renderObject = this
      ..onTransformChanged = () {
        if (attached) {
          onTransformChanged();
        }
      };

    return layer;
  }

  @mustCallSuper
  @override
  void paint(PaintingContext context, ui.Offset offset) {
    layer!.offset = offset;
    super.paint(context, offset);
  }

  void onTransformChanged();
}

@internal
mixin TransformTrackingRenderObjectMixin on RenderProxyBox {
  @override
  GeometryTransformTrackingLayer? get layer =>
      super.layer as GeometryTransformTrackingLayer?;

  @override
  @nonVirtual
  bool get isRepaintBoundary => false;

  @override
  bool get alwaysNeedsCompositing => true;

  @mustCallSuper
  @override
  void paint(PaintingContext context, ui.Offset offset) {
    setUpLayer(offset);
    context.pushLayer(layer!, (context, offset) {}, offset);
    super.paint(context, offset);
  }

  GeometryTransformTrackingLayer setUpLayer(Offset offset) {
    // ignore: unnecessary_this
    return (this.layer ??= GeometryTransformTrackingLayer())
      ..renderObject = this
      ..onTransformChanged = () {
        if (attached) {
          onTransformChanged();
        }
      };
  }

  void onTransformChanged();
}

@internal
class GeometryTransformTrackingLayer extends OffsetLayer {
  GeometryTransformTrackingLayer();

  RenderObject? renderObject;
  VoidCallback? onTransformChanged;
  Matrix4? _lastTransform;

  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void addToScene(ui.SceneBuilder builder) {
    final currentTransform = renderObject?.getTransformTo(null);
    if (!MatrixUtils.matrixEquals(currentTransform, _lastTransform)) {
      onTransformChanged?.call();
      _lastTransform = currentTransform;
    }
  }
}
