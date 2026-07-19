import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import '../liquid_glass_renderer.dart';
import '../internal/render_liquid_glass_geometry.dart';
import '../internal/snap_rect_to_pixels.dart';
import '../logging.dart';
import 'package:meta/meta.dart';

/// A render object that can assemble [RenderLiquidGlassGeometry] shapes and
/// render them to the screen with the liquid glass effect.
@internal
abstract class LiquidGlassRenderObject extends RenderProxyBox {
  LiquidGlassRenderObject({
    required GeometryRenderLink link,
    required this.renderShader,
    required LiquidGlassSettings settings,
    required double devicePixelRatio,
    BackdropKey? backdropKey,
    ui.Image? captureImage,
    Offset captureOriginInScreenSpace = Offset.zero,
  })  : _settings = settings,
        _devicePixelRatio = devicePixelRatio,
        _backdropKey = backdropKey,
        _captureImage = captureImage,
        _captureOriginInScreenSpace = captureOriginInScreenSpace,
        _link = link,
        _cachedLightDir = Offset(
          cos(settings.lightAngle),
          -sin(settings.lightAngle),
        );

  static final logger = Logger(LgrLogNames.render);

  final FragmentShader renderShader;

  /// Cached light direction vector — updated only when [settings.lightAngle]
  /// changes. Avoids recomputing cos/sin on every setting change.
  Offset _cachedLightDir;

  /// The size that the geometry texture should have.
  Size get desiredMatteSize;

  Matrix4 get matteTransform;

  late GeometryRenderLink _link;
  GeometryRenderLink get link => _link;
  set link(GeometryRenderLink value) {
    if (_link == value) return;
    markNeedsPaint();
    _link = value;
  }

