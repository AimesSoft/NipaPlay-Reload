// Package-private brightness resolution utility.
//
// NOT part of the public API — do not export from liquid_glass_widgets.dart.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Resolves the effective brightness for glass widgets using a priority cascade:
///
/// 1. **Explicit [CupertinoThemeData.brightness]** — a developer-pinned
///    brightness on the Cupertino theme. Non-null means intentional.
/// 2. **Material [Theme] brightness** — honours [ThemeMode.light],
///    [ThemeMode.dark], and [ThemeMode.system] via [Theme.maybeBrightnessOf].
///    Returns null if no Material ancestor exists (e.g. pure CupertinoApp),
///    so this level is a safe no-op in pure-Cupertino apps.
/// 3. **[MediaQuery.platformBrightnessOf]** — the device/OS system setting.
///    This is the historical default and the safe fallback.
///
/// Level 4 (the [GlassThemeData.brightness] explicit glass-theme override) is
/// checked by [GlassTheme.brightnessOf] **before** calling this function, so
/// that this function remains free of glass-package imports (avoiding circular
/// dependencies in the theme hierarchy).
///
/// **Never call this function directly from widgets.** Always use
/// [GlassTheme.brightnessOf] so the glass-theme override at level 4 is
/// correctly honoured.
Brightness resolveGlassBrightness(BuildContext context) {
  // Level 1: explicit Cupertino brightness pin.
  //
  // CupertinoTheme.of(context).brightness returns null when the developer has
  // not explicitly set brightness in CupertinoThemeData. Only use it when it
  // is non-null, i.e. when the intent is explicit.
  final cupertinoBrightness = CupertinoTheme.of(context).brightness;
  if (cupertinoBrightness != null) return cupertinoBrightness;

  // Level 2: Material ThemeMode.
  //
  // Theme.maybeBrightnessOf returns null if no Material ancestor exists
  // (e.g. pure CupertinoApp). It correctly resolves ThemeMode: returns
  // Brightness.light for ThemeMode.light, Brightness.dark for ThemeMode.dark,
  // and follows the platform setting for ThemeMode.system.
  final materialBrightness = Theme.maybeBrightnessOf(context);
  if (materialBrightness != null) return materialBrightness;

  // Level 3: device/OS system brightness.
  //
  // This is the safe fallback and the historical behaviour before this fix.
  return MediaQuery.platformBrightnessOf(context);
}
