// ignore_for_file: public_member_api_docs
// Internal spring animation utilities — drop-in replacement for the motor
// package, implemented entirely on top of Flutter's built-in physics.
//
// Only the subset of motor that is actually used in this package is
// implemented here.  Public API is intentionally not exported.

import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../widgets/shared/glass_accessibility_scope.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Spring presets
// These match motor's CupertinoMotion presets exactly.
// motor delegates to SpringDescription.withDurationAndBounce — same here.
// ─────────────────────────────────────────────────────────────────────────────

/// Static spring-description factories that mirror motor's named presets.
///
/// Every preset uses [SpringDescription.withDurationAndBounce], which is the
/// same factory motor's `CupertinoMotion` uses internally.
abstract final class GlassSpring {
  /// Bouncy spring — motor's `Motion.bouncySpring`.
  /// Default duration 500 ms, bounce 0.3.
  static SpringDescription bouncy({
    Duration duration = const Duration(milliseconds: 500),
    double extraBounce = 0.0,
  }) =>
      SpringDescription.withDurationAndBounce(
        duration: duration,
        bounce: 0.3 + extraBounce,
      );

  /// Snappy spring — motor's `Motion.snappySpring`.
  /// Default duration 500 ms, bounce 0.15.
  static SpringDescription snappy({
    Duration duration = const Duration(milliseconds: 500),
    double extraBounce = 0.0,
  }) =>
      SpringDescription.withDurationAndBounce(
        duration: duration,
        bounce: 0.15 + extraBounce,
      );

  /// Smooth spring — motor's `Motion.smoothSpring`.
  /// Default duration 500 ms, bounce 0.0 (critically-damped).
  static SpringDescription smooth({
    Duration duration = const Duration(milliseconds: 500),
    double extraBounce = 0.0,
  }) =>
      SpringDescription.withDurationAndBounce(
        duration: duration,
        bounce: 0.0 + extraBounce,
      );