  LiquidGlassSettings? _settings;
  LiquidGlassSettings get settings => _settings!;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    // Only recompute the trig if lightAngle actually changed.
    if (value.lightAngle != _settings?.lightAngle) {
      _cachedLightDir = Offset(
        cos(value.lightAngle),
        -sin(value.lightAngle),
      );
    }
    _settings = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// The [BackdropKey] for blur-sharing via the layer's own [BackdropGroup].
  /// Set to [BackdropGroup.of(context)?.backdropKey] from the layer's local
  /// [BackdropGroup]; null when no group exists (no-op).
  BackdropKey? _backdropKey;
  BackdropKey? get backdropKey => _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (_backdropKey == value) return;
    _backdropKey = value;
    markNeedsPaint();
  }

  // ── Capture-path fields ───────────────────────────────────────────────────
  //
  // When [captureImage] is non-null, [paintLiquidGlass] implementations MUST
  // use [paintLiquidGlassWithCapture] instead of the BackdropFilterLayer path.
  // The captured image is the background texture fed directly to the shader,
  // bypassing the live compositor read entirely.
  //
  // [captureOriginInScreenSpace] is the global (screen-space) logical-pixel
  // position of the RepaintBoundary that produced [captureImage]. It is used
  // to derive [uCaptureOffset]: the physical-pixel shift from the render
  // surface's canvas origin to the capture boundary's origin, which corrects
  // [FlutterFragCoord()] (canvas-local) into capture-image space.

  ui.Image? _captureImage;
  ui.Image? get captureImage => _captureImage;
  set captureImage(ui.Image? value) {
    if (identical(_captureImage, value)) return;
    _captureImage = value;
    markNeedsPaint();
  }

  Offset _captureOriginInScreenSpace = Offset.zero;
  Offset get captureOriginInScreenSpace => _captureOriginInScreenSpace;
  set captureOriginInScreenSpace(Offset value) {
    if (_captureOriginInScreenSpace == value) return;
    _captureOriginInScreenSpace = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _geometryImage != null;

  /// Pre-rendered geometry texture in the render object's LOCAL coordinate space.
  /// Because the geometry is recorded without `matteTransform`, its screen-space
  /// position is always derived synchronously at paint time — zero async lag.
  ui.Image? _geometryImage;
  @protected
  ui.Image? get geometryImage => _geometryImage;

  /// Bounding box of [_geometryImage] in the render object's LOCAL logical-pixel
  /// coordinate space (snapped to physical pixels).
  /// Apply `matteTransform` at paint time to get the current screen-space bounds.
  Rect _geometryLocalBounds = Rect.zero;
  @protected
  Rect get geometryLocalBounds => _geometryLocalBounds;

  @override
  @mustCallSuper
  void attach(PipelineOwner owner) {
    super.attach(owner);
  }

  @override
  @mustCallSuper
  void detach() {
    super.detach();
  }

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    needsGeometryUpdate = true;
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  ui.Rect _paintBounds = ui.Rect.zero;

  @override
  ui.Rect get paintBounds => _paintBounds;

  // Reusable list to avoid per-frame allocations during paint traversal.
  final _shapesWithGeometry =
      <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];

  // MARK: Painting

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    // Guard: if this render object has been detached mid-frame (e.g. rapid
    // widget removal during isolate shutdown), skip all GPU operations to
    // prevent use-after-free on Mali GPU Vulkan resources.
    if (!attached) return;

    if (LgrLogs.isLogActive(logger)) {
      logger.finest(
        '$hashCode Painting liquid glass with '
        '${link._shapeGeometries.length} shapes.',
      );
    }

    _shapesWithGeometry.clear();

    Rect? boundingBox;

    for (final geometryRo in link.shapes) {
      final geometry = geometryRo.maybeRebuildGeometry();

      if (geometry == null) continue;

      final transform = geometryRo.getTransformTo(this);
      _shapesWithGeometry.add((geometryRo, geometry, transform));

      final geoBounds = MatrixUtils.transformRect(
        transform,
        geometry.bounds,
      );
      boundingBox = boundingBox == null
          ? geoBounds
          : boundingBox.expandToInclude(geoBounds);
    }

    if (boundingBox == null) {
      _clearGeometryImage();

      super.paint(context, offset);
      return;
    }

    _paintBounds = boundingBox;

    // Fast-path: if there is no geometric thickness AND no blur, there is
    // nothing to render — skip the expensive async geometry build entirely.
    // If blur > 0 but thickness == 0, we must still run paintLiquidGlass so
    // the BackdropFilterLayer blur pass fires in liquid_glass_layer.dart.
    if (settings.effectiveThickness <= 0 && settings.effectiveBlur <= 0) {
      _clearGeometryImage();
      paintShapeContents(
        context,
        offset,
        _shapesWithGeometry,
        insideGlass: true,
      );
      paintShapeContents(
        context,
        offset,
        _shapesWithGeometry,
        insideGlass: false,
      );
      super.paint(context, offset);
      return;
    }

    if (needsGeometryUpdate || _geometryImage == null || link._dirty) {
      link.updateAllGeometries();
      link._dirty = false;
      needsGeometryUpdate = false;

      // Synchronous rasterization (toImageSync) eliminates 1-frame jitter
      // during size animations (like modal sheet expansion).
      _updateGeometrySync(_shapesWithGeometry, boundingBox);

      // The image is now current — no latency. On the very first frame there
      // is no previous image — fall through to the early-return below via the
      // null check on _geometryImage.
    }

    if (debugPaintLiquidGlassGeometry) {
      _debugPaintGeometry(context, offset);
      paintShapeContents(
        context,
        offset,
        _shapesWithGeometry,
        insideGlass: true,
      );
      paintShapeContents(
        context,
        offset,
        _shapesWithGeometry,
        insideGlass: false,
      );
    } else {
      if (_geometryImage case final geometryImage?) {
        // Map the texture to exactly the bounds it was originally built for
        // (_geometryLocalBounds) rather than the newly expanding current frame
        // bounds (_paintBounds).
        //
        // Using _paintBounds causes severe multi-button jitter during animations:
        // as one button scales, _paintBounds expands/shifts to contain it. Since
        // the asynchronous texture lags 1 frame behind, rendering the old texture
        // using the new origin visually shifted entire group of buttons on the
        // screen until the next texture arrived.
        //
        // Locking the shader mapping to the precise bounds the texture was built
        // with ensures stable pixel positioning for the life of the texture.
        final activeBounds = MatrixUtils.transformRect(
          matteTransform,
          _geometryLocalBounds,
        ).snapToPixels(devicePixelRatio);

        renderShader
          // Slot 0-1: uSize — physical-pixel size of the backdrop layer.
          // Must be set before painting so the shader can derive correct screen UVs.
          ..setFloatUniforms(initialIndex: 0, (value) {
            value.setSize(desiredMatteSize * devicePixelRatio);
          })
          // Slots 2-5: uGeometryOffset + uGeometrySize in physical pixels.
          ..setFloatUniforms(initialIndex: 2, (value) {
            value
              ..setOffset(activeBounds.topLeft * devicePixelRatio)
              ..setSize(activeBounds.size * devicePixelRatio);
          })
          ..setFloatUniforms(initialIndex: 6, (value) {
            value
              ..setColor(settings.effectiveGlassColor)
              ..setFloats([
                settings.effectiveRefractiveIndex,
                settings.effectiveChromaticAberration,
                settings.effectiveThickness,
                settings.effectiveLightIntensity,
                settings.effectiveAmbientStrength,
                settings.effectiveSaturation,
              ])
              ..setOffset(_cachedLightDir);
          })
          // Slot 18: uWhiten (whitening amount); slot 19: uWhitenGated
          // (1 = luminance-gated, the light-mode behaviour; 0 = uniform lift).
          // Slot 20: uPinchStrength (concave horizontal-pinch for indicator pills).
          ..setFloatUniforms(initialIndex: 18, (value) {
            value
              ..setFloat(settings.whitenStrength)
              ..setFloat(settings.whitenGated ? 1.0 : 0.0)
              ..setFloat(settings.pinchStrength);
          })
          // Slots 21-24: uBackgroundFallback (straight RGBA). An opaque stand-in
          // for backdrop regions the engine can't capture (e.g. a PlatformView
          // past the glass, which the lens would otherwise render black); a == 0
          // (the default) disables it. See the over-composite in textureBilinear
          // (liquid_glass_final_render.frag).
          //
          // Sourced from platformViewFallbackColor, falling back to backerColor
          // when unset — so backerColor keeps doubling as the fill for existing
          // recipes, while platformViewFallbackColor lets callers decouple the
          // PlatformView fill from the aesthetic backer.
          ..setFloatUniforms(initialIndex: 21, (value) {
            final b = settings.platformViewFallbackColor ??
                settings.backerColor ??
                const Color(0x00000000);
            value.setFloats(<double>[b.r, b.g, b.b, b.a]);
          })
          // Slots 25-26: uCaptureOffset — zero in BackdropFilter mode (no-op).
          // The capture path sets this non-zero via paintLiquidGlassWithCapture.
          ..setFloatUniforms(initialIndex: 25, (value) {
            value.setOffset(Offset.zero);
          })
          // Slot 27: uAmbientRim — full-perimeter Fresnel rim boost.
          ..setFloatUniforms(initialIndex: 27, (value) {
            value.setFloat(settings.ambientRim);
          })
          ..setImageSampler(
            1,
            geometryImage,
            filterQuality: FilterQuality.medium,
          );
        paintLiquidGlass(
          context,
          offset,
          _shapesWithGeometry,
          _paintBounds,
        );
      }
    }

    super.paint(context, offset);
  }

  void _clearGeometryImage() {
    _geometryImage?.dispose();
    _geometryImage = null;
  }

  /// Subclasses implement the actual glass rendering
  /// (e.g., with backdrop filters)
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
  );

  /// Direct-draw paint path used when [captureImage] is non-null.
  ///
  /// Instead of emitting a [BackdropFilterLayer] (which reads from the live
  /// compositor), this draws the shader as a plain rect onto the current canvas,
  /// binding the pre-captured background image to sampler slot 0.
  ///
  /// Coordinate math:
  ///   [FlutterFragCoord()] in a plain canvas.drawRect gives the fragment
  ///   position within the current compositing layer (the RepaintBoundary that
  ///   [LiquidGlassLayer] creates). [captureOriginInScreenSpace] is the global
  ///   logical-pixel origin of the capture boundary (from localToGlobal).
  ///   The physical-pixel offset between the two coordinate origins is:
  ///
  ///     uCaptureOffset = (captureOriginGlobal - thisRenderOriginGlobal) * dpr
  ///
  ///   Adding this to [FlutterFragCoord()] maps each fragment into capture-image
  ///   space, so [screenUV] correctly addresses the pre-captured bar texture.
  @protected
  void paintLiquidGlassWithCapture(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
    ui.Image capture,
  ) {
    if (!attached) return;

    final dpr = devicePixelRatio;

    // Our render object's global logical-pixel origin.
    final thisOriginGlobal = getTransformTo(null).getTranslation();
    final thisOriginLogical = Offset(thisOriginGlobal.x, thisOriginGlobal.y);

    // Physical-pixel offset from our canvas origin → capture-boundary origin.
    // This is the uCaptureOffset uniform: it shifts FlutterFragCoord() (which
    // is relative to the compositing layer, i.e. our RepaintBoundary surface)
    // into the capture image's coordinate space.
    final captureOffset =
        (_captureOriginInScreenSpace - thisOriginLogical) * dpr;

    // uSize: physical pixel dimensions of the captured image.
    final captureSize =
        ui.Size(capture.width.toDouble(), capture.height.toDouble());

    // Geometry bounds in screen space, snapped to pixels.
    final activeBounds = MatrixUtils.transformRect(
      matteTransform,
      _geometryLocalBounds,
    ).snapToPixels(dpr);

    // uGeometryOffset/uGeometrySize are relative to the capture image origin
    // (not screen origin) so that geometryUV = (fragCoord + uCaptureOffset -
    // uGeometryOffset) / uGeometrySize resolves correctly.
    final geometryOffsetInCapture =
        (activeBounds.topLeft - _captureOriginInScreenSpace) * dpr;
    final geometrySizePhysical = activeBounds.size * dpr;

    renderShader
      // Slot 0-1: uSize — physical size of the capture image.
      ..setFloatUniforms(initialIndex: 0, (value) {
        value.setSize(captureSize);
      })
      // Slots 2-5: uGeometryOffset + uGeometrySize, relative to capture origin.
      ..setFloatUniforms(initialIndex: 2, (value) {
        value
          ..setOffset(geometryOffsetInCapture)
          ..setSize(geometrySizePhysical);
      })
      ..setFloatUniforms(initialIndex: 6, (value) {
        value
          ..setColor(settings.effectiveGlassColor)
          ..setFloats([
            settings.effectiveRefractiveIndex,
            settings.effectiveChromaticAberration,
            settings.effectiveThickness,
            settings.effectiveLightIntensity,
            settings.effectiveAmbientStrength,
            settings.effectiveSaturation,
          ])
          ..setOffset(_cachedLightDir);
      })
      ..setFloatUniforms(initialIndex: 18, (value) {
        value
          ..setFloat(settings.whitenStrength)
          ..setFloat(settings.whitenGated ? 1.0 : 0.0)
          ..setFloat(settings.pinchStrength);
      })
      ..setFloatUniforms(initialIndex: 21, (value) {
        final b = settings.platformViewFallbackColor ??
            settings.backerColor ??
            const Color(0x00000000);
        value.setFloats(<double>[b.r, b.g, b.b, b.a]);
      })
      // Slot 25-26: uCaptureOffset — shift fragCoord into capture-image space.
      ..setFloatUniforms(initialIndex: 25, (value) {
        value.setOffset(captureOffset);
      })
      // Slot 27: uAmbientRim — full-perimeter Fresnel rim boost.
      ..setFloatUniforms(initialIndex: 27, (value) {
        value.setFloat(settings.ambientRim);
      })
      // Slot 0: captured background image (replaces the BackdropFilter read).
      ..setImageSampler(0, capture)
      ..setImageSampler(1, geometryImage!, filterQuality: FilterQuality.medium);

    // Draw the capture path: no BackdropFilterLayer needed — draw directly
    // onto the canvas over the expanded clip rect.
    final clipRect = boundingBox.expandToInclude(
      Rect.fromLTRB(
        boundingBox.left - 20,
        boundingBox.top - 15,
        boundingBox.right + 20,
        boundingBox.bottom + 15,
      ),
    );

    // Pass 1 (blur): retained even in capture mode — the blur layer reads from
    // the BackdropGroup which is the internal bar blur, not the external capture.
    // This is correct: the inner blur pass blurs icon content inside the glass,
    // the capture provides the bar background behind the glass.
    paintShapeContents(context, offset, shapes, insideGlass: true);

    // Pass 2: glass refraction shader as a plain canvas.drawRect.
    // No BackdropFilter wrapper; the captured image is already bound to slot 0.
    context.canvas
      ..save()
      ..clipRect(clipRect.shift(offset))
      ..drawRect(
        clipRect.shift(offset),
        Paint()..shader = renderShader,
      )
      ..restore();

    // Pass 3: shape contents painted on top (non-glass child layer).
    paintShapeContents(context, offset, shapes, insideGlass: false);
  }

  @protected
  void paintShapeContents(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes, {
    required bool insideGlass,
  }) {
    for (final (geometryRenderObject, _, _) in shapes) {
      geometryRenderObject.paintShapeContents(
        this,
        context,
        offset,
        insideGlass: insideGlass,
      );
    }
  }

  void _debugPaintGeometry(PaintingContext context, Offset offset) {
    if (_geometryImage case final geometryImage?) {
      // The geometry image is in local space. Draw it at the local bounds
      // position so it overlays the glass content at the correct on-screen
      // location (the rendering canvas already applies the correct transform).
      context.canvas
        ..save()
        ..translate(_geometryLocalBounds.left, _geometryLocalBounds.top)
        ..scale(1 / devicePixelRatio)
        ..drawImage(
          geometryImage,
          Offset.zero,
          Paint()..blendMode = BlendMode.src,
        )
        ..restore();
    }
  }

  /// Synchronously rasterizes the geometry picture using [ui.Picture.toImageSync].
  /// This eliminates the 1-frame async lag that caused visible ghosting during
  /// modal sheet and button-group animations. For the small pill-shape geometry
  /// used here, synchronous GPU upload is sub-millisecond and safe.
  void _updateGeometrySync(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
    Rect bounds,
  ) {
    // Record canvas commands synchronously — pure CPU work.
    final (picture, localBounds, imageSize) =
        _recordGeometryPicture(geometries, bounds);

    try {
      // Synchronous GPU rasterization — no async lag.
      // Clamp to ≥1: jelly squash can push geometry to near-zero size and
      // toImageSync(0, n) throws "Invalid image dimensions".
      final image = picture.toImageSync(
        max(1, imageSize.width.ceil()),
        max(1, imageSize.height.ceil()),
      );

      _clearGeometryImage();
      _geometryImage = image;
      _geometryLocalBounds = localBounds;
      // No markNeedsPaint() needed — we are already inside paint().
    } finally {
      picture.dispose();
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    _clearGeometryImage();
    // Break reference chains to prevent stale GPU resource retention during
    // isolate shutdown. The render shader holds a DlRuntimeEffectColorSource
    // that retains Vulkan textures — nulling _settings ensures no closure
    // retains a path back to the shader's GPU resources past the Vulkan
    // context lifetime (Crash 2 in Mali GPU crash analysis).
    _settings = null;
    super.dispose();
  }

  // MARK: Geometry

  @protected
  bool needsGeometryUpdate = true;

  /// Records all geometry drawing commands into a [ui.Picture] synchronously.
  /// Returns the picture, the LOCAL-SPACE bounding rect, and the physical
  /// pixel size needed for rasterization. The caller is responsible for
  /// disposing the picture after rasterization.
  ///
  /// ## Local-space rasterization (A3)
  ///
  /// The geometry is recorded WITHOUT applying [matteTransform] (position,
  /// jelly scale, global screen offset). This means:
  ///
  /// - The image represents the pill SDF purely in the render object's own
  ///   coordinate space, at its current LOCAL size.
  /// - [matteTransform] is applied SYNCHRONOUSLY at paint time to derive the
  ///   screen-space [uGeometryOffset] / [uGeometrySize] uniforms — no 1-2
  ///   frame async lag, no correction needed.
  /// - Geometry rebuilds are only needed when the LOCAL shape changes
  ///   (layout/style), not for every position or jelly-scale animation frame.
  (ui.Picture, Rect, Size) _recordGeometryPicture(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
    Rect bounds,
  ) {
    // Work in local coordinate space — no matteTransform applied.
    // Inflate by 2 logical pixels (= 2×DPR physical pixels after snapToPixels
    // aligns to the pixel grid) to ensure the anti-aliased SDF edge is fully
    // captured. Without this, the picture boundaries tightly crop the fractional
    // edge pixels, abruptly cutting off the rim lighting at the pill boundary.
    final localBounds = bounds.snapToPixels(devicePixelRatio).inflate(2.0);
    final size = localBounds.size * devicePixelRatio;

    final logging = LgrLogs.isLogActive(logger);
    final buffer = logging
        ? StringBuffer(
            '$hashCode Recording geometry picture (local space) with '
            '${geometries.length} shapes at size '
            '${size.width}x${size.height}:\n',
          )
        : null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    for (final (_, geometry, transform) in geometries) {
      canvas
        ..save()
        ..scale(devicePixelRatio)
        // Shift so localBounds.topLeft is the texture origin.
        ..translate(-localBounds.left, -localBounds.top)
        // Apply geometry-local → glass-local transform only (no matteTransform).
        ..transform(transform.storage)
        ..scale(1 / devicePixelRatio)
        ..translate(
          geometry.matteBounds.topLeft.dx,
          geometry.matteBounds.topLeft.dy,
        );

      switch (geometry) {
        case UnrenderedGeometryCache(matte: final picture):
          buffer?.writeln('\t- Unrendered @ ${geometry.bounds}');
          canvas.drawPicture(picture);
        case RenderedGeometryCache(matte: final image):
          buffer?.writeln('\t- Rendered @ ${geometry.bounds}');
          canvas.drawImage(image, Offset.zero, Paint());
      }

      canvas.restore();
    }

    if (buffer != null) logger.fine(buffer.toString());
    return (recorder.endRecording(), localBounds, size);
  }
}

