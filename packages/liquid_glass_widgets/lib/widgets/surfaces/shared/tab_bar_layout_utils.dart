// Pure-Dart layout utilities shared across the bottom bar widgets.
//
// No Flutter widget imports — keep this file dependency-free so that
// SearchableBottomBarController can import it without breaking the
// "controller must be widget-free" testability constraint.
library;

import 'dart:math' as math;

/// Resolves the effective tab pill width given a per-slot [tabWidth] and
/// the maximum space available.
///
/// - [tabWidth] `null`  → returns [maxAvailable] (expand — fills available space).

/// - [tabWidth] set     → returns `tabWidth × tabCount`, clamped to [maxAvailable].
///
/// [maxAvailable] is floored to 0 before clamping so that unusual layout
/// constraints (e.g. tightly constrained test environments or a very large
/// [extraButton]) never produce a negative clamp range, which would throw a
/// [RangeError] in Dart's [num.clamp].
///
/// This is the single authoritative implementation used by:
/// - [SearchableBottomBarController.computeLayout] (searchable bar)
/// - [GlassBottomBar]'s build method (standalone bar)
///
/// Both bars share the same compact-sizing semantics: [tabWidth] controls the
/// per-tab slot width, and the total pill is bounded by the available space.
double resolveTabPillWidth({
  required double? tabWidth,
  required int tabCount,
  required double maxAvailable,
}) {
  // Guard: clamp requires min ≤ max. If an unusual constraint makes
  // maxAvailable negative (e.g. extra button wider than the bar), floor to 0
  // so we degrade gracefully instead of throwing a RangeError.
  final safeMax = math.max(0.0, maxAvailable);
  if (tabWidth == null) return safeMax;
  return (tabWidth * tabCount).clamp(0.0, safeMax);
}
