part of '../glass_modal_sheet.dart';

// ===========================================================================
// Sheet States & Modes
// ===========================================================================

enum GlassSheetState { hidden, peek, half, full }

enum GlassSheetMode {
  /// Scenario 1: hidden ↔ half ↔ full
  /// Can swipe down from half to hidden. From full → half → hidden.
  dismissible,

  /// Scenario 2: peek ↔ half ↔ full
  /// peek is the minimum state, cannot be hidden.
  /// Swiping down from half returns to peek, not hidden.
  persistent,
}

enum GlassFillTransition {
  /// Gradual transition through gradient (current behavior)
  gradual,

  /// Instant color change after reaching threshold
  instant,
}

// ===========================================================================
// SheetStateMachine — isolated state machine
// ===========================================================================

/// Immutable state of the sheet at any given moment.
class SheetSnapshot {
  final GlassSheetState state;
  final double position; // 0.0 .. 1.0 fraction of screen height
  final double velocity; // pixels/second, positive = up
  final Size screenSize;

  const SheetSnapshot({
    required this.state,
    required this.position,
    this.velocity = 0.0,
    required this.screenSize,
  });

  SheetSnapshot copyWith({
    GlassSheetState? state,
    double? position,
    double? velocity,
    Size? screenSize,
  }) =>
      SheetSnapshot(
        state: state ?? this.state,
        position: position ?? this.position,
        velocity: velocity ?? this.velocity,
        screenSize: screenSize ?? this.screenSize,
      );

  double get expandProgress {
    final halfPos =
        SheetGeometry.positionFor(GlassSheetState.half, screenSize.height);
    final fullPos =
        SheetGeometry.positionFor(GlassSheetState.full, screenSize.height);
    if (fullPos <= halfPos) return 0.0;
    return ((position - halfPos) / (fullPos - halfPos)).clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      'SheetSnapshot(state: $state, pos: ${position.toStringAsFixed(4)}, vel: ${velocity.toStringAsFixed(1)})';
}

/// Pure geometry calculations — no BuildContext, no side effects.
class SheetGeometry {
  final GlassSheetMode mode;
  final double halfSize;
  final double? fullSize;
  final double peekSize;
  final bool enablePeek;

  const SheetGeometry({
    required this.mode,
    required this.halfSize,
    this.fullSize,
    required this.peekSize,
    this.enablePeek = true,
  });

  static double positionFor(
    GlassSheetState state,
    double screenHeight, {
    GlassSheetMode? mode,
    double? halfSize,
    double? fullSize,
    double? peekSize,
  }) {
    switch (state) {
      case GlassSheetState.hidden:
        return 0.0;
      case GlassSheetState.peek:
        double pos = peekSize ?? 5.0;
        return pos > 1.0 ? pos / screenHeight : pos;
      case GlassSheetState.half:
        double pos = halfSize ?? 0.45;
        return pos > 1.0 ? pos / screenHeight : pos;
      case GlassSheetState.full:
        double? target = fullSize;
        if (target != null) {
          return target > 1.0 ? target / screenHeight : target;
        }
        // Strictly use the specified inset (default 90.0) for accurate top positioning
        final topInset = 90.0;
        return (screenHeight - topInset) / screenHeight;
    }
  }

  double positionForState(GlassSheetState state, double screenHeight) {
    final hiddenPos = positionFor(GlassSheetState.hidden, screenHeight,
        mode: mode, halfSize: halfSize, fullSize: fullSize, peekSize: peekSize);
    final peekPos = positionFor(GlassSheetState.peek, screenHeight,
        mode: mode, halfSize: halfSize, fullSize: fullSize, peekSize: peekSize);
    final halfPos = positionFor(GlassSheetState.half, screenHeight,
        mode: mode, halfSize: halfSize, fullSize: fullSize, peekSize: peekSize);
    final fullPos = positionFor(GlassSheetState.full, screenHeight,
        mode: mode, halfSize: halfSize, fullSize: fullSize, peekSize: peekSize);

    // Cascade constraint: ensure order hidden <= peek <= half <= full
    final safePeek = peekPos.clamp(hiddenPos, 1.0);
    final safeHalf = halfPos.clamp(safePeek, 1.0);
    final safeFull = fullPos.clamp(safeHalf, 1.0);

    switch (state) {
      case GlassSheetState.hidden:
        return hiddenPos;
      case GlassSheetState.peek:
        return safePeek;
      case GlassSheetState.half:
        return safeHalf;
      case GlassSheetState.full:
        return safeFull;
    }
  }

