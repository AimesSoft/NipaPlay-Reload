part of '../glass_menu.dart';

class _GlassMenuState extends State<GlassMenu> with TickerProviderStateMixin {
  final OverlayPortalController _overlayController = OverlayPortalController();

  late final GlassMorphController _morphController;

  late final ScrollController _scrollController;
  Size? _triggerSize;
  double? _triggerBorderRadius;
  Offset _triggerGlobalPosition = Offset.zero; // captured in _openMenu
  int? _hoveredIndex;
  bool _isDragging = false;
  bool _hasStretched =
      false; // Prevents closing if we moved into stretch territory
  double _initialScrollOffset = 0.0;
  Offset _initialLocalPosition = Offset.zero;
  double _horizontalOffset = 0.0;
  double _verticalOffset = 0.0;

  /// Live screen-space nudge added to the captured trigger position while the
  /// menu is OPEN, so an external owner can keep the floating menu glued to a
  /// moving anchor (e.g. a canvas tile trailing under a rubberband) WITHOUT
  /// re-opening. Reset to zero on each [_openMenu]. Applied to both morph blobs
  /// in [_buildMorphingOverlay]. It deliberately does NOT recompute the
  /// screen-edge clamping ([_horizontalOffset]/[_verticalOffset]) — trails are
  /// small and bounded, and recomputing per-frame is not worth the cost. Driven
  /// via [GlassMenuController.setFollowOffset] / [setFollowOffset].
  Offset _followOffset = Offset.zero;

  // --- Granular Update System (Performance + No flicker) ---
  // We cache the outer list but use notifiers to update selection state
  // without rebuilding the entire menu tree.
  late final ValueNotifier<int?> _hoveredIndexNotifier;
  late final ValueNotifier<bool> _isDraggingNotifier;
  List<Widget>? _cachedWrappedItems;

  @override
  void didUpdateWidget(GlassMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (!identical(widget.items, oldWidget.items)) {
      _cachedWrappedItems = null;
      // BUG 12 FIX: Clear hover state if items shrink while menu is open
      // to prevent RangeError when the selection pill tries to measure
      // a now-deleted index.
      if (widget.items.length < oldWidget.items.length) {
        _hoveredIndex = null;
        _hoveredIndexNotifier.value = null;
      }
    }
  }

  Alignment _morphAlignment = Alignment.topLeft;

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

