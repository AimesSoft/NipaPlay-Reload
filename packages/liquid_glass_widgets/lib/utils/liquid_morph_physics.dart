// ignore_for_file: comment_references

import 'package:flutter/animation.dart';

/// Semantic phase of the liquid glass morph lifecycle.
///
/// Consuming widgets can use this to react to *where* in the animation
/// lifecycle the morph currently is — without re-deriving it from raw
/// animation values.
///
/// State machine (open direction):
/// ```
/// idle → detaching → travelling → arriving → settled
/// ```
/// State machine (close direction, spring bounces back):
/// ```
/// settled → arriving → travelling → detaching → [bounce] → idle
/// ```
enum MorphPhase {
  /// The morph has not started or has fully settled at its origin.
  idle,

  /// The anchor blob is shrinking and Blob B is just beginning to pull away.
  /// In practice this covers animation values [0.0 – 0.4].
  detaching,

  /// Blob B is in mid-travel — the teardrop neck is at maximum stretch.
  /// Animation values [0.4 – 0.8].
  travelling,

  /// Blob B is approaching its destination and the neck is retracting.
  /// Animation values [0.8 – 1.0).
  arriving,

  /// Blob B has fully settled at its target position.
  /// Animation value ≥ 1.0.
  settled,
}

/// The fully computed render state for one frame of a liquid morph animation.
///
/// All values are pre-calculated and ready to be applied directly to widget
/// geometry. Consumers must not re-derive values from the raw animation value.
class LiquidMorphState {
  const LiquidMorphState({
    required this.pathT,
    required this.sizeT,
    required this.currentDx,
    required this.currentDy,
    required this.pushDx,
    required this.pushDy,
    required this.anchorScale,
    required this.blend,
    required this.containerScale,
    required this.phase,
  });

  /// Position interpolation value — drives the J-curve overshoot.
  ///
  /// Computed by [_BackOutCurve]. Can legitimately exceed `[0, 1]` during the
  /// close undershoot phase. Use this to position Blob B.
  final double pathT;

  /// Size interpolation value — drives the teardrop size expansion.
  ///
  /// Computed by [Curves.linearToEaseOut]. Stays within `[0, 1]` during
  /// normal operation (any close undershoot is added additively).
  final double sizeT;

  /// Absolute horizontal displacement of the menu body (Blob B) from the
  /// trigger center, in logical pixels.
  final double currentDx;

  /// Absolute vertical displacement of the menu body (Blob B) from the
  /// trigger center, in logical pixels.
  final double currentDy;

  /// Horizontal displacement applied to the anchor blob (Blob A) during the
  /// underdamped closing bounce. Zero during the opening animation.
  final double pushDx;

  /// Vertical displacement applied to the anchor blob (Blob A) during the
  /// underdamped closing bounce. Zero during the opening animation.
  final double pushDy;

  /// Scale factor for the anchor (ghost trigger) blob in `[0.0 – 1.0]`.
  ///
  /// Shrinks to `0.0` over the first 40 % of the opening animation so the
  /// liquid bridge detaches cleanly. Grows back during closing so the real
  /// trigger button is ready to "catch" the returning menu.
  final double anchorScale;

  /// Metaball merge intensity in SDF blur units, clamped to `[0.0 – 28.0]`.
  ///
  /// Derived from the separation between [pathT] and [sizeT]: zero when the
  /// blobs perfectly overlap (no swell needed), and maximum when the teardrop
  /// bridge is at peak stretch.
  final double blend;

  /// Scale pulse applied to the menu container (Blob B) during the spring
  /// overshoot phases.
  ///
  /// - `1.0` during normal travel.
  /// - Slightly above `1.0` on open overshoot (negligible — overdamped).
  /// - Drops below `1.0` on close undershoot to produce the visible squeeze.
  final double containerScale;

  /// Semantic lifecycle phase of the morph for this frame.
  final MorphPhase phase;
}