  GlassSheetState get minState =>
      enablePeek ? GlassSheetState.peek : GlassSheetState.hidden;

  /// Computes target state based on current position and velocity.
  GlassSheetState resolveTarget(
    SheetSnapshot current, {
    required double snapThreshold,
    required double velocityThreshold,
  }) {
    // Build the ordered sequence of available states for the current mode
    final List<GlassSheetState> states = [];
    if (!enablePeek && mode == GlassSheetMode.dismissible) {
      states.add(GlassSheetState.hidden);
    }
    if (enablePeek) {
      states.add(GlassSheetState.peek);
    }
    // Skip half state when halfSize is 0 — allows direct full→hidden.
    if (halfSize > 0) {
      states.add(GlassSheetState.half);
    }
    states.add(GlassSheetState.full);

    final positions = states
        .map((s) => positionForState(s, current.screenSize.height))
        .toList();
    final velocity = current.velocity;

    // Fast flick handling
    if (velocity > velocityThreshold) {
      // Find the next state above current
      for (int i = 0; i < states.length - 1; i++) {
        if (current.position < positions[i + 1] - 0.001) return states[i + 1];
      }
      return GlassSheetState.full;
    }
    if (velocity < -velocityThreshold) {
      // Find the next state below current
      for (int i = states.length - 1; i > 0; i--) {
        if (current.position > positions[i - 1] + 0.001) return states[i - 1];
      }
      return states.first;
    }

    // Boundary safety: if outside the range of segments, snap to extremes
    if (current.position <= positions.first) return states.first;
    if (current.position >= positions.last) return states.last;

    // Static snap handling: find which segment we are in
    for (int i = 0; i < states.length - 1; i++) {
      final s1 = states[i];
      final s2 = states[i + 1];
      final p1 = positions[i];
      final p2 = positions[i + 1];

      if (current.position >= p1 && current.position <= p2) {
        final range = p2 - p1;
        if (range <= 0.0001) continue;

        final progress = (current.position - p1) / range;

        // If we were moving towards s2, check if we crossed threshold
        if (current.state == s1) {
          return progress >= snapThreshold ? s2 : s1;
        }
        // If we were moving towards s1, check if we crossed threshold
        if (current.state == s2) {
          return (1.0 - progress) >= snapThreshold ? s1 : s2;
        }

        // Default: snap to nearest
        return progress >= 0.5 ? s2 : s1;
      }
    }

    // Final fallback: return the closest state overall
    double minDistance = double.infinity;
    GlassSheetState closest = current.state;
    for (int i = 0; i < states.length; i++) {
      final dist = (current.position - positions[i]).abs();
      if (dist < minDistance) {
        minDistance = dist;
        closest = states[i];
      }
    }
    return closest;
  }

  /// Applies rubber-band resistance when dragging beyond bounds.
  double applyResistance(
    double rawPosition,
    double screenHeight, {
    required double resistance,
  }) {
    final minPos = positionForState(minState, screenHeight);
    final fullPos = positionForState(GlassSheetState.full, screenHeight);

    if (rawPosition < minPos) {
      final overflow = minPos - rawPosition;
      return minPos - overflow * resistance;
    }
    if (rawPosition > fullPos) {
      final overflow = rawPosition - fullPos;
      return fullPos + overflow * resistance;
    }
    return rawPosition;
  }
}

// ===========================================================================
// Controllers
// ===========================================================================

class GlassModalSheetController {
  _GlassModalSheetState? _state;

  void _attach(_GlassModalSheetState state) => _state = state;
  void _detach() => _state = null;

  void snapToState(GlassSheetState state,
      {bool animate = true, double velocity = 0}) {
    _state?._snapToState(state, animate: animate, velocity: velocity);
  }

  GlassSheetState get currentState =>
      _state?._currentState ?? GlassSheetState.hidden;

  /// Internal expansion value (0.0 to 1.0).
  /// Primarily used for testing and synchronized animations.
  double get value => _state?._currentPosition ?? 0.0;
  set value(double newValue) {
    _state?._jumpTo(newValue);
  }

