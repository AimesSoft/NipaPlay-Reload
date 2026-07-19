part of '../glass_modal_sheet.dart';

class _GlassModalSheetState extends State<GlassModalSheet>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Animation Controllers ─────────────────────────────────────────────────
  late AnimationController _animationController;
  late AnimationController _saturationController;
  late Animation<double> _saturationAnimation;
  final _progressNotifier = _ProgressNotifier();

  // ── State ─────────────────────────────────────────────────────────────────
  late final ValueNotifier<GlassSheetState> _currentStateNotifier;
  GlassSheetState get _currentState => _currentStateNotifier.value;
  set _currentState(GlassSheetState v) => _currentStateNotifier.value = v;

  /// The state most recently published to consumers via
  /// [GlassModalSheet.onStateChanged] (and from which haptics and
  /// scroll-to-top side effects fired).
  ///
  /// Distinct from [_currentState]: that value is mutated mid-gesture
  /// by [_applyDrag] and [_jumpTo] to drive in-flight visual
  /// interpolation (radii, expand-progress, glass settings) toward the
  /// resolved snap target. Comparing the snap target against
  /// [_currentState] in [_snapToState] therefore silently skips the
  /// side-effects branch whenever the drag itself had already crossed
  /// a snap threshold — by the time the user releases, [_currentState]
  /// already equals the target.
  ///
  /// [_settledState] is updated only inside the side-effects branch,
  /// so the equality check correctly answers "did the state change
  /// since the last time we told consumers about it".
  late GlassSheetState _settledState;

  double _currentPosition = 0.0;
  double _currentEffectiveHeight = 0.0;

  FrozenState? _frozenState;
  Size _lastPhysicalSize = Size.zero;

  bool _isInteractingWithChild = false;
  bool _suppressScalingForSession = false;

  // ── Unified Gesture & Scroll ──────────────────────────────────────────────
  final GestureArena _gestureArena = GestureArena();
  final ScrollController _scrollController = ScrollController();

  // ── Geometry & Metrics ────────────────────────────────────────────────────
  late SheetGeometry _geometry;
  Size _screenSize = Size.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _currentStateNotifier = ValueNotifier(widget.initialState);
    _settledState = widget.initialState;
    _geometry = _buildGeometry();

    _animationController = AnimationController.unbounded(vsync: this);
    _animationController.addListener(_progressNotifier.notify);
    _saturationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _saturationAnimation =
        CurvedAnimation(parent: _saturationController, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateScreenSize();
        _lastPhysicalSize = View.of(context).physicalSize;
        _snapToState(_currentState, animate: false);
      }
    });

    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(GlassModalSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?._detach();
      widget.controller?._attach(this);
    }

    final oldGeometry = _geometry;
    _geometry = _buildGeometry();

    // Hot Reload reaction: if dimensions changed, force position recalculation
    if (oldGeometry.halfSize != _geometry.halfSize ||
        oldGeometry.fullSize != _geometry.fullSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _gestureArena.phase == GesturePhase.idle) {
          _snapToState(_currentState, animate: true);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller?._detach();
    _animationController.removeListener(_progressNotifier.notify);
    _animationController.dispose();
    _progressNotifier.dispose();
    _saturationController.dispose();
    _scrollController.dispose();
    _currentStateNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;

    final view = View.of(context);
    // Filter system call spam: the spring only jitters if the window size actually changes
    if (_lastPhysicalSize != view.physicalSize) {
      if (_lastPhysicalSize != Size.zero) {
        _updateScreenSize();
        _snapToState(_currentState, animate: true);
      }
      _lastPhysicalSize = view.physicalSize;
    }
  }

  SheetGeometry _buildGeometry() => SheetGeometry(
        mode: widget.mode,
        halfSize: widget.halfSize,
        fullSize: widget.fullSize,
        peekSize: widget.peekSize,
        enablePeek:
            widget.enablePeek ?? (widget.mode == GlassSheetMode.persistent),
      );

  void _updateScreenSize() {
    final view = View.of(context);
    _screenSize = view.physicalSize / view.devicePixelRatio;
  }

  // ════════════════════════════════════════════════════════════════════════
  // Snap & State Management
  // ════════════════════════════════════════════════════════════════════════

  void _snapToState(GlassSheetState state,
      {bool animate = true, double velocity = 0}) {
    if (!mounted) return;

    if (widget.mode == GlassSheetMode.persistent &&
        state == GlassSheetState.hidden) {
      state = GlassSheetState.peek;
    }

    final screenHeight = MediaQuery.sizeOf(context).height;
    final targetPosition = _geometry.positionForState(state, screenHeight);

    if (animate) {
      final simulation = SpringSimulation(
        const SpringDescription(mass: 1.0, stiffness: 220.0, damping: 30.0),
        _currentPosition,
        targetPosition,
        velocity / screenHeight,
      );
      _animationController.animateWith(simulation);
    } else {
      _animationController.value = targetPosition;
    }

    // Compare against `_settledState`, not `_currentState` — see the
    // doc comment on `_settledState` for why. Briefly: `_currentState`
    // tracks the in-flight snap target during drag (mutated silently
    // by `_applyDrag` and `_jumpTo`), so checking it here would skip
    // side effects whenever the drag itself had already updated the
    // target mid-gesture. `_settledState` only updates inside this
    // branch, ensuring side effects fire on every consumer-visible
    // state transition.
    if (state != _settledState) {
      if (state == GlassSheetState.peek || state == GlassSheetState.hidden) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.mediumImpact();
      }

      _currentState = state;
      _settledState = state;
      widget.onStateChanged?.call(state);

      if (state != GlassSheetState.full && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  void _jumpTo(double value) {
    if (!mounted) return;
    _animationController.value = value;
    _currentPosition = value;

    // Update current state based on position if needed
    final snapshot = SheetSnapshot(
      state: _currentState,
      position: value,
      screenSize: _screenSize,
    );
    final target = _geometry.resolveTarget(
      snapshot,
      snapThreshold: widget.snapThreshold,
      velocityThreshold: widget.velocityThreshold,
    );
    if (target != _currentState) {
      _currentState = target;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // Gesture Handlers — Handle Drag & Scroll Notification
  // ════════════════════════════════════════════════════════════════════════

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is OverscrollNotification && notification.overscroll < 0) {
      if (_gestureArena.phase == GesturePhase.scrolling ||
          _gestureArena.phase == GesturePhase.idle) {
        _gestureArena.phase = GesturePhase.contentDrag;
        if (notification.dragDetails != null) {
          _gestureArena.dragStartY =
              notification.dragDetails!.globalPosition.dy;
        }
        _gestureArena.dragStartSheetPosition = _currentPosition;

        if (_animationController.isAnimating) {
          _animationController.stop();
        }
      }
    }
    return false;
  }

  // ════════════════════════════════════════════════════════════════════════
  // Gesture Handlers — Pointer Events (Content Zone)
  // ════════════════════════════════════════════════════════════════════════

  void _onPointerDown(PointerDownEvent event) {
    // ALWAYS initialize the gesture arena so swipes can start from anywhere,
    // even from buttons or interactive children.
    _gestureArena.beginPointer(
        event.position.dy, event.position.dx, _currentPosition, event.kind);

    // If the touch is in the handle zone (top 44 pixels), immediately set phase.
    if (event.localPosition.dy <= 44.0) {
      _gestureArena.phase = GesturePhase.handleDrag;
    }

    // Now, if we are interacting with a child (e.g. a button), we SUPPRESS
    // the visual feedback (scaling/glow) for the duration of this gesture,
    // BUT ONLY if the feature is enabled via suppressInteractionOnChildren.
    if (widget.suppressInteractionOnChildren && _isInteractingWithChild) {
      _suppressScalingForSession = true;
      _isInteractingWithChild = false;
      // Do NOT fire haptic or saturation — this touch is silenced.
      return;
    }

    // Always reset suppression state if we didn't return above
    _isInteractingWithChild = false;
    _suppressScalingForSession = false;

    // Haptic and saturation only fire for genuine sheet-level touches
    // (not for touches on child buttons that were suppressed above).
    final isFull = _currentState == GlassSheetState.full;

    if (widget.enableInteractionGlow && !isFull) {
      HapticFeedback.selectionClick();
    }

    if (widget.enableSaturationGlow && !isFull) {
      _saturationController.forward();
    }

    _frozenState = null;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_isInteractingWithChild) {
      return;
    }

    _gestureArena.velocityTracker.addPosition(event.timeStamp, event.position);

    // If we're already dragging the handle, just apply the drag
    if (_gestureArena.phase == GesturePhase.handleDrag) {
      _applyDrag(event.position.dy);
      return;
    }

    final shouldClaim = _gestureArena.evaluateMove(
      event.position.dy,
      event.position.dx,
      _currentState,
      10.0,
      hasScrollClients: _scrollController.hasClients,
      canScrollListUp:
          _scrollController.hasClients && _scrollController.offset > 0,
    );

    if (shouldClaim) {
      if (_animationController.isAnimating) {
        _animationController.stop();
        _gestureArena.dragStartY = event.position.dy;
        _gestureArena.dragStartSheetPosition = _currentPosition;
      }

      final dy = event.position.dy - _gestureArena.dragStartY;
      if ((_currentState == GlassSheetState.half ||
              _currentState == GlassSheetState.peek) &&
          dy < 0) {
        _frozenState = FrozenState(
          bottomScale: widget.interactionScale,
          heightAtFreeze: _currentEffectiveHeight,
        );
      }

      _applyDrag(event.position.dy);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _isInteractingWithChild = false;
    _suppressScalingForSession = false;
    _saturationController.reverse();

    final wasDragging = _gestureArena.phase == GesturePhase.contentDrag ||
        _gestureArena.phase == GesturePhase.handleDrag;
    _gestureArena.reset();
    _frozenState = null;

    if (!wasDragging) return;

    final estimate = _gestureArena.velocityTracker.getVelocityEstimate();
    final velocity = -(estimate?.pixelsPerSecond.dy ?? 0.0);

    final snapshot = SheetSnapshot(
      state: _currentState,
      position: _currentPosition,
      velocity: velocity,
      screenSize: _screenSize,
    );
    final target = _geometry.resolveTarget(
      snapshot,
      snapThreshold: widget.snapThreshold,
      velocityThreshold: widget.velocityThreshold,
    );

    _snapToState(target, velocity: velocity);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _isInteractingWithChild = false;
    _suppressScalingForSession = false;
    _saturationController.reverse();
    _gestureArena.reset();
    _frozenState = null;
  }

  // ════════════════════════════════════════════════════════════════════════
  // Drag Application
  // ════════════════════════════════════════════════════════════════════════

  void _applyDrag(double currentY) {
    final delta = currentY - _gestureArena.dragStartY;
    double newPosition =
        _gestureArena.dragStartSheetPosition - delta / _screenSize.height;

    newPosition = _geometry.applyResistance(newPosition, _screenSize.height,
        resistance: widget.resistance);
    _animationController.value = newPosition;

    final snapshot = SheetSnapshot(
      state: _currentState,
      position: newPosition,
      velocity: 0,
      screenSize: _screenSize,
    );
    final target = _geometry.resolveTarget(
      snapshot,
      snapThreshold: widget.snapThreshold,
      velocityThreshold: widget.velocityThreshold,
    );

    if (target != _currentState &&
        (widget.mode != GlassSheetMode.dismissible ||
            target != GlassSheetState.hidden)) {
      _currentState = target;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // Metrics Calculation Helpers
  // ════════════════════════════════════════════════════════════════════════

  double get _expandProgress {
    final halfPos =
        _geometry.positionForState(GlassSheetState.half, _screenSize.height);
    final fullPos =
        _geometry.positionForState(GlassSheetState.full, _screenSize.height);
    if (fullPos <= halfPos) return 0.0;
    return ((_currentPosition - halfPos) / (fullPos - halfPos)).clamp(0.0, 1.0);
  }

  _RenderMetrics _calculateMetrics({
    required double pos,
    required double t,
    required double halfPos,
    required double minPos,
    required double extraHeight,
    required double mqHeight,
    required LiquidGlassSettings baseSettings,
    required Color effectiveExpandedColor,
    required double topRadiusBase,
    required double bottomRadiusBase,
    required double topRadiusFull,
    required double bottomRadiusFull,
    required double fullPos,
  }) {
    late LiquidGlassSettings effectiveSettings;
    // Disable scaling in full state by lerping effective interactionScale to 1.0
    // Also disable scaling if we are interacting with a child (Smart Silence)
    final baseInteractionScale =
        _suppressScalingForSession ? 1.0 : widget.interactionScale;

    final effectiveInteractionScale = lerpDouble(baseInteractionScale, 1.0, t)!;
    final effectiveInteractionStretch =
        lerpDouble(_suppressScalingForSession ? 0.0 : widget.stretch, 0.0, t)!;

    double stretchT = 1.0;
    // Protection against division by zero if halfPos == minPos
    final range = halfPos - minPos;
    if (pos < halfPos && range > 0.0001) {
      stretchT = ((pos - minPos) / range).clamp(0.0, 1.0);
    }

    late double effectiveHeight;
    late double effectiveBottom;
    late double topRadius;
    late double bottomRadius;
    late double hPad;
    late double colorOpacity;
    late double glassOpacity;

    // Ideal target visual height of the window
    final targetVisualHeight = pos * mqHeight;

    // baseSettings is now passed from outside to avoid theme lookups every frame.

    // Calculate state-specific settings interpolation
    final peekPos = _geometry.positionForState(GlassSheetState.peek, mqHeight);

    final sPeek = widget.peekSettings ?? baseSettings;
    final sHalf = widget.halfSettings ?? baseSettings;
    final sFull = widget.fullSettings ?? baseSettings;

    // Determine target expanded colors for each state
    // If blur is 0, the state itself provides the solid color
    final cPeek = sPeek.blur == 0 ? sPeek.glassColor : effectiveExpandedColor;
    final cHalf = sHalf.blur == 0 ? sHalf.glassColor : effectiveExpandedColor;
    final cFull = sFull.blur == 0 ? sFull.glassColor : effectiveExpandedColor;

    Color currentExpandedColor;

    if (pos < halfPos) {
      final range = halfPos - peekPos;
      final tProgress =
          range > 0.0001 ? ((pos - peekPos) / range).clamp(0.0, 1.0) : 1.0;

      effectiveSettings = LiquidGlassSettings.lerp(sPeek, sHalf, tProgress);
      currentExpandedColor = Color.lerp(cPeek, cHalf, tProgress)!;

      if (sPeek.blur > 0 && sHalf.blur == 0) {
        colorOpacity = tProgress;
      } else if (sPeek.blur == 0 && sHalf.blur > 0) {
        colorOpacity = 1.0 - tProgress;
      } else if (sPeek.blur == 0 && sHalf.blur == 0) {
        colorOpacity = 1.0;
      } else {
        colorOpacity = 0.0;
      }
      glassOpacity = 1.0 - colorOpacity;
    } else {
      final range = fullPos - halfPos;
      final tProgress =
          range > 0.0001 ? ((pos - halfPos) / range).clamp(0.0, 1.0) : 1.0;

      effectiveSettings = LiquidGlassSettings.lerp(sHalf, sFull, tProgress);
      currentExpandedColor = Color.lerp(cHalf, cFull, tProgress)!;

      if (widget.fullSettings != null) {
        // Use explicit state settings for opacity transition
        if (sHalf.blur > 0 && sFull.blur == 0) {
          colorOpacity = tProgress;
        } else if (sHalf.blur == 0 && sFull.blur > 0) {
          colorOpacity = 1.0 - tProgress;
        } else if (sHalf.blur == 0 && sFull.blur == 0) {
          colorOpacity = 1.0;
        } else {
          colorOpacity = 0.0;
        }
      } else {
        // Fallback to classic threshold logic OR maintain solid if half was solid
        if (sHalf.blur == 0) {
          colorOpacity = 1.0;
        } else if (baseSettings.blur == 0) {
          colorOpacity = 1.0;
        } else {
          final fadeRange = (1.0 - widget.fillThreshold).clamp(0.01, 1.0);
          switch (widget.fillTransition) {
            case GlassFillTransition.gradual:
              const plateau = 0.04;
              final rawT =
                  ((tProgress - widget.fillThreshold) / (fadeRange - plateau))
                      .clamp(0.0, 1.0);
              colorOpacity = Curves.easeInOutCubic.transform(rawT);
              break;
            case GlassFillTransition.instant:
              colorOpacity = tProgress >= widget.fillThreshold ? 1.0 : 0.0;
              break;
          }
        }
      }
      glassOpacity = 1.0 - colorOpacity;
    }

    // Apply saturation glow pulse if enabled
    if (widget.enableSaturationGlow && _saturationAnimation.value > 0) {
      effectiveSettings = effectiveSettings.copyWith(
        saturation: effectiveSettings.saturation *
            (1.0 + _saturationAnimation.value * 0.25),
        lightIntensity: effectiveSettings.lightIntensity *
            (1.0 + _saturationAnimation.value * 0.35),
      );
    }

    // ════════════════════════════════════════════════════════════════════════
    // Peek to Half Morphing
    // ════════════════════════════════════════════════════════════════════════
    if (pos < halfPos) {
      final range = halfPos - peekPos;
      final tProgressRaw =
          range > 0.0001 ? ((pos - peekPos) / range).clamp(0.0, 1.0) : 1.0;

      // Calibrate for Apple Maps behavior:
      // Morphing should be almost instant (complete within first 15% of movement)
      final tMorph = (tProgressRaw / 0.15).clamp(0.0, 1.0);
      final tProgress = Curves.easeOut.transform(tMorph);

      // 1. Resolve Peek-specific geometry
      final peekHMargin =
          widget.peekHorizontalMargin ?? widget.horizontalMargin;
      final peekBMargin = widget.peekBottomMargin ?? widget.bottomMargin;
      final peekTRadius = widget.peekTopBorderRadius ?? topRadiusBase;
      final peekBRadius = widget.peekBottomRadius ?? bottomRadiusBase;

      // 2. Resolve Peek-specific width (hPad)
      double peekHPad = peekHMargin;
      if (widget.peekWidth != null && mqHeight > 0) {
        peekHPad = ((_screenSize.width - widget.peekWidth!) / 2.0)
            .clamp(0.0, _screenSize.width / 2.0);
      }

      if (widget.mode == GlassSheetMode.persistent) {
        // Morph from peek metrics to half metrics
        effectiveBottom =
            lerpDouble(peekBMargin, widget.bottomMargin, tProgress)!;
        hPad = lerpDouble(peekHPad, widget.horizontalMargin, tProgress)!;

        // Morph corner radii
        final targetTRadius =
            lerpDouble(peekTRadius, topRadiusBase, tProgress)!;
        final targetBRadius =
            lerpDouble(peekBRadius, bottomRadiusBase, tProgress)!;

        if (_frozenState != null) {
          final pivotScale = _frozenState!.bottomScale;
          topRadius = lerpDouble(targetTRadius, targetTRadius * pivotScale,
              _saturationAnimation.value)!;
          bottomRadius = lerpDouble(targetBRadius, targetBRadius * pivotScale,
              _saturationAnimation.value)!;
        } else {
          topRadius = lerpDouble(
              targetTRadius,
              targetTRadius * effectiveInteractionScale,
              _saturationAnimation.value)!;
          bottomRadius = lerpDouble(
              targetBRadius,
              targetBRadius * effectiveInteractionScale,
              _saturationAnimation.value)!;
        }

        // Window changes height visually
        effectiveHeight = targetVisualHeight - effectiveBottom;
      } else {
        // Dismissible mode: hiding downwards
        final pivotPos = _geometry.enablePeek
            ? _geometry.positionForState(GlassSheetState.peek, mqHeight)
            : halfPos;

        final pivotVisualHeight = pivotPos * mqHeight;

        if (pos < pivotPos && pivotPos > 0.001) {
          // Sliding from hidden up to pivot
          final slideProgress = (pos / pivotPos).clamp(0.0, 1.0);
          final offscreenBottom = -(pivotVisualHeight + 100.0);
          effectiveBottom =
              lerpDouble(offscreenBottom, peekBMargin, slideProgress)!;
          effectiveHeight = pivotVisualHeight - peekBMargin;
          hPad = peekHPad;
          topRadius = peekTRadius;
          bottomRadius = peekBRadius;
        } else {
          // Morphing between pivot (peek) and half
          effectiveBottom =
              lerpDouble(peekBMargin, widget.bottomMargin, tProgress)!;
          hPad = lerpDouble(peekHPad, widget.horizontalMargin, tProgress)!;
          effectiveHeight = targetVisualHeight - effectiveBottom;
          topRadius = lerpDouble(peekTRadius, topRadiusBase, tProgress)!;
          bottomRadius = lerpDouble(peekBRadius, bottomRadiusBase, tProgress)!;
        }
      }
    } else {
      // From half to full
      final halfVisualHeight = halfPos * mqHeight;
      final frozenScale = _frozenState?.bottomScale ?? 1.0;

      final halfPhysicalHeight = halfVisualHeight - widget.bottomMargin;
      final frozenBottomOffset =
          (_frozenState?.heightAtFreeze ?? halfPhysicalHeight) *
              (frozenScale - 1.0) /
              2.0;
      final frozenBottom = widget.bottomMargin - frozenBottomOffset;

      // Phase 1: Wrap corners (t: 0.0 -> 0.92) - movement is diagonal towards the screen corners.
      // Phase 2: Final sink (t: 0.92 -> 1.0) - the sheet submerges only when it's fully expanded.
      const transitionEnd = 0.92;
      final marginProgress = (t / transitionEnd).clamp(0.0, 1.0);
      final sinkProgress =
          ((t - transitionEnd) / (1.0 - transitionEnd)).clamp(0.0, 1.0);

      if (_frozenState != null) {
        final baseBottom = lerpDouble(frozenBottom, 0.0, marginProgress)!;
        effectiveBottom = lerpDouble(baseBottom, -extraHeight, sinkProgress)!;
      } else {
        final baseBottom =
            lerpDouble(widget.bottomMargin, 0.0, marginProgress)!;
        effectiveBottom = lerpDouble(baseBottom, -extraHeight, sinkProgress)!;
      }

      // Physical height adjusts so the top edge always stays at targetVisualHeight
      effectiveHeight = targetVisualHeight - effectiveBottom;

      hPad =
          lerpDouble(widget.horizontalMargin, 0.0, (t / 0.92).clamp(0.0, 1.0))!;
      // Independent lerp for top and bottom radii
      final baseRadiusTop = lerpDouble(
          topRadiusBase,
          topRadiusBase * effectiveInteractionScale,
          _saturationAnimation.value)!;
      final baseRadiusBottom = lerpDouble(
          bottomRadiusBase,
          bottomRadiusBase * effectiveInteractionScale,
          _saturationAnimation.value)!;

      topRadius = lerpDouble(baseRadiusTop, topRadiusFull, t)!;
      bottomRadius = sinkProgress > 0
          ? lerpDouble(baseRadiusBottom, bottomRadiusFull, sinkProgress)!
          : baseRadiusBottom;
    }

    return _RenderMetrics(
      stretchT: stretchT,
      effectiveHeight: effectiveHeight,
      effectiveBottom: effectiveBottom,
      topRadius: topRadius,
      bottomRadius: bottomRadius,
      hPad: hPad,
      colorOpacity: colorOpacity,
      glassOpacity: glassOpacity,
      effectiveSettings: effectiveSettings,
      interactionScale: effectiveInteractionScale,
      interactionStretch: effectiveInteractionStretch,
      effectiveExpandedColor: currentExpandedColor,
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Build
  // ════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isDark = GlassTheme.brightnessOf(context) == Brightness.dark;
    final effectiveExpandedColor = widget.expandedColor ??
        (isDark ? const Color(0xFF1C1C1E) : Colors.white);
    final effectiveQuality = GlassThemeHelpers.resolveQuality(
      context,
      widgetQuality: widget.quality,
      fallback: GlassQuality.premium,
    );
    final mqSize = MediaQuery.sizeOf(context);
    final mqHeight = mqSize.height;
    final mqPadding = MediaQuery.paddingOf(context);

    final adaptive = GlassThemeHelpers.resolveAdaptiveRadius(context);
    final topRadiusBase = widget.topBorderRadius ?? adaptive;
    final bottomRadiusBase = widget.bottomBorderRadius ?? adaptive;

    // Use explicit full radii if provided, otherwise default to a sensible constant
    // or fallback to the base radii.
    final topRadiusFull = widget.fullTopBorderRadius ?? topRadiusBase;
    final bottomRadiusFull = widget.fullBottomBorderRadius ?? bottomRadiusBase;

    final extraHeight = mqPadding.bottom + bottomRadiusBase;

    final baseSettings = GlassThemeHelpers.resolveSettings(
      context,
      explicit: widget.settings,
      fallback: kDefaultSheetSettings,
    );

    // Focus listener that snaps the sheet to full whenever a focusable
    // descendant gains focus (e.g. tapping a TextField inside the sheet).
    //
    // IMPORTANT: this Focus widget intentionally carries NO key.
    // Any key derived from `widget.child` (e.g. `GlobalObjectKey(widget.child)`)
    // changes every time the parent rebuilds — because the parent passes a
    // fresh `child` widget instance each frame — and Flutter responds to a
    // changed key by tearing down the entire child Element subtree and
    // rebuilding it. That destroys child State (calling `dispose` and
    // re-running `initState`) on every sheet expand/collapse, which surfaces
    // as scroll position resets, re-initialised controllers, re-fired fetches,
    // etc. The FocusNode is owned internally by the Focus widget's Element and
    // persists correctly without an external key.
    final focusBridge = Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus && _currentState != GlassSheetState.full) {
          _snapToState(GlassSheetState.full);
        }
      },
      child: widget.child,
    );

    return AnimatedBuilder(
      animation:
          Listenable.merge([_animationController, _saturationController]),
      builder: (context, _) {
        final fullPos =
            _geometry.positionForState(GlassSheetState.full, mqHeight);
        final halfPos =
            _geometry.positionForState(GlassSheetState.half, mqHeight);
        final minPos = _geometry.positionForState(_geometry.minState, mqHeight);

        double pos = _animationController.value;

        // Snap to exact positions when not dragging
        if (_gestureArena.phase == GesturePhase.idle) {
          if ((pos - halfPos).abs() < 0.002) pos = halfPos;
          if ((pos - fullPos).abs() < 0.002) pos = fullPos;
          if ((pos - minPos).abs() < 0.002) pos = minPos;
        }

        _currentPosition = pos;
        final t = _expandProgress;

        final metrics = _calculateMetrics(
          pos: pos,
          t: t,
          halfPos: halfPos,
          minPos: minPos,
          extraHeight: extraHeight,
          mqHeight: mqHeight,
          baseSettings: baseSettings,
          effectiveExpandedColor: effectiveExpandedColor,
          topRadiusBase: topRadiusBase,
          bottomRadiusBase: bottomRadiusBase,
          topRadiusFull: topRadiusFull,
          bottomRadiusFull: bottomRadiusFull,
          fullPos: fullPos,
        );

        _currentEffectiveHeight = metrics.effectiveHeight;

        final fadedSettings = metrics.effectiveSettings.copyWith(
          glassColor: metrics.effectiveSettings.glassColor.withValues(
              alpha: metrics.effectiveSettings.glassColor.a *
                  metrics.glassOpacity),
          blur: metrics.effectiveSettings.blur * metrics.glassOpacity,
          lightIntensity:
              metrics.effectiveSettings.lightIntensity * metrics.glassOpacity,
          ambientStrength:
              metrics.effectiveSettings.ambientStrength * metrics.glassOpacity,
        );

        Widget result = _SheetLayout(
          interactionScale: metrics.interactionScale,
          enableInteractionGlow: widget.enableInteractionGlow,
          platformViewBackdrop: widget.platformViewBackdrop,
          glowColor: widget.glowColor,
          glowRadius: widget.glowRadius,
          stretch: widget.stretch,
          interactionStretch: metrics.interactionStretch,
          resistance: widget.resistance,
          hPad: metrics.hPad,
          effectiveBottom: metrics.effectiveBottom,
          effectiveHeight: metrics.effectiveHeight,
          topRadius: metrics.topRadius,
          bottomRadius: metrics.bottomRadius,
          showDragIndicator: widget.showDragIndicator,
          dragIndicatorColor: widget.dragIndicatorColor,
          dragIndicatorWidth: widget.dragIndicatorWidth,
          colorOpacity: metrics.colorOpacity,
          glassOpacity: metrics.glassOpacity,
          effectiveExpandedColor: metrics.effectiveExpandedColor,
          fadedSettings: fadedSettings,
          effectiveQuality: effectiveQuality,
          saturationAnimation: _saturationAnimation,
          expandProgress: t,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          padding: widget.padding,
          scrollController: _scrollController,
          currentStateNotifier: _currentStateNotifier,
          expandProgressValue: t,
          maintainContentGlass: widget.maintainContentGlass,
          fullStateContentSettings: widget.fullStateContentSettings,
          enableSaturationGlow: widget.enableSaturationGlow,
          enableTopFade: widget.enableTopFade,
          topFadeHeight: widget.topFadeHeight,
          onFocusGained: () {
            if (_currentState != GlassSheetState.full) {
              _snapToState(GlassSheetState.full);
            }
          },
          suppressInteractionOnChildren: widget.suppressInteractionOnChildren,
          child: focusBridge,
        );

        if (widget.suppressInteractionOnChildren) {
          result = NotificationListener<InteractionNotification>(
            onNotification: (notification) {
              if (widget.suppressInteractionOnChildren) {
                _isInteractingWithChild = true;
              }
              return false;
            },
            child: result,
          );
        }

        return NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: result,
        );
      },
    );
  }
}

/// Minimal [ChangeNotifier] subclass that exposes [notifyListeners] publicly
/// via [notify], avoiding `invalid_use_of_protected_member` lint when the
/// controller is used as an animation listener target from outside the class.
class _ProgressNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
