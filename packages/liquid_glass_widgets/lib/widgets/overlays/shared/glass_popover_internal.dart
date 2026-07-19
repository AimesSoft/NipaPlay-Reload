part of '../glass_popover.dart';

class _GlassPopoverState extends State<GlassPopover>
    with TickerProviderStateMixin {
  final OverlayPortalController _overlayController = OverlayPortalController();

  late final GlassMorphController _morphController;

  Size? _triggerSize;
  double? _triggerBorderRadius;
  Offset _triggerGlobalPosition = Offset.zero;
  double _horizontalOffset = 0.0;
  double _verticalOffset = 0.0;

  Alignment _morphAlignment = Alignment.topLeft;

  /// Measured intrinsic height of the popover content.
  /// Only used when [widget.popoverHeight] is null.
  double? _measuredContentHeight;

  /// True once the first measurement pass has fired for the current open cycle,
  /// so we never queue a second [postFrameCallback] while the first is still
  /// pending or after measurement has settled.
  bool _contentMeasured = false;

  /// Cached widget subtree from [widget.contentBuilder].
  ///
  /// Set exactly once in [_openPopover] and again in [didUpdateWidget] when the
  /// widget configuration changes while the popover is showing. It is NEVER
  /// mutated inside [build] — that would violate Flutter's purity contract.
  Widget? _cachedContent;

  /// Key used to measure the intrinsic height of the content subtree.
  final GlobalKey _contentKey = GlobalKey();

  // ---------------------------------------------------------------------------
  // Alignment helper
  // ---------------------------------------------------------------------------

  Alignment? _getAlignment(GlassMenuAlignment align) {
    switch (align) {
      case GlassMenuAlignment.none:
        return null;
      case GlassMenuAlignment.topLeft:
        return Alignment.topLeft;
      case GlassMenuAlignment.topCenter:
        return Alignment.topCenter;
      case GlassMenuAlignment.topRight:
        return Alignment.topRight;
      case GlassMenuAlignment.centerLeft:
        return Alignment.centerLeft;
      case GlassMenuAlignment.center:
        return Alignment.center;
      case GlassMenuAlignment.centerRight:
        return Alignment.centerRight;
      case GlassMenuAlignment.bottomLeft:
        return Alignment.bottomLeft;
      case GlassMenuAlignment.bottomCenter:
        return Alignment.bottomCenter;
      case GlassMenuAlignment.bottomRight:
        return Alignment.bottomRight;
    }
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _morphController = GlassMorphController(vsync: this);
    _morphController.addListener(() {
      // Hide the overlay only when the spring has FULLY SETTLED near zero.
      // The velocity guard prevents premature hiding on the first zero-crossing
      // during the underdamped close bounce.
      if (_overlayController.isShowing &&
          _morphController.value <= 0.001 &&
          _morphController.velocity.abs() < 0.5 &&
          _morphController.status != AnimationStatus.forward) {
        _overlayController.hide();
        // Reset per-open-cycle state so stale values from a previous position
        // never bleed into the next open cycle.
        setState(() {
          _horizontalOffset = 0.0;
          _verticalOffset = 0.0;
          _measuredContentHeight = null;
          _contentMeasured = false;
          _cachedContent = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _morphController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync the reduced-motion accessibility flag to the morph controller.
    _morphController.setDisableAnimations(
      MediaQuery.of(context).disableAnimations,
    );
  }

  @override
  void didUpdateWidget(GlassPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the popover is showing and the widget configuration changed, refresh
    // the cached content tree so the user sees up-to-date data. This is the
    // correct lifecycle hook — never do this inside build().
    if (_overlayController.isShowing &&
        (oldWidget.contentBuilder != widget.contentBuilder ||
            oldWidget.popoverWidth != widget.popoverWidth ||
            oldWidget.popoverHeight != widget.popoverHeight)) {
      setState(() {
        _cachedContent = widget.contentBuilder(context, _closePopover);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Mirror the GlassMenu structure exactly:
    //   AnimatedBuilder (top-level, no render object) →
    //     builder returns Stack([trigger, OverlayPortal])
    //
    // This matters for _openPopover(): context.findRenderObject() traverses
    // down from the GlassPopover element. Because AnimatedBuilder has NO render
    // object, it keeps descending into the builder's returned Stack. That Stack
    // is always sized to the trigger button, so localToGlobal(Offset.zero) gives
    // the correct global position of the trigger on screen.
    //
    // If we return an outer Stack from build() instead, findRenderObject() stops
    // at the outer Stack, whose origin can be corrupted by the OverlayPortal
    // sibling when the overlay is visible.
    //
    // The trigger is passed as AnimatedBuilder's `child` (not rebuilt inside
    // the builder closure) so it is stable across animation ticks.
    final Widget triggerContent = widget.triggerBuilder != null
        ? widget.triggerBuilder!(context, _togglePopover)
        : GestureDetector(
            onTap: _togglePopover,
            child: widget.trigger,
          );

    return AnimatedBuilder(
      animation: _morphController.animation,
      builder: (context, child) {
        final rawValue = _morphController.value;

        // Block trigger taps while the popover is meaningfully open.
        final isPopoverBlocking =
            _overlayController.isShowing && rawValue > 0.8;

        // During the closing handoff the real trigger becomes visible again
        // and inherits the liquid momentum from the collapsing blob.
        final isHandoff =
            _morphController.isClosing && _morphController.hasHandedOff;
        final triggerOpacity =
            (_overlayController.isShowing && !isHandoff) ? 0.0 : 1.0;

        // Push vector: the trigger physically recoils as the popover snaps shut.
        // These values mirror _buildMorphingOverlay's finalDx/finalDy so the
        // trajectory is mathematically identical to the blob's path.
        final tw = _triggerSize?.width ?? 44.0;
        final th = _triggerSize?.height ?? 44.0;
        final dxMag = (widget.popoverWidth - tw) / 2.0;
        final dyMag = (_effectivePopoverHeight() - th) / 2.0;
        final double pushDx = isHandoff
            ? (-_morphAlignment.x * dxMag + _horizontalOffset) * rawValue
            : 0.0;
        final double pushDy = isHandoff
            ? (-_morphAlignment.y * dyMag + _verticalOffset) * rawValue
            : 0.0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Trigger ────────────────────────────────────────────────────
            // Only apply Transform/Opacity/IgnorePointer layers when actually needed
            // to prevent unnecessary compositing layers that cause BackdropFilter
            // flickering (Premium quality) during scroll.
            pushDx != 0.0 || pushDy != 0.0
                ? Transform.translate(
                    offset: Offset(pushDx, pushDy),
                    child: Opacity(
                      opacity: triggerOpacity,
                      child: IgnorePointer(
                        ignoring: isPopoverBlocking,
                        child: child, // triggerContent
                      ),
                    ),
                  )
                : triggerOpacity < 1.0
                    ? Opacity(
                        opacity: triggerOpacity,
                        child: IgnorePointer(
                          ignoring: isPopoverBlocking,
                          child: child,
                        ),
                      )
                    : isPopoverBlocking
                        ? IgnorePointer(
                            ignoring: true,
                            child: child,
                          )
                        : child ??
                            const SizedBox
                                .shrink(), // Raw trigger when completely idle

            // ── Overlay portal ─────────────────────────────────────────────
            // OverlayPortal renders in the overlay layer, not in-tree, so it
            // is zero-sized here and does not affect the Stack's dimensions.
            OverlayPortal(
              controller: _overlayController,
              overlayChildBuilder: _buildMorphingOverlay,
            ),
          ],
        );
      },
      child: triggerContent,
    );
  }

  // ---------------------------------------------------------------------------
  // Popover open / close
  // ---------------------------------------------------------------------------

  void _togglePopover() {
    if (_overlayController.isShowing && _morphController.value > 0.1) {
      _closePopover();
    } else {
      _openPopover();
    }
  }

  void _closePopover() {
    if (!mounted) return;
    // GlassMorphController.close() injects the −2.5 velocity hint internally,
    // maximising the rubber-band bounce amplitude on close.
    _morphController.close();
    widget.onClose?.call();
  }

  void _openPopover() {
    // context.findRenderObject() works correctly here because build() returns
    // AnimatedBuilder at the top level. AnimatedBuilder has no render object of
    // its own, so the traversal descends into the builder's returned Stack,
    // which is always sized to the trigger button. localToGlobal therefore gives
    // the trigger's actual screen position.
    final renderBox = context.findRenderObject() as RenderBox?;

    if (renderBox == null || !renderBox.hasSize) return;

    _triggerSize = renderBox.size;
    _triggerBorderRadius = _triggerSize!.height / 2;
    _triggerGlobalPosition = renderBox.localToGlobal(Offset.zero);

    // Build the content widget exactly once for this open cycle. All
    // subsequent frames read _cachedContent; didUpdateWidget refreshes it
    // if the parent rebuilds with changed props while the popover is open.
    _cachedContent = widget.contentBuilder(context, _closePopover);

    // If popoverHeight is explicitly provided, measurement is already known.
    // Mark it measured so the Offstage pass is skipped and we open immediately.
    _contentMeasured = widget.popoverHeight != null;

    // Compute alignment / clamping offsets and notify Flutter in a single
    // setState so the first overlay build sees fully consistent values.
    // If popoverHeight is null, we can't compute clamping yet — the first
    // frame will be an invisible Offstage measurement pass instead.
    setState(() {
      if (_contentMeasured) {
        _updatePositionAndClamping();
      }
      _overlayController.show();
    });

    if (_contentMeasured) {
      _morphController.open();
    }
    widget.onOpen?.call();
  }

  // ---------------------------------------------------------------------------
  // Layout helpers
  // ---------------------------------------------------------------------------

  /// Returns the maximum height the popover may occupy, bounded by the
  /// safe-area-inset screen height.
  ///
  /// Falls back to a finite sentinel (800 dp) instead of [double.infinity]
  /// so downstream lerp / arithmetic never yields NaN or Infinity when
  /// [MediaQuery] is unavailable (e.g. in some test environments).
  double _getMaxPopoverHeight([EdgeInsets? precomputedPadding]) {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) return 800.0;

    final screenHeight = mediaQuery.size.height;
    final insets = precomputedPadding ?? _viewInsets();
    final double safeTop = widget.screenPadding.top + insets.top;
    final double safeBottom = widget.screenPadding.bottom + insets.bottom;
    return math.max(0.0, screenHeight - safeTop - safeBottom);
  }

  /// Computes [EdgeInsets] from the platform view padding once so callers
  /// that need both max-height and edge clamping share the same values.
  EdgeInsets _viewInsets() {
    final flutterView = View.of(context);
    return EdgeInsets.fromViewPadding(
        flutterView.padding, flutterView.devicePixelRatio);
  }

  double _effectivePopoverHeight([EdgeInsets? precomputedPadding]) {
    if (widget.popoverHeight != null) return widget.popoverHeight!;
    final maxH = _getMaxPopoverHeight(precomputedPadding);
    // By the time the morph animation uses this value, _measuredContentHeight
    // is guaranteed to be populated via the Offstage measurement pass.
    return math.min(_measuredContentHeight ?? 0.0, maxH);
  }

  /// Recomputes [_morphAlignment], [_horizontalOffset], and [_verticalOffset]
  /// from the current trigger geometry and screen metrics.
  ///
  /// Must only be called when [_triggerSize] is non-null.
  /// Safe to call inside a [setState] callback; it only mutates fields and
  /// never calls [setState] itself.
  void _updatePositionAndClamping() {
    if (_triggerSize == null) return;

    final position = _triggerGlobalPosition;
    final mediaQuery = MediaQuery.maybeOf(context);
    final screenWidth = mediaQuery?.size.width ?? double.infinity;
    final screenHeight = mediaQuery?.size.height ?? double.infinity;

    // Compute view insets once and share between max-height and clamping.
    final insets = _viewInsets();
    final popoverHeight = _effectivePopoverHeight(insets);

    // 1. Determine alignment (auto vs. manual)
    if (widget.alignment == null ||
        widget.alignment == GlassMenuAlignment.none) {
      final isRightHalf = screenWidth.isFinite && position.dx > screenWidth / 2;

      final spaceBelow = screenHeight.isFinite
          ? screenHeight - (position.dy + _triggerSize!.height)
          : double.infinity;
      final spaceAbove = screenHeight.isFinite ? position.dy : double.infinity;

      final shouldFlipVertical =
          spaceBelow < popoverHeight && spaceAbove > popoverHeight;

      _morphAlignment = shouldFlipVertical
          ? (isRightHalf ? Alignment.bottomRight : Alignment.bottomLeft)
          : (isRightHalf ? Alignment.topRight : Alignment.topLeft);
    } else {
      _morphAlignment = _getAlignment(widget.alignment!) ?? Alignment.center;
    }

    // 2. Edge clamping: compute offsets to keep the popover within the safe area
    double hOffset = 0.0;
    double vOffset = 0.0;

    if (widget.autoAdjustToScreen) {
      final double safeTop = widget.screenPadding.top + insets.top;
      final double safeBottom = widget.screenPadding.bottom + insets.bottom;
      final double safeLeft = widget.screenPadding.left + insets.left;
      final double safeRight = widget.screenPadding.right + insets.right;

      final double targetX =
          position.dx + (1 + _morphAlignment.x) * _triggerSize!.width / 2;
      final double targetY =
          position.dy + (1 + _morphAlignment.y) * _triggerSize!.height / 2;
      final double popoverLeft =
          targetX - (1 + _morphAlignment.x) * widget.popoverWidth / 2;
      final double popoverTop =
          targetY - (1 + _morphAlignment.y) * popoverHeight / 2;

      // Horizontal
      if (popoverLeft < safeLeft) {
        hOffset = safeLeft - popoverLeft;
      } else if (screenWidth.isFinite &&
          popoverLeft + widget.popoverWidth > screenWidth - safeRight) {
        hOffset =
            (screenWidth - safeRight) - (popoverLeft + widget.popoverWidth);
      }

      // Vertical
      if (popoverTop < safeTop) {
        vOffset = safeTop - popoverTop;
      } else if (screenHeight.isFinite &&
          popoverTop + popoverHeight > screenHeight - safeBottom) {
        vOffset = (screenHeight - safeBottom) - (popoverTop + popoverHeight);
      }
    }

    _horizontalOffset = hOffset;
    _verticalOffset = vOffset;
  }

  // ---------------------------------------------------------------------------
  // Overlay rendering
  // ---------------------------------------------------------------------------

  Widget _buildMorphingOverlay(BuildContext context) {
    if (_triggerSize == null) return const SizedBox.shrink();

    if (!_contentMeasured) {
      // Invisible measurement pass.
      // Renders the content offstage to allow Flutter's layout engine to
      // synchronously calculate its exact intrinsic height before we launch
      // the morph animation on the very next frame.
      return Offstage(
        child: OverflowBox(
          alignment: Alignment.center,
          minWidth: widget.popoverWidth,
          maxWidth: widget.popoverWidth,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Builder(builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _contentMeasured) return;
              final renderBox =
                  _contentKey.currentContext?.findRenderObject() as RenderBox?;
              if (renderBox != null && renderBox.hasSize) {
                setState(() {
                  _measuredContentHeight = renderBox.size.height;
                  _contentMeasured = true;
                  _updatePositionAndClamping();
                });
                _morphController.open();
              }
            });
            return SizedBox(
              key: _contentKey,
              width: widget.popoverWidth,
              child: _cachedContent ?? const SizedBox.shrink(),
            );
          }),
        ),
      );
    }

    // ── Values computed ONCE per overlay build ──────────────────────────────
    // These are hoisted outside AnimatedBuilder so they are never recomputed
    // on every animation tick (60 fps). They only change when the overlay is
    // rebuilt due to a setState (open, close-complete, or measurement update).

    final tw = _triggerSize!.width;
    final th = _triggerSize!.height;
    final popoverWidth = widget.popoverWidth;
    final popoverHeight = _effectivePopoverHeight();

    final dxMag = (popoverWidth - tw) / 2.0;
    final dyMag = (popoverHeight - th) / 2.0;
    final finalDx = -_morphAlignment.x * dxMag;
    final finalDy = -_morphAlignment.y * dyMag;

    // InheritedWidget lookups — traverses the element tree; must NOT be inside
    // the AnimatedBuilder's builder closure.
    final inheritedSettings = InheritedLiquidGlass.of(context);
    final effectiveSettings = widget.settings ??
        inheritedSettings ??
        const LiquidGlassSettings(
          blur: 10,
          thickness: 10,
          glassColor: Color.fromRGBO(255, 255, 255, 0.12),
          lightAngle: GlassDefaults.lightAngle,
          lightIntensity: 0.7,
          ambientStrength: 0.4,
          saturation: 1.2,
          refractiveIndex: 0.7,
          chromaticAberration: 0.0,
        );

    final effectiveQuality = GlassThemeHelpers.resolveQuality(
      context,
      widgetQuality: widget.quality,
    );

    final isDark = GlassTheme.brightnessOf(context) == Brightness.dark;

    // ── Per-frame AnimatedBuilder ────────────────────────────────────────────
    return AnimatedBuilder(
      animation: _morphController.animation,
      builder: (context, child) {
        final rawValue = _morphController.value;
        final clampedValue = rawValue.clamp(0.0, 1.0);

        // Physics delegated to GlassMorphController — pure arithmetic, no
        // tree traversal, safe at 60 fps.
        final state = _morphController.computeState(
          finalDx: finalDx,
          finalDy: finalDy,
          horizontalOffset: _horizontalOffset,
          verticalOffset: _verticalOffset,
        );

        final currentHeight = lerpDouble(th, popoverHeight, state.sizeT)!;
        final currentWidth = lerpDouble(tw, popoverWidth, state.sizeT)!;

        return Stack(
          children: [
            // ── Tap-to-close barrier ─────────────────────────────────────────
            if (clampedValue > 0.3 && widget.barrierDismissible)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _closePopover,
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),

            // ── Non-dismissible barrier (absorbs taps without closing) ───────
            if (clampedValue > 0.3 && !widget.barrierDismissible)
              const Positioned.fill(
                child: AbsorbPointer(),
              ),

            // ── Two-blob metaball morphing ───────────────────────────────────
            Positioned.fill(
              child: Opacity(
                opacity: (_morphController.isClosing &&
                        _morphController.hasHandedOff)
                    ? 0.0
                    : 1.0,
                child: LiquidGlassLayer(
                  settings: effectiveSettings,
                  child: InheritedLiquidGlass(
                    settings: effectiveSettings,
                    quality: effectiveQuality,
                    isBlurProvidedByAncestor: false,
                    child: LiquidGlassBlendGroup(
                      blend: state.blend,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // ── Blob A: Trigger ghost ────────────────────────
                          // Stays centred on the trigger and shrinks to 0
                          // over the first 40 % of the open animation,
                          // smoothly breaking the liquid bridge.
                          Positioned(
                            left: _triggerGlobalPosition.dx + state.pushDx,
                            top: _triggerGlobalPosition.dy + state.pushDy,
                            child: Transform.scale(
                              scale: state.anchorScale,
                              child: GlassContainer(
                                useOwnLayer: false,
                                settings: effectiveSettings,
                                quality: effectiveQuality,
                                width: tw,
                                height: th,
                                shape: LiquidRoundedSuperellipse(
                                  borderRadius: _triggerBorderRadius ??
                                      _triggerSize!.shortestSide / 2.0,
                                ),
                              ),
                            ),
                          ),

                          // ── Blob B: Popover body ─────────────────────────
                          Positioned(
                            left: _triggerGlobalPosition.dx +
                                tw / 2.0 +
                                state.currentDx -
                                currentWidth / 2.0 +
                                (_horizontalOffset * clampedValue),
                            top: _triggerGlobalPosition.dy +
                                th / 2.0 +
                                state.currentDy -
                                currentHeight / 2.0 +
                                (_verticalOffset * clampedValue),
                            child: IgnorePointer(
                              ignoring: clampedValue < 0.8,
                              child: _buildPopoverContainer(
                                state,
                                clampedValue,
                                currentWidth,
                                currentHeight,
                                effectiveSettings,
                                effectiveQuality,
                                isDark,
                                popoverHeight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPopoverContainer(
    LiquidMorphState state,
    double clampedValue,
    double currentWidth,
    double currentHeight,
    LiquidGlassSettings effectiveSettings,
    GlassQuality effectiveQuality,
    bool isDark,
    double targetHeight,
  ) {
    // Morph border radius from pill → target corner radius.
    final maxRadius = math.min(currentWidth, currentHeight) / 2.0;
    final double radiusT =
        Curves.easeInExpo.transform(state.sizeT.clamp(0.0, 1.0));
    final currentRadius =
        lerpDouble(maxRadius, widget.popoverBorderRadius, radiusT)!;

    final teardropShape = LiquidRoundedSuperellipse(
      borderRadius: currentRadius,
    );

    return LiquidStretch(
      stretch: widget.stretch,
      interactionScale: widget.interactionScale,
      resistance: widget.stretchResistance,
      axis: widget.stretchAxis,
      suppressInteractionOnChildren: false,
      anchorStretch: false,
      allowPositiveX: widget.allowPositiveX ?? (_morphAlignment.x < 0),
      allowNegativeX: widget.allowNegativeX ?? (_morphAlignment.x > 0),
      allowPositiveY: widget.allowPositiveY ?? (_morphAlignment.y < 0),
      allowNegativeY: widget.allowNegativeY ?? (_morphAlignment.y > 0),
      child: GlassContainer(
        useOwnLayer: false,
        settings: effectiveSettings,
        quality: effectiveQuality,
        allowElevation: false,
        width: currentWidth,
        height: currentHeight,
        shape: teardropShape,
        clipBehavior: Clip.antiAlias,
        glowIntensity: widget.glowIntensity,
        child: GlassGlow(
          enabled: widget.enableInteractionGlow,
          glowOnTapOnly: widget.glowOnTapOnly,
          glowColor: widget.glowColor ??
              (isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.10)),
          glowRadius: widget.glowRadius,
          glowBlurRadius: 40,
          clipper: ShapeBorderClipper(shape: teardropShape),
          child: Transform.scale(
            scale: state.containerScale,
            alignment: Alignment.center,
            child: Stack(
              alignment: _morphAlignment,
              clipBehavior: Clip.none,
              children: [
                // Content enters at 30 % morph progress and scales 0.5 → 1.0.
                // On close the reverse plays, matching GlassMenu behaviour.
                if (clampedValue > 0.3)
                  _buildContentWithMeasurement(clampedValue, targetHeight),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentWithMeasurement(
      double clampedValue, double targetHeight) {
    // Fade in smoothly: fully opaque by 70 % morph progress.
    final contentOpacity = ((clampedValue - 0.3) / 0.4).clamp(0.0, 1.0);

    // Scale 0.5 → 1.0 with easeOut, in sync with the expanding container.
    final contentScale = lerpDouble(
      0.5,
      1.0,
      Curves.easeOut.transform(
        ((clampedValue - 0.3) / 0.7).clamp(0.0, 1.0),
      ),
    )!;

    // _cachedContent was set in _openPopover (or refreshed in didUpdateWidget).
    // The null-coalesce is a last-resort safety net only.
    final content =
        _cachedContent ?? widget.contentBuilder(context, _closePopover);

    Widget measuredContent;
    if (widget.popoverHeight == null) {
      measuredContent = SizedBox(
        width: widget.popoverWidth,
        child: content,
      );
    } else {
      measuredContent = SizedBox(
        width: widget.popoverWidth,
        height: widget.popoverHeight,
        child: content,
      );
    }

    // OverflowBox provides the full target size to the content during layout
    // while the container is still morphing. The visual illusion is maintained
    // by the Transform.scale above; GlassContainer's Clip.antiAlias clips
    // anything outside the current morph boundary.
    return OverflowBox(
      alignment: Alignment.center,
      minWidth: widget.popoverWidth,
      maxWidth: widget.popoverWidth,
      minHeight: 0,
      maxHeight:
          widget.popoverHeight ?? _measuredContentHeight ?? double.infinity,
      child: Opacity(
        opacity: contentOpacity,
        child: Transform.scale(
          scale: contentScale,
          child: measuredContent,
        ),
      ),
    );
  }
}