  /// Live progress between the half and full snaps: 0.0 at (or below) the half
  /// snap, 1.0 at full. Use with [progressListenable] to react during a drag.
  double get progress => _state?._expandProgress ?? 0.0;

  /// Notifies on every sheet position change — drag and snap animation alike.
  /// Null until the sheet is mounted; read [progress] from inside the listener.
  Listenable? get progressListenable => _state?._progressNotifier;
}

// ===========================================================================
// GestureArena — unified gesture handling
// ===========================================================================

enum GesturePhase { idle, handleDrag, contentDrag, scrolling }

class GestureArena {
  GesturePhase phase = GesturePhase.idle;
  double dragStartY = 0.0;
  double dragStartX = 0.0;
  double dragStartSheetPosition = 0.0;
  bool isVerticalGesture = false;
  VelocityTracker velocityTracker =
      VelocityTracker.withKind(PointerDeviceKind.touch);

  void reset() {
    phase = GesturePhase.idle;
    isVerticalGesture = false;
  }

  void beginHandleDrag(double y, double sheetPosition) {
    phase = GesturePhase.handleDrag;
    dragStartY = y;
    dragStartSheetPosition = sheetPosition;
  }

  void beginPointer(
      double y, double x, double sheetPosition, PointerDeviceKind kind) {
    phase = GesturePhase.idle;
    dragStartY = y;
    dragStartX = x;
    dragStartSheetPosition = sheetPosition;
    isVerticalGesture = false;
    velocityTracker = VelocityTracker.withKind(kind);
  }

  /// Returns true if gesture should be claimed by sheet (not scroll).
  bool evaluateMove(
    double y,
    double x,
    GlassSheetState currentState,
    double threshold, {
    required bool canScrollListUp,
    required bool hasScrollClients,
  }) {
    if (phase == GesturePhase.contentDrag) return true;
    if (phase == GesturePhase.scrolling) return false;
    if (phase == GesturePhase.handleDrag) return true;

    final dy = (y - dragStartY).abs();
    final dx = (x - dragStartX).abs();

    if (dy > threshold && dy > dx) {
      if (currentState == GlassSheetState.full) {
        if ((y - dragStartY) < 0) {
          // Swiping UP
          if (hasScrollClients) {
            phase = GesturePhase.scrolling;
            return false;
          } else {
            phase = GesturePhase.contentDrag;
            isVerticalGesture = true;
            return true;
          }
        } else {
          // Swiping DOWN
          if (canScrollListUp) {
            phase = GesturePhase.scrolling;
            return false;
          } else {
            phase = GesturePhase.contentDrag;
            isVerticalGesture = true;
            return true;
          }
        }
      } else {
        phase = GesturePhase.contentDrag;
        isVerticalGesture = true;
        return true;
      }
    }
    return false;
  }
}

// ===========================================================================
// FrozenState — immutable freeze record
// ===========================================================================

class FrozenState {
  final double bottomScale;
  final double heightAtFreeze;

  const FrozenState({
    required this.bottomScale,
    required this.heightAtFreeze,
  });

  @override
  String toString() =>
      'FrozenState(scale: ${bottomScale.toStringAsFixed(3)}, height: ${heightAtFreeze.toStringAsFixed(1)})';
}

// ===========================================================================
// RenderMetrics — Internal record for build geometry calculations
// ===========================================================================

class _RenderMetrics {
  final double stretchT;
  final double effectiveHeight;
  final double effectiveBottom;
  final double topRadius;
  final double bottomRadius;
  final double hPad;
  final double colorOpacity;
  final double glassOpacity;
  final LiquidGlassSettings effectiveSettings;
  final double interactionScale;
  final double interactionStretch;
  final Color effectiveExpandedColor;

  const _RenderMetrics({
    required this.stretchT,
    required this.effectiveHeight,
    required this.effectiveBottom,
    required this.topRadius,
    required this.bottomRadius,
    required this.hPad,
    required this.colorOpacity,
    required this.glassOpacity,
    required this.effectiveSettings,
    required this.interactionScale,
    required this.interactionStretch,
    required this.effectiveExpandedColor,
  });
}