/// Pure, stateless math engine for liquid glass morphing animations.
///
/// This class implements the J-curve back-out position curve and
/// [Curves.linearToEaseOut] size curve that together create the
/// iOS 26 liquid teardrop morphing effect.
///
/// It is **intentionally stateless** — feed it the raw animation value plus
/// the source/destination geometry and it returns a fully computed
/// [LiquidMorphState] for that frame. No `BuildContext`, no `State`, no
/// `ChangeNotifier` dependencies.
///
/// ## Design
///
/// Two conceptual blobs drive the morph:
///
/// - **Blob A** (anchor / ghost trigger) stays at the trigger position and
///   shrinks away over the first 40 % of the animation to cleanly break the
///   liquid bridge.
/// - **Blob B** (menu body) travels from the trigger center to the menu
///   center along a J-curve overshoot trajectory, expanding from trigger size
///   to menu size.
///
/// The metaball SDF shader automatically creates the teardrop neck between the
/// two blobs — there is no explicit neck geometry.
///
/// ## Usage
///
/// ```dart
/// // Typically called from an AnimatedBuilder or addListener callback.
/// final state = LiquidMorphPhysics.compute(
///   rawValue: controller.value,
///   finalDx: finalDx,
///   finalDy: finalDy,
///   horizontalOffset: _horizontalOffset,
///   verticalOffset: _verticalOffset,
/// );
///
/// // Apply to the UI:
/// Positioned(
///   left: triggerX + state.pushDx,
///   top:  triggerY + state.pushDy,
///   child: Transform.scale(scale: state.anchorScale, child: blobA),
/// )
/// ```
class LiquidMorphPhysics {
  // Pure utility class — no instances.
  const LiquidMorphPhysics._();

  // ─── iOS 26 Spring Constants ───────────────────────────────────────────────
  //
  // Both open and close use the same underdamped spring profile:
  //   mass: 1.0, stiffness: 120.0, damping: 16.0
  //   ω₀ = √(120/1) ≈ 11 rad/s,  ζ = 16/(2×11) ≈ 0.73 — slightly underdamped.
  //
  // The underdamping is intentional: it lets the spring overshoot past 0.0 on
  // close, which drives the physical "bump" on the trigger icon. The J-curve
  // position curve and the [closeVelocityHint] amplify this into the satisfying
  // iOS-native rubber-band momentum feel.

  /// Spring profile for the iOS 26 liquid morph **opening** animation.
  static const SpringDescription openSpring = SpringDescription(
    mass: 1.0,
    stiffness: 120.0,
    damping: 16.0,
  );

  /// Spring profile for the iOS 26 liquid morph **closing** animation.
  ///
  /// Identical constants to [openSpring]. The closing "bump" is produced by
  /// injecting [closeVelocityHint] at the moment of close — not by different
  /// spring physics.
  static const SpringDescription closeSpring = SpringDescription(
    mass: 1.0,
    stiffness: 120.0,
    damping: 16.0,
  );

  /// Initial velocity hint injected when the close animation starts.
  ///
  /// A negative value immediately drives the spring toward zero with
  /// momentum, maximising the visible rubber-band bounce amplitude.
  static const double closeVelocityHint = -2.5;

  // ─── Tuning constants (intentionally not public) ───────────────────────────
  //
  // These constants are calibrated for iOS 26 native parity. Exposing them
  // as public parameters would allow developers to produce physically broken
  // animations. Use [GlassMorphController.speed] for safe speed control.

  /// Amplitude of the J-curve back-out overshoot for position interpolation.
  static const double _backOutAmplitude = 2.5;

  /// Fraction of the animation over which the anchor blob shrinks to zero.
  static const double _anchorEaseDuration = 0.4;

  /// Multiplier from path/size separation to SDF blur units.
  static const double _blendMultiplier = 150.0;

  /// Maximum SDF blend value to prevent excessive merging on small movements.
  static const double _maxBlend = 28.0;

  // ─── Core computation ──────────────────────────────────────────────────────