@internal
class GeometryRenderLink {
  final List<RenderLiquidGlassGeometry> _shapeGeometries = [];

  UnmodifiableListView<RenderLiquidGlassGeometry> get shapes =>
      UnmodifiableListView(_shapeGeometries);

  bool _dirty = false;

  void updateAllGeometries() {
    for (final renderObject in _shapeGeometries) {
      renderObject.maybeRebuildGeometry();
    }
  }

  void registerGeometry(
    RenderLiquidGlassGeometry renderObject,
  ) {
    _dirty = true;
    _shapeGeometries.add(renderObject);
  }

  /// Signals that a geometry object has completed a rebuild and the render
  /// layer should integrate the updated result on the next paint.
  void notifyGeometryChanged(RenderLiquidGlassGeometry renderObject) {
    _dirty = true;
  }

  void unregisterGeometry(RenderLiquidGlassGeometry renderObject) {
    _shapeGeometries.remove(renderObject);
  }

  void dispose() {
    _shapeGeometries.clear();
  }
}

@internal
class InheritedGeometryRenderLink extends InheritedWidget {
  const InheritedGeometryRenderLink({
    required this.link,
    required super.child,
    super.key,
  });

  final GeometryRenderLink link;

  static GeometryRenderLink? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InheritedGeometryRenderLink>()
        ?.link;
  }

  @override
  bool updateShouldNotify(covariant InheritedGeometryRenderLink oldWidget) {
    return oldWidget.link != link;
  }
}