  @override
  void initState() {
    super.initState();
    _morphController = GlassMorphController(vsync: this);
    _morphController.addListener(() {
      if (mounted) setState(() {});

      // Hide overlay only when the spring has FULLY SETTLED near 0.
      // Velocity guard prevents premature hiding on first zero-crossing
      // during the underdamped close bounce.
      if (_overlayController.isShowing &&
          _morphController.value <= 0.001 &&
          _morphController.velocity.abs() < 0.5 &&
          _morphController.status != AnimationStatus.forward) {
        _overlayController.hide();
        // Reset screen-edge clamping offsets so stale values from a previous
        // open position don't bleed into the next open cycle.
        _horizontalOffset = 0.0;
        _verticalOffset = 0.0;
      }
    });
    _scrollController = ScrollController();
    _hoveredIndexNotifier = ValueNotifier(null);
    _isDraggingNotifier = ValueNotifier(false);
    widget.controller?._attach(this);
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _morphController.dispose();
    _scrollController.dispose();
    _hoveredIndexNotifier.dispose();
    _isDraggingNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync the reduced-motion accessibility flag to the morph controller.
    // This fires on first build and again whenever MediaQuery changes
    // (e.g. user toggles Reduce Motion in Settings while the app is running).
    _morphController.setDisableAnimations(
      MediaQuery.of(context).disableAnimations,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _morphController.animation,
      builder: (context, child) {
        final rawValue = _morphController.value;

        // Block trigger taps while menu is significantly open.
        final isMenuBlocking = _overlayController.isShowing && rawValue > 0.8;

        // Early handoff during close:
        // When closing and the liquid morph is almost finished, we latch the handoff.
        // We instantly hide the empty glass overlay and reveal the REAL trigger.
        // The latch ensures that even if the underdamped spring bounces back up
        // past 0.15, we don't hide the icon again!
        final isHandoff =
            _morphController.isClosing && _morphController.hasHandedOff;
        final triggerOpacity =
            (_overlayController.isShowing && !isHandoff) ? 0.0 : 1.0;

        // Calculate the momentum push vector based on the exact same logic as Blob B
        // so the real trigger precisely inherits the menu's momentum trajectory.
        final tw = _triggerSize?.width ?? 44.0;
        final th = _triggerSize?.height ?? 44.0;
        final menuWidth = widget.menuWidth;
        final menuHeight = _calculateMenuHeight();
        final dxMag = (menuWidth - tw) / 2.0;
        final dyMag = (menuHeight - th) / 2.0;
        final finalDx = -_morphAlignment.x * dxMag;
        final finalDy = -_morphAlignment.y * dyMag;

        // Apply the push momentum to the real trigger during the underdamped bounce
        // Include the offsets so the trajectory is mathematically perfect.
        final double pushDx =
            isHandoff ? (finalDx + _horizontalOffset) * rawValue : 0.0;
        final double pushDy =
            isHandoff ? (finalDy + _verticalOffset) * rawValue : 0.0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Trigger — physically bounces when slammed by the closing menu!
            Transform.translate(
              offset: Offset(pushDx, pushDy),
              child: Opacity(
                opacity: triggerOpacity,
                child: IgnorePointer(
                  ignoring: isMenuBlocking,
                  child: widget.triggerBuilder != null
                      ? widget.triggerBuilder!(context, _toggleMenu)
                      : GestureDetector(
                          onTap: _toggleMenu,
                          child: widget.trigger,
                        ),
                ),
              ),
            ),

            // Overlay portal for morphing animation
            // The overlay contents fade out during the handoff so the real button shows instead
            OverlayPortal(
              controller: _overlayController,
              overlayChildBuilder: _buildMorphingOverlay,
            ),
          ],
        );
      },
    );
  }

  void _toggleMenu() {
    if (_overlayController.isShowing && _morphController.value > 0.1) {
      _closeMenu();
    } else {
      _openMenu();
    }
  }

  /// Nudges the OPEN menu by [offset] (screen px) on top of its captured trigger
  /// position, so an external owner can track a moving anchor live. A no-op
  /// delta is skipped to avoid needless rebuilds. Has no visible effect while
  /// closed; the next [_openMenu] resets it to zero.
  void setFollowOffset(Offset offset) {
    if (_followOffset == offset) return;
    setState(() => _followOffset = offset);
  }

  void _openMenu() {
    // Capture geometry and screen position for morphing
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      // Safety: Cannot open menu if render box is not ready
      return;
    }

    _triggerSize = renderBox.size;
    _triggerBorderRadius = _triggerSize!.height / 2;
    _triggerGlobalPosition =
        renderBox.localToGlobal(Offset.zero); // store for overlay
    // A fresh open must never inherit a previous open's live anchor nudge.
    _followOffset = Offset.zero;
    final position = _triggerGlobalPosition;
    final mediaQuery = MediaQuery.maybeOf(context);
    final screenWidth = mediaQuery?.size.width ?? double.infinity;
    final screenHeight = mediaQuery?.size.height ?? double.infinity;

    // Calculate menu height for vertical boundary check
    final menuHeight = _calculateMenuHeight();

    // 1. Determine base alignment (Auto vs Manual)
    if (widget.menuAlignment == null ||
        widget.menuAlignment == GlassMenuAlignment.none) {
      // Horizontal alignment: left vs right half
      final isRightHalf = screenWidth.isFinite && position.dx > screenWidth / 2;

      // Vertical alignment: check if menu would overflow bottom
      final spaceBelow = screenHeight.isFinite
          ? screenHeight - (position.dy + _triggerSize!.height)
          : double.infinity;
      final spaceAbove = screenHeight.isFinite ? position.dy : double.infinity;

      // Prefer downward opening unless insufficient space
      final shouldFlipVertical =
          spaceBelow < menuHeight && spaceAbove > menuHeight;

      if (shouldFlipVertical) {
        _morphAlignment =
            isRightHalf ? Alignment.bottomRight : Alignment.bottomLeft;
      } else {
        _morphAlignment = isRightHalf ? Alignment.topRight : Alignment.topLeft;
      }
    } else {
      // MANUAL: Use the provided alignment directly.
      // Note: autoAdjustToScreen clamping will still compensate for overflow.
      _morphAlignment =
          _getAlignment(widget.menuAlignment!) ?? Alignment.center;
    }

    // 2. Clamping: calculate offsets to keep menu within screen bounds
    double hOffset = 0.0;
    double vOffset = 0.0;

    if (widget.autoAdjustToScreen) {
      final flutterView = View.of(context);
      final mqPadding = EdgeInsets.fromViewPadding(
          flutterView.padding, flutterView.devicePixelRatio);

      final double safeTop = widget.menuPadding.top + mqPadding.top;
      final double safeBottom = widget.menuPadding.bottom + mqPadding.bottom;
      final double safeLeft = widget.menuPadding.left + mqPadding.left;
      final double safeRight = widget.menuPadding.right + mqPadding.right;

      // Calculate global menu position
      final double targetX =
          position.dx + (1 + _morphAlignment.x) * _triggerSize!.width / 2;
      final double targetY =
          position.dy + (1 + _morphAlignment.y) * _triggerSize!.height / 2;
      final double menuLeft =
          targetX - (1 + _morphAlignment.x) * widget.menuWidth / 2;
      final double menuTop = targetY - (1 + _morphAlignment.y) * menuHeight / 2;

      // Horizontal adjustment
      if (menuLeft < safeLeft) {
        hOffset = safeLeft - menuLeft;
      } else if (screenWidth.isFinite &&
          menuLeft + widget.menuWidth > screenWidth - safeRight) {
        hOffset = (screenWidth - safeRight) - (menuLeft + widget.menuWidth);
      }

      // Vertical adjustment
      if (menuTop < safeTop) {
        vOffset = safeTop - menuTop;
      } else if (screenHeight.isFinite &&
          menuTop + menuHeight > screenHeight - safeBottom) {
        vOffset = (screenHeight - safeBottom) - (menuTop + menuHeight);
      }
    }

    setState(() {
      _horizontalOffset = hOffset;
      _verticalOffset = vOffset;
    });

    _overlayController.show();
    // GlassMorphController.open() uses 0.0 velocity — spring starts from rest
    // for a clean, smooth teardrop expansion with no artificial kick.
    _morphController.open();
  }

  void _closeMenu() {
    setState(() {
      _hoveredIndex = null;
      _isDragging = false;
    });
    // GlassMorphController.close() injects the -2.5 velocity hint internally,
    // maximising the rubber-band bounce amplitude at close.
    _morphController.close();
    widget.onClose?.call();
  }

  Widget _buildMorphingOverlay(BuildContext context) {
    if (_triggerSize == null) return const SizedBox.shrink();

    // Raw value can legitimately exceed [0, 1]: the underdamped spring
    // overshoots on close (goes negative) to create the J-curve bounce.
    final rawValue = _morphController.value;
    final clampedValue = rawValue.clamp(0.0, 1.0);

    final tw = _triggerSize!.width;
    final th = _triggerSize!.height;
    final menuWidth = widget.menuWidth.toDouble();
    final menuHeight = _calculateMenuHeight();

    // The destination of the menu center relative to the trigger center.
    // By setting dyMag to exactly (menuHeight - th) / 2.0, the final menu
    // will perfectly align its top edge with the trigger's top edge, effectively
    // "covering" the faded out menu button.
    final dxMag = (menuWidth - tw) / 2.0;
    final dyMag = (menuHeight - th) / 2.0;
    final finalDx = -_morphAlignment.x * dxMag;
    final finalDy = -_morphAlignment.y * dyMag;

    // ─── Delegate physics to GlassMorphController ────────────────────────────
    //
    // All J-curve, size, push, anchor-scale, blend, and containerScale math
    // is encapsulated in LiquidMorphPhysics.compute() via the controller.
    final state = _morphController.computeState(
      finalDx: finalDx,
      finalDy: finalDy,
      horizontalOffset: _horizontalOffset,
      verticalOffset: _verticalOffset,
    );

    final targetHeight = widget.menuHeight ?? menuHeight;
    // Under morphFromZero the body lerps from a zero-size point at the trigger
    // center (collapse-to-point) rather than from the trigger's own size; the
    // false path keeps tw/th so the spawn-blob behavior is byte-identical.
    final double sizeStartW = widget.morphFromZero ? 0.0 : tw;
    final double sizeStartH = widget.morphFromZero ? 0.0 : th;
    // Clamp to >= 0: the rubber-band close drives sizeT slightly negative during
    // the undershoot, which lerps the size below zero for a tiny trigger and
    // trips a debug BoxConstraints assert. A size can't be negative; 0 (fully
    // collapsed) is the correct floor and is visually identical to the intended
    // shrink-to-nothing at the close tail. Under morphFromZero the lerp already
    // starts at 0, so this same clamp still floors the close undershoot.
    final currentHeight = lerpDouble(sizeStartH, targetHeight, state.sizeT)!
        .clamp(0.0, double.infinity);
    final currentWidth = lerpDouble(sizeStartW, widget.menuWidth, state.sizeT)!
        .clamp(0.0, double.infinity);

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

    final maxRadius = math.min(currentWidth, currentHeight) / 2.0;
    final double radiusT =
        Curves.easeInExpo.transform(state.sizeT.clamp(0.0, 1.0));
    final currentRadius =
        lerpDouble(maxRadius, widget.menuBorderRadius, radiusT)!;

    final blobBLeft = _triggerGlobalPosition.dx +
        _followOffset.dx +
        tw / 2.0 +
        state.currentDx -
        currentWidth / 2.0 +
        (_horizontalOffset * clampedValue);

    final blobBTop = _triggerGlobalPosition.dy +
        _followOffset.dy +
        th / 2.0 +
        state.currentDy -
        currentHeight / 2.0 +
        (_verticalOffset * clampedValue);

    return Stack(
      children: [
        // Invisible full-screen tap-to-close barrier
        if (clampedValue > 0.3 && widget.showDismissBarrier)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
              child: Container(color: Colors.black.withValues(alpha: 0.0)),
            ),
          ),

        // ── Two-Blob Metaball Morphing ───────────────────────────────────────
        //
        // We use LiquidGlassLayer at the root to create the transparent blend group.
        // Inside it, we use two CompositedTransformFollowers, BOTH anchored to the
        // trigger's center. This avoids manual coordinate math and prevents pixel drift.
        Positioned.fill(
          child: Opacity(
            opacity:
                (_morphController.isClosing && _morphController.hasHandedOff)
                    ? 0.0
                    : 1.0,
            child: AdaptiveLiquidGlassLayer(
              settings: effectiveSettings,
              quality: effectiveQuality,
              blendAmount: state.blend,
              platformViewBackdrop: widget.platformViewBackdrop,
              child: LiquidGlassBlendGroup(
                blend: state.blend,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // ─── Blob A: Trigger Ghost ───────────────────────────────
                    // Stays perfectly centered on the trigger, BUT absorbs the
                    // closing momentum (pushDx/pushDy) to bounce when slammed.
                    // Shrinks to 0 scale over the first 40% of the animation to
                    // smoothly break the liquid bridge.
                    // Blob A is the spawn blob; under morphFromZero there is no trigger to ghost.
                    if (!widget.morphFromZero)
                      Positioned(
                        left: _triggerGlobalPosition.dx +
                            _followOffset.dx +
                            state.pushDx,
                        top: _triggerGlobalPosition.dy +
                            _followOffset.dy +
                            state.pushDy,
                        child: Transform.scale(
                          scale: state.anchorScale,
                          child: GlassContainer(
                            useOwnLayer: false,
                            settings: effectiveSettings,
                            quality: effectiveQuality,
                            platformViewBackdrop: widget.platformViewBackdrop,
                            width: tw,
                            height: th,
                            shape: LiquidRoundedSuperellipse(
                              borderRadius: _triggerBorderRadius ??
                                  _triggerSize!.shortestSide / 2.0,
                            ),
                          ),
                        ),
                      ),

                    // ── Blob B: Menu Body ───────────────────────────────────
                    // Its center travels diagonally relative to the trigger.
                    // By scaling the x/y offsets with the width/height curves,
                    // its edges stay perfectly pinned while it grows!
                    Positioned(
                      left: blobBLeft,
                      top: blobBTop,
                      child: IgnorePointer(
                        ignoring: clampedValue < 0.8,
                        child: _buildMorphingContainer(
                          state,
                          clampedValue,
                          currentWidth,
                          currentHeight,
                          currentRadius,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _calculateMenuHeight() {
    if (widget.menuHeight != null) {
      return widget.menuHeight!;
    }

    // Account for system text scaling when calculating natural height.
    // Without this, increased text size causes items to render taller than
    // the height budget, triggering unwanted scrolling (GitHub issue).
    final mediaQuery = MediaQuery.maybeOf(context);

    // Sum all menu item heights, scaled by text scaler
    final itemHeights = widget.items.fold<double>(
      0.0,
      (sum, item) => sum + _getScaledItemHeight(item, context),
    );

    // Add vertical padding (12px top + 12px bottom = 24px total)
    // plus vertical gaps between items (2px each)
    final gaps = (widget.items.length - 1) * 2.0;
    final naturalHeight = itemHeights + 24.0 + gaps;

    if (widget.autoAdjustToScreen) {
      if (mediaQuery != null) {
        final flutterView = View.of(context);
        final mqPadding = EdgeInsets.fromViewPadding(
            flutterView.padding, flutterView.devicePixelRatio);

        // Clamp to screen height minus safe areas and a 20px safety buffer
        final maxHeight = mediaQuery.size.height -
            mqPadding.vertical -
            widget.menuPadding.vertical -
            20.0;
        return math.min(naturalHeight, math.max(0.0, maxHeight));
      }
    }

    return naturalHeight;
  }

  Widget _buildMorphingContainer(LiquidMorphState state, double clampedValue,
      double currentWidth, double currentHeight, double currentRadius) {
    // Sub-pixel blob registers no blend-group shape: skip it so the premium
    // Impeller geometry never rasterizes a 0-area matte (Invalid image dimensions).
    // The 1.0 logical-px floor is provably safe at every devicePixelRatio: a
    // logical size in [0.5, 1.0) can still snap to a 0-area matte at dpr=1.0
    // (matteBounds = (bounds * dpr).snapToPixels(1); ceil() == 0), which would
    // reach the unclamped toImageSync in the geometry raster. Below 1.0 px is
    // invisible on any display, so flooring here costs nothing visually.
    if (currentWidth < 1.0 || currentHeight < 1.0) {
      return const SizedBox.shrink();
    }

    // Inherit quality from parent layer if not explicitly set
    final effectiveQuality = GlassThemeHelpers.resolveQuality(
      context,
      widgetQuality: widget.quality,
    );

    // ─── True Metaball Morphing ──────────────────────────────────────────────
    //
    // By using the pure spring value for both width and height, the menu container
    // expands uniformly while moving diagonally. This is the SECRET to the native
    // iOS liquid teardrop. The metaball shader naturally creates the bulbous bottom
    // and the pinched neck connecting back to the trigger.
    //
    // No more faking the shape with tall, thin rectangles! Let the shader do the work.

    // Build the shape
    final teardropShape = LiquidRoundedSuperellipse(
      borderRadius: currentRadius,
    );

    // containerScale is pre-computed by LiquidMorphPhysics inside GlassMorphController.
    final containerScale = state.containerScale;

    // ─── Item Stagger ─────────────────────────────────────────────────────────
    // Pre-compute per-item stagger offsets (used in _buildMorphingContainer
    // via the items list length).  Each item is offset by 20ms relative to
    // the previous one so they cascade in smoothly from top-to-bottom.

    // Inherit settings from context (like GlassCard/GlassContainer)
    // If user provides custom settings, use those. Otherwise, check for inherited
    // settings from parent layer. If none, use subtle overlay defaults.
    // This matches the pattern used by all other glass widgets.
    final inheritedSettings = InheritedLiquidGlass.of(context);
    final effectiveSettings = widget.settings ??
        inheritedSettings ??
        const LiquidGlassSettings(
          blur: 10,
          thickness: 10,
          glassColor: Color.fromRGBO(255, 255, 255, 0.12),
          lightAngle: GlassDefaults.lightAngle, // Apple iOS 26 standard
          lightIntensity: 0.7,
          ambientStrength: 0.4,
          saturation: 1.2,
          refractiveIndex: 0.7, // Thin rim - iOS 26 delicate aesthetic
          chromaticAberration: 0.0,
        );

    final glassContent = LiquidStretch(
      stretch: widget.stretch,
      interactionScale: widget.interactionScale,
      resistance: widget.stretchResistance,
      axis: widget.stretchAxis,
      suppressInteractionOnChildren: false,
      anchorStretch: false, // Menus use jelly-follow, not anchored
      // Constrain stretch to 'Down' and 'Away from screen edge' by default,
      // but allow explicit user overrides.
      allowPositiveX: widget.allowPositiveX ?? (_morphAlignment.x < 0),
      allowNegativeX: widget.allowNegativeX ?? (_morphAlignment.x > 0),
      allowPositiveY: widget.allowPositiveY ?? (_morphAlignment.y < 0),
      allowNegativeY: widget.allowNegativeY ?? (_morphAlignment.y > 0),
      child: GlassContainer(
        useOwnLayer: false, // blends with the trigger ghost
        settings: effectiveSettings,
        quality: effectiveQuality,
        platformViewBackdrop: widget.platformViewBackdrop,
        allowElevation:
            false, // Menu is overlay - don't darken when outside parent
        width: currentWidth,
        height: currentHeight, // Constrained during morph, natural when open
        shape: teardropShape,
        clipBehavior:
            Clip.antiAlias, // Clip items at the edges for edge-to-edge feel
        glowIntensity: widget.glowIntensity,
        child: Builder(builder: (context) {
          final isDark = GlassTheme.brightnessOf(context) == Brightness.dark;
          return GlassGlow(
            enabled: widget.enableInteractionGlow,
            glowOnTapOnly: widget.glowOnTapOnly,
            glowColor: widget.glowColor ??
                (isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.10)),
            glowRadius: widget.glowRadius,
            glowBlurRadius: 40,
            clipper: ShapeBorderClipper(
              shape: teardropShape,
            ),
            child: Transform.scale(
              scale: containerScale,
              alignment: Alignment.center,
              child: Stack(
                alignment: _morphAlignment, // Align internal stack content
                clipBehavior:
                    Clip.none, // Prevent double-clip artifacts during stretch
                children: [
                  // Menu content scales up with the container morph — items
                  // enter the tree at 30% and scale from 0.5× to 1.0×.
                  if (clampedValue > 0.3)
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Sliding selection pill (background)
                        ValueListenableBuilder<int?>(
                          valueListenable: _hoveredIndexNotifier,
                          builder: (context, hoveredIndex, _) {
                            if (hoveredIndex == null) {
                              return const SizedBox.shrink();
                            }
                            return AnimatedPositioned(
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOutCubic,
                              left: 12,
                              right: 12,
                              top: _getItemOffset(hoveredIndex, context) -
                                  (_scrollController.hasClients
                                      ? _scrollController.offset
                                      : 0.0),
                              height: _getScaledItemHeight(
                                  widget.items[hoveredIndex], context),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: widget.selectionColor,
                                  borderRadius: BorderRadius.circular(
                                      widget.itemBorderRadius),
                                  border: Border.all(
                                    color: GlassTheme.brightnessOf(context) ==
                                            Brightness.dark
                                        ? const Color(0x0DFFFFFF)
                                        : const Color(0x0D000000),
                                    width: 0.5,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        Listener(
                          onPointerDown: (event) {
                            _isDragging = true;
                            _isDraggingNotifier.value = true;
                            _hasStretched = false;
                            _initialLocalPosition = event.localPosition;
                            _initialScrollOffset = _scrollController.hasClients
                                ? _scrollController.offset
                                : 0.0;
                            _updateHoveredIndex(event.localPosition);
                          },
                          onPointerMove: (event) {
                            if (_isDragging) {
                              _updateHoveredIndex(event.localPosition);
                            }
                          },
                          onPointerUp: (event) {
                            if (_isDragging) {
                              final currentOffset = _scrollController.hasClients
                                  ? _scrollController.offset
                                  : 0.0;
                              final scrollDisplacement =
                                  (currentOffset - _initialScrollOffset).abs();
                              final dragDisplacement =
                                  (event.localPosition - _initialLocalPosition)
                                      .distance;

                              // Slide-to-select tap logic (only for non-scrollable menus)
                              if (scrollDisplacement < 10 &&
                                  dragDisplacement < 10 &&
                                  !_isScrollable) {
                                final indexToTap = _hoveredIndex ??
                                    _calculateIndexFromPosition(
                                        event.localPosition, context);
                                if (indexToTap != null) {
                                  final item = widget.items[indexToTap];
                                  if (item is GlassMenuItem && item.enabled) {
                                    item.onTap();
                                    _closeMenu();
                                  }
                                }
                              }
                              _isDragging = false;
                              _isDraggingNotifier.value = false;
                              _hoveredIndex = null;
                              _hoveredIndexNotifier.value = null;
                              _hasStretched = false;
                            }
                          },
                          onPointerCancel: (_) {
                            _isDragging = false;
                            _isDraggingNotifier.value = false;
                            _hoveredIndex = null;
                            _hoveredIndexNotifier.value = null;
                          },
                          child: SizedBox(
                            width: currentWidth,
                            height: widget.menuHeight, // Apply fixed height
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                physics: _isScrollable
                                    ? const ClampingScrollPhysics() // iOS-style
                                    : const NeverScrollableScrollPhysics(),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 12), // Top padding
                                    ..._buildWrappedItems()
                                        .asMap()
                                        .entries
                                        .expand((entry) {
                                      final itemOpacity =
                                          ((clampedValue - 0.3) / 0.4)
                                              .clamp(0.0, 1.0);
                                      final itemScale = lerpDouble(
                                        0.5,
                                        1.0,
                                        Curves.easeOut.transform(
                                          ((clampedValue - 0.3) / 0.7)
                                              .clamp(0.0, 1.0),
                                        ),
                                      )!;
                                      return [
                                        Opacity(
                                          opacity: itemOpacity,
                                          child: Transform.scale(
                                            scale: itemScale,
                                            child: entry.value,
                                          ),
                                        ),
                                        if (entry.key < widget.items.length - 1)
                                          const SizedBox(height: 2),
                                      ];
                                    }),
                                    const SizedBox(
                                        height: 12), // Bottom padding
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ), // outer Stack
            ), // Transform.scale
          ); // GlassGlow
        }), // Builder
      ), // GlassContainer
    ); // LiquidStretch (glassContent)

    // The blob is always fully opaque — shape morph is the only animation.
    return glassContent;
  }

  List<Widget> _buildWrappedItems() {
    return _cachedWrappedItems ??= widget.items.asMap().entries.map((entry) {
      final item = entry.value;

      if (item is GlassMenuItem) {
        return _SelectionItemWrapper(
          index: entry.key,
          hoverNotifier: _hoveredIndexNotifier,
          dragNotifier: _isDraggingNotifier,
          builder: (context, isSelected, isPressed) {
            return GlassMenuItem(
              key: item.key ?? ValueKey(item.title),
              title: item.title,
              subtitle: item.subtitle,
              icon: item.icon,
              isDestructive: item.isDestructive,
              enabled: item.enabled,
              trailing: item.trailing,
              height: item.height,
              titleStyle: item.titleStyle,
              subtitleStyle: item.subtitleStyle,
              iconColor: item.iconColor,
              iconSize: item.iconSize,
              maxLines: item.maxLines,
              isSelected: isSelected,
              isPressed: isPressed,
              onTap: () {
                // For scrollable menus, we delegate taps to the native GestureDetector
                // so it can properly participate in the gesture arena with the ScrollView.
                if (_isScrollable && item.enabled) {
                  item.onTap();
                  _closeMenu();
                }
              },
            );
          },
        );
      }
      return item;
    }).toList();
  }

  bool get _isScrollable {
    final visibleHeight = _calculateMenuHeight();
    final itemHeights = widget.items.fold<double>(
      0.0,
      (sum, item) => sum + _getScaledItemHeight(item, context),
    );
    final gaps = (widget.items.length - 1) * 2.0;
    final naturalHeight = itemHeights + 24.0 + gaps;
    return widget.menuHeight != null || visibleHeight < naturalHeight - 1.0;
  }

  /// Accounts for system text scaling.
  ///
  /// When the user increases the system text size, GlassMenuItem renders
  /// with scaled text inside a ConstrainedBox (minHeight). The text content
  /// may push the actual height beyond the nominal [GlassMenuItem.height].
  /// This method estimates the rendered height to prevent the menu from
  /// becoming scrollable when it shouldn't be.
  double _getScaledItemHeight(Widget item, BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    final textScaler = mediaQuery?.textScaler ?? TextScaler.noScaling;

    if (item is GlassMenuItem) {
      // The item has 8px vertical padding top + bottom = 16px fixed chrome.
      // The remaining space is text content that scales with system text size.
      const fixedPadding = 16.0;
      final baseFontSize = item.titleStyle?.fontSize ?? 17.0;
      final scaledFontSize = textScaler.scale(baseFontSize);
      final lineHeight = scaledFontSize * 1.2; // Approximate line height
      final textHeight = lineHeight * item.maxLines;

      // Subtitle adds another scaled line
      double subtitleHeight = 0;
      if (item.subtitle != null) {
        final subFontSize = item.subtitleStyle?.fontSize ?? 13.0;
        subtitleHeight = textScaler.scale(subFontSize) * 1.2;
      }

      final contentHeight = textHeight + subtitleHeight + fixedPadding;
      // Use the larger of nominal height or scaled content height
      return math.max(item.height, contentHeight);
    }
    // Dividers and labels don't contain user-facing scaled text
    if (item is GlassMenuDivider) return item.height;
    if (item is GlassMenuLabel) return item.height;
    return 44.0;
  }

  double _getItemOffset(int index, BuildContext context) {
    double offset = 12.0; // Top padding
    for (int i = 0; i < index; i++) {
      offset += _getScaledItemHeight(widget.items[i], context) +
          2.0; // height + 2px gap
    }
    return offset;
  }

  int? _calculateIndexFromPosition(Offset localPosition, BuildContext context) {
    final visibleHeight = _calculateMenuHeight();
    final x = localPosition.dx;
    final dy = localPosition.dy;
    final y =
        dy + (_scrollController.hasClients ? _scrollController.offset : 0.0);

    final isWithinActiveZone = x > -20 &&
        x < widget.menuWidth + 20 &&
        dy > -20 &&
        dy < visibleHeight + 20;

    if (!isWithinActiveZone) return null;

    double currentOffset = 12.0;
    for (int i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      final itemHeight = _getScaledItemHeight(item, context);

      if (y >= currentOffset && y <= currentOffset + itemHeight) {
        if (item is GlassMenuItem && item.enabled) {
          return i;
        }
        break;
      }
      currentOffset += itemHeight + 2.0; // height + 2px gap
    }
    return null;
  }

  void _updateHoveredIndex(Offset localPosition) {
    // Detect if we've moved into "stretch territory" (outside visible menu bounds)
    // We use the visible container height if fixed, otherwise the natural height.
    final visibleHeight = _calculateMenuHeight();
    final x = localPosition.dx;
    final dy = localPosition.dy;

    // We add a 100px buffer to allow for intense liquid stretching without accidental closure.
    // We also allow cancelling the stretch if the user moves their finger back.
    final outsideBounds = dy < -100 ||
        dy > visibleHeight + 100 ||
        x < -100 ||
        x > widget.menuWidth + 100;

    if (_hasStretched != outsideBounds) {
      setState(() => _hasStretched = outsideBounds);
    }

    int? detectedIndex;

    // Only calculate hover selection for non-scrollable menus (slide-to-select).
    if (!_isScrollable) {
      detectedIndex = _calculateIndexFromPosition(localPosition, context);
    }

    _hoveredIndex = detectedIndex;
    _hoveredIndexNotifier.value = detectedIndex;
  }
}

/// Internal helper to update selection state for cached items.
class _SelectionItemWrapper extends StatelessWidget {
  final int index;
  final ValueNotifier<int?> hoverNotifier;
  final ValueNotifier<bool> dragNotifier;
  final Widget Function(BuildContext context, bool isSelected, bool isPressed)
      builder;

  const _SelectionItemWrapper({
    required this.index,
    required this.hoverNotifier,
    required this.dragNotifier,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: hoverNotifier,
      builder: (context, hoveredIndex, _) {
        final isSelected = hoveredIndex == index;
        return ValueListenableBuilder<bool>(
          valueListenable: dragNotifier,
          builder: (context, isDragging, _) {
            return builder(context, isSelected, isDragging && isSelected);
          },
        );
      },
    );
  }
}