  /// Computes the full [LiquidMorphState] for a single animation frame.
  ///
  /// ### Parameters
  ///
  /// - [rawValue] — the raw, unclamped value from `AnimationController.unbounded`.
  ///   Legitimately exceeds `[0, 1]` during spring overshoot phases.
  /// - [finalDx] — target horizontal displacement from the trigger center to
  ///   the menu center, in logical pixels.
  /// - [finalDy] — target vertical displacement from the trigger center to
  ///   the menu center, in logical pixels.
  /// - [horizontalOffset] — screen-edge clamping correction for horizontal
  ///   overflow, accumulated by the menu positioning logic.
  /// - [verticalOffset] — screen-edge clamping correction for vertical overflow.
  static LiquidMorphState compute({
    required double rawValue,
    required double finalDx,
    required double finalDy,
    double horizontalOffset = 0.0,
    double verticalOffset = 0.0,
  }) {
    final clampedValue = rawValue.clamp(0.0, 1.0);

    // Inject the close undershoot so Blob B bounces past the anchor on close.
    // The open-side overshoot (rawValue > 1) is intentionally excluded because
    // it causes an unwanted size wobble during the initial expansion.
    final closeUndershoot = rawValue < 0.0 ? rawValue : 0.0;

    // ── J-Curve Position ──────────────────────────────────────────────────────
    // The back-out curve overshoots far past 1.0 before snapping back,
    // creating the "string pull" teardrop neck at maximum separation.
    final pathT = _BackOutCurve(_backOutAmplitude).transform(clampedValue) +
        closeUndershoot;

    // ── Size ─────────────────────────────────────────────────────────────────
    // Size grows steadily then decelerates so the teardrop bulge is clearly
    // visible before the container reaches its final dimensions.
    final sizeT =
        Curves.linearToEaseOut.transform(clampedValue) + closeUndershoot;

    // ── Closing Momentum Push (Blob A displacement) ───────────────────────────
    // When the spring overshoots past 0 (rawValue < 0), Blob A is displaced
    // proportionally to mirror the closing momentum.
    final pushDx =
        rawValue < 0.0 ? (finalDx + horizontalOffset) * rawValue : 0.0;
    final pushDy = rawValue < 0.0 ? (finalDy + verticalOffset) * rawValue : 0.0;

    // ── Blob B Displacement ───────────────────────────────────────────────────
    final currentDx = finalDx * pathT;
    final currentDy = finalDy * pathT;

    // ── Anchor Scale ─────────────────────────────────────────────────────────
    // Shrinks the ghost trigger (Blob A) to 0 over the first 40 % of the
    // animation. Grows back during close so the real trigger "catches" the menu.
    final anchorScale =
        (1.0 - (clampedValue / _anchorEaseDuration)).clamp(0.0, 1.0);

    // ── Metaball Blend ────────────────────────────────────────────────────────
    // Separation between pathT (position) and sizeT (size) represents how far
    // Blob B has pulled away from its anchor. Blend naturally scales with this.
    final separation = (pathT - sizeT).abs();
    final blend = (separation * _blendMultiplier).clamp(0.0, _maxBlend);

    // ── Container Scale Pulse ─────────────────────────────────────────────────
    // Subtle squeeze/swell during spring overshoot phases.
    final containerScale = rawValue > 1.0
        ? 1.0 + (rawValue - 1.0) * 0.10 // open overshoot (negligible)
        : rawValue < 0.0
            ? 1.0 + rawValue * 0.55 // close undershoot → visible squeeze
            : 1.0;

    // ── Phase ─────────────────────────────────────────────────────────────────
    final phase = _derivePhase(rawValue, clampedValue);

    return LiquidMorphState(
      pathT: pathT,
      sizeT: sizeT,
      currentDx: currentDx,
      currentDy: currentDy,
      pushDx: pushDx,
      pushDy: pushDy,
      anchorScale: anchorScale,
      blend: blend,
      containerScale: containerScale,
      phase: phase,
    );
  }

  static MorphPhase _derivePhase(double rawValue, double clampedValue) {
    if (rawValue < 0.0) return MorphPhase.detaching; // close bounce
    if (clampedValue < 0.001) return MorphPhase.idle;
    if (clampedValue < 0.4) return MorphPhase.detaching;
    if (clampedValue < 0.8) return MorphPhase.travelling;
    if (clampedValue < 0.999) return MorphPhase.arriving;
    return MorphPhase.settled;
  }
}

/// Back-out easing curve for the J-curve position overshoot.
///
/// Creates a pronounced overshoot past `1.0` before snapping back to `1.0`,
/// which manifests as the teardrop "string pull" effect during the liquid morph.
///
/// - [amplitude] controls how far past `1.0` the curve overshoots.
///   The default value of `2.5` is calibrated for iOS 26 native parity.
class _BackOutCurve extends Curve {
  const _BackOutCurve(this.amplitude);
  final double amplitude;

  @override
  double transformInternal(double t) {
    return (t -= 1.0) * t * ((amplitude + 1.0) * t + amplitude) + 1.0;
  }
}