  /// Interactive spring — motor's `Motion.interactiveSpring`.
  /// Short 150 ms response, light bounce 0.14.
  static SpringDescription interactive({
    Duration duration = const Duration(milliseconds: 150),
    double extraBounce = 0.0,
  }) =>
      SpringDescription.withDurationAndBounce(
        duration: duration,
        bounce: 0.14 + extraBounce,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SingleSpringController  (replaces SingleMotionController /
//                          BoundedSingleMotionController / MotionController)
// ─────────────────────────────────────────────────────────────────────────────

/// A lightweight controller that drives a single [double] value using
/// [SpringSimulation].  Equivalent to motor's `SingleMotionController`.
///
/// Features:
/// * [value] — current animated value.
/// * [velocity] — current spring velocity (units/second).
/// * [animateTo] — start/redirect a spring toward a new target, preserving
///   current velocity.
/// * [spring] can be changed at any time; a running simulation is redirected
///   immediately (mirrors motor's hot-swap behaviour).
/// * Optional [lowerBound]/[upperBound] clamping (mirrors
///   `BoundedSingleMotionController`).
/// * Implements [Listenable] so it works directly with [ListenableBuilder].
class SingleSpringController extends ChangeNotifier {
  SingleSpringController({
    required TickerProvider vsync,
    required SpringDescription spring,
    double initialValue = 0.0,
    double? lowerBound,
    double? upperBound,
  })  : _spring = spring,
        _value = initialValue,
        _lowerBound = lowerBound,
        _upperBound = upperBound {
    _ticker = vsync.createTicker(_tick);
  }

  SpringDescription _spring;
  double _value;
  double _tickerElapsed = 0.0; // total time since ticker.start()
  double _simStartTime = 0.0; // ticker time when the current sim was created
  double _target = 0.0;
  SpringSimulation? _sim;
  late final Ticker _ticker;

  final double? _lowerBound;
  final double? _upperBound;

  // Public API ----------------------------------------------------------------

  /// The current animated value.
  double get value => _value;

  double get velocity {
    final sim = _sim;
    if (sim == null) return 0.0;
    final t = (_tickerElapsed - _simStartTime).clamp(0.0, double.infinity);
    return sim.dx(t);
  }

  /// The spring description.  Changing it will redirect any running
  /// simulation immediately, preserving current velocity.
  SpringDescription get spring => _spring;
  set spring(SpringDescription value) {
    if (_spring == value) return;
    _spring = value;
    if (_ticker.isActive) _startSim(target: _target, fromVelocity: velocity);
  }

  /// Animates toward [target], preserving current velocity.
  /// If [fromVelocity] is provided it overrides the current velocity.
  void animateTo(double target, {double? fromVelocity}) {
    _target = _clamp(target);
    _startSim(target: _target, fromVelocity: fromVelocity ?? velocity);
  }

  /// Immediately sets the value without animating.
  void setValue(double value) {
    _ticker.stop();
    _sim = null;
    _value = _clamp(value);
    _tickerElapsed = 0.0;
    _simStartTime = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // Internal ------------------------------------------------------------------

  double _clamp(double v) {
    if (_lowerBound != null && v < _lowerBound) return _lowerBound;
    if (_upperBound != null && v > _upperBound) return _upperBound;
    return v;
  }

  void _startSim({required double target, required double fromVelocity}) {
    _sim = SpringSimulation(
      _spring,
      _value,
      target,
      fromVelocity,
    );
    if (!_ticker.isActive) {
      // The Dart Ticker resets its elapsed counter to zero on each start().
      // _simStartTime must match so that sim.x/dx are evaluated at t=0 on the
      // first tick — not at (0 - stale_elapsed) which extrapolates backward
      // and can produce astronomically large velocity/position values.
      _tickerElapsed = 0.0;
      _simStartTime = 0.0;
      _ticker.start();
    } else {
      // Ticker is already running; anchor the new sim to the current position
      // in the ticker timeline so it starts at t=0 relative to now.
      _simStartTime = _tickerElapsed;
    }
  }

  void _tick(Duration elapsed) {
    _tickerElapsed = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    // Guard: simElapsed must always be ≥ 0.  Negative values can occur during
    // rapid-fire redirects where _simStartTime was set from a _tickerElapsed
    // that was incremented after _startSim returned.  SpringSimulation.x(t<0)
    // extrapolates backward and can produce huge/NaN values.
    final simElapsed =
        (_tickerElapsed - _simStartTime).clamp(0.0, double.infinity);
    final sim = _sim;
    if (sim == null) {
      _ticker.stop();
      return;
    }

    _value = _clamp(sim.x(simElapsed));

    if (sim.isDone(simElapsed)) {
      _value = _clamp(_target);
      _sim = null;
      _ticker.stop();
    }
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OffsetSpringController  (replaces MotionController<Offset> with
//                          OffsetMotionConverter — used by GlassGlowLayerState)
// ─────────────────────────────────────────────────────────────────────────────

/// A controller that drives an [Offset] value using two independent
/// [SingleSpringController]s (one per axis).
///
/// Implements [Listenable]; listeners fire whenever either axis ticks.
class OffsetSpringController extends ChangeNotifier {
  OffsetSpringController({
    required TickerProvider vsync,
    required SpringDescription spring,
    Offset initialValue = Offset.zero,
  }) {
    _x = SingleSpringController(
      vsync: vsync,
      spring: spring,
      initialValue: initialValue.dx,
    )..addListener(notifyListeners);
    _y = SingleSpringController(
      vsync: vsync,
      spring: spring,
      initialValue: initialValue.dy,
    )..addListener(notifyListeners);
  }

  late final SingleSpringController _x;
  late final SingleSpringController _y;

  /// Current animated offset.
  Offset get value => Offset(_x.value, _y.value);

  /// Current spring velocity as an [Offset].
  Offset get velocity => Offset(_x.velocity, _y.velocity);

  /// Animate toward [target], preserving current velocity.
  void animateTo(Offset target) {
    _x.animateTo(target.dx);
    _y.animateTo(target.dy);
  }

  /// Immediately set both axes without animating.
  set value(Offset v) {
    _x.setValue(v.dx);
    _y.setValue(v.dy);
  }

  /// Change the spring for both axes, redirecting any running simulation.
  set spring(SpringDescription s) {
    _x.spring = s;
    _y.spring = s;
  }

  @override
  void dispose() {
    _x.removeListener(notifyListeners);
    _y.removeListener(notifyListeners);
    _x.dispose();
    _y.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SpringBuilder  (replaces SingleMotionBuilder / MotionBuilder without velocity)
// ─────────────────────────────────────────────────────────────────────────────

typedef SpringWidgetBuilder = Widget Function(
  BuildContext context,
  double value,
  Widget? child,
);

/// Animates a [double] [value] to new targets using a spring, calling
/// [builder] on every frame.
///
/// Equivalent to motor's `SingleMotionBuilder`.
///
/// When [value] changes, the spring is redirected to the new target while
/// preserving the current velocity (identical to motor's behaviour).
/// When [spring] changes, the running simulation is redirected too.
class SpringBuilder extends StatefulWidget {
  const SpringBuilder({
    required this.value,
    required this.spring,
    required this.builder,
    this.child,
    super.key,
  });

  final double value;
  final SpringDescription spring;
  final SpringWidgetBuilder builder;
  final Widget? child;

  @override
  State<SpringBuilder> createState() => _SpringBuilderState();
}

class _SpringBuilderState extends State<SpringBuilder>
    with SingleTickerProviderStateMixin {
  late final SingleSpringController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = SingleSpringController(
      vsync: this,
      spring: widget.spring,
      initialValue: widget.value,
    );
  }

  @override
  void didUpdateWidget(SpringBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spring != oldWidget.spring) {
      _ctrl.spring = widget.spring;
    }
    if (widget.value != oldWidget.value) {
      // IP1: When Reduce Motion is active, snap instantly instead of animating.
      // GlassAccessibilityData.of reads MediaQuery directly when no
      // GlassAccessibilityScope is present, so this always respects the system
      // setting with no developer setup required.
      final reduceMotion = GlassAccessibilityData.of(context).reduceMotion;
      if (reduceMotion) {
        _ctrl.setValue(widget.value);
      } else {
        _ctrl.animateTo(widget.value);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, child) => widget.builder(context, _ctrl.value, child),
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VelocitySpringBuilder  (replaces VelocityMotionBuilder<double> /
//                         SingleVelocityMotionBuilder)
// ─────────────────────────────────────────────────────────────────────────────

typedef VelocitySpringWidgetBuilder = Widget Function(
  BuildContext context,
  double value,
  double velocity,
  Widget? child,
);

/// Like [SpringBuilder] but also provides the current spring [velocity] to
/// the builder.  Equivalent to motor's `VelocityMotionBuilder` /
/// `SingleVelocityMotionBuilder`.
///
/// [springWhenActive] is used while the user is interacting (dragging).
/// [springWhenReleased] is used after the user lifts their finger.
/// Switching between them mid-animation redirects the simulation smoothly.
class VelocitySpringBuilder extends StatefulWidget {
  const VelocitySpringBuilder({
    required this.value,
    required this.springWhenActive,
    required this.springWhenReleased,
    required this.builder,
    this.active = true,
    this.child,
    super.key,
  });

  /// Current target value.
  final double value;

  /// Spring used while [active] is true (following a pointer).
  final SpringDescription springWhenActive;

  /// Spring used while [active] is false (settling to rest).
  final SpringDescription springWhenReleased;

  /// Whether the user is currently dragging (selects [springWhenActive]).
  final bool active;

  final VelocitySpringWidgetBuilder builder;
  final Widget? child;

  @override
  State<VelocitySpringBuilder> createState() => _VelocitySpringBuilderState();
}

class _VelocitySpringBuilderState extends State<VelocitySpringBuilder>
    with SingleTickerProviderStateMixin {
  late final SingleSpringController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = SingleSpringController(
      vsync: this,
      spring: _currentSpring,
      initialValue: widget.value,
    );
  }

  SpringDescription get _currentSpring =>
      widget.active ? widget.springWhenActive : widget.springWhenReleased;

  @override
  void didUpdateWidget(VelocitySpringBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Spring selection changes when drag state or spring params change.
    // Note: active here only controls WHICH spring is used, never stops the
    // animation — motor's VelocityMotionBuilder had no snap-on-inactive path.
    final springChanged = widget.active != oldWidget.active ||
        widget.springWhenActive != oldWidget.springWhenActive ||
        widget.springWhenReleased != oldWidget.springWhenReleased;
    if (springChanged) {
      _ctrl.spring = _currentSpring;
    }
    if (widget.value != oldWidget.value) {
      // IP1: When Reduce Motion is active, snap instantly instead of animating.
      final reduceMotion = GlassAccessibilityData.of(context).reduceMotion;
      if (reduceMotion) {
        _ctrl.setValue(widget.value);
      } else {
        _ctrl.animateTo(widget.value);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, child) =>
          widget.builder(context, _ctrl.value, _ctrl.velocity, child),
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OffsetSpringBuilder  (replaces MotionBuilder<Offset> with OffsetMotionConverter)
// ─────────────────────────────────────────────────────────────────────────────

typedef OffsetSpringWidgetBuilder = Widget Function(
  BuildContext context,
  Offset value,
  Widget? child,
);

/// Like [SpringBuilder] but for [Offset] values.
/// Equivalent to motor's `MotionBuilder<Offset>` with `OffsetMotionConverter`.
class OffsetSpringBuilder extends StatefulWidget {
  const OffsetSpringBuilder({
    required this.value,
    required this.spring,
    required this.builder,
    this.child,
    super.key,
  });

  final Offset value;
  final SpringDescription spring;
  final OffsetSpringWidgetBuilder builder;
  final Widget? child;

  @override
  State<OffsetSpringBuilder> createState() => _OffsetSpringBuilderState();
}

class _OffsetSpringBuilderState extends State<OffsetSpringBuilder>
    with TickerProviderStateMixin {
  late final OffsetSpringController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = OffsetSpringController(
      vsync: this,
      spring: widget.spring,
      initialValue: widget.value,
    );
  }

  @override
  void didUpdateWidget(OffsetSpringBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spring != oldWidget.spring) {
      _ctrl.spring = widget.spring;
    }
    if (widget.value != oldWidget.value) {
      _ctrl.animateTo(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, child) => widget.builder(context, _ctrl.value, child),
      child: widget.child,
    );
  }
}
