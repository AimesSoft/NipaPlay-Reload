# 0.21.3

## 🐛 Bug Fixes

- **SVG and custom icons restored** — `SizedBox`-wrapped icons (e.g. `SvgPicture`) were silently stripped from the render tree since `0.20.0`. The `SizedBox.shrink()` sentinel detection now checks `width`, `height`, and `child` fields so a caller-supplied `SizedBox` wrapping a real icon is always rendered correctly.
- **Searchable bar pill stays active while dragging** — the glass indicator on `GlassTabBar.searchable` collapsed back to its resting state when the finger passed over the currently selected tab mid-drag. The thickness spring now includes the `tabIsDragging` guard, matching the behaviour already present in `GlassTabBar.bottom`.
- **`JellyClipper` Impeller radius guard** — the clip radius is now clamped to strictly less than half the indicator's shortest side, preventing a malformed `RRect` path that caused content to vanish under Impeller's Metal renderer in certain animation frames.

## 🧹 Example

- **Indicator Parity demo calibrated** — default refraction set to `1.15` (`GlassDefaults.refractiveIndex`) to match all Apple demos; both `GlassTabBar.inline` variants now wire live tuner sliders for expansion and pinch strength.

---

# 0.21.2


## 🐛 Bug Fixes

- **Extra button stretch disabled over platform views** — `GlassTabBarExtraButton` now correctly disables its stretch effect when `platformViewBackdrop: true`, matching the behavior of `GlassTabBar.bottom` and fixing the jittery spring animation.
- **`GlassMenu` item scroll wiggle fixed** — menu items with wrapped text (e.g. `maxLines: 2`) could drift sub-pixel vertically during slide-to-select dragging because `ClampingScrollPhysics` allowed fractional scroll offsets even when no overflow was intended. Non-scrollable menus now use `NeverScrollableScrollPhysics`, locking the content completely in place during drag.
- **`GlassPopover` first-frame height fixed** — the popover was briefly rendered at full-screen height before its content height was known, producing a visible flash and forcing users to wrap content in a `SingleChildScrollView` as a workaround. An invisible `Offstage` measurement pass now runs on Frame 1, letting Flutter's layout engine calculate the exact intrinsic content height before the morph animation starts. The animation launches on Frame 2 with perfect geometry — no mid-flight height correction, no flash, no heuristics.

## ⚡ Performance

- **Removed unnecessary compositing layer in `GlassBottomBar`** — the `RepaintBoundary` wrapping the icon layer in `_buildHighQualityMode` is now only mounted when `platformViewBackdrop: true`, where it is required for the Platform View capture path (bug #99). In the common case (`platformViewBackdrop: false`) the boundary was creating a GPU offscreen texture every frame with no caching benefit, since the `JellyClipper` changes on every animation frame.
- **`GlassPopover` idle trigger optimised** — when the popover is fully closed, the trigger widget now skips unnecessary `Transform`, `Opacity`, and `IgnorePointer` compositing layers. This removes redundant GPU work in the common idle state.

## 🧹 Code Quality

- **Null-safe trigger child access** — replaced a `child!` force-unwrap in `GlassPopoverInternal` with a null-safe `child ?? const SizedBox.shrink()` fallback, preventing a hard crash if `child` is ever omitted in a future refactor.

## 🧪 Example

- **Refraction slider added to Indicator Parity demo tuner** — a "Refraction (n)" slider (range 1.0–2.0, default 1.59 matching `GlassTabBar.bottom`'s internal default) for tuning the `refractiveIndex` on the Premium (Impeller) glass indicator. Standard indicators do not perform background capture so the parameter has no visual effect there.

---

# 0.21.1

## 🐛 Bug Fixes — Standard indicator parity

- **Two-pills misalignment fixed** — at `GlassQuality.standard`, the background rim and glass lens now share the same shape geometry (`ShapeDecoration`) and ride the same jelly `Transform`, eliminating the visible separation mid-morph. Regression reported against `GlassTabBar.inline` / segmented controls.
- **Indicator collapse on drag fixed** — the glass indicator no longer morphs back to the resting pill when dragging over the selected tab. The thickness gate now includes `tabIsDragging` so the indicator stays fully active for the entire gesture duration.
- **Standard rim thickness normalised** — the indicator rim on `GlassQuality.standard` is now proportionally mapped from `indicatorSettings.thickness` (same value as Premium) rather than scaling from the raw glass-depth value, which produced a ~2.8 px border. The result is a fine hairline that gracefully matches the Premium look on Standard-quality devices.

---

# 0.21.0

## ✨ New Features

- **`GlassModalSheet` drag progress** — controller now exposes a `progress` getter and `progressListenable` reporting the live 0–1 drag position between half↔full snap points, so hosts can drive coordinated UI in real time. ([#148](https://github.com/sdegenaar/liquid_glass_widgets/pull/148), [@jfhair](https://github.com/jfhair))
- **`GlassTabBar.inline` spring control** — the `.inline` factory now accepts `springDescription`, matching the other factory constructors. Previously inline tab bars were locked to the shared default spring. ([#149](https://github.com/sdegenaar/liquid_glass_widgets/pull/149), [@jfhair](https://github.com/jfhair))
- **`LiquidGlassSettings.ambientRim`** — tunable full-perimeter rim on the moving indicator pill. Defaults match Apple Music's segmented control (brighter in light mode, off in dark). ([#150](https://github.com/sdegenaar/liquid_glass_widgets/pull/150), [@jfhair](https://github.com/jfhair))
- **`AnimatedGlassIndicator` shadow** — `shadowElevation`/`shadow` in `indicatorSettings` now correctly paints a drop shadow on the glass jelly. Previously these values were silently ignored. ([#151](https://github.com/sdegenaar/liquid_glass_widgets/pull/151), [@jfhair](https://github.com/jfhair))

## 🐛 Bug Fixes — PlatformView gesture stability

- **Tab bar freeze fixed:** Intermittent freeze where the tab indicator stopped
  responding after interacting over an iOS `PlatformView` (e.g. a map or WebView).
  The iOS gesture arena can silently drop terminal callbacks, leaving the recognizer
  wedged. Fixed with proactive cleanup on `PointerDown`, post-frame recovery, and
  a gesture ID guard to prevent rapid-tap state corruption.
- **Hybrid gesture mode on `platformViewBackdrop: true`:** When the tab bar
  floats over a `PlatformView`, the visual indicator now animates to its new
  position instantly on touch-down (matching native iOS responsiveness), while the
  actual tab content swap is deferred safely to touch-up. This prevents the iOS
  UIKit view system from dropping the touch stream mid-gesture due to a mid-frame
  unmount of the `PlatformView`. No impact on any screen where
  `platformViewBackdrop` is `false` — those continue to swap instantly on down.
- **Stretch disabled on `platformViewBackdrop: true`:** Flutter's `BackdropFilter`
  must re-acquire the native pixel buffer every time its bounding box changes.
  Stretch animations resize the glass container, causing a one-frame flicker over
  a `PlatformView`. Stretch is now skipped on all bar elements when
  `platformViewBackdrop` is set; press-scale (`interactionScale`) is unaffected
  because it is a GPU-level transform that leaves the backdrop bounds stable.
  No impact on any other screen or platform.

---

# 0.20.1

## 🐛 Bug Fix — `GlassButton.custom` layout expansion

**Fixes:** `GlassButton.custom` unexpectedly expanding to fill bounded parent constraints (e.g., inside `AppBar` actions) ([#146](https://github.com/sdegenaar/liquid_glass_widgets/issues/146)).

- `GlassButton.custom` `height` now correctly defaults to `null` (matching documented behavior).
- The button now properly shrink-wraps to its content when explicit width/height are not provided.
- **Migration:** No breaking changes. If you were relying on the undocumented `56px` default height, explicitly set `height: 56`.

---

# 0.20.0

## 💥 Breaking — `GlassListTile` divider refactor

`GlassListTile` no longer draws its own divider. The `isLast`, `showDivider`,
and `dividerIndent` parameters have been removed.

**Rationale:** A list tile should be a clean, position-agnostic item. Divider
rendering is a layout concern that belongs to the parent container.

### Migration

**Inside `GlassGroupedSection` — no changes needed.**
`GlassGroupedSection` now automatically injects `GlassDivider`s between tiles
with smart leading-indent detection (56px if the preceding tile has a leading
widget, 16px otherwise). The last tile never gets a trailing divider.

**Standalone column layouts — compose `GlassDivider` explicitly:**

```dart
// Before:
Column(children: [
  GlassListTile(title: Text('A')),                    // showDivider: true (default)
  GlassListTile(title: Text('B'), isLast: true),      // suppresses divider
])

// After (standard Flutter composition pattern):
Column(children: [
  GlassListTile(title: Text('A')),
  GlassDivider(indent: 16),
  GlassListTile(title: Text('B')),
])
```

This aligns with Flutter's own `ListTile` + `Divider` composition model.

---

## ✨ New — `GlassTabBar.inline`

A compact glass tab bar for pinned content-filter sections — sits fixed between
a page header and its scrollable list, not inside the scroll view itself.

> **Performance note:** `GlassQuality.premium` re-runs the full shader pipeline
> whenever the backdrop changes. Placing the bar inside a scroll view invalidates
> the backdrop on every scroll frame. Pin it outside the scrollable region or
> drop to `GlassQuality.standard` if embedding inside a list.

```dart
GlassTabBar.inline(
  tabs: const [
    GlassTab(label: 'For You'),
    GlassTab(label: 'Following'),
    GlassTab(label: 'New'),
  ],
  selectedIndex: _selectedIndex,
  onTabSelected: (i) => setState(() => _selectedIndex = i),
)
```

**Key differences from `GlassTabBar.bottom`:**
- Zero padding — sits flush in its parent container.
- Compact height (40px) with a full stadium shape (`barBorderRadius: 100`, clamped to `height/2`).
- Indicator pill automatically matches the track corner radius (`indicatorBorderRadius` defaults to `barBorderRadius`).
- Indicator expansion `h:12, v:10` — same horizontal weight as `GlassSegmentedControl` and `GlassTabBar.bottom`, +2px vertical to compensate for the shorter bar height giving the glass pill proportional visual mass.
- `indicatorPinchStrength: 0.4` — aligned with all other pill controls.
- Magnification disabled (`1.0x`) — text labels never grow on selection.
- Text-only tabs render with correct vertical centering (no icon slot consuming space).
- `extraButton` not supported (structural navigation feature only).

All standard physics parameters (`indicatorPinchStrength`, `indicatorExpansion`,
`indicatorSettings`, `quality`) are still fully configurable.

See the updated **Indicator Parity** demo (`indicator_parity_demo.dart`) where
`GlassTabBar.inline` now appears alongside the other five pill widgets — including
a text-only variant (40px) and an icon + text variant (52px) — with live tuning sliders.

---

# 0.19.7


## 🐛 Bug Fixes

- **`GlassTabBar.bottom` / `GlassBottomBar`** — fixes RTL support (#143, @naeemeltaief).
  The pill and tap/drag hit-testing now correctly align with the visually reversed tab order
  under RTL. The bottom layout normalises the tab data, selected index and callback for RTL,
  and pins only the two inner tab `Row`s to LTR — leaving `indicatorExpansion`, `tabPadding`
  and all text to resolve against the ambient direction as expected. Consumers no longer
  need to force `Directionality.ltr` and reverse tabs by hand. +2 tests.

- **`AnimatedGlassIndicator`** — restores the resting selection pill inside a `GlassContainer`
  (#144, @jfhair). The background pill was permanently hidden whenever an ancestor set
  `avoidsRefraction`, which is a steady-state layout flag on `GlassContainer` — not a
  transient capture signal. The guard was incorrect and is removed. The pill now renders
  correctly in all contexts. No API change. +1 test.


# 0.19.6

## ✨ New — `GlassLargeTitle` + `GlassLargeTitleController`

First-class iOS 26 large-title + search-bar collapse. Replaces manual
`ScrollController` + `setState` wiring with a single controller and two
widgets.

### Two-phase collapse

- **Phase 1** — large title fades out (`Curves.easeIn`, rubber-band overscroll stretch).
- **Phase 2** — optional inline search bar collapses under the nav bar immediately after.

### New API

- `GlassLargeTitle` — sliver widget. Drop it as the first sliver in any `CustomScrollView`.
  - `searchBar: Widget?` — Phase 2 collapse (e.g. `GlassSearchBar`).
  - `trailing`, `fontSize`, `fontWeight`, `letterSpacing`, `padding`, `searchBarPadding`, `color`.
- `GlassLargeTitleController` — owns the `ScrollController`, exposes `collapseProgress` and `searchBarCollapseProgress`. Self-calibrates to Dynamic Type via `reportMeasuredHeight` / `reportSearchBarHeight`.
- `GlassAppBar.largeTitleController` — new optional param. Bar title cross-fades in as the large title collapses. Non-breaking.

```dart
final _ctrl = GlassLargeTitleController(); // dispose in State.dispose()

// Phase 1 only
GlassLargeTitle(text: 'Chats', controller: _ctrl)

// Phase 1 + 2
GlassLargeTitle(
  text: 'Messages',
  controller: _ctrl,
  searchBar: GlassSearchBar(placeholder: 'Search', onChanged: (_) {}),
)
```

### Demo

- Pattern 2 updated to new API. Pattern 7 (Large Title + Search Bar) added.
- Apple Messages demo migrated from manual `AnimatedOpacity` to `GlassLargeTitle`.

+10 tests. **2,291 total, all passing.**

## ⚡ Performance — `GlassBottomBar` Indicator (Impeller)

- **`GlassBottomBar` indicator** — eliminates the live `BackdropFilterLayer` on Impeller
  premium, replacing it with a deterministic `toImageSync` capture path. Fixes the
  opaque-white indicator rendering on physical iOS (#99) and improves drag performance
  by removing a redundant compositor pass.

## 🔧 `GlassGroupedSection` — Header/Footer styling

- Header and footer text is now styled automatically via `DefaultTextStyle`
  (`CupertinoColors.secondaryLabel`, 13pt) — callers no longer need to style them manually.
- Margin is now applied via `Padding` wrapping the full section rather than on the inner
  `GlassCard`, fixing card-edge clipping when a header or footer is present.
- Import changed to `cupertino.dart` for correct `CupertinoColors` resolution.

## 📝 Dart doc improvements

- `GlassContainer`, `GlassCard`, `GlassGroupedSection`, `GlassSegmentedControl` — added
  **⚠️ Anti-Pattern** sections documenting the glass-in-glass restriction: placing interactive
  glass controls inside a container degrades refraction and clips jelly animations.

# 0.19.5

- **`LiquidGlassSettings`** — adds `platformViewFallbackColor` (#138, @jfhair). Splits
  `backerColor`'s dual role: `backerColor` remains the aesthetic backer pad; the new
  field controls the `uBackgroundFallback` shader uniform (PlatformView fill).
  Fully backwards-compatible — defaults to `null`, falling back to `backerColor`.

- **`GlassModalSheet`** — removes the interior `BoxShadow` that bled through the glass
  as a vignette (#137, @jfhair). Elevation now flows via `LiquidGlassSettings.shadowElevation`.
  Pass `shadowElevation: 0` to disable entirely.

# 0.19.4

## ✨ Enhancements — `GlassButtonGroupItem.menu` & `GlassPullDownButton` improvements

### `GlassButtonGroupItem.menu` — whole-pill liquid glass morph


Adds a new `GlassButtonGroupItem.menu` named constructor that turns any item in a
`GlassButtonGroup.icons` pill into a pull-down menu trigger.

When tapped, the **entire pill morphs** into the menu — the full `GlassButton.custom`
shell becomes the `GlassMenu` trigger, so the whole group shape liquefies and expands
into the menu card. This matches the iOS 26 `GlassEffectContainer` morph pattern where
the source shape, not just the tapped slot, participates in the transition.

```dart
GlassButtonGroup.icons(
  items: [
    GlassButtonGroupItem(icon: Icon(CupertinoIcons.chart_bar), onTap: () {}),
    GlassButtonGroupItem(icon: Icon(CupertinoIcons.clock),     onTap: () {}),
    GlassButtonGroupItem.menu(
      icon: Icon(CupertinoIcons.ellipsis),
      menuItems: [
        GlassMenuItem(title: 'Add to Watchlist', icon: Icon(CupertinoIcons.star), onTap: () {}),
        GlassMenuItem(title: 'Share',            icon: Icon(CupertinoIcons.share), onTap: () {}),
        GlassMenuDivider(),
        GlassMenuItem(title: 'Remove', icon: Icon(CupertinoIcons.trash), isDestructive: true, onTap: () {}),
      ],
      menuAlignment: GlassMenuAlignment.topRight, // optional
      menuWidth: 200,                              // optional, default 200
    ),
  ],
)
```

**Notes:**
- Only the first `GlassButtonGroupItem.menu` in the list is used as the menu trigger; any subsequent menu items are treated as plain tap items.
- Accepts both `GlassMenuItem` and `GlassMenuDivider`, matching `GlassMenu.items` directly.
- Non-menu siblings in the group continue to fire their own `onTap` independently.
- Works with both `Axis.horizontal` and `Axis.vertical` groups.

**Alternatively — group + standalone `GlassPullDownButton`**

For cases where the menu trigger is a separate, visually distinct action from the
group (e.g. a trailing overflow button next to a row of chart controls), compose a
`GlassButtonGroup` alongside a standalone `GlassPullDownButton`. The pull-down
button morphs independently and fully, with no pill residue:

```dart
Row(
  children: [
    GlassButtonGroup.icons(
      items: [
        GlassButtonGroupItem(icon: Icon(CupertinoIcons.chart_bar), onTap: () {}),
        GlassButtonGroupItem(icon: Icon(CupertinoIcons.clock),     onTap: () {}),
      ],
    ),
    SizedBox(width: 8),
    GlassPullDownButton(
      icon: Icon(CupertinoIcons.ellipsis),
      menuAlignment: GlassMenuAlignment.topRight,
      items: [
        GlassMenuItem(title: 'Add to Watchlist', icon: Icon(CupertinoIcons.star), onTap: () {}),
        GlassMenuItem(title: 'Share',            icon: Icon(CupertinoIcons.share), onTap: () {}),
        GlassMenuDivider(),
        GlassMenuItem(title: 'Remove', icon: Icon(CupertinoIcons.trash), isDestructive: true, onTap: () {}),
      ],
    ),
  ],
)
```

| | `.menu` item (shared pill) | group + standalone |
|---|---|---|
| All actions in one pill | ✅ | ❌ |
| Entire pill morphs | ✅ | — |
| Menu button morphs independently | — | ✅ |
| Best for | Overflow within a related set | Separate trailing action |

### `GlassPullDownButton` improvements

- **`items` widened to `List<Widget>`** — now accepts `GlassMenuDivider` alongside `GlassMenuItem`. Source-compatible: existing `List<GlassMenuItem>` code compiles and behaves identically. The `onSelected` callback is applied only to `GlassMenuItem` instances.
- **`menuAlignment` exposed** — new `GlassMenuAlignment?` parameter forwarded to the underlying `GlassMenu`. Defaults to `null` (auto-detect from screen position) — fully backward-compatible.

## 🐛 Bug Fixes — PlatformView Frost Halo & GlassButton Dispose-Race ([#134](https://github.com/sdegenaar/liquid_glass_widgets/pull/134), [#135](https://github.com/sdegenaar/liquid_glass_widgets/pull/135))

Both fixes contributed by [@jfhair](https://github.com/jfhair).

### `LiquidOval` rectangular blur halo over a PlatformView ([#134](https://github.com/sdegenaar/liquid_glass_widgets/pull/134))

**Problem:** Any glass surface with a `LiquidOval` shape (the default for `GlassButton`,
`GlassIconButton`, the collapsed search/dismiss pill, and `GlassBottomBarExtraButton`)
rendered a rectangular blur halo when `platformViewBackdrop: true` routed it through the
`_FrostedFallback` `BackdropFilter` path. The halo matched the widget's bounding box rather
than its circular outline.

**Root cause:** Flutter engine PR #177551 (3.41+) forwards `ClipRRect` clip data to the iOS
PlatformView mutator stack, allowing a descendant `BackdropFilter` to be bounded correctly
over a hybrid-composed view. The same forwarding does NOT apply to `ClipPath` — and
`LiquidOval` (unlike `LiquidRoundedSuperellipse`) was routing through `ClipPath`, leaving
the `BackdropFilter` unclipped.

**Fix:** `_ShapeClip` now accepts a `platformViewBackdrop` flag. When set, any shape whose
border radius can be expressed as a `BorderRadius` (including `LiquidOval` →
`circular(9999)`, `LiquidRoundedRectangle`, and their vertical variants) is routed through
`ClipRRect` instead of `ClipPath`. The clip is then forwarded to the PlatformView mutator
stack and the frost is bounded cleanly to the shape. Off a PlatformView the original
`ClipPath` is used (true ellipse). The flag is threaded through all `_ShapeClip` call sites
in `_FrostedFallback` — the blur body, the content clip, and the specular rim — as well as
the backer dimming pad in `AdaptiveGlass._wrapWithBacker`.

Completes the partial fix shipped in 0.19.3 and fully resolves the rectangular-blur
regression first reported in [#79](https://github.com/sdegenaar/liquid_glass_widgets/issues/79).

### `GlassButton` crash when disposed mid-press ([#135](https://github.com/sdegenaar/liquid_glass_widgets/pull/135))

**Problem:** Tapping a `GlassButton` that is removed by the very tap that activates it
(e.g. a collapsed bar restore button that expands the bar and disposes itself) could throw:

```
AnimationController.reverse() called after AnimationController.dispose()
(assert _ticker != null)
```

A queued `pointerUp` or `pointerCancel` was still dispatched to the now-disposed
`RenderPointerListener`, and the press handler called `_saturationController.reverse()`
after `dispose()`.

**Fix:** All six tap/pointer press handlers in `_GlassButtonState` now guard on `!mounted`
before touching `_saturationController`. A disposed `State` always has `mounted == false`,
so the handler bails safely without touching the controller.

Surfaces frequently in apps that morph or collapse a bar on the tap of a glass control
over a PlatformView (the pattern introduced in #127/#79).

# 0.19.3

## 🐛 Bug Fixes — Search Pill Colors & PlatformView Compositing

- Fixed an issue where the `SearchPill` icon colors (search, mic) would incorrectly render as black when using dark glass (`glassColor: Colors.black26`) over an iOS PlatformView. The root cause was that the color resolution used the OS system brightness (light) instead of the glass brightness (dark), causing `CupertinoDynamicColor.label` to always resolve to its light-mode black variant. The widget now resolves colors through `GlassTheme.brightnessOf()` — the package's single brightness authority — and explicitly passes the resolved color via `IconThemeData` to guarantee white glyphs on dark glass regardless of system brightness.
- Mitigated a Flutter engine clipping bug over PlatformViews by ensuring `LiquidRoundedSuperellipse` and `LiquidOval` correctly clip their bounds using an outer `ClipRRect` when rendering over an iOS PlatformView, preventing blur bleed outside the circular button shape.
- Updated the `google_maps_demo` to correctly demonstrate how to configure `selectedIconColor`, `unselectedIconColor`, and `searchIconColor` for dark glass bottom bars to ensure all tab elements remain visible over the map layer.

# 0.19.2

## 🐛 Bug Fixes — PlatformView Gesture & Rendering

This release resolves a pair of related issues that caused the glass bottom bar
to freeze and render incorrectly when floating over an iOS PlatformView (e.g. a
Mapbox map). All three fixes were contributed by [@jfhair](https://github.com/jfhair)
via detailed PRs that included root-cause analysis, regression tests, and working
reproductions. Many thanks for the exceptional quality of this contribution.

### Gesture freeze over an iOS PlatformView ([#127](https://github.com/sdegenaar/liquid_glass_widgets/pull/127))

**Problem:** `GlassTabBar.searchable` (and `GlassBottomBar`) would freeze when
the draggable indicator was dragged or tapped while the bar floated over an iOS
PlatformView. The freeze was permanent until the widget was rebuilt or disposed.

**Root cause:** iOS reconstructs the platform-view clip chain whenever a clip
layer is added or removed mid-gesture. The engine responds by cancelling the
active touch, which left the bar's `GestureDetector` recognizer wedged — it
never received a terminal callback (`onDragEnd` / `onDragCancel`) and stopped
responding to input. The most frequent trigger was the indicator's `innerBlur`
frost layer unmounting at drag-start (a clip-add/remove cycle).

**Fix — two-part:**
- **Primary fix (PR #127):** The indicator's frost `ClipRRect + BackdropFilter`
  layer now stays _mounted_ across the full drag lifecycle by tracking a
  persistent `bool _frostMounted` flag in `AnimatedGlassIndicator`. This
  eliminates the clip-add/remove cycle that was triggering the iOS clip-chain
  reconstruction.
- **Backstop fix (PR #127):** `TabBarDragGestureMixin` gains a
  `gestureEpoch` counter, a `_gestureActive` liveness flag, and a raw
  `Listener` on the `GestureDetector` subtree. If the raw pointer-up or
  pointer-cancel arrives while `_gestureActive` is still `true` (i.e. the
  terminal callback was silently dropped by the platform-view gesture arena),
  `recoverIfGestureStuck` is called: it selects a fallback tab, bumps
  `gestureEpoch` (forcing the `GestureDetector` to be torn down and
  recreated via `ValueKey`), and clears the stuck state. Covers both the
  tap-without-cancel and drag-start-without-end freeze signatures.

### PlatformView backdrop routing ([#128](https://github.com/sdegenaar/liquid_glass_widgets/pull/128))

**Problem:** Setting `platformViewBackdrop: true` on a bar had no visible effect
for the glass indicator or bar body — the premium/standard Impeller shader paths
read a captured backdrop that excludes hybrid-composed PlatformViews, so the
glass rendered inert (opaque black or clear) over a map.

**Fix:** `AdaptiveGlass` now routes any surface with `platformViewBackdrop: true`
to the frosted fallback (`_FrostedFallback`) regardless of the requested quality
tier. The frosted fallback uses a live `BackdropFilter`, which correctly blurs
hybrid-composed PlatformViews. `_FrostedFallback` also overrides the
`isInteractive` blur-omission that would otherwise skip the blur for interactive
indicator surfaces — over a PlatformView the live blur must always run.

### Premium glass goes black over a PlatformView — `backerColor` fallback ([#129](https://github.com/sdegenaar/liquid_glass_widgets/pull/129))

**Problem:** At `GlassQuality.premium` over a PlatformView, the Impeller shader
sampled a captured backdrop that contained only transparent black where the
PlatformView sat. With no real background pixels to refract, the glass lens
rendered black.

**Fix:** A new `uBackgroundFallback` (vec4) uniform was added to
`liquid_glass_final_render.frag`. The shader composites the fallback colour
over the captured backdrop using a standard `over` blend weighted by the
backdrop's own alpha — where the backdrop is real (alpha ≈ 1) it is left
untouched; where it is transparent black (alpha ≈ 0, i.e. over a PlatformView)
the fallback fills in. `backerColor` from `LiquidGlassSettings` is bound to
this uniform at render time, giving the premium lens a solid colour to refract
instead of transparent black.

### Extra button `platformViewBackdrop` threading (follow-up, this release)

`GlassTabBarExtraButton` previously ignored the bar's `platformViewBackdrop`
flag — the internal `BottomBarExtraBtn` widget was not forwarding it to the
underlying `GlassButton`, so the extra button continued to use the inert shader
path even when the rest of the bar correctly used the frosted fallback.
`platformViewBackdrop` is now threaded through `BottomBarExtraBtn` and both
call sites (`TabBarBottomLayout`, `TabBarSearchableLayout`) to `GlassButton`.

---

# 0.19.1


## 🛡️ Stability Improvements

Addresses production crash and ANR reports seen with v0.19.0 on Flutter 3.44.2
(tracked in flutter/flutter#187140). These are exposure-window mitigations — the
root cause is a Flutter engine issue and requires an engine-level fix.

### Changes

**`GlassEffect` & `LightweightLiquidGlass` — lifecycle-aware Ticker suspension**
Both state classes now implement `WidgetsBindingObserver` and halt background-capture
Tickers during `AppLifecycleState.inactive`, `paused`, and `hidden`. Captures restart
one frame after `resumed`. This reduces GPU texture activity during surface transitions
(rotation, split-screen, keyboard resize) which is the window where engine-level
crashes and ANRs are most likely to occur.

**`GlassEffect` & `LightweightLiquidGlass` — `_isDisposed` guard**
A `_isDisposed` flag prevents Ticker callbacks and async `.then()` continuations
from accessing GPU resources after `dispose()` has completed, guarding against
post-frame-callback / dispose races during rapid navigation.

**`LiquidGlassWidgets.initialize()` — faster startup**
The Impeller pipeline warm-up is no longer `await`ed inside `initialize()`. It now
runs after the first frame via `addPostFrameCallback`, removing a `~16ms` delay from
the startup critical path. Shader disk-loads are still awaited as before.

**Debug log cleanup**
Removed stale `debugPrint` success messages from `GlassEffect` and `LightweightLiquidGlass`
shader pre-warm paths (`✓ Shader precached`, `✓ Created unique shader instance`). These
fired on every debug startup for every app using the package. Failures still surface via
the existing `[LightweightGlass] Pre-warm failed:` error log. The `[LiquidGlass]`
startup bracket (`Initializing...` / `Initialization complete.`) and the
`PerformanceMonitor started` log are retained as actionable developer information.


# 0.19.0


## 💥 Breaking: Pre-v1.0 Public API Cleanup

A pre-release naming audit to establish consistent, idiomatic conventions before v1.0 locks the API.

### Renames

| Old | New | Reason |
|---|---|---|
| `GlassBottomBarExtraButton` | `GlassTabBarExtraButton` | Tracks parent rename `GlassBottomBar` → `GlassTabBar` |
| `GlassGroupItem` | `GlassButtonGroupItem` | Mirrors Flutter's `DropdownMenuItem` pattern |
| `SheetState` | `GlassSheetState` | Prevents collision with Material 3 sheet infrastructure |
| `SheetMode` | `GlassSheetMode` | Same — too generic as a bare name |
| `FillTransition` | `GlassFillTransition` | Too generic as a bare name |
| `ExtraButtonPosition` | `GlassExtraButtonPosition` | Ambiguous without prefix |

> **Migration:** A `@Deprecated` typedef for `GlassBottomBarExtraButton` is provided. All other old names will produce compile errors — migration is mechanical find-and-replace.

### GlassSegment — new concrete class

`GlassSegment` was previously a `typedef` alias for `GlassTab`. It is now a proper class with a focused API for `GlassSegmentedControl`:

```dart
// GlassSegment — for GlassSegmentedControl only
GlassSegment({ Widget? icon, String? label, String? tooltip, String? semanticLabel, bool enabled = true })

// GlassTab — for GlassTabBar.bottom() and GlassTabBar.searchable()
GlassTab({ Widget? icon, Widget? activeIcon, String? label, Color? glowColor, double? thickness })
```

Fields like `activeIcon`, `glowColor`, and `thickness` are navigation-specific and only exist on `GlassTab`. `GlassSegment` adds `tooltip` and `enabled` (with built-in disabled rendering at 38% opacity).

### Barrel hygiene

Internal types (`SheetSnapshot`, `SheetGeometry`, `GesturePhase`, `GestureArena`, `FrozenState`) are no longer accessible from the package barrel. These were implementation details that leaked through `part` file exports.

## ⚡ Performance

- **Shader:** `interactive_indicator.frag` — replaced `pow()` calls with multiply chains; collapsed duplicate rim pass; zero transcendental functions in highlight path.
- **Shader:** `liquid_glass_final_render.frag` — `⁶√x` computed via sqrt cascade (3 SFU vs 2 transcendentals); `sceneSDF` samples reduced from 5 → 4.
- **Dart:** `resolveAdaptiveRadius` scoped to `MediaQuery.viewPaddingOf` + `MediaQuery.sizeOf` — glass widgets no longer rebuild on keyboard or unrelated `MediaQueryData` changes.
- **Dart:** Searchable tab bar and `GlassSegmentedControl` spring animations now use `ListenableBuilder` scoped to the indicator subtree. Verified on-device: zero `State.build()` calls during 120Hz spring animation.

## 🐛 Fix

- **`LiquidGlassWidgets.initialize()`** now pre-warms all four shaders — `liquid_glass_geometry_blended.frag` and `liquid_glass_final_render.frag` were previously lazy-loaded, causing first-frame jank.
- **`GlassSegment.enabled = false` now blocks tap/tapDown** — disabled segments rendered at 38% opacity but still fired `onSegmentSelected` in both fixed-width and scrollable modes. Tap and `onTapDown` handlers now early-return when the target segment is disabled.


---

# 0.18.6

## 🐛 Fix: Glass widgets now honour app `ThemeMode`, not OS dark mode

Resolves a class of UI inconsistency where glass widgets incorrectly read the **device/OS** brightness instead of the **app**'s brightness. The most visible symptom was `GlassBottomTabBar` shadows disappearing when the device was in Dark Mode but the app was pinned to Light Mode via `MaterialApp(themeMode: ThemeMode.light)`.

### Root cause

Every glass widget that needed to decide between light/dark colours or shadow visibility called either `CupertinoTheme.of(context).brightness` or `MediaQuery.platformBrightnessOf(context)` directly. Both of these APIs fall back to the OS/device setting and are blind to `MaterialApp.themeMode`.

### Fix: Centralised brightness cascade

A new `GlassTheme.brightnessOf(context)` authority now governs all brightness decisions in the library. It resolves via a four-level cascade:

1. **`GlassThemeData.brightness`** — new field; an explicit developer override pinned in the `GlassTheme` widget tree (highest priority).
2. **`CupertinoThemeData.brightness`** — explicit Cupertino pin (non-null only; intentional opt-in).
3. **`Theme.maybeBrightnessOf(context)`** — Material `ThemeMode.light`/`.dark`/`.system`, honouring `MaterialApp.themeMode`.
4. **`MediaQuery.platformBrightnessOf(context)`** — OS/device setting (safe fallback).

### Changes

- **New:** `lib/utils/glass_brightness.dart` — `resolveGlassBrightness(context)` utility (package-private).
- **New field:** `GlassThemeData.brightness` — explicit brightness override for fine-grained glass-subtree control. Accepted by both the default and `GlassThemeData.simple()` constructors.
- **New method:** `GlassTheme.brightnessOf(context)` — the single, mandatory brightness authority for the entire library.
- **Fixed:** Shadow suppression in `GlassBottomTabBar`, `GlassSearchableBottomBar`, `AdaptiveLiquidGlassLayer`, and `AdaptiveGlass` (`_FrostedFallback`).
- **Fixed:** Shader `backdropLuma` proxy in `GlassEffect` (controls glass strength in the GPU path).
- **Fixed:** Light/dark colour selection in 20+ widget files across `interactive/`, `containers/`, `input/`, `overlays/`, and `surfaces/` layers.

### Tests

Three new test files cover every level of the cascade:

- `test/utils/glass_brightness_test.dart` — unit tests for `resolveGlassBrightness`.
- `test/theme/glass_theme_brightness_test.dart` — `GlassTheme.brightnessOf` integration tests including the canonical regression scenario.
- `test/theme/glass_theme_data_brightness_test.dart` — `GlassThemeData.brightness` override field, `copyWith`, equality, and backward-compat tests.

---

# 0.18.5

## 🔧 Corrected minimum SDK constraint — Flutter ≥ 3.41.0

- **Fix:** Raised the minimum Flutter constraint to `3.41.0`. The `filterQuality` parameter on `FragmentShader.setImageSampler()` was actually introduced in Flutter 3.41.0 (commit `add442b29c`), not 3.24.0 as previously stated. This prevents users on 3.38.x from failing at compile time.
- **Reverted:** Raised the internal `meta` constraint back to `^1.18.0` since Flutter 3.41.0 guarantees this version is available.

---

# 0.18.4

- **Fix:** Loosened the `meta` dependency constraint to `^1.12.0` (instead of `^1.18.0`) to avoid pub resolution conflicts for users on older Flutter SDKs where `flutter_test` is bound to `meta 1.17.0`.

---

# 0.18.3


## ✨ Per-state label text style on bottom bars — `selectedLabelStyle` / `unselectedLabelStyle`

Adds `selectedLabelStyle` / `unselectedLabelStyle` (`TextStyle?`) to `GlassTabBar.bottom`, `GlassTabBar.searchable`, and the deprecated `GlassBottomBar` / `GlassSearchableBottomBar`.

This complements the `selectedLabelColor` / `unselectedLabelColor` parameters by letting callers set the selected/unselected label's **font family, weight, and letter-spacing per state** — needed to match Apple's tab bar, where the selected label is heavier than a single shared `textStyle` can express.

The per-state style is **merged over** the base label style, so it overrides only the fields it sets and keeps the resolved per-state label color unless the style provides its own. Both default to `null` → existing behavior unchanged.

Also fixes a related precedence bug: an explicit `selectedLabelColor` / `unselectedLabelColor` was silently dropped whenever a `textStyle` was also supplied (the per-state color only fed the fallback style). It now overrides the base color — including a color baked into `textStyle` — while `textStyle`-only callers are unaffected.


## ✨ `innerBlur` — Apple-style rest-blur behind the selected tab

The `innerBlur` parameter on `GlassTabBar.bottom`/`.searchable` (and the deprecated `GlassBottomBar`/`GlassSearchableBottomBar` shims) now renders. It was declared and threaded bar→internal, but never forwarded to the indicator, and `AnimatedGlassIndicator` had no implementation. This wires it through the tab-bar internals and adds the rest-gated `BackdropFilter`.

It paints a backdrop blur behind the **resting** selected pill — the iOS 26 "frost at rest" look — with the sigma scaled by the pill's resting opacity, so the frost is full when settled and fades out as it morphs into the liquid-glass lens during a drag/tap (motion stays crisp).

- `0.0` (default) disables it — no behavior change for existing callers.
- Only the background-painting indicator is affected (reads through a translucent `indicatorColor`).

## ✨ `platformViewBackdrop` on the public glass widgets

Follows up [#94](https://github.com/sdegenaar/liquid_glass_widgets/pull/94) by exposing the premium-over-PlatformView flag on the remaining public widgets — `GlassContainer`, `GlassButton`, `GlassIconButton`, `GlassButtonGroup`, `GlassMenu`, and `GlassModalSheet` — so apps can render premium glass cleanly over an iOS PlatformView (e.g. a Mapbox `MapWidget`) for any control, not just the bottom bar.

Each gets an explicit `platformViewBackdrop` parameter defaulting to `false` (zero overhead / no behavior change for callers that don't need it), forwarded to the underlying `AdaptiveGlass`. For `GlassModalSheet` the flag threads through `GlassModalSheetScaffold` and the sheet state down to the `_SheetLayout`'s glass. Adds widget tests covering the simple-widget forwards.


## 🧹 Removed — `GlassTintBlend` (a no-op since 0.17.0)

`GlassTintBlend` (added in [#107](https://github.com/sdegenaar/liquid_glass_widgets/pull/107)) and the `LiquidGlassSettings.tintBlend` field have been removed.

Since the 0.17.0 shader rewrite, `tintBlend` was never wired into the renderer — it was packed into no uniform, so setting it had no effect: every surface used the automatic chroma-gated blend regardless of the value. We only caught this during real-device tuning, after all the related PRs had already landed.

The automatic behavior is unchanged. `applyGlassColor` still picks luminosity-preserving blending for chromatic tints and flat blending for achromatic tints. Recipes that previously passed `tintBlend: flat` for achromatic (white / grey / near-black) tints render identically, because the chroma gate already resolves those to the flat path.

**Breaking, but inert:** code that passed `LiquidGlassSettings(tintBlend: …)` must drop the argument. No rendered output changes.

## 🔧 SDK constraints bump *(corrected in 0.18.5)*

Raised minimum Flutter to `>=3.24.0` — this was incorrect. The actual minimum is `3.41.0`, corrected in `0.18.5`.

---

# 0.18.2

### Rendering Quality

- **Fix:** Eliminated stair-step aliasing on `AnimatedGlassIndicator` / `GlassEffect` pill edges during press animations.
  Root cause: `FragmentShader.setImageSampler()` defaults to `FilterQuality.none` (Nearest-Neighbor). The 4 % press-scale animation was block-replicating geometry texels into 2×2 stair-step patterns visible as jagged fringe on the pill rim.
  **Resolution:** Pass `filterQuality: FilterQuality.medium` to every `setImageSampler()` call in `liquid_glass_render_object.dart`, `glass_effect.dart`, and `lightweight_liquid_glass.dart`. Zero GPU cost — hardware bilinear filtering happens in a single texel-unit clock cycle.

- **Fix:** Eliminated 2×2 blocky normal artifacts on glass pill edges (all platforms, most visible on iOS/macOS Metal).
  Root cause: Metal's `dFdx`/`dFdy` evaluate in 2×2 pixel quads, so all four neighbours share one gradient vector. At the high-contrast white rim of the pill this produces a coarse stair-step normal map that manifests as jaggy rainbow banding regardless of scale.
  **Resolution:** Replaced hardware derivatives with per-pixel central finite differences in `liquid_glass_geometry_blended.frag` (`dx = sceneSDF(p + 0.5) − sceneSDF(p − 0.5)`). Costs 4 extra SDF evaluations per geometry pixel — negligible on a cached, one-shot geometry pass.

- **Fix:** Restored full rim brightness after the anti-aliasing band was widened.
  Root cause: The previous asymmetric `smoothstep(-smoothing, 0.0, sd)` placed the mathematical pill boundary (`sd = 0`) at the dark end of the alpha ramp (alpha = 0). The rim-lighting peak lives exactly at `sd = 0`, so it was multiplied by zero and rendered invisible.
  **Resolution:** Centred the smoothstep around the boundary — `smoothstep(smoothing * 0.5, -smoothing * 0.5, sd)` — so `sd = 0` maps to alpha = 0.5. This is the canonical SDF anti-aliasing formulation and restores maximum rim brightness with no other visual side-effect.

- **Fix:** Eliminated backdrop texture wrap-around artifacts during `LiquidStretch` scaling and jelly overshoot.
  Root cause: Impeller's default texture sampler wrap mode is `Repeat`. A fragment slightly outside `uGeometrySize` (e.g. during a spring overshoot) produced a `geometryUV` marginally above 1.0; the sampler wrapped it to near-0.0, sampling the opposite edge of the SDF and producing inverted normals and extreme chromatic aliasing.
  **Resolution:** Clamp `geometryUV` to `[0, 1]` before the texture fetch. Clamped-edge pixels have near-zero SDF alpha and are discarded by the existing `geometryData.a < 0.01` early-out — no separate bounds-check branch required.

- **Fix:** Eliminated chromatic wrap artifacts during jelly overshoot in `interactive_indicator.frag`.
  Root cause: When the indicator pill overshoots its `RepaintBoundary` bounds, out-of-bounds `textureBilinear` sample points could trigger the same Repeat-mode wrap in the background texture.
  **Resolution:** Explicitly clamp all four bilinear sample points to `[0, physSize − 1]` before the `texture()` fetch.

- **Fix:** Eliminated jagged/pixelated stair-step artifacts on `AnimatedGlassIndicator` pill edges when `indicatorPinchStrength > 0`.
  Root cause: `BackdropFilterLayer` implicit samplers are bound to `FragmentShader` as Nearest-Neighbor with no Dart API to override it ([Flutter Issue #139887](https://github.com/flutter/flutter/issues/139887)). Continuous sub-pixel UV shifts from the lens pinch and chromatic aberration were snapping to integer texels, producing blocky rainbow fringes on high-contrast backgrounds.
  **Resolution:** Added a `textureBilinear` helper to `liquid_glass_final_render.frag` that performs a standard 4-texel bilinear interpolation in GLSL, restoring perfectly smooth sub-pixel background sampling. The geometry texture (`uGeometryTexture`) is intentionally excluded — its pixel-aligned SDF data must not be softened.

- **Fix:** Eliminated pixelation on the interactive indicator pill (`GlassSegmentedControl`, `GlassEffect`).
  Two compounding causes: (1) the background texture was previously captured at `pixelRatio: 1.0`, so each texel covered a 3×3 block of physical pixels on a 3× Retina display; (2) Impeller's `setImageSampler()` binding defaults to Nearest-Neighbor, snapping continuous UV offsets from edge refraction to these large texels.
  **Resolution:** Background capture now uses the device's full DPR. A `textureBilinear` GLSL helper replaces all raw `texture()` calls in `interactive_indicator.frag`. ~250 KB additional GPU texture memory; sub-0.1 ms additional GPU time per frame — negligible on any modern device.

- **Fix:** Resolved intermittent Metal API Validation abort on iOS (`GlassQuality.premium`) — missing buffer bindings for `uWhiten`, `uWhitenGated`, and `uPinchStrength` ([#121](https://github.com/sdegenaar/liquid_glass_widgets/issues/121)).
  All shader uniforms (slots 0–20) are now written atomically on every paint frame, preventing a stale or zero-initialised `FragmentShader` snapshot from reaching the Metal draw call. Affected: `GlassTabBar.bottom(quality: GlassQuality.premium)` with an animating indicator. No API changes.

### Notes

- **Note (Flutter engine limitation):** The `textureBilinear` workaround in `liquid_glass_final_render.frag` (4-tap bilinear in GLSL) remains necessary for backdrop sampling because Impeller binds the implicit `BackdropFilterLayer` sampler as Nearest-Neighbor with no Dart API to override `FilterQuality`. A Flutter engine feature request to expose sampler filter quality for backdrop layers has been filed at [Flutter Issue #188365](https://github.com/flutter/flutter/issues/188365). Once resolved, the GLSL workaround can be replaced with a single `texture()` call.

### Chore

- **Chore:** Removed unreachable early-out branch in `liquid_glass_final_render.frag` — the `if (any(lessThan(geometryUV, ...)))` check after `clamp(geometryUV, 0.0, 1.0)` could never fire. Replaced with a single consolidated comment explaining how the clamp and the downstream alpha check together handle both the Impeller Repeat-mode and clipExpansion cases.
- **Chore:** Removed dead code from `render.glsl` (`computeY`, `getHeight`, `calculateLighting`, `calculateRefraction`, `renderLiquidGlass`, `debugNormals`) — functions superseded by the inline logic in `liquid_glass_final_render.frag`. Reduces compiled shader binary size.

# 0.18.1

- **Hotfix:** Resolved missing coverage in layout engines and segmented controls.
- **Hotfix:** Fixed package analysis warnings due to unused local variables and unnecessary imports in test files.

# 0.18.0

## 🏗️ Unified Navigation API — iOS 26 Alignment

This release consolidates the widget API to map 1:1 with Apple's iOS 26 control vocabulary. Two v1-era widgets are deprecated (see Migration below), and `GlassTabBar` becomes the single source of truth for all tab-navigation work.

---

### ⚠️ Breaking Change: Android Bottom Bar Padding

`GlassScaffold` now automatically manages the Android system navigation bar padding for `bottomBar`. If you previously added manual `Padding` or `SafeArea` around your bottom bar to prevent it from slipping behind the Android navigation buttons, please remove it to avoid double-padding.

---

### New: `GlassTabBar.bottom()` — iOS 26 UITabBar equivalent

Named constructor for bottom navigation bars. Full liquid glass layer, jelly physics pill indicator, `MaskingQuality` dual-layer icon rendering, and optional `dividerSettings`.

```dart
GlassTabBar.bottom(
  tabs: [
    GlassTab(icon: Icon(Icons.home), label: 'Home'),
    GlassTab(icon: Icon(Icons.search), label: 'Search'),
    GlassTab(icon: Icon(Icons.person), label: 'Profile'),
  ],
  selectedIndex: _selectedIndex,
  onTabSelected: (i) => setState(() => _selectedIndex = i),
)
```

---

### New: `GlassTabBar.searchable()` — UITabBar + morphing search

Named constructor combining bottom navigation with a morphing glass search pill. Identical API to `GlassTabBar.bottom()` with additional `searchBarConfig` and `controller` parameters.

```dart
GlassTabBar.searchable(
  tabs: [...],
  selectedIndex: _selectedIndex,
  onTabSelected: (i) => setState(() => _selectedIndex = i),
  searchBarConfig: GlassSearchBarConfig(hintText: 'Search...'),
  controller: _tabBarController,
)
```

---

### New: `GlassSegmentedControl` — icon support + scrollable mode

#### Icon + label support (fixed mode)

`segments` now accepts `List<GlassTab>` instead of `List<String>`. Each segment can render:
- **Label only** — `GlassTab(label: 'Weekly')`
- **Icon only** — `GlassTab(icon: Icon(Icons.photo))`
- **Icon + label** — `GlassTab(icon: Icon(Icons.photo), label: 'Photos')` (icon above label)

This matches iOS 26 UISegmentedControl which has supported `UIImage` segments since early iOS.

#### Scrollable mode — 100% parity with original `GlassTabBar(isScrollable: true)`

---

### 🚨 Removed: `GlassTabBar()` inline constructor

The default `GlassTabBar()` constructor has been **removed**. `GlassTabBar` is now exclusively used for structural bottom navigation (`GlassTabBar.bottom()` and `GlassTabBar.searchable()`). 

**Migration:**
For all inline tab bars, pill menus, or scrollable tag lists, use `GlassSegmentedControl()` or `GlassSegmentedControl.scrollable()`. They provide 100% feature parity with the old inline `GlassTabBar`.

```diff
- GlassTabBar(
-   tabs: const [
-     GlassTab(label: 'A'),
-     GlassTab(label: 'B'),
-   ],
-   selectedIndex: _selectedIndex,
-   onTabSelected: (i) => setState(() => _selectedIndex = i),
- )
+ GlassSegmentedControl(
+   segments: const [
+     GlassSegment(label: 'A'),
+     GlassSegment(label: 'B'),
+   ],
+   selectedIndex: _selectedIndex,
+   onSegmentSelected: (i) => setState(() => _selectedIndex = i),
+ )
```


New `GlassSegmentedControl.scrollable()` named constructor for category filter tabs (6+ items). Internally uses `ScrollableSegmentContent` — a dedicated widget that owns scrollable pill physics, gesture handling, and 3-layer rendering. Structurally identical to the old inline `GlassTabBar(isScrollable: true)`, now correctly located in the interactive widget family.

```dart
// Fixed (UISegmentedControl — equal width, 2–6 items)
GlassSegmentedControl(
  segments: const [
    GlassSegment(label: 'All'),
    GlassSegment(icon: Icon(Icons.photo), label: 'Photos'),
    GlassSegment(label: 'Videos'),
  ],
  selectedIndex: _selectedIndex,
  onSegmentSelected: (i) => setState(() => _selectedIndex = i),
)

// Scrollable (category filter tabs — natural width, 7+ items)
GlassSegmentedControl.scrollable(
  segments: List.generate(12, (i) => GlassSegment(label: 'Category ${i + 1}')),
  selectedIndex: _selectedIndex,
  onSegmentSelected: (i) => setState(() => _selectedIndex = i),
)
```

---

### Architecture: Dependency inversion

All tab-bar layout logic now lives in dedicated layout files:

| File | Owns |
|---|---|
| `interactive/shared/scrollable_segment_content.dart` | `ScrollableSegmentContent` — scrollable pill + gesture engine (used by `GlassSegmentedControl.scrollable`) |
| `interactive/shared/segmented_control_internal.dart` | `SegmentedControlContent` — fixed-width pill + gesture engine (used by `GlassSegmentedControl`) |
| `surfaces/shared/tab_bar_bottom_layout.dart` | `TabBarBottomLayout` — full glass bottom shell |
| `surfaces/shared/tab_bar_searchable_layout.dart` | `TabBarSearchableLayout` — search morph shell |

`GlassTabBar` dispatches to these shells. `GlassBottomBar` and `GlassSearchableBottomBar` are now zero-logic shims that delegate to the same shells.

---

### Deprecated — removal in v1.0

#### `GlassBottomBar` → `GlassTabBar.bottom()`

```dart
// BEFORE
GlassBottomBar(
  tabs: [GlassBottomBarTab(icon: Icon(Icons.home), label: 'Home')],
  selectedIndex: _selectedIndex,
  onTabSelected: (i) => setState(() => _selectedIndex = i),
)

// AFTER
GlassTabBar.bottom(
  tabs: [GlassTab(icon: Icon(Icons.home), label: 'Home')],
  selectedIndex: _selectedIndex,
  onTabSelected: (i) => setState(() => _selectedIndex = i),
)
```

#### `GlassSearchableBottomBar` → `GlassTabBar.searchable()`

```dart
// BEFORE
GlassSearchableBottomBar(tabs: [...], ...)

// AFTER
GlassTabBar.searchable(tabs: [...], ...)
```

#### `GlassTabBar()` default constructor → `GlassSegmentedControl`

```dart
// BEFORE
GlassTabBar(
  tabs: [GlassTab(label: 'A'), GlassTab(label: 'B')],
  selectedIndex: _selectedIndex,
  onTabSelected: (i) => setState(() => _selectedIndex = i),
)

// AFTER
GlassSegmentedControl(
  segments: [GlassTab(label: 'A'), GlassTab(label: 'B')],
  selectedIndex: _selectedIndex,
  onSegmentSelected: (i) => setState(() => _selectedIndex = i),
)
```

#### `GlassSegmentedControl.segments: List<String>` → `List<GlassTab>`

```dart
// BEFORE
GlassSegmentedControl(segments: ['Daily', 'Weekly', 'Monthly'], ...)

// AFTER
GlassSegmentedControl(
  segments: [
    GlassTab(label: 'Daily'),
    GlassTab(label: 'Weekly'),
    GlassTab(label: 'Monthly'),
  ],
  ...
)
```

---

### iOS 26 control vocabulary — full mapping

| Widget | iOS 26 equivalent | Glass tier |
|---|---|---|
| `GlassSegmentedControl(...)` | `UISegmentedControl` | Light tint + glass pill |
| `GlassSegmentedControl.scrollable(...)` | Scrollable filter tabs | Light tint + glass pill |
| `GlassTabBar.bottom(...)` | `UITabBar` | Full liquid glass |
| `GlassTabBar.searchable(...)` | `UITabBar` + search | Full liquid glass |

---

### New: Configurable label colors and indicator border radius for bottom bars

`GlassTabBar.bottom()`, `GlassTabBar.searchable()`, `GlassBottomBar`, and `GlassSearchableBottomBar` expose three additional styling parameters:

- **`selectedLabelColor`** — tab label colour when selected, independent of `selectedIconColor`
- **`unselectedLabelColor`** — tab label colour when unselected, independent of `unselectedIconColor`
- **`indicatorBorderRadius`** — pill indicator corner radius, independent of `barBorderRadius` (e.g. `100` for a fully round pill on a subtly curved bar)

All three are optional; omitting them preserves existing behaviour exactly.

```dart
GlassTabBar.bottom(
  tabs: [...],
  selectedIndex: _selectedIndex,
  onTabSelected: (i) => setState(() => _selectedIndex = i),
  selectedLabelColor: Colors.blue,
  unselectedLabelColor: Colors.grey,
  indicatorBorderRadius: 100,
)
```

---

# 0.17.1

## 🐛 Fix — `platformViewBackdrop` toggle no longer snaps the selected-tab indicator ([#112](https://github.com/sdegenaar/liquid_glass_widgets/pull/112) by [@jfhair](https://github.com/jfhair))

Toggling `platformViewBackdrop` at runtime (e.g. switching between a map tab and a Flutter-content tab) caused the selected-indicator pill to snap to the new tab instead of sliding. The spring animation controllers inside the indicator subtree were being re-seeded at their already-settled value because the toggle added or removed the `LiquidGlassBlendGroup` wrapper in `AdaptiveLiquidGlassLayer`, changing the child's depth in the element tree and forcing Flutter to discard and re-inflate the whole subtree via `initState`.

**Fix:** `AdaptiveLiquidGlassLayer` is now a `StatefulWidget` that holds a stable `GlobalKey`. The child is always wrapped in a `KeyedSubtree` with that key, so the element identity is preserved across the wrapper toggle — the indicator's `AnimationController`s survive and the morph continues correctly.

No API changes. No breaking changes.

---

# 0.17.0


## 🔬 iOS 26 Concave Lens Pinch — All Four Pill Widgets

The `indicatorPinchStrength` concave lens warp is now unified across all four interactive pill widgets. During a drag the pill edges curve inward (iOS 26 "through a lens" effect). Fully tunable — `0.0` disables it, `1.0` is maximum distortion.

### New parameters

- **`GlassTabBar.indicatorPinchStrength`** (default `0.4`)
- **`GlassTabBar.indicatorExpansion`** (default `EdgeInsets.symmetric(horizontal: 12, vertical: 8)`)
- **`GlassSegmentedControl.indicatorPinchStrength`** (default `0.4`)
- **`GlassSegmentedControl.indicatorExpansion`** (default `EdgeInsets.symmetric(horizontal: 12, vertical: 8)`)
- **`AnimatedGlassIndicator`** exported from the public API — enables `baseIndicatorSettings.copyWith(...)` from app code.

### Changed defaults (`AnimatedGlassIndicator.baseIndicatorSettings`)

- `glassColor`: `alpha: 0.15` → `alpha: 0.0` — glass pill no longer applies a white tint overlay by default.
- `chromaticAberration`: `GlassDefaults.chromaticAberration` → `0.15` — the iridescent rim fringe is now explicitly set for iOS 26 parity.

### Bug fixes

- **`GlassSegmentedControl` refraction** — labels are now refracted through the glass pill at `GlassQuality.premium` (was rendered in wrong z-order).
- **`GlassTabBar` indicator radius** — resting pill now inherits the tab bar's `borderRadius` (was hardcoded `16 px`).
- **`AnimatedGlassIndicator` settings merge** — partial `indicatorSettings` overrides no longer silently reset `chromaticAberration`.
- **Pinch lens jitter at rest** — icon and label content no longer shimmers through the lens when the pill settles. Root cause: the jelly spring's micro-oscillations (±10 % of `thickness`) were directly amplified into the UV warp. Fixed by applying a quadratic ease-out to the pinch multiplier (`1 − (1 − fade)²`), compressing the near-settled oscillation range ≈10×.

### Try it — Indicator Parity demo

The example app includes a live **Indicator Parity** demo (`Demos → Indicator Parity`) with all four pill widgets side-by-side and real-time sliders for `pinchStrength`, `indicatorExpansion`, and `chromaticAberration`. Use it to tune parameters before writing any code.

## 🌑 Apple Dimming Layer — `LiquidGlassSettings.backerColor` ([#111](https://github.com/sdegenaar/liquid_glass_widgets/pull/111) by [@jfhair](https://github.com/jfhair))

New optional `backerColor` on `LiquidGlassSettings` — a shape-matched color pad composited *behind* the glass, giving a control's content contrast over rich or colorful backdrops (video, maps, photography) where the glass tint alone can't. This is Apple's "dimming layer" guidance from the Human Interface Guidelines (Materials section) and the pattern behind SwiftUI's clear `Glass` variant.

```dart
LiquidGlassSettings(
  glassColor: Color(0x20FFFFFF),
  backerColor: Color(0x59000000), // ~35% black — Apple's starting point
)
```

- **`backerColor`** (`Color?`, default `null`) — the color's alpha *is* the dimming opacity. `null` means no backer, so all existing recipes are untouched.
- Rendered at the widget level (like `shadow`) and clipped to the glass shape via `ClipRRect`, so it composites correctly even over a `PlatformView` — maps, video — where a shader-side tint cannot reach.
- Applies in both light and dark mode, and for flat-edge shapes (a bar over a map is a primary use case).
- Skipped on the grouped path (like shadow) — inserting a `Stack` between grouped glass and its shared layer would break metaball morphing.
- `lerp` fades `backerColor` smoothly from transparent when one side is `null`, rather than snapping at the midpoint.

### Migration

All four widgets share the same tuning API:

```dart
indicatorPinchStrength: 0.4,
indicatorExpansion: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
indicatorSettings: AnimatedGlassIndicator.baseIndicatorSettings
    .copyWith(chromaticAberration: 0.15),
```

---

# 0.16.3

## ✨ `GlassTintBlend` — selectable tint blending path ([#107](https://github.com/sdegenaar/liquid_glass_widgets/pull/107) by [@jfhair](https://github.com/jfhair))

New `GlassTintBlend` enum on `LiquidGlassSettings` to explicitly control how `glassColor` blends with the refracted backdrop, instead of relying entirely on the chroma heuristic.

- `GlassTintBlend.auto` — the default. Existing chroma gate, byte-for-byte unchanged behavior.
- `GlassTintBlend.luminosity` — always preserve backdrop luminosity. For near-neutral tints that need to keep the glassy look rather than flattening to a film.
- `GlassTintBlend.flat` — always impose the tint's brightness. For dimming layers, backing scrims, or deliberate frost-film surfaces.

Fully threaded through `LiquidGlassSettings` (`copyWith`, `lerp`, `props`), both the Premium and Standard shader paths, and preserved through `AdaptiveGlass` elevation rebuilds. Frosted fallback renders flat by construction and ignores the setting.

## ✨ `GlassScrollEdgeEffect.bottomFadeInset` ([#109](https://github.com/sdegenaar/liquid_glass_widgets/pull/109) by [@jfhair](https://github.com/jfhair))

New optional `bottomFadeInset` parameter (default `0.0`) that lifts the bottom fade off the widget's true bottom edge by the specified logical pixels. Fixes cases where the scroll viewport extends below the visible area — such as a bottom sheet whose content box overflows past the screen bottom — causing the bottom fade to anchor off-screen and never appear.

**No breaking changes.** All new parameters are optional with safe defaults.

---

# 0.16.2

## 🐛 Bug Fix — `GlassMenu` / `GlassPopover` rebuild on keyboard open/close

`GlassMenu` and `GlassPopover` were rebuilding on every keyboard open/close event,
even when closed. Caused by `MediaQuery.of(context)` in `didChangeDependencies`
subscribing to `viewInsets`. Fixed by switching to scoped accessors
(`disableAnimationsOf`, `maybeSizeOf`, `textScalerOf`). Regression tests added.

## ✨ Content-luminance scroll-edge scrim ([#106](https://github.com/sdegenaar/liquid_glass_widgets/pull/106) by [@jfhair](https://github.com/jfhair))

The continuous companion to the `contentAwareBrightness` discrete lever. Scroll-edge
fades now track content luminance and dissolve toward a dark color as dark content
scrolls under the bars — matching the native App Store early-darkening behaviour.

- `GlassContentAwareScope.register()` gains `onLuminanceChanged` (brightness callback is now optional). Per-rect mean luminance is delivered from the existing single capture; deliveries are gated on >0.005 movement.
- `GlassScrollEdgeEffect.contentAwareFade` — each edge band registers with the scope and lerps toward `darkFadeColor` as content darkens (`luminanceDarkBelow` / `luminanceLightAbove` thresholds, 280 ms ease-out). Inert without a scope.
- `GlassScaffold.contentAwareEdgeFade` — one flag to enable both bars, composing with `contentAwareBrightness`.
- **Latent wrap-order fix (0.16.0):** `GlassScaffold` was wrapping the body in `GlassContentAwareContent` *after* the edge fade, so the fade overlays were inside the sampled region. With the adaptive scrim this is a feedback loop. Wrap order corrected + regression test added.

## 🐛 `GlassModalSheet` handle-drag fixes ([#106](https://github.com/sdegenaar/liquid_glass_widgets/pull/106))

- Handle drag no longer fights the inner scroll. `_handleDragActive` notifier is set on pointer-down (before the inner `Scrollable` can claim slop), disabling inner scroll for the gesture lifetime. Fixes a freeze when dragging the handle over a `PlatformView`.
- `dragIndicatorColor` now actually reaches the drag indicator — it was silently wired into `_SheetLayout` but never forwarded to `_GlassDragIndicator`.

## 🐛 `GlassEffect` — defer capture when boundary is mid-paint ([#106](https://github.com/sdegenaar/liquid_glass_widgets/pull/106))

`toImageSync` called during a dirty repaint boundary spammed `[GlassEffect] toImageSync failed` in debug and dropped the frame's capture. Guarded with `debugNeedsPaint` check (release-safe, same pattern as `GlassScrollEdgeEffect`).

**No breaking changes.** New parameters are all optional with safe defaults — existing code compiles and behaves identically without changes.

---

# 0.16.1


## 🍎 iOS 26 Indicator Defaults — Parity Calibration

Three indicator defaults have been updated across `GlassBottomBar` and
`GlassSearchableBottomBar` to better match the iOS 26 bottom-bar pill
out of the box. No API changes — all parameters remain fully configurable.

### Changed defaults

#### `indicatorPinchStrength` — `1.0` → `0.4`

The previous default of `1.0` applied the maximum concave lens / pinch effect
during drag. iOS 26's actual pinch is more restrained — `0.4` produces the
characteristic "through a lens" look without over-distorting the edges.

**To restore the previous behaviour:**
```dart
GlassBottomBar(
  indicatorPinchStrength: 1.0,
  ...
)
```

#### `indicatorExpansion` — `EdgeInsets.all(8)` → `EdgeInsets.symmetric(horizontal: 12, vertical: 8)`

The indicator pill in iOS 26 bottom bars is slightly wider than it is tall —
a subtle "landing pad" shape that reads as a rounded rectangle rather than a
near-circle. The new default matches this proportion.

**To restore the previous behaviour:**
```dart
GlassBottomBar(
  indicatorExpansion: const EdgeInsets.all(8.0),
  ...
)
```

#### `AnimatedGlassIndicator` chromatic aberration — `0.0` → `0.15`

The indicator's internal `_baseGlassSettings` now sets
`chromaticAberration: 0.15`. Real iOS 26 glass has a faint iridescent
rainbow fringe at the rim. At `0.15` the effect is a whisper — visible
up close, subliminal during normal use.

**To disable the aberration** pass a full `indicatorSettings` override:
```dart
GlassBottomBar(
  indicatorSettings: LiquidGlassSettings(
    chromaticAberration: 0.0,
    // include other fields you need
  ),
  ...
)
```

### Affected widgets

- `GlassBottomBar` — `indicatorPinchStrength` and `indicatorExpansion`
- `GlassSearchableBottomBar` — `indicatorPinchStrength` and `indicatorExpansion`
- All widgets using `AnimatedGlassIndicator` — `chromaticAberration` baseline

`GlassTabBar` and `GlassSegmentedControl` retain their existing expansion
defaults (`EdgeInsets.all(8.0)`) as their geometry is different from a
bottom navigation bar.

---

# 0.16.0

## 🎨 Content-Aware Light/Dark Adaptation

Glass bars now automatically adapt their icon and label colors to match the
content scrolling behind them — light glyphs over dark content, dark glyphs over
light content — with a smooth cross-fade transition. This matches the iOS 26
behaviour where navigation chrome remains legible regardless of what is visible
underneath.

*Core engine contributed by [@jfhair](https://github.com/jfhair) in [PR #103](https://github.com/sdegenaar/liquid_glass_widgets/pull/103).*

### New widgets

- **`GlassContentAwareScope`** — wraps a screen and owns the sampling engine.
  Captures the content boundary at scroll rate (~5 fps), divides each registered
  control's rectangle into voting cells, and delivers per-control brightness
  verdicts via WCAG contrast ratios and dual-threshold hysteresis.
- **`GlassContentAwareContent`** — marks the sampled content region. Installs a
  `RepaintBoundary` that the scope captures. Controls must be **outside** this
  region (e.g. in `Scaffold.bottomNavigationBar` with `extendBody: true`).
- **`GlassContentAwareBrightness`** — per-control consumer that cross-fades
  between the light and dark `GlassThemeVariant` via `GlassThemeVariant.lerp`.
  Supports an external `brightnessOverride` (for PlatformView escape hatches),
  configurable grid dimensions, and per-control flip duration/curve overrides.

### New parameters on existing widgets

- **`GlassBottomBar`** — `adaptiveBrightness`, `brightnessOverride`,
  `onBrightnessChanged`. Set `adaptiveBrightness: true` to opt in.
- **`GlassSearchableBottomBar`** — same three parameters. Both bars
  automatically wrap in `GlassContentAwareBrightness` when enabled.
- **`GlassScaffold`** — `contentAwareBrightness`. When `true`, the scaffold
  automatically wraps the body in `GlassContentAwareContent` and the entire
  layout in `GlassContentAwareScope`. One flag, no manual widget wiring.

### New API surface

- **`GlassThemeVariant.lerp(a, b, t)`** — interpolates settings, glow colors,
  quality, and border radius between two theme variants. Used internally by the
  cross-fade but available to consumers building custom transitions.
- **`GlassThemeSettings.lerp(a, b, t)`** — interpolates all 9 glass setting
  fields (thickness, blur, glassColor, lightAngle, lightIntensity, etc.).
- **`resolveBarLabelColor(context, brightness)`** — shared utility for bars
  to resolve label color from `CupertinoTheme` given an overridden brightness.

### Usage

The recommended path — one flag on `GlassScaffold`, one on the bar:

```dart
GlassScaffold(
  contentAwareBrightness: true,
  bottomBar: GlassBottomBar(
    adaptiveBrightness: true,
    onBrightnessChanged: (b) => /* flip your own icon colors */,
    tabs: [...],
    selectedIndex: _index,
    onTabSelected: (i) => setState(() => _index = i),
  ),
  body: CustomScrollView(...),
)
```

For custom layouts without `GlassScaffold`, use the standalone widgets directly:

```dart
GlassContentAwareScope(
  child: Scaffold(
    extendBody: true,
    body: GlassContentAwareContent(
      child: ListView(...),
    ),
    bottomNavigationBar: GlassBottomBar(
      adaptiveBrightness: true,
      ...
    ),
  ),
)
```

### Bug fix

- **`GlassThemeVariant.==` / `hashCode` missing `borderRadius`** — fixed a
  pre-existing bug where two variants differing only in `borderRadius` compared
  equal. This caused stale radius during content-aware cross-fades where
  intermediate lerped variants would not trigger rebuilds.

### Polish

- **`_sample()` error reporting** — the bare `catch (_)` in the sampling
  pipeline now reports to `FlutterError` inside an assert closure. Errors are
  still suppressed in release builds but surface in debug mode so programming
  mistakes are visible.
- **Removed redundant `setState`** — `_GlassContentAwareBrightnessState._setBrightness`
  no longer calls `setState` since `AnimatedBuilder` already listens to the
  animation controller and rebuilds on every tick.

### Example app

- **Content-Aware Brightness demo** (new) — dedicated showcase with alternating
  light and dark content bands that force visible bar flips during scrolling.
  Available in the Examples tab.

---

# 0.15.7

## 🌙 Adaptive Brightness Fix

Fixed a bug in `LightweightLiquidGlass` where the shader's internal brightness estimation (`backdropLuma`) was incorrectly reading from the OS-level `MediaQuery.platformBrightnessOf(context)` rather than the inherited Flutter `Theme.of(context).brightness`. 

This ensures that glass surfaces now correctly switch to Light Mode parameters (such as the legibility veil) when the app itself overrides the theme to Light Mode, even if the user's physical device remains in Dark Mode.

---

# 0.15.6

## 🌫️ Scroll Edge Fade — Perceptual Gradient Curve

Replaced the 2-stop linear alpha gradient in `GlassScrollEdgeEffect` with a
multi-stop eased curve that matches the perceptual dissolve of iOS 26.

- **5-stop gradient profiles** for both `soft` and `hard` styles — eliminates
  the "denser in the centre" banding and the visible seam at the fade boundary.
- **`hard` style reworked**: steeper hold → sharper drop curve instead of just
  compressing the soft profile. Height multiplier relaxed from 0.33× to 0.5×.
- **Example app**: Nav Patterns demo now fully brightness-aware (adaptive text
  colours, `GlassStatusBarStyle.auto`, adaptive solid-bar colour).

No API changes. No breaking changes.

---

# 0.15.5

## ✨ Whiten Strength — Light-Mode Legibility Veil

Opt-in whitening ("legibility veil") lifts glass toward white for legibility over
busy light backgrounds — modelling iOS 26's light-mode glass.

- **`LiquidGlassSettings.whitenStrength`** (0.0–1.0, default 0.0): lifts the
  finished glass toward white as the last step of the render. A single
  control-wide value with no spatial seams or halo artifacts.
- **`LiquidGlassSettings.whitenGated`** (default `true`): when gated, the lift
  scales by per-pixel luminance so bright content lifts to white while dark
  content (text, icons) stays crisp. Ungated applies the lift uniformly — useful
  for dark-mode frost effects.
- **Consistent across all three quality tiers** from one knob: Premium
  (fragment shader), Standard (tint lerp), and Minimal (frosted fallback) all
  render the same whitenStrength value consistently.
- **`GlassSearchableBottomBar` whiten-at-bottom**: when a `scrollController`
  is provided, the bar animates its whitening toward full white as the page
  nears the scroll bottom — the iOS light-mode behaviour where content crowding
  under a bar gets the strongest legibility lift.

- **Example app**: Buttons & Shadows demo now includes a real-time whiten
  slider with side-by-side comparison cards and scroll-to-bottom boost preview.

*Contributed by [@jfhair](https://github.com/jfhair) in [PR #100](https://github.com/sdegenaar/liquid_glass_widgets/pull/100).*

## 🎬 Scale-with-Morph — Cohesive Overlay Content Reveal

Menu items and popover content now scale in alongside the liquid morph animation
instead of popping in at the tail. The glass container and its content feel like
a single continuous motion.

- **Items enter the tree at 30% morph progress** (down from 94%) and scale from
  0.5× to 1.0× via an `easeOut` curve alongside opacity. Text and icons visually
  grow with the expanding glass container.
- **Applied to both `GlassMenu` and `GlassPopover`** for consistent overlay
  behaviour across the widget family. Content scales in on open and scales
  back out on close — the morph animation is symmetrical in both directions.
- No new API surface. No breaking changes. Purely visual polish.

*`GlassMenu` scale-with-morph contributed by [@F1orian](https://github.com/F1orian) in [PR #97](https://github.com/sdegenaar/liquid_glass_widgets/pull/97).*

---

# 0.15.4

## ⚡ Render Pipeline Performance Pass — FPS & Battery

Internal optimizations targeting the render object `paint()` hot path and background
capture lifecycle. Zero API changes, zero visual changes. All 2,050 tests passing.

## 🎯 Bottom Bar Lateral Sway

- **Subtle lateral sway on fast pill drags** — `GlassBottomBar` and
  `GlassSearchableBottomBar` now respond with a near-subliminal horizontal
  shift when the interactive pill is flicked quickly, matching iOS 26 bottom
  bar physics. Velocity-gated (slow drags produce no movement) and
  spring-animated back to center on release.

### GPU allocation pressure (FPS)

- **Cached `ImageFilter` in `_RenderLightweightGlass`** — the composed
  blur+saturation `ImageFilter` (and its 20-element `ColorFilter.matrix` list) was
  previously reconstructed on every `paint()` frame for every visible glass widget.
  With 5 glass cards at 60 fps, that's ~300 list allocations/second hitting the GC.
  The filter is now cached on the render object and only rebuilt when `blur` or
  `saturation` changes.
- **Cached `ImageFilter` in `_RenderInteractiveIndicator`** — same optimization
  for the interactive indicator shader path (`GlassEffect`). The brightness+blur
  composed filter is now cached and invalidated only when `blurSigma` changes.
- **Cached `ImageFilter.blur` in `RenderLiquidGlassLayer`** — the premium glass
  layer's `BackdropFilterLayer` blur filter was previously recreated on every
  `paintLiquidGlass()` call, even when the blur sigma hadn't changed. During
  jelly/morph animations (60 fps), this creates an `ImageFilter.blur` object per
  frame per premium glass layer. Now cached and reused.
- **Cached `_shapesWithGeometry` list** — the premium glass `paint()` method
  previously allocated a new list on every frame to collect active geometry
  shapes. It now reuses a cleared instance list, eliminating another per-frame
  allocation on the hot path.
- **Cached light angle trigonometry** — both `_RenderLightweightGlass` and
  `_RenderInteractiveIndicator` now cache `cos(lightAngle)` and `-sin(lightAngle)`
  instead of recomputing them on every `_updateShaderUniforms()` call. Matches the
  caching pattern already used by the premium `LiquidGlassRenderObject._cachedLightDir`.
- **Conditional `alwaysNeedsCompositing`** — both `_RenderLightweightGlass` and
  `_RenderInteractiveIndicator` previously returned `true` unconditionally, forcing
  the framework to create a compositing layer even in the fallback path (null shader
  or zero blur). Now returns `true` only when a `BackdropFilterLayer` will actually
  be pushed. Reduces layer tree depth on low-end devices.

### Battery life

- **Background Ticker auto-suspend** — `LightweightLiquidGlass` runs a Ticker to
  capture the background behind each glass widget via `toImageSync`. Previously,
  this ticker ran at 60 fps permanently — even when the background hadn't changed
  for minutes (e.g. a static bottom bar over a static page). After 3 consecutive
  no-change frames (~50 ms), the ticker now self-suspends. It restarts automatically
  when `didUpdateWidget` detects a configuration change. For a bottom bar with 5 tab
  pills, this eliminates 300 unnecessary method calls/second while idle.

### GC pressure on frame timing path

- **Optimised `GlassQualityAdapter._percentile`** — the Phase 3 runtime percentile
  computation previously called `_window.toList()` + `List.from(data)..sort()` every
  120 frames, creating two heap-allocated lists on the frame timing callback path.
  Now reuses a pre-allocated sort buffer (`List<int>.filled`) that is overwritten
  in-place. Eliminates GC pressure from the very code path that monitors for
  GC-induced frame drops.

### Community contribution

- **Collapsed search indicator stretch feedback** — the collapsed indicator in
  `GlassSearchableBottomBar` now wraps in `LiquidStretch`, giving it the same
  press-scale physics as the normal tab indicator.
  *Contributed by [@g3mf0r](https://github.com/g3mf0r) in [PR #96](https://github.com/sdegenaar/liquid_glass_widgets/pull/96).*

### Widget tree rebuild reduction

- **Shared spring listener in `GlassSearchableBottomBar`** — the three morph-
  animation `AnimationController`s (tab width, search left, search width) each
  had their own anonymous `addListener(() => setState(() {}))` callback. During
  a pill morph all three springs tick every frame, producing three independent
  `setState` calls per frame. Now all three share a single named `_onSpringTick`
  callback — Flutter coalesces the dirty mark so only one rebuild fires. Also
  fixes a subtle listener leak: anonymous lambdas can't be matched by
  `removeListener`, but named methods can.

### Consistency fix

- **`GlassEffect.preWarm()` dummy image** — changed from async `await picture.toImage(1, 1)`
  to synchronous `picture.toImageSync(1, 1)`, matching the `LightweightLiquidGlass`
  pattern. Eliminates a 1-frame async initialization delay for a 1×1 transparent
  texture. Added `picture.dispose()` to prevent a minor leak.

---

# 0.15.3

## `platformViewBackdrop` — Premium Glass Over iOS PlatformViews

New opt-in flag that lets glass bars render correctly over native iOS views
(Google Maps, Apple Maps, WebView, MapLibre, video players) while keeping the
premium indicator animations alive. Previously, developers had to downgrade to
`GlassQuality.standard` on iOS — now they can stay on `premium`.

*Contributed by [@jfhair](https://github.com/jfhair) in [PR #94](https://github.com/sdegenaar/liquid_glass_widgets/pull/94).*

### New parameter: `platformViewBackdrop`

- **`GlassBottomBar`** — new `platformViewBackdrop` parameter. When `true`,
  the bar background renders via live `BackdropFilter` (the premium shader's
  `toImageSync` cannot capture a `UIKitView`), while the premium indicator
  refracts the bar's own icon layer instead of the un-capturable backdrop.
- **`GlassSearchableBottomBar`** — same parameter, applied to both the tab
  indicator and the search pill. The collapsed search button automatically
  falls back to `GlassQuality.standard` over a PlatformView.
- **`AdaptiveGlass` / `AdaptiveGlass.grouped()`** — new `platformViewBackdrop`
  parameter that forces the `BackdropFilter` rendering path even at
  `GlassQuality.premium`.
- **`AdaptiveLiquidGlassLayer`** — new `platformViewBackdrop` parameter that
  skips the `LiquidGlassBlendGroup` wrapper when rendering over a PlatformView.

### Usage

```dart
GlassBottomBar(
  quality: GlassQuality.premium,
  platformViewBackdrop: Platform.isIOS, // ← one line fix
  tabs: myTabs,
  selectedIndex: _index,
  onTabSelected: (i) => setState(() => _index = i),
)
```

### Example app

- **Google Maps demo** — updated to use `platformViewBackdrop: Platform.isIOS`
  instead of the old `Platform.isIOS ? GlassQuality.standard : GlassQuality.premium`
  workaround. The bar now stays at `GlassQuality.premium` on all platforms.

---

# 0.15.2

## GPU SDF Shadows — Light Mode Performance & Metaball Support

Replaced the previous inverse-clip shadow system with GPU SDF shadows that render
directly from the merged geometry matte. This is both a performance improvement
and a visual correctness fix — shadows now correctly follow the liquid metaball
shape during morph animations, which was impossible with the old per-element
`ClipPath` approach.

### Light mode shadows

- **GPU SDF shadow pass** — `RenderLiquidGlassLayer.paintGlass` now includes a
  Pass 0 that draws each `BoxShadow` using the geometry matte image. The matte
  is drawn with `ImageFilter.blur` for the shadow spread, tinted via
  `ColorFilter.mode`, and then the interior is punched out with `BlendMode.dstOut`
  so the glass backdrop filter never samples its own shadow. This replaces the
  widget-level `_InversePillClipper` / `_InverseOvalClipper` `ClipPath` approach.
- **Shadows plumbed through the full stack** — `LiquidGlassSettings.effectiveShadow`
  is now resolved at the `AdaptiveGlass` and `AdaptiveLiquidGlassLayer` level and
  passed through `LiquidGlass.withOwnLayer` → `LiquidGlassLayer` → `_RawShapes` →
  `RenderLiquidGlassLayer`. Dark mode and flat-edge shapes (`borderRadius: 0`)
  correctly receive an empty shadow list.
- **Removed old clip-based shadow system** — deleted `_InversePillClipper`,
  `_InverseOvalClipper` from `GlassBottomBar`, and the equivalent clippers from
  `GlassSearchableBottomBar`. Removed `_wrapWithLightModeShadow` from
  `AdaptiveGlass`. This eliminates ~140 lines of widget-level shadow plumbing and
  the associated `ClipPath` compositing cost.
- **Geometry image exposed to subclasses** — `LiquidGlassRenderObject` now
  exposes `geometryImage` and `geometryLocalBounds` as `@protected` getters so
  `RenderLiquidGlassLayer` can access the matte for shadow rendering.

### `GlassMenu` overlay rendering

- **`AdaptiveLiquidGlassLayer` in menu overlay** — the morph overlay now uses
  `AdaptiveLiquidGlassLayer` instead of raw `LiquidGlassLayer`, ensuring correct
  quality resolution and backdrop blur when the menu is rendered in premium mode.

### Example app

- **Buttons & Shadows demo** — locked to Light Mode (`Brightness.light`) to serve
  as the definitive showcase for GPU SDF shadows. Moved from the Demos tab to the
  Examples tab with updated card gradient and subtitle.
- **Apple Messages demo** — menu trigger buttons now use `useOwnLayer: true` to
  correctly enter the GPU SDF shadow pipeline. Menu glass settings are
  brightness-aware (`Colors.white12` dark / `Color(0x99FFFFFF)` light).
- **Surfaces demo** — `_buildDemoBackground()` now accepts `BuildContext` and
  returns a light frosted gradient in Light Mode instead of the hardcoded dark
  navy gradient that caused unreadable text.

### Bug fixes

- Fixed unused import `snap_rect_to_pixels.dart` in `liquid_glass_layer.dart`.
- Fixed unused `isDark` variable in `glass_menu_internal.dart`.
- Removed unnecessary `package:flutter/material.dart` import from
  `adaptive_liquid_glass_layer.dart` (already provided by `cupertino.dart`).
- Fixed duplicate doc comment in `glass_bottom_bar.dart`.
- Fixed release-mode crash in `GlassScrollEdgeEffect._captureBackground` — 
  `RenderRepaintBoundary.toImage()` throws synchronously on `layer!` when called
  before the first paint completes (layer not yet composited). The
  `debugNeedsPaint` guard only runs inside `assert()` and is stripped in release
  builds. Fixed by deferring the initial capture to a post-frame callback and
  wrapping `toImage()` in `try`/`catch` as a safety net. Falls back to the
  solid-colour gradient overlay on failure. _(reported by [@RuslanTsitser](https://github.com/RuslanTsitser) via [#93](https://github.com/sdegenaar/liquid_glass_widgets/pull/93))_
- Updated `GlassBottomBar` golden test reference image.



# 0.15.1

## Full Light & Dark Mode — Complete Adaptive UI Kit

`liquid_glass_widgets` is now a **fully adaptive** iOS 26 UI kit. Every widget
— buttons, menus, search bars, sliders, switches, sheets, toasts, chips, form
fields, and all surface bars — automatically resolves the correct glass color,
rim lighting, shadow, text, and icon values for both **Light** and **Dark**
mode. No manual configuration required.

This release closes the last remaining light-mode rendering gaps and ships a
reference implementation in the Apple Messages demo that matches the
iOS 26 Messages app in both modes. Run the example app to toggle light and dark mode for all demo pages.

### New features

- **Configurable glass shadow** — `LiquidGlassSettings.shadowElevation` scales the light-mode drop shadow (`0.0` = off, `1.0` = default, `2.0` = double). `LiquidGlassSettings.shadow` accepts a custom `List<BoxShadow>` for full control. Both flow through `globalSettings` (theme-level) and per-widget `settings:`.
- **`GlassShadow` constants** — centralised shadow values (`GlassShadow.elevation`, `.contact`, `.defaults`, `.scaled(double)`) exported for custom widget authors.
- **`GlassButtonGroup.icons()`** — introduced a lightweight group constructor for iOS 26 style segmented icon toolbars. Uses a single `GlassButton` parent to drive cohesive group-level stretch/glow interaction, while children are rendered as zero-overhead stateless tap targets.
- **`GlassMenuController`** — imperative controller for `GlassMenu` with `open()`, `close()`, and `isOpen`. Drives the menu programmatically instead of (or in addition to) tapping the trigger — useful for gesture-arena-driven menus. _(contributed by [@F1orian](https://github.com/F1orian))_
- **`GlassMenu.showDismissBarrier`** — when `false`, suppresses the full-screen tap-to-dismiss barrier so an external gesture owner can keep receiving pointer events while the menu is open. Defaults to `true`. _(contributed by [@F1orian](https://github.com/F1orian))_
- **`GlassMenu.morphFromZero`** — when `true`, the menu body lerps from a zero-size point at the trigger center instead of from the trigger's own dimensions, suppressing the spawn blob (Blob A). For invisible or zero-sized triggers. _(contributed by [@F1orian](https://github.com/F1orian))_
- **`GlassMenuController.setFollowOffset(Offset)`** — nudges the open menu to track a moving anchor in real-time. The offset is added to the captured trigger position each frame and reset on the next `open()`. _(contributed by [@F1orian](https://github.com/F1orian))_

### Light & dark mode improvements

- **Complete adaptive rendering** — all widgets now resolve glass color, rim borders, shadows, text, and icon colors from `CupertinoTheme.brightnessOf(context)`. Switching between light and dark mode requires zero widget-level changes.
- **Light-mode rim borders** — removed the heavy dark rim border on glass surfaces in light mode. Dark mode rim lighting remains fully intact and unchanged.
- **Light-mode drop shadows** — added inverse-clipped drop shadows to glass surfaces in light mode (cards, standalone buttons, bottom bars). Shadows render outside the glass boundary so the backdrop filter doesn't blur them. Note: morphing elements like the search pill do not have shadows to prevent animation artifacts.
- **Standard glass white frost** — standard quality glass in light mode now correctly renders as clean frosted white instead of muddy grey.
- **Dynamic color resolution** — improved internal text and icon styling to accurately resolve `CupertinoColors` against the active theme brightness.
- **`GlassSearchBar` and `GlassTextField` default colors now brightness-aware** — default text, icon, and glow colors now resolve dynamically against `CupertinoTheme.brightnessOf(context)` instead of being hardcoded to white. This ensures correct contrast in both light and dark mode.

### Bug fixes

- Fixed missing `} else {` in `lightweight_glass.frag` that caused PATH B (standard widgets) to run inside PATH A.
- Fixed `GlassSheet` sharp corners on macOS by decoupling top and bottom border radius.
- Fixed `GlassMenu` selection pill alignment and hit-test accuracy when system text scaler is active.
- Fixed `GlassChip` resolving with invisible white text and icons in light mode.
- Fixed Apple Podcasts demo incorrectly forcing dark-mode glass colors in light mode.
- Fixed `GlassFormField` label (`Colors.white`) and helper text (`Color(0x99FFFFFF)`) being invisible in light mode — now resolves from `CupertinoColors.label` / `.secondaryLabel`
- Fixed `GlassPicker` value text (`Colors.white`) and chevron icon (`Colors.white70`) being invisible in light mode — now resolves from `CupertinoColors.label` / `.secondaryLabel`.
- Fixed `GlassPasswordField` lock and eye toggle icons (`Colors.white70`) being invisible in light mode — now resolves from `CupertinoColors.secondaryLabel`.
- Fixed `GlassActionSheet` forcing dark card background (`Colors.black @ 0.65`), dividers, and pressed highlights regardless of brightness — now resolves to light frosted glass in light mode.
- Fixed `GlassToast` forcing dark pill (`Colors.black @ 0.7`) and white text regardless of brightness — background and text now resolve from brightness for correct contrast in both modes.
- Removed unnecessary `import 'package:flutter/material.dart'` from `GlassFormField`, `GlassPicker`, `GlassPasswordField`, and `GlassToast`.
- Fixed `GlassMenu` morph size going negative during spring undershoot on small triggers — `currentWidth`/`currentHeight` now clamped to `>= 0` to prevent debug `BoxConstraints` assertion. _(contributed by [@F1orian](https://github.com/F1orian))_
- Fixed `GlassMenu` sub-pixel Impeller crash — body container is replaced with `SizedBox.shrink()` when dimensions fall below 1.0 logical pixel, preventing 0-area matte rasterisation. _(contributed by [@F1orian](https://github.com/F1orian))_
- Fixed `GlassIconButton` bypassing theme quality chain — `quality` now passes `null` through to `GlassButton.custom()` so `GlassThemeHelpers.resolveQuality` can resolve from ancestor layers, theme, then widget default. _(contributed by [@F1orian](https://github.com/F1orian))_

### ⚠️ Breaking — Removed frosted well overlay from `GlassTextField`

`GlassTextField` no longer applies a hidden internal darkening overlay ("frosted well") on top of the glass surface. Previously, a `DecoratedBox` with `Colors.black.withValues(alpha: 0.12)` plus a top-edge gradient was composited inside the glass shape to simulate an iOS 26 recessed input tray. This has been removed entirely.

**Why:** The frosted well fought against user-specified `glassColor`, making text fields appear darker/muddier than buttons with identical settings. It also caused visible nested border artifacts when the overlay's `BorderRadius.circular()` didn't match the glass surface's `LiquidRoundedSuperellipse` shape — especially with `useOwnLayer: true` and `padding: EdgeInsets.zero`.

**Design philosophy:** `GlassTextField` is a hero surface (search bars, compose bars, app bar inputs) — not a form field nested inside glass cards. `glassColor` is now the single source of truth for appearance, consistent with every other glass widget.

**Migration:** If you relied on the frosted well for visual distinction inside a grouped layout, set a slightly darker `glassColor` on the text field explicitly. Most users will see cleaner, more predictable text fields with no action required.

### Example app

- **Input demos** — replaced `GlassCard` wrappers around form fields with flat `CupertinoColors.systemFill` containers. Glass text fields now render as standalone hero surfaces (`useOwnLayer: true`) inside flat-colored form sections, demonstrating the correct pattern. Glass-in-glass nesting is an anti-pattern.
- **Apple Messages demo** — fully adaptive light and dark mode implementation. Light mode uses the iOS system grouped background (`#F2F2F7`), brightness-aware white glass tint, and dynamic layer separation to enable shadows. Dark mode retains liquid blending via the shared `AdaptiveLiquidGlassLayer`. Press interactions use `persistPressOnDrag: true` and an elevated `ambientBaseLight` in light mode so the pressed state remains visible while holding and dragging off the button edge.


# 0.15.0

## ⚠️ Breaking — API Cleanup & Standardisation

Removes Material-leaning widgets and thin wrappers that don't map to real
iOS 26 components. Standardises the public API for v1.0 readiness. This is a
breaking release — users on `^0.14.0` will not auto-upgrade.

### Deleted widgets

| Widget | Migration |
|---|---|
| `GlassPanel` | Replace with `GlassCard(padding: EdgeInsets.all(24))` |
| `GlassWizard` / `GlassWizardStep` | No direct replacement — use `GlassStepper` for sequential steps |
| `GlassSideBar` / `GlassSideBarItem` | No direct replacement — a proper `UISplitViewController`-style sidebar is planned for post-1.0 |
| `GlassSnackBar` | Replace with `GlassToast` (identical API — `GlassSnackBar` was documented as an alias) |

### `glassSettings` → `settings` rename

The `glassSettings` parameter on 8 widgets has been renamed to `settings` for
consistency. The `Glass` prefix on the widget name already identifies the
settings type — `glassSettings` was redundant.

**Affected widgets:** `GlassBottomBar`, `GlassSearchableBottomBar`,
`GlassSegmentedControl`, `GlassButtonGroup`, `GlassMenu`, `GlassPopover`,
`GlassToolbar`, `GlassPicker`.

**Migration:** Find-and-replace `glassSettings:` → `settings:` in your code.

### `GlassSheet.show()` API Cleanup

Removed dead Material parameters from `GlassSheet.show()` that have no effect in the liquid glass rendering pipeline:
- `backgroundColor`
- `elevation`
- `shape`
- `clipBehavior`
- `constraints`

**Migration:** Remove these parameters from your `GlassSheet.show()` calls. Use `settings` to configure the glass visual appearance, and `margin` / `padding` / `borderRadius` to control the layout and shape.

## 🎨 Content Colour Audit — Adaptive Light/Dark Mode

All hardcoded `Colors.white` / `Colors.black` in widget content layers replaced with `CupertinoColors` adaptive equivalents. Widgets now render correctly in both light and dark mode without requiring a `MaterialApp` ancestor.

**Affected widgets:** `GlassDialog`, `GlassActionSheet`, all interactive and surface widgets.

`GlassPage` is now fully safe to use inside a pure `CupertinoApp` — the `Theme.of` guard no longer throws when no Material ancestor is present.

## 🐛 Bug Fixes

### `GlassSheet` sharp corners (All Platforms)

Fixed a bug where `GlassSheet` would render with completely sharp, square corners on all devices (including iOS and Android). The internal `SafeArea` wrapper was consuming the bottom safe area before the adaptive radius calculation could read it, causing it to incorrectly fallback to `0.0` everywhere. `GlassSheet` now decouples its top and bottom border radii, defaulting to `topBorderRadius: 32.0`, and smartly assigning `bottomBorderRadius` to `32.0` when floating (with margin) or `0.0` when docked.

## ✨ New — `GlassButtonStyle.prominent`

A new button style matching iOS 26's `.prominentGlass` / `.glassProminent`
configuration — thicker, more opaque glass for primary call-to-action buttons.

```dart
GlassButton(
  style: GlassButtonStyle.prominent,
  icon: Icon(CupertinoIcons.plus),
  onTap: () {},
)
```

## ✨ New — `GlassGroupedSection`

A convenience wrapper that groups `GlassListTile`s inside a `GlassCard`,
automatically applying `isLast: true` to the final tile to suppress its
bottom divider — the most common source of bugs.

```dart
GlassGroupedSection(
  header: Text('Network'),
  children: [
    GlassListTile(title: Text('Wi-Fi')),
    GlassListTile(title: Text('Bluetooth')),
    GlassListTile(title: Text('VPN')), // isLast applied automatically
  ],
)
```

## ✨ New — `GlassPageControl`

iOS `UIPageControl` equivalent — dot indicators for paged content (carousels,
onboarding, gallery pages). Features animated capsule-shaped active dot with
glass treatment and optional tap-to-navigate.

```dart
GlassPageControl(
  count: 5,
  currentPage: _currentPage,
  onPageChanged: (page) => _pageController.animateToPage(page,
    duration: Duration(milliseconds: 300),
    curve: Curves.easeInOut,
  ),
)
```

## 📖 README — Glass vs Content design guide

Added a design philosophy section explaining iOS 26's glass hierarchy:
glass for navigation chrome and controls, opaque for content areas.
Repositioned `GlassContainer` as an advanced primitive in the widget catalogue.

### What stays

- **`GlassBackdropScope`** — deprecated no-op stays until 1.0.0 as previously
  committed in the 0.14.0 changelog. Zero cost to keep.
- All other widgets — no changes.

## 🐛 Fix — `GlassMenu` auto-scrolling with large system text

When the user increased system text size, `GlassMenu` would become scrollable
even without `menuHeight` being set. The height calculation now accounts for
`textScaler` so the menu sizes correctly at any accessibility text scale.

## 🐛 Fix — `GlassMenu` selection pill misalignment at large text scale

The sliding selection highlight and hit-test math used the nominal `44px` item
height for positioning, while the actual `GlassMenuItem` widgets grew taller
via `ConstrainedBox` when system text was scaled up. This caused the pill to
drift out of alignment and sometimes produce a "double highlight" effect. All
layout math (`_getItemOffset`, `_calculateIndexFromPosition`, `_isScrollable`)
now uses the `TextScaler`-aware height calculation.

## 🐛 Fix — `GlassMenuItem` / `GlassMenuDivider` / `GlassMenuLabel` Light Mode

These widgets previously hardcoded `Colors.white` for text, icons, and divider
colours, making them invisible on light backgrounds. They now inherit from
`CupertinoTheme.of(context)`:

| Widget | Colour Source |
|---|---|
| `GlassMenuItem` | `theme.textTheme.textStyle.color` → `CupertinoColors.label` |
| `GlassMenuDivider` | `theme.textTheme.tabLabelTextStyle.color` at 15 % opacity |
| `GlassMenuLabel` | `theme.textTheme.tabLabelTextStyle.color` at 45 % opacity |

Custom `iconColor`, `titleStyle`, and `color` parameters still take priority
over the theme default — zero breaking changes.

## 🧹 Core — `CupertinoApp` compatibility

Removed all `Theme.of(context)` dependencies from the core library, replacing them with `CupertinoTheme` and `defaultTargetPlatform`. This ensures glass widgets adapt correctly to dark mode and background colours in pure `CupertinoApp` structures without falling back to Material defaults.

## 🧹 Example app — `CupertinoApp` migration

All 16 standalone demos and the main showcase app have been migrated from
`MaterialApp` to `CupertinoApp`. This is the correct root widget for an iOS 26
glass library — it provides `CupertinoTheme` to the entire widget tree, which
glass widgets depend on for colour resolution.

A `Theme(data: ThemeData.dark(...))` builder is injected below `CupertinoApp`
so that any `Scaffold` widgets in demo pages continue to receive proper Material
theming (background colour, text defaults).

## 🧹 Example app — `GlassMenu` demo controls

Added text-scale slider (1.0×–3.0×) and light/dark theme toggle to the menu
demo. Also added `GlassMenuLabel`, `GlassMenuDivider`, and a destructive
`GlassMenuItem` to the menu items so their theme colour inheritance can be
visually verified.

---

# 0.14.2

## 🧹 Material Artifact Purge

Replaced internal Material primitives with Cupertino-native equivalents for
better iOS 26 fidelity. No public API changes.

- **Tap feedback:** `InkWell` → `GestureDetector` + iOS-style opacity highlight
  in `GlassListTile` and `GlassActionSheet`.
- **Icons:** `Icons.chevron_right`, `Icons.add`, `Icons.remove`, `Icons.info_outline`
  → `CupertinoIcons` equivalents in `GlassListTile` and `GlassStepper`.
- **Colours:** Hardcoded `Colors.green` / `Colors.red` → `CupertinoColors.systemGreen`
  / `CupertinoColors.destructiveRed` across `GlassSwitch`, `GlassBadge`,
  `GlassWizard`, `GlassDialog`, `GlassMenuItem`, and `GlassFormField`.

---

# 0.14.1

## 🐛 Fixed — `GlassScaffold` black background

`GlassScaffold` with no `background:` widget was forcing the inner `Scaffold` to
`Colors.transparent`, rendering black instead of `Theme.scaffoldBackgroundColor`.
Added a `backgroundColor: Color?` parameter; the scaffold now defaults to the
theme colour when no explicit background is provided.

## ✨ Improved — Cancel icon size & customisation

The dismiss `×` button in `GlassSearchableBottomBar` was hardcoded to `size: 16`,
which felt undersized compared to iOS 26. Default bumped to `24`. Both
`GlassSearchBar` and `GlassSearchBarConfig` now expose `cancelIconSize` and
`cancelIcon` so the icon size and glyph are fully overridable.

## ✨ New — `GlassPopover`

A new overlay widget that presents **custom content** in a glass container with
the same liquid morph animation as `GlassMenu`. Use it for tooltips, mini forms,
preview cards, colour pickers, or any content that should appear in a glass
popover — without being limited to a list of menu items.

`GlassPopover` shares `GlassMenu`'s liquid teardrop expansion, spring physics,
auto-positioning, and screen-edge clamping. The `contentBuilder` receives a
`close` callback so popover content can dismiss itself.

```dart
GlassPopover(
  trigger: GlassIconButton(
    icon: Icon(CupertinoIcons.info_circle),
    onPressed: null, // handled by GlassPopover
  ),
  contentBuilder: (context, close) => Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Profile Details',
          style: TextStyle(color: Colors.white, fontSize: 16)),
        SizedBox(height: 12),
        GlassButton(onTap: close, child: Text('Done')),
      ],
    ),
  ),
)
```

**Key parameters:**
- `contentBuilder` — builder for custom popover content, receives a `close` callback
- `trigger` / `triggerBuilder` — the widget that opens the popover on tap
- `popoverWidth` / `popoverHeight` — size control (height defaults to intrinsic)
- `alignment` — manual `GlassMenuAlignment`, or `null` for auto-detect
- `autoAdjustToScreen` — screen-edge clamping (on by default, with 12px padding)
- `barrierDismissible` — whether tapping outside closes the popover (default: true)
- `onOpen` / `onClose` — lifecycle callbacks
- Full `LiquidStretch` and `GlassGlow` support

# 0.14.0

## ⚠️ Breaking — `GlassAppBar` redesigned as pure layout widget

`GlassAppBar` has been fundamentally redesigned from a `StatefulWidget` with its own glass rendering to a lightweight `StatelessWidget` that serves purely as a layout container. This matches iOS 26's actual navigation bar pattern where the bar itself is transparent and glass effects belong on individual interactive elements.

**Removed parameters:**
- `settings` — glass surface settings (the bar no longer renders glass)
- `quality` — glass quality selector
- `useOwnLayer` — layer isolation control
- `scrollController` — scroll-driven glass transition
- `scrollEdgeThreshold` — scroll fade threshold

**New parameter:**
- `buttonSettings: LiquidGlassSettings?` — provides default glass settings to all descendant `GlassButton` widgets via `DefaultButtonSettings` (a new `InheritedWidget`). Individual buttons can still override with their own `settings`.

**Migration:**

```dart
// Before (0.13.x) — scroll-driven glass bar:
GlassAppBar(
  title: Text('Title'),
  scrollController: _ctrl,
  scrollEdgeThreshold: 50.0,
  settings: LiquidGlassSettings(blur: 15),
  quality: GlassQuality.premium,
)

// After (0.14.0) — transparent layout bar:
GlassAppBar(
  title: Text('Title'),
  buttonSettings: LiquidGlassSettings(
    glassColor: Color(0x33FFFFFF),
    thickness: 20,
  ),
)
// Use GlassScaffold.header + headerScrollController for fading headers.
```

Apps that relied on `GlassAppBar.scrollController` for scroll-driven glass should migrate to `GlassScaffold` with its `header` / `headerScrollController` parameters (see below).

## ✨ New — `GlassScaffold` — one-widget page layout

A brand new scaffold that replaces the manual assembly of `GlassPage` + `Scaffold` + `GlassScrollEdgeEffect` + `Stack` with a single widget. Handles z-ordering (bars always above body), edge fading, safe-area padding, and glass layer setup automatically.

### `header` + `headerScrollController` + `headerFadeDistance`

A fixed header widget positioned below the status bar that fades out as the user scrolls — matching the iOS 26 large-title pattern used by Apple Music ("Listen Now"), Apple Podcasts, and similar apps.

```dart
GlassScaffold(
  header: Text('Listen Now', style: largeTitle),
  headerScrollController: _scrollController,
  headerFadeDistance: 60.0,
  body: CustomScrollView(
    controller: _scrollController,
    slivers: [...],
  ),
)
```

The header is wrapped in `IgnorePointer` only when fully faded (opacity == 0), so tappable elements remain interactive at full visibility.

### `bodyOverlays`

Optional list of widgets rendered between the body and the navigation bars in z-order. Designed for floating elements like Apple Music's play-bar pill that need to render above scrollable content but below the bottom bar.

```dart
GlassScaffold(
  bodyOverlays: [
    AnimatedPositioned(
      bottom: isMiniMode ? miniBottom : aboveBarBottom,
      left: 20, right: 20,
      child: PlayBarPill(),
    ),
  ],
  body: scrollContent,
)
```

### `AnnotatedRegion` status bar fix

`GlassScaffold` now wraps the internal `Scaffold` in an `AnnotatedRegion<SystemUiOverlayStyle>` so that the `statusBarStyle` setting correctly overrides `CupertinoPageRoute`'s own region. Previously, pages without a `GlassAppBar` could lose their status bar icon styling when pushed via `CupertinoPageRoute`.

### Improved isolation strategy

`GlassScaffold` now wraps app bar and bottom bar in `GlassIsolationScope(isolated: false, defaultQuality: GlassQuality.premium)` instead of the previous `GlassIsolationScope(isolated: true)`. This means bar buttons join the page-level glass blend group (shared backdrop capture) rather than creating their own layers — saving GPU cost. Stack paint order already guarantees bars render on top of body content.

### Stable `ValueKey`s on stack children

All conditional children (header, app bar, bottom bar) now have explicit `ValueKey`s so Flutter tracks them by identity rather than position. This prevents unmount/remount cycles (and loss of animation state) when toggling the header on and off.

> See `example/lib/demos/nav_bar_patterns_demo.dart` for complete `GlassScaffold` usage patterns.

## ✨ New — `GlassIsolationScope.defaultQuality`

`GlassIsolationScope` gains a `defaultQuality: GlassQuality?` parameter that provides a quality hint for descendants without requiring explicit `quality:` on each widget. This is separate from `isolated` — a scope can be de-isolated (for grouping) while still providing a premium quality default.

`GlassThemeHelpers.resolveQuality` now checks `scopeDefault` and skips inherited page-level quality when a scope provides a `defaultQuality`. This fixes a regression where bar buttons inside `GlassScaffold` would inherit the page's `standard` quality instead of getting the bar's intended `premium`.

## ✨ New — `DefaultButtonSettings` InheritedWidget

A new `InheritedWidget` in `glass_app_bar.dart` that provides default `LiquidGlassSettings` to descendant `GlassButton` widgets. `GlassButton` now checks `DefaultButtonSettings.of(context)` as a fallback between explicit `settings` and inherited layer settings.

## ✨ New — `AdaptiveGlass` interactive auto-promotion

`AdaptiveGlass` now automatically promotes interactive elements (`isInteractive: true`) to their own compositing layer in premium mode. This gives buttons the prominent independent refraction that matches iOS 26's button design, rather than softly blending them into the page blend group. The own-layer wrapper de-isolates children via `GlassIsolationScope(isolated: false)` so nested glass (e.g. tab items inside a bottom bar) groups correctly with the button's layer.

## 🐛 Fix — `GlassBottomBar` extra button z-order

Fixed a compositing z-order issue where the jelly tab indicator would incorrectly render behind the extra trailing button. The internal layout has been restructured from a `Row` to a `Stack` with explicit paint ordering — the extra button is painted first (bottom of z-order), and the tab indicator is painted last (top). This matches the existing pattern in `GlassSearchableBottomBar`.

## 🐛 Fix — `GlassSearchableBottomBar` pill z-order

Fixed the paint order of the search pill and tab pill in `GlassSearchableBottomBar`. The search pill is now painted first (bottom of stack) and the tab pill last (top), so the glass indicator correctly renders on top when it overlaps the search pill during tab transitions.

## 🐛 Fix — `mounted` guards in gesture handlers

Added `if (mounted)` guards before every `setState()` call in `TabDragGestureMixin`, `TabIndicator`, and `SearchableTabIndicator`. Pointer events (`onPointerDown`, `onPointerUp`, `onPointerCancel`) and drag gesture callbacks can fire after the widget has been unmounted during rapid tab switching or page transitions, causing `setState() called on disposed widget` exceptions in debug mode. These guards are zero-cost safety nets.

## 🔄 Changed — Nav bar patterns demo

Removed three `GlassAppBar` demo patterns that used the now-deleted scroll-driven glass API:
- ~~Scroll-Driven Glass~~ (transparent → glass on scroll)
- ~~Static Glass~~ (always-on glass surface)
- ~~Large Title Glass on Scroll~~ (combined collapsing + glass materialisation)

Added a new "Fade Header (No App Bar)" pattern demonstrating the `GlassScaffold.header` fade approach (Apple Music / Podcasts style).

## 🔄 Changed — Example app restructured

### Showcase app uses `GlassScaffold`
The main showcase app (`main.dart`) now uses `GlassScaffold` instead of manually composing `GlassPage` + `Scaffold` + `bottomNavigationBar`. Added a fourth tab ("Examples") and redesigned the Widgets tab with a 2-column card grid.

### Apple demos migrated to `GlassScaffold`
All four Apple demo apps have been migrated from manual `Scaffold` + `Stack` + `GlassScrollEdgeEffect` composition to `GlassScaffold`:

- **Apple Messages** — `GlassScaffold` handles positioning, z-ordering, and edge fading automatically. 8 lines changed.
- **Apple Music** — uses `GlassScaffold.header` for the "Listen Now" fade header, `bodyOverlays` for the floating play pill. Major simplification (294 lines changed).
- **Apple News** — migrated to `GlassScaffold`. Removed unnecessary nested `Stack`. 57 lines changed.
- **Apple Podcasts** — uses `GlassScaffold.bodyOverlays` for the mini-player pill. 372 lines changed.

### Category pages re-indented
All 6 showcase category pages (containers, feedback, input, interactive, overlays, surfaces) have been re-indented for consistency. No functional changes.


## 🐛 Fix — Impeller backdrop visual corruption

Fixed a critical rendering issue where `GlassAppBar` buttons would lose their glass background (rendering as invisible) when multiple `LiquidGlassLayer`s shared a single root `BackdropGroup` (via `GlassBackdropScope`). On Impeller, sharing a `BackdropKey` across multiple `RepaintBoundary` layers caused the engine to bind stale or incorrect backdrop textures.

**Root cause:** The shared `BackdropGroup` architecture assumed that all glass surfaces could safely share a single GPU backdrop capture. On Impeller's tile-based renderer, this created a race between layers trying to use the same `BackdropKey`, causing visual corruption (backgrounds vanishing, ghost artifacts during route transitions).

**Fix:** Each `LiquidGlassLayer` now creates its own isolated `BackdropGroup` → `RepaintBoundary` subtree. This ensures every glass surface captures only its own clipped bounding box — a ~30× reduction in GPU bandwidth compared to the previous full-screen capture, and eliminates cross-layer texture conflicts entirely.

## ⚠️ Deprecated — `GlassBackdropScope`

`GlassBackdropScope` is now a no-op and can be safely removed from your widget tree. Each glass layer manages its own backdrop isolation automatically. `GlassPage` continues to work exactly as before — no migration needed for apps using `GlassPage`.

Apps using `GlassBackdropScope` directly will see a deprecation warning but will compile and run without issues. Remove the widget at your convenience; it will be deleted in 1.0.0.

## 🔄 Changed — `GlassInteractionSettings` is now the canonical interaction API

`GlassInteractionSettings` (introduced in 0.13.0) is now the recommended way to configure all interaction physics app-wide. Pass it via `GlassThemeData.interaction` inside `LiquidGlassWidgets.wrap()`:

```dart
runApp(LiquidGlassWidgets.wrap(
  child: const MyApp(),
  theme: GlassThemeData(
    interaction: GlassInteractionSettings(
      stretch: 0.2,              // subtler drag-following globally
      interactionScale: 1.03,    // less scale-up on press
      resistance: 0.01,          // drag damping factor
      anchorStretch: true,       // iOS 26 rubber-band from anchor
      anchorStretchSettings: AnchorStretchSettings(
        intensity: 0.8,
        squashFactor: 0.15,
      ),
    ),
  ),
));
```

Set `stretch: 0.0` to disable drag-following app-wide while keeping press-scale. Individual widgets can still override any value via their own `stretch:` / `interactionScale:` parameters.

---

# 0.13.0

## ✨ New — Anchor Stretch, Ambient Light, and Interaction Physics

### `AnchorStretchSettings` — fine-tuned stretch feel

A new configuration class for `LiquidStretch` that controls how widgets deform when pressed and dragged. Widgets now stretch *from their anchor point* toward the drag direction — matching iOS 26 button physics where the surface rubber-bands from its resting position rather than free-following the finger.

```dart
GlassButton(
  anchorStretchSettings: AnchorStretchSettings(
    intensity: 0.8,       // more stretchy
    squashFactor: 0.3,    // perpendicular compression
    translationDamping: 0.15, // center-shift toward finger
    bounciness: 0.2,      // elastic snap-back overshoot
  ),
)
```

All parameters have sensible defaults matching iOS 26 behaviour. Most developers won't need to change them.

### `GlassButton.ambientBaseLight` — surface luminosity

A subtle white overlay (default `0.08`) applied during press/drag interactions. Simulates iOS 26 surface luminosity — when the directional glow tracks off-edge, the button still maintains a faint lit appearance rather than going completely dark.

### `GlassButton.persistPressOnDrag`

Controls whether the pressed visual state persists when the user's finger drags outside the button bounds. Defaults to `true`, matching iOS 26 behaviour where buttons stay visually pressed during drag-off and only release on pointer-up. Set to `false` for the traditional behaviour where leaving the hit-test area cancels the press.

### `GlassPage.settings` — page-level glass configuration

`GlassPage` now accepts an optional `settings: LiquidGlassSettings` parameter and internally wraps its child in an `AdaptiveLiquidGlassLayer`. This means all glass widgets inside the page (`GlassAppBar`, `GlassCard`, `GlassButton`, etc.) automatically inherit the page's glass settings — no need to set `useOwnLayer: true` or pass `settings:` to each widget individually.

```dart
GlassPage(
  settings: LiquidGlassSettings(
    glassColor: Color.fromRGBO(28, 28, 30, 0.8),
    thickness: 30,
    blur: 4,
  ),
  child: Scaffold(...),
)
```

When `settings` is null, the layer inherits from `GlassTheme` or uses defaults.

### `GlassScaffold` — comprehensive structural layer

A new structural widget that coordinates interactions between `GlassAppBar`, `GlassBottomBar`, and the page body. It automatically handles edge-to-edge layout, scroll bleeding, and isolates glass rendering layers for maximum performance. This replaces the need to manually compose `AdaptiveLiquidGlassLayer` and `GlassIsolationScope` at the page root.

### `GlassInteractionSettings` Theme

Added a dedicated theme extension to globally configure interaction physics across all glass widgets — stretch, press scale, drag resistance, anchor stretch, and anchor stretch fine-tuning. No more passing interaction parameters to every widget manually.

```dart
GlassThemeData(
  interaction: GlassInteractionSettings(
    stretch: 0.2,              // subtler drag-following globally
    interactionScale: 1.03,    // less scale-up on press
    resistance: 0.01,          // drag damping factor
    anchorStretch: true,       // iOS 26 rubber-band from anchor
    anchorStretchSettings: AnchorStretchSettings(
      intensity: 0.8,
      squashFactor: 0.15,
    ),
  ),
)
```

Set `stretch: 0.0` to disable drag-following app-wide while keeping press-scale. Individual widgets can still override any value.

## 🐛 Fixes & Improvements

### Wide Button Stretch Distortion
Fixed a rendering artifact where very wide `GlassButton`s would exhibit severe shape distortion at the extreme edges during horizontal stretch physics.ts.

### `GlassSearchBarConfig.cursorColor` — cursor follows Flutter theme by default

Thanks to [@jfhair](https://github.com/jfhair) for [PR #71](https://github.com/sdegenaar/liquid_glass_widgets/pull/71). 🙏

`GlassSearchableBottomBar`'s expanded search field now exposes a `cursorColor` knob via `GlassSearchBarConfig`, and the default behaviour aligns with Flutter convention — the cursor follows the standard theme-resolution chain (`Theme.of(context).textSelectionTheme.cursorColor` → `CupertinoTheme.primaryColor` on iOS → `Theme.of(context).colorScheme.primary`) rather than being hard-coupled to `textColor`.

Apps that want the previous behaviour — cursor matching `textColor` — can opt in explicitly:

```dart
GlassSearchBarConfig(
  textColor: Colors.white,
  cursorColor: Colors.white,  // ← previously implicit
)
```

> **⚠ Breaking change.** Apps that set a `textColor` and rely on the cursor implicitly matching it will see their cursor colour change to whatever their `Theme.of(context).colorScheme.primary` is (typically `Colors.blue` if untouched). Two-line migration above.

## 🐛 Fix — Premium stretch edge clipping

Premium-quality `GlassButton` could exhibit jagged rasterization edges during stretch deformation. The Impeller `LiquidGlassLayer` rasterizes at its native resolution, which doesn't perfectly align with the deformed shape boundary during stretch.

Fixed by wrapping the premium glass surface in a vector `ClipPath` at the shape boundary. This renders at screen resolution every frame while preserving full refraction, chromatic aberration, and 3D specular — no quality downgrade needed.

## 🐛 Fix — Mali GPU crash guard

`render_liquid_glass_geometry.dart` now guards against zero and negative dimensions in both `render()` and `renderAsync()`. During jelly animations or rapid layout transitions (modal expansion, tab switching), `matteBounds` can momentarily collapse to zero dimensions — producing an invalid GPU texture request that crashes Mali drivers.

The fix returns a minimal 1×1 fallback cache for zero-dimension frames. Additionally, `matte.toImageSync()` is wrapped in a `try/catch` to handle Mali driver failures gracefully — returning a safe fallback instead of crashing the app. The next paint frame rebuilds the geometry with valid dimensions automatically.

## 🐛 Fix — Searchable bottom bar collapsed shape

The collapsed search button and tab indicator in `GlassSearchableBottomBar` used `LiquidRoundedSuperellipse` even when collapsed to a square. A superellipse with `borderRadius: 32` on a 50×50 square has subtle flat segments between the arcs — invisible at rest but clearly distorted during stretch deformation.

Fixed by switching to `LiquidOval` when constraints are square (within 2px tolerance), which renders a mathematically perfect circle that stretches uniformly. During the collapse animation (when the width is still wider than the height), the superellipse is used to avoid a squashed oval appearance.

## 🎨 Visual — iOS 26 thin glass defaults

The three default theme variants have been standardised to match the thin, refractive glass aesthetic of iOS 26:

| Property | Dark | Light | Minimal |
|----------|------|-------|---------|
| thickness | 40 → **10** | 20 → **12** | 30 → **10** |
| blur | 5 → **4** | 6 → **5** | 12 → **8** |
| lightIntensity | 1.5 → **0.7** | 1.2 → **0.85** | unchanged |
| lightAngle | unset → **135°** | unset → **135°** | unchanged |
| chromaticAberration | unset → **0.01** | 0.3 → **0.02** | unchanged |

> **⚠ Visual change.** Apps using `GlassThemeVariant.dark`, `.light`, or `.minimal` without explicit `LiquidGlassSettings` overrides will see thinner, subtler glass. This is intentional — the previous defaults were heavier than the native iOS 26 aesthetic. If you prefer the heavier look, set explicit `thickness` and `blur` values in your `GlassThemeData`.

## ⚠️ Semi-Breaking — `GlassAppBar` transparent by default

`GlassAppBar` now renders a **transparent** navigation bar by default — no glass surface, no specular rim. This matches iOS 26's actual navigation bar pattern where the glass effect is on individual buttons, not the bar itself.

Previously, `GlassAppBar` always wrapped its content in an `AdaptiveGlass` surface with `LiquidGlassSettings(blur: 15)`. This created a visible glass rectangle behind the title and actions — a Material-style app bar with glass paint, not an iOS 26 navigation bar. A better version of this to come next

To opt in to a glass background (e.g. for scroll-edge transitions), pass explicit `settings`:

```dart
// Before (0.12.x) — glass was always on:
GlassAppBar(title: Text('Title'))

// After (0.13.0) — transparent by default:
GlassAppBar(title: Text('Title'))  // transparent, iOS 26 style

// Opt-in glass background:
GlassAppBar(
  title: Text('Title'),
  settings: LiquidGlassSettings(blur: 15, thickness: 10),
)
```

Additionally, `quality` now defaults to `null` (inherits from ambient scope) instead of `GlassQuality.premium`.

## 🎨 Visual — Specular rim refinement

Standard/minimal quality glass surfaces now render a more refined specular inner-border rim:

- **True inner border** — the specular stroke is now clipped to its inner half via `_ShapeClip`, creating an optically correct glass-edge reflection instead of a center-straddling stroke that bleeds outside the shape boundary.
- **Organic overlay blending** — `BlendMode.overlay` replaces `BlendMode.srcOver`, so the rim reacts to the background colour underneath rather than appearing as a flat white line. Darker backgrounds produce subtler rims; lighter backgrounds produce brighter ones.
- **Flat-edge suppression** — shapes with `borderRadius: 0` (used by `GlassAppBar`, `GlassSideBar`, `GlassToolbar`) no longer render the specular rim. On full-width flat surfaces, the rim looked like a Material divider line rather than an internal glass reflection.

Only affects standard and minimal quality. Premium quality uses Impeller's native `LiquidGlassLayer` which has its own refraction-based edge rendering.

## ⚡ Performance — Quality adapter tuning

- **Faster degradation** — Phase 3 runtime monitoring now triggers a quality step-down after 2 consecutive over-budget windows (previously 3), reducing reaction time from ~6 seconds to ~4 seconds. This means devices that genuinely can't sustain their assigned quality level are protected sooner.
- **Documentation updated** — removed provisional calibration warnings from warmup threshold docs. The 20ms premium / 28ms standard thresholds are now considered validated.

## ⚠️ Semi-Breaking — `LiquidStretch.resistance` default

The default `resistance` value for `LiquidStretch` has changed from `0.08` to `0.01`. This makes all stretch interactions feel more responsive and fluid — closer to the iOS 26 native feel. The previous value was overly dampened.

All widgets using `LiquidStretch` without explicitly setting `resistance` (including `GlassButton`, `GlassCard`, `GlassContainer`, `GlassMenu`) will feel stretchier. To restore the previous behaviour:

```dart
LiquidStretch(
  resistance: 0.08, // previous default
  child: ...,
)
```

## 🧪 Tests — 1898 passing (+124 new)

- New `GlassButton` tests: `persistPressOnDrag` true/false behaviour, default values, cancel paths.
- New `GlassSearchBarConfig.cursorColor` tests: default null, explicit value, independence from `textColor`.
- Updated `glass_quality_adapter` tests for `degradeWindowCount: 2`.
- Updated stretch tests for new `resistance` default.
- Updated `GlassAppBar` defaults test for transparent-by-default change.
- Updated golden tests for specular rim flat-edge suppression.

## 📦 Example app

- **Keypad lock screen demo** — new full-screen demo showcasing `GlassButton` in a PIN-entry layout.
- **Restructured showcase pages** — all category pages (containers, feedback, input, interactive, overlays, surfaces) reorganised for cleaner presentation. More work to come...

---

# 0.12.8

## 🐛 Fix — `GlassTextField` reverted to v0.12.4 + icon drift fix

- **Reverted to v0.12.4** — restored exact line-count and layout logic. The v0.12.6–0.12.7 changes introduced regressions (line breaks at wrong character boundary, icons pinned to container bottom).
- **Fixed icon drift under system text scaling** — in fixed-height mode, icons are now always centred relative to the container rather than relative to the text row. This prevents icons from shifting position when users change system text scaling. In dynamic-height mode (no `height` parameter), `iconAlignment` is respected as before.

Thanks [@g3mf0r](https://github.com/g3mf0r) for the detailed testing.

---

# 0.12.7

## 🐛 Fix — `GlassTextField` icon alignment (retained) + line-count regression fix

- **`iconAlignment: .end` no longer drifts under system Large Text.** The `Center` widget wraps only the `TextField`, not the entire icon `Row`, so `CrossAxisAlignment.end/.start` works correctly against the full container height. *(retained from 0.12.6)*
- **Reverted line-count measurement** back to `renderBox.size.width` (the v0.12.4 approach). The v0.12.6 `RenderEditable` width change caused line breaks to fire a couple of characters early. Thanks [@g3mf0r](https://github.com/g3mf0r) for catching this.

---

# 0.12.6

## 🐛 Fix — `GlassTextField` icon alignment and line-count accuracy

- **`iconAlignment: .end` no longer drifts under system Large Text.** The `Center` widget now wraps only the `TextField`, not the entire icon `Row`, so `CrossAxisAlignment.end/.start` works correctly against the full container height.
- **Line-count measurement is now pixel-perfect.** `_measureLineCount` walks the render tree to find the actual `RenderEditable` and uses its layout width (which accounts for the internal `_caretMargin` ≈ 3 px). Falls back gracefully if the render walk fails.

---

# 0.12.5

## ✨ New — `GlassMenu.onClose` callback

Added `onClose: VoidCallback?` to `GlassMenu`. Fires when a close is triggered
(barrier tap, trigger re-tap, or item selection), before the animation completes.
Useful for synchronising external state such as a `GlassMorphController`.

Thanks to [@g3mf0r](https://github.com/g3mf0r) for the contribution ([#67](https://github.com/sdegenaar/liquid_glass_widgets/pull/67)).

---

# 0.12.4

## 🐛 Fix — `GlassTextField` layout and reactivity

### `onLineCountChanged` fires correctly under fixed-height constraints

The `onLineCountChanged` callback silently stopped firing after the first
measurement when the field was inside a fixed-height container (e.g.
`SizedBox(height: 46)` or `height: 46` on the field itself). The internal
guard used `size == _lastTextFieldSize` — but a fixed outer height keeps the
`RenderBox` size constant, so the guard always exited early after the first
call. The fix replaces the size-equality guard with a `(text, constrainedWidth)`
guard: the callback fires whenever the text content or available wrapping width
changes, regardless of what the outer height is doing.

This also resolves the stale-state reactivity bug where `_lines` stored in
`State` stopped updating `borderRadius` after re-opening the keyboard.

### Placeholder and text stay vertically centred under system Large Text

When `height` is specified (fixed-height mode), the outer `padding`'s vertical
component was applied inside the `SizedBox`, pushing placeholder text and icons
downward when the user enabled a large system font. The field now strips
vertical padding in fixed-height mode and centres the text row via `Align`,
matching the behaviour of `GlassSearchBar`. The `padding` parameter's
horizontal values are unchanged.

## ✨ New — `bottom` panel for `GlassTextField` and `GlassTextArea`

Both widgets now accept an optional `bottom` widget that renders below the text
area inside the same glass card. Use it to build the "rich composer" pattern — a
text input on top with an action bar, attachment strip, or formatting toolbar
below, all sharing one glass surface:

```dart
GlassTextField(
  maxLines: 5,
  minHeight: 44,
  maxHeight: 160,
  bottom: Padding(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Row(
      children: [
        IconButton(icon: Icon(Icons.attach_file), onPressed: _attach),
        const Spacer(),
        IconButton(icon: Icon(Icons.send), onPressed: _send),
      ],
    ),
  ),
)
```

The panel renders inside the glass surface alongside the text area.
Callers can add a `Divider` between the text area and the panel if a visual
separator is desired. Not available on `GlassTextField.search` (that
constructor is single-line only; `bottom` is always `null` there).

---

# 0.12.3

## 🎨 Visual — Slider & Switch thumb refraction tuning

- **`GlassSlider` thumb** — increased `refractiveIndex` (1.15 → 1.3) and `thickness` (10 → 13) for a more pronounced glass lens feel. Reduced `glassColor` alpha (0.1 → 0.08), `lightIntensity` (2.0 → 1.8 premium), `baseAlphaMultiplier` (0.2 → 0.08 premium), and `edgeAlphaMultiplier` (0.4 → 0 premium) for a cleaner, more transparent thumb.
- **`GlassSwitch` thumb** — reduced `refractiveIndex` (1.15 → 1.12) and `glassColor` alpha (0.1 → 0.08) for subtler refraction.
- **Material fade via `Opacity` widget** — slider thumb now uses widget-level `Opacity` (matching `GlassSwitch` pattern) instead of color alpha for the press-down fade. Critical for Impeller: properly removes the child from the compositing tree so native refraction shows through.

## ⚡ Jelly physics — spring-based velocity

- **`GlassSlider` jelly** — replaced raw `_velocity` tracking with a `SingleSpringController` feeding `buildJellyTransform`. Produces smooth squash/stretch with natural deceleration and elastic bounce-back, matching the tab bar / bottom bar pill feel. `maxDistortion` raised (0.25 → 0.6), `velocityScale` lowered (30 → 2) to account for the spring's normalised 0→1 position range.

---

# 0.12.2

## ✨ New — `GlassTextField` enhancements

Three community-requested features for `GlassTextField` (and `GlassTextArea`):

### Explicit size properties

`height`, `minHeight`, and `maxHeight` give direct control over the field's dimensions — no wrapping `SizedBox` needed:

```dart
// Fixed height — matches GlassSearchBar's 44pt:
GlassTextField(height: 44, placeholder: 'Search')

// Constrained range — grows with content:
GlassTextField(minHeight: 44, maxHeight: 200, maxLines: 10)
```

`height` is mutually exclusive with `minHeight`/`maxHeight` (assertion enforced).

### `onLineCountChanged` callback

Fires whenever the number of **rendered** lines changes (accounting for text wrapping, not `\n` characters). Also fires on initial build. Uses the `TextField`'s own `RenderBox` height — no external `TextPainter` math, so it works correctly with text scaling and system accessibility settings.

```dart
GlassTextField(
  maxLines: 6,
  onLineCountChanged: (lines) {
    setState(() => _borderRadius = lines > 1 ? 8.0 : 20.0);
  },
)
```

### `iconAlignment` parameter

Controls where prefix/suffix icons sit when the field spans multiple lines:

```dart
// Pin send button to bottom — chat composer pattern:
GlassTextField(
  maxLines: 6,
  iconAlignment: CrossAxisAlignment.end,
  suffixIcon: Icon(Icons.send),
)
```

Accepts `CrossAxisAlignment.start` (top), `.center` (default), or `.end` (bottom). No visible effect on single-line fields.

All three features are forwarded through `GlassTextArea`.

### `GlassTextField.search` named constructor

A new convenience constructor that pre-configures `GlassTextField` with compact search-bar defaults: `height: 44`, `iconSpacing: 8`, `padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)`, `borderRadius: 22`, and `textInputAction: TextInputAction.search`. Eliminates the boilerplate previously required to match `GlassSearchBar` visuals:

```dart
GlassTextField.search(
  placeholder: 'Search messages…',
  prefixIcon: Icon(CupertinoIcons.search, size: 20),
  useOwnLayer: true,
)
```

`GlassSearchBar` now uses this constructor internally, reducing duplicated decoration code.

## 🐛 Fix

- **`onLineCountChanged` now fires on programmatic controller changes** — Previously the callback only responded to physical keyboard input (`TextField.onChanged`). Setting `controller.text = '...'` or calling `controller.clear()` (e.g. in a chat "Send" handler) did not re-measure the line count. The widget now actively listens to the `TextEditingController` and re-measures on any text mutation.

- **Suffix icon spacing now respects `iconSpacing`** — The gap before the suffix icon was hard-coded to 12px while the prefix icon correctly used `widget.iconSpacing`. Both sides now use the same parameter.

# 0.12.1

## 🐛 Fix — eliminate rectangular blur halo over PlatformViews (iOS Impeller)

`LightweightLiquidGlass` and `_FrostedFallback` previously wrapped their glass surface in `ClipPath(ShapeBorderClipper(...))`. When the parent was an iOS PlatformView (e.g. `mapbox_maps_flutter` `MapWidget`, `video_player` on iOS), the descendant `BackdropFilter`'s rectangular blur output leaked past the rounded clip — visible as a faint square halo around the rounded glass shape, most obvious when light backdrop content scrolled underneath.

Flutter framework [PR #177551](https://github.com/flutter/flutter/pull/177551) (merged Dec 2025, shipped in 3.41.0-0.0.pre+) fixed this at the engine level by forwarding `ClipRRect` clip data to the iOS PlatformView mutator stack — but **only `ClipRRect`, not `ClipPath`**, even when the path inside is mathematically a rounded rect.

This release routes shapes that resolve to a `RoundedRectangleBorder` (i.e. `LiquidRoundedSuperellipse`, `LiquidVerticalRoundedSuperellipse`) through `ClipRRect` instead of `ClipPath`. The engine fix now triggers and the halo disappears for those shapes.

`LiquidOval` is intentionally NOT routed through `ClipRRect` — empirically the engine fix doesn't forward `ClipRRect` with `circular(double.infinity)` nor a `LayoutBuilder`-computed finite radius on the `LiquidOval` path. Callers that need a halo-free circular glass surface over a PlatformView should use `LiquidRoundedSuperellipse(borderRadius: size / 2)` instead, which renders identically on a square widget and triggers the engine fix.

Closes upstream Flutter [#175048](https://github.com/flutter/flutter/issues/175048) and [#115926](https://github.com/flutter/flutter/issues/115926) for `liquid_glass_widgets` users.

*Based on [PR #61](https://github.com/sdegenaar/liquid_glass_widgets/pull/61) by [@jfhair](https://github.com/jfhair).*

# 0.12.0

## ✨ New

### `LiquidGlassWidgets.wrap()` — `theme` parameter

`wrap()` now accepts an optional `GlassThemeData? theme` parameter. When provided, it wraps the child in a `GlassTheme` — eliminating the need for a separate `GlassTheme` widget in your tree.

### `LiquidGlassSettings.standardOpacityMultiplier`

A new multiplier applied to the glass colour alpha when rendering in Standard mode. This allows tuning Standard 2D compositing opacity to achieve more parity with Premium 3D volumetric refraction without needing separate colour values for each mode.

```dart
LiquidGlassSettings(
  glassColor: Colors.white.withValues(alpha: 0.3),
  standardOpacityMultiplier: 0.4, // Standard renders at 0.3 × 0.4 = 0.12 alpha
)
```

Defaults to `1.0` (no change). Fully interpolated via `LiquidGlassSettings.lerp()` and wired through `copyWith()`.

### `GlassPage` — full-screen glass scaffold

A new full-screen scaffold widget for glass-based layouts. Handles background imagery, status bar styling, and background sampling in a single widget.

`enableBackgroundSampling` defaults to `true` when a `background` widget is provided, and `false` otherwise — so the common case just works without extra configuration.

```dart
GlassPage(
  background: Image.asset('assets/wallpaper.jpg'),
  child: Scaffold(...),
)
```

### Export hygiene

- `glass_page.dart` now uses a `show` clause: only `GlassPage` and `GlassStatusBarStyle` are exported (internal state classes are no longer public).
- `liquid_glass_scope.dart` now uses a `show` clause: only `LiquidGlassScope`, `GlassBackgroundSource`, and `GlassRefractionSource` are exported.

## 🎨 Visual — Standard/Premium parity improvements

### Shader composite improvements (`lightweight_glass.frag`)

The Standard-tier lightweight shader composite logic has been improved for closer visual parity with the Premium Impeller path. Shader rim constants are **unchanged** from 0.11.0 — AdaptiveGlass normalization now handles Premium → Standard scaling in Dart space instead:

- **PATH A** (background texture): now uses `applyGlassColorLW()` — a luminosity-preserving glass tint that matches Premium's colour handling for both chromatic (mint, bronze) and achromatic (white, grey) glass colours.
- **PATH A** ambient darkening: `ambientStrength × 0.25 + 0.08` creates the glass shadow effect that visually separates glass from non-glass, matching what Premium achieves through blur compositing.
- **PATH A** adaptive rim colour: `mix(bgRgb, white, 0.7)` brightens the background at the edge, matching Premium's `getHighlightColor`.
- **PATH A** edge-zone refraction: indicator-style background warping at rounded corners using `smoothstep` edge zone with quadratic falloff — the same proven approach as `interactive_indicator.frag` but scaled for containers. Zero transcendentals (polynomial `smoothstep` + multiplies only). Flat interior pixels naturally produce zero offset. Currently active on surface widgets (`GlassBottomBar`, `GlassTabBar`, `GlassSideBar`, `GlassToolbar`) when a `backgroundKey` is provided; `GlassCard` and `GlassButton` use PATH B and will benefit once `AdaptiveGlass` gains scope-aware background key passthrough.
- **PATH A** unified interactive glow: `uGlowIntensity` press-feedback now applies in PATH A, closing an architectural gap where switch/slider thumbs inside background-sampled containers had no glow.
- **Volumetric depth gradient**: subtle top-to-bottom ambient shading (`+vertCoord × 0.04`) in both PATH A and PATH B creates a natural 3D anchored depth feel, simulating light entering from above. Cost: one multiply + one add per fragment.
- **PATH B** frost floor: 8% minimum material alpha ensures glass surfaces are always visible when `glassColor.a = 0` (Premium default), preventing invisible glass in SrcOver compositing.
- **PATH B** contrast-adaptive rim: shifts rim colour toward mid-grey on bright backgrounds so white-on-white borders remain distinguishable.
- **Directional rim bonus**: a small `0.15 × directionalInfluence × lightIntensity` term adds subtle lit-side variation on top of the constant rim base — matching how Premium's 3D bevel naturally brightens toward the light source.

### Interactive widget transparency tuning

- `GlassSwitch` standard thumb: `baseAlphaMultiplier: 0.0`, `edgeAlphaMultiplier: 0.15` — fully transparent body with subtle edge presence for a cleaner glass look.
- `GlassSlider` standard thumb: `baseAlphaMultiplier: 0.08`, `edgeAlphaMultiplier: 0.1` — minimal body opacity with soft edge glow.

### Elevated widget predictability

Removed the arbitrary `+0.2` alpha boost on elevated widgets inside `AdaptiveGlass`. Elevation is now expressed purely through the shader's `densityFactor` physics, making the opacity response predictable and proportional to user settings.

### Interactive widget normalisation (`GlassEffect`)

Standard-tier interactive indicators (slider thumbs, switch thumbs, segmented control pills) now apply the same normalisation as `AdaptiveGlass` — `thickness × 0.4`, `lightIntensity × 0.6` — preventing the 2D shader from rendering these elements heavier than their Premium counterparts.

## 📦 Example app

- Quality comparison demo background image bundled as a local asset (`example/assets/mountain_landscape.jpg`) — eliminates network dependency and first-frame loading flash.

---

# 0.11.0

## ✨ New — Liquid Morph Engine (new architectural system)

This release introduces the **Liquid Morph Engine** — a standalone, reusable physics and animation system for iOS 26-style liquid glass morphing. It lives in `lib/engine/` and is fully decoupled from any specific widget.

`GlassMenu` is the **first consumer** of the engine. Future widgets (sheets, cards, buttons) will use the same engine to achieve consistent, physics-correct liquid glass transitions throughout the library.

> **Documentation:** [`docs/LIQUID_MORPH_ENGINE.md`](docs/LIQUID_MORPH_ENGINE.md) — full guide covering `GlassMorphController`, `LiquidMorphState`, `LiquidMorphPhysics`, and how to integrate the engine into your own custom widgets.

### Core engine types

| Type | Role |
|---|---|
| `GlassMorphController` | Lifecycle owner — manages the spring, exposes `open()` / `close()` |
| `LiquidMorphState` | Immutable value object — one per frame, contains all render values |
| `MorphPhase` | Semantic lifecycle enum — tells you where in the animation you are |
| `MorphSpeed` | Enum — controls spring stiffness without exposing raw physics constants |
| `LiquidMorphPhysics` | Internal stateless math engine |

### How it works

Two conceptual "blobs" drive every morphing animation:

- **Blob A** (anchor) — the ghost trigger that shrinks away over the first 40 % of the animation, cleanly breaking the liquid bridge.
- **Blob B** (body) — travels from the trigger centre to the widget centre along a J-curve overshoot trajectory, expanding from trigger size to target size.

The SDF metaball shader creates the teardrop neck between the blobs automatically — there is no explicit neck geometry. `LiquidMorphPhysics.compute()` determines each blob's position, scale, and blend factor on every frame.

### `GlassMenu` — first engine consumer

- **Teardrop open animation** · The menu grows from the trigger point along the dual-curve SDF path, producing the iOS 26 "bubble emerging from button" effect.
- **Rubber-band close physics** · On dismiss the teardrop recoils with a critically-damped spring + overshoot tail, matching the tactile snap of native iOS context menus.
- **Velocity-bump alignment** · Spring initial velocity is seeded from touch velocity at release — fast flicks close snappily, slow releases settle deliberately.
- **Handoff latching** · Re-opening during a close animation inherits the in-flight velocity and reverses smoothly — no pop or cut.
- **Blob scaling** · Blob sizes scale relative to trigger size and computed menu height, so short and tall menus receive proportionally correct teardrop curvature.

> **See it live:** The [Apple Messages demo](example/lib/apple_messages/apple_messages_demo.dart) (`cd example && flutter run -t lib/apple_messages/apple_messages_demo.dart`) showcases the morphing engine in a real-world context — tap the menu or **Edit** button at the top of the screen to trigger the `GlassMenu` with full teardrop open/close physics.

### Spring physics refinements

- Critical damping (`ζ = 1.0`) on all spring controllers prevents oscillation on rapid successive opens.
- `interactionScale`, `stretch`, and `stretchResistance` integrate into the morphing path via the same spring solver used by `LiquidStretch`.

## 🐛 Fixes

- **`GlassMenu` — safe area / notch clipping on iOS and Android** · Menu position and maximum height were computed from `MediaQuery.padding`, which is consumed by ancestor `SafeArea` widgets and reports `0` inside a fully-safe tree. Switched to `View.of(context).padding` (raw hardware insets) so the menu is always clamped correctly regardless of `SafeArea` nesting depth. Fixes the menu appearing under the Dynamic Island on iPhone 14 Pro and similar devices.

- **`GlassMenu` (scrollable) — scrolling now works on large menus** · Menus with more items than fit on screen can now be scrolled reliably.

## 🗂 Example restructure — `demos/` suite

The `example/` package has been reorganised for a cleaner public-facing demo experience:

- New `example/lib/demos/` folder containing seven self-contained, copy-pasteable demos:
  - **`glass_menu_demo.dart`** — all 9 `GlassMenuAlignment` positions, scrollable item list
  - **`glass_tab_bar_scrollable_demo.dart`** — scrollable `GlassTabBar` with dynamic tab add
  - **`glass_modal_sheet_demo.dart`** — all sheet states (peek / half / full), Apple Maps peek style
  - **`glass_bottom_bar_demo.dart`** — magic-lens masking with `GlassBottomBar`
  - **`bottom_bar_tab_width_demo.dart`** — `tabWidth` on both bar variants side-by-side
  - **`searchable_bar_demo.dart`** — `GlassSearchableBottomBar` edge cases
  - **`shape_debug_demo.dart`** — `GlassButton` shape visualiser

- **Apple Messages demo** (`example/lib/apple_messages/`) — showcases the Liquid Morph Engine in a full real-world context; tap the menu or **Edit** button at the top to trigger `GlassMenu`.
- `example/lib/modal_sheet_showcase/` removed (file moved to `demos/glass_modal_sheet_demo.dart`).
- Experimental scratchpad scripts moved to git-ignored `example/lib/playground/`.

---

# 0.10.10


Thanks to [@g3mf0r](https://github.com/g3mf0r) for [PR #55](https://github.com/sdegenaar/liquid_glass_widgets/pull/55). 🙏

## ✨ New

- **`GlassMenu` — `menuAlignment` enum** · A new `GlassMenuAlignment` enum (10 values: `none`, `topLeft`, `topCenter`, `topRight`, `centerLeft`, `center`, `centerRight`, `bottomLeft`, `bottomCenter`, `bottomRight`) lets you pin the menu to a specific edge or corner of its trigger instead of relying solely on auto-detection. The enum is now part of the public API surface exported from `glass_menu.dart`.

- **`GlassMenu` — `autoAdjustToScreen` with `menuPadding`** · When `autoAdjustToScreen: true`, the new `menuPadding: EdgeInsets?` parameter applies additional inset constraints so the menu body never clips against device edges.

- **`GlassMenu` — `itemBorderRadius`** · Controls the corner radius of individual menu item cells, independent of the outer `menuBorderRadius`.

## 🐛 Fixes

- **`GlassTabBar` — multi-tab drag jump** · Dragging the indicator across multiple tab widths in a single gesture now snaps to the correct distant tab. The previous implementation only incremented/decremented by ±1 regardless of drag distance, causing the indicator to teleport unexpectedly when the finger crossed more than one tab boundary.

- **`GlassTabBar` — glass refraction during indicator drag** · Refraction and shadow effects are correctly suppressed during the drag animation and restored on settlement, eliminating a visual glitch where the glass distortion would persist after releasing the indicator.

## 🧪 Tests

- Added 4 new `GlassMenu` tests covering `GlassMenuAlignment` enum values, `menuAlignment` parameter, `autoAdjustToScreen` + `menuPadding`, and `itemBorderRadius`.
- Added 2 new `GlassTabBar` tests covering multi-tab drag jump (left and right) to prevent regression of the PR #55 fix.

---

# 0.10.9

Thanks to [@g3mf0r](https://github.com/g3mf0r) for [PR #54](https://github.com/sdegenaar/liquid_glass_widgets/pull/54). 🙏

## ✨ New

- **`GlassTabBar` (scrollable) — jelly physics on indicator drag** · The scrollable indicator pill now feeds real-time drag velocity into the liquid glass shader, producing the same organic stretch-and-settle effect that fixed-mode tabs already had.

## 🐛 Fixes

- **`LiquidGlassWidgets.wrap` — `adaptiveQuality: true` without `adaptiveConfig` permanently locks to `standard`** · The default fallback config was created with `initialQuality: GlassQuality.standard`, which the adapter treats as a skip-Phase-2 signal — immediately jumping to Phase 3 at `standard` without ever running the warmup benchmark. On capable devices (including the iPhone simulator on Apple Silicon) this prevented the adapter from ever discovering that the device can sustain `premium`. Fixed by removing the erroneous `initialQuality` from the fallback; Phase 2 now always runs when no explicit quality is provided.

- **`GlassTabBar` (scrollable) — indicator overflows bar on low tab counts** · The right drag boundary was computed as `viewMax` instead of `viewMax - indicatorWidth`, allowing the pill to slide outside the bar when there were only 2–3 wide tabs. Corrected to `viewMax - targetWidth`.

- **`GlassTabBar` (fixed) — tiny accidental drags switch tabs** · Tab switching on drag-end now requires either a displacement greater than 20 % of the tab width **or** a flick velocity above 400 px/s, preventing unintended switches from small incidental movements.

- **`GlassTabBar` (scrollable) — flick gesture ignored in scrollable mode** · A horizontal flick with sufficient velocity now overrides the nearest-tab distance calculation and advances the indicator in the flick direction, matching the fixed-mode behaviour.

---

# 0.10.8


Thanks to [@g3mf0r](https://github.com/g3mf0r) for [PR #52](https://github.com/sdegenaar/liquid_glass_widgets/pull/52). 🙏

## 🐛 Fixes

- **`GlassTabBar` — indicator drag drift on desktop/web** · The indicator position was accumulated via `delta.dx` additions each frame, causing the pill to visually lag behind the pointer on desktop platforms where pointer events arrive at a higher frequency than the frame budget. Fixed by computing position from the absolute global pointer coordinate on every update event, eliminating accumulated drift.

- **`GlassTabBar` (scrollable) — tab labels hidden behind indicator pill** · The `SingleChildScrollView` (tab labels) and the background pill were inserted in the wrong stack order — labels were painted first, then the pill on top, obscuring them. Fixed by inserting the pill before the labels so labels always paint above the pill (correct z-order).

- **`GlassTabBar` (scrollable) — indicator fly-off past bar edges** · The indicator pill had no boundary clamping in scrollable mode, allowing it to animate outside the visible bar area. Drag offset is now clamped to `[scrollOffset - 35 %, scrollOffset + screen + 35 %]`.

## ✨ New

- **`DividerSettings`** — new optional `dividerSettings` parameter on `GlassTabBar`. Renders animated vertical dividers between tabs with configurable `thickness`, `indent`, `endIndent`, custom `decoration`, animation `duration`/`curve`, and an `isHideAutomatically` flag that fades out dividers adjacent to the active tab. Includes a `copyWith` helper for convenient inline customisation.

- **Grab-to-drag in scrollable mode** — the indicator pill in scrollable mode can now be directly grabbed and dragged to a new tab. Uses a `GestureArenaTeam` (`HorizontalDragGestureRecognizer` as captain + `TapGestureRecognizer`) to correctly win the arena against the `SingleChildScrollView` when the initial touch is within the active indicator's bounds. The scroll view retains natural scrolling behaviour when touching outside the pill.

- **`indicatorShadow`** — new optional `indicatorShadow: List<BoxShadow>?` parameter on `GlassTabBar`. Applies a drop shadow to the resting (solid-colour) indicator pill, improving contrast in light-mode themes where the pill and track share similar colours. The shadow is automatically suppressed during the liquid glass drag animation so it does not interact with the backdrop blur, and restored when the pill returns to its idle state.

---

# 0.10.7


Thanks to [@yukinoaruu](https://github.com/yukinoaruu) for [PR #51](https://github.com/sdegenaar/liquid_glass_widgets/pull/51). 🙏

## 🐛 Fixes

- **`GlassMenu` — trigger button dead zone after closing** · After closing the menu, the trigger button would ignore taps for the duration of the closing spring animation (~95% of travel), forcing the user to wait several seconds before being able to reopen it. Fixed by separating the visual-hide threshold (`0.05`) from the input-block threshold (`0.80`) into two independent booleans: `isButtonVisible` and `isMenuBlocking`. The button now becomes tappable again as soon as the animation drops below 80%, and the morphing glass overlay wraps in `IgnorePointer(ignoring: value < 0.8)` to prevent the contracting container from consuming the tap instead.

---

# 0.10.6

## 🐛 Fixes

- **`GlassBottomBar` — `extraButton` causes bar to float in the middle of the screen** · Wrapped the inner `Row` in a `SizedBox(height: barHeight)` so the `Scaffold.bottomNavigationBar` slot always receives an explicit tight height constraint. Without this, the `Expanded` child introduced by `extraButton` propagated an unbounded height through `LiquidGlassLayer`, causing Flutter to render the bar centred on screen instead of pinned to the bottom edge.

---


# 0.10.5

## ✨ New

- **`SearchableBottomBarController`** — added `openSearch()`, `closeSearch()`, and `isSearchOpen` getter for programmatic search control. Previously the only way to open search was by driving `isSearchActive` from parent state.
- **`GlassTabBar`** — added `maskingQuality` parameter (`MaskingQuality.high` / `MaskingQuality.off`), matching the existing `GlassBottomBar` API. Set to `off` to disable the 8 px jelly-bloom expansion on lower-end devices.
- **`GlassSlider`** — added `interactionBehavior`, `glowColor`, and `glowRadius` for consistent drag-glow customisation across all interactive widgets.
- **`GlassSegmentedControl`** — same `interactionBehavior`, `glowColor`, `glowRadius` params added for API parity with `GlassSlider` and `GlassTextField`.
- **`LiquidGlassWidgets.respectsAccessibility`** — deprecated alias added pointing to `respectSystemAccessibility`. Will be removed in v1.0.

## 🐛 Fixes

- **`GlassTextField`** — fixed a use-after-dispose crash when `focusNode` cycled `null → external → null`. The widget now tracks ownership with an explicit `_ownsNode` flag and correctly creates a fresh internal node on each transition.
- **`GlassTabBar`** — resolved scrollable-mode visual glitches. The indicator now stays perfectly glued to the active tab during scrolling without drifting, uses native "snappy" spring physics for consistent feel, and implements a three-layer rendering architecture so the solid indicator pill cleanly clips at the rounded viewport corners while the 8px jelly bloom expands freely over the tab bar boundaries.

# 0.10.4

A huge, heartfelt thank-you to [@yukinoaruu](https://github.com/yukinoaruu) for [PR #49](https://github.com/sdegenaar/liquid_glass_widgets/pull/49). 🙏

We made a mess of the original 0.10.3 merge of his work — introducing regressions that broke the very things he had so carefully built. He came straight back, fixed every issue, and did it with incredible patience and generosity. This release is entirely his. If you are enjoying `GlassMenu`, it is because of him.

## 🐛 Fixes (regressions from 0.10.3 merge)

- **GlassMenu — full-list rebuilds on every pointer event** · Restored the `_cachedWrappedItems` mechanism that was accidentally dropped. The previous merge caused the entire wrapped-item list to be recreated on each pointer move, resetting pressed/hover states mid-gesture and tanking performance on menus with many items.
- **GlassMenu — selection and hover state precision** · Migrated to a `ValueNotifier` system (`_hoveredIndexNotifier`, `_isDraggingNotifier`). Individual menu items now rebuild in isolation instead of triggering a full `setState` on the entire menu tree, keeping animations at a steady 60 fps.
- **GlassMenu — ghosting on selection pill** · Fixed a double-background artifact where the selected `GlassMenuItem` painted its own hover fill on top of the sliding pill, producing a faint ghost ring. Selected items now transition to `Colors.transparent` instantly.
- **GlassMenu — disabled items could be tapped** · Tapping a disabled item no longer calls `onTap` or closes the menu. The pill highlight correctly skips disabled items during pointer tracking.
- **GlassMenu — double `onTap` firing** · Removed a redundant `onTap` callback in the internal wrapped-item builder that was causing every selection to fire twice.
- **GlassMenu — `RangeError` when item list shrinks while open** · `didUpdateWidget` now clears `_hoveredIndex` when `items.length` decreases, preventing an out-of-bounds crash when the pill tried to measure a deleted item.
- **GlassMenuItem — disabled opacity** · Disabled items now render at `Opacity(0.4)` to match the design spec and test expectations.
- **GlassMenuLabel — hybrid `title`/`child` API** · `GlassMenuLabel` now accepts either a `title` String (rendered as stylised uppercase) or an arbitrary `child` Widget, enabling diverse non-interactive content beyond simple section headers.
- **GlassMenuLabel — `height` default** · Default `height` set to `30.0` so the selection pill cannot drift when items with non-standard font sizes are mixed in.
- **GlassMenu — `glowIntensity` parameter** · Added `glowIntensity` and wired it through to `GlassContainer`, completing the full interaction-glow parameter surface.
- **GlassMenu — `glowOnTapOnly` default corrected** · Default changed to `true` to prevent a permanently stuck glow artefact during scroll and drag gestures.
- **GlassMenu — stretch parameter rename** · Renamed `allowPositiveXStretch` / `allowNegativeXStretch` / `allowPositiveYStretch` / `allowNegativeYStretch` to `allowPositiveX` / `allowNegativeX` / `allowPositiveY` / `allowNegativeY` to align with the `LiquidStretch` API surface.
- **GlassMenu — compositing architecture** · Removed redundant `RepaintBoundary` nodes that were leaving descendant glass layers DETACHED from the compositor scene, and moved `GlassGlow` inside `GlassContainer`'s clip subtree to prevent glow bleed onto the background.

## ⚠️ Breaking — `GlassMenu` stretch parameter renames

The four optional stretch-axis override parameters introduced in 0.10.3 have been renamed:

| 0.10.3 name | 0.10.4 name |
|---|---|
| `allowPositiveXStretch` | `allowPositiveX` |
| `allowNegativeXStretch` | `allowNegativeX` |
| `allowPositiveYStretch` | `allowPositiveY` |
| `allowNegativeYStretch` | `allowNegativeY` |

All four remain optional with `null` defaults (auto-inferred from menu position). Only code explicitly passing the old names needs updating.


# 0.10.3

Big thanks to [@yukinoaruu](https://github.com/yukinoaruu) for [PR #47](https://github.com/sdegenaar/liquid_glass_widgets/pull/47) — a comprehensive interaction engine upgrade for `GlassMenu` that brings it more in line with iOS 26 context menu behaviour. 🙏

## ✨ Features

### Heterogeneous menu items — `GlassMenuDivider` and `GlassMenuLabel`

Menus now accept any `Widget`, enabling iOS 26-style section grouping:

```dart
GlassMenu(items: [
  const GlassMenuLabel(title: 'Actions'),    // renders as 'ACTIONS'
  GlassMenuItem(title: 'Save', onTap: () {}),
  const GlassMenuDivider(),
  GlassMenuItem(title: 'Delete', isDestructive: true, onTap: () {}),
])
```

`GlassMenuLabel` exposes a `height` parameter (default `30.0`) so custom font sizes don't drift the selection-pill position.

### `GlassMenuItem` — rich content

Six new parameters: `subtitle`, `enabled`, `titleStyle`, `subtitleStyle`, `iconColor`, `iconSize`.

### Scroll-aware selection pill

A sliding highlight follows the pointer and disappears automatically when the user starts scrolling (10 px drag-slop guard + `ScrollNotification` listener).

### Elastic stretch and scroll-safe glow

`GlassMenu` now wraps in `LiquidStretch` for spring physics on drag. `glowOnTapOnly: true` (the new default) suppresses the glass glare after a drag, preventing a stuck-glow artefact during list scrolling. Full parameter surface: `interactionScale`, `stretch`, `stretchResistance`, `stretchAxis`, `allowPositiveX/NegativeX/Y`.

### New primitives on `GlassGlow` and `GlassContainer`

`GlassGlow.enabled`, `GlassGlow.glowOnTapOnly`, and `GlassContainer.glowIntensity` are now available for custom integrations.

## 🐛 Fixes

- **GlassMenu — double `BackdropFilter`** · Removed an extra blur layer above `GlassContainer` that doubled the blur sigma and created an over-frosted ring.
- **GlassMenu — DETACHED compositing layers** · Removed the outer `RepaintBoundary` wrapping `_buildMorphingContainer`. When `GlassContainer(useOwnLayer: true)` installs a `BackdropFilter` layer it forces compositing on the entire subtree; a `RepaintBoundary` above it fought the compositor for `OffsetLayer` ownership, leaving descendant `RepaintBoundary` nodes (i.e. each `GlassMenuItem`'s glass layer) DETACHED from the scene. `GlassGlow` and `GlassContainer` already own their compositing layers — no extra boundary is needed. Separately, `Opacity` widgets at `>= 1.0` are now skipped entirely so no gratuitous `OpacityLayer` is inserted when compositing is already being forced by a `BackdropFilter` descendant.
- **GlassMenu — layout overflow during open animation** · `GlassContainer(height: currentHeight)` propagated tight height constraints through its entire subtree during the morph. When menu items became visible (previously at `value > 0.65`), the container was only ~114 px tall while 3 items needed 132 px, causing the `Column` inside `Positioned.fill` to overflow by 18 px. Fixed by deferring content rendering until `value ≥ 0.85`, exactly when `currentHeight` becomes `null` and the container sizes naturally — no tight-constraint cascade possible.
- **GlassMenu — interaction glow bleeds onto background** · `GlassGlow` previously wrapped `GlassContainer` from the outside. `_RenderGlassGlowLayer.paint()` called `canvas.drawCircle()` over the full overlay canvas with no shape boundary, causing the radial gradient to paint beyond the menu's glass shape onto the background. Fixed by moving `GlassGlow` inside `GlassContainer`'s `clipBehavior: Clip.antiAlias` subtree — matching the architecture used by `GlassButton`.
- **GlassMenuItem — `AnimatedScale` layout overflow on press** · `AnimatedScale` (backed by `RenderTransform`) retains the pre-scale layout size during a 0.98-scale press animation, causing a spurious overflow against the menu's bounded `Positioned.fill`. Fixed by wrapping `AnimatedScale` in `SizedBox(height: effectiveHeight)` to isolate the transform's layout footprint.
- **GlassMenu — selection pill layout exception** · `AnimatedPositioned` is now inside a bounded `SizedBox(height: totalH) → Stack`, preventing a debug-mode layout exception and an out-of-bounds pill position when scrolled.
- **GlassMenu — `RangeError` on item removal** · `didUpdateWidget` clears `_hoveredIndex` when `items.length` shrinks while the menu is open.
- **GlassMenu — `GlassMenuItem` state flicker** · Wrapped items cached; only rebuilt when `widget.items` changes, preventing pressed/hover resets during the 60 fps spring ticker.
- **GlassGlow — permanently muted glow** · `didUpdateWidget` resets `_glowSuppressed` when `glowOnTapOnly` is toggled off.
- **GlassMenuItem — desktop hover state leak** · `dispose()` clears `_isHovered`.
- **Impeller — extreme-stretch glyph-bounds crash** · Scale determinant clamped before reaching the shader.
- **Android — negative safe-area assertion** · `sysBottom > 25` guard added.

## ⚠️ Semi-Breaking

`GlassMenu.items` changed from `List<GlassMenuItem>` to `List<Widget>`. Existing code compiles unchanged — only typed `List<GlassMenuItem>` variable declarations need widening.

## 🧪 Tests — 1,648 passing

---

# 0.10.2


## Fixes

- **GlassTabBar (scrollable) — indicator clipping** · Migrated the selected-tab indicator to an overlay architecture outside `SingleChildScrollView`, eliminating clip artifacts during scrolling and preserving the full iOS 26 glass bloom expansion.
- **GlassTabBar (scrollable) — tap fires on scroll** · `onTabSelected` no longer fires when the user scrolls the tab bar; selection is now only triggered on confirmed taps.
- **GlassTabBar (scrollable) — bloom activates on scroll** · The pressed indicator bloom no longer activates when scrolling the tab bar content.
- **GlassTabBar (scrollable) — indicator pulsates on transition** · Fixed a threshold bug that caused the bloom to flicker during tab-switch animations.
- **GlassTabBar (scrollable) — scroll into view** · Tapping or programmatically selecting a partially-visible tab now smoothly scrolls it fully into view.
- **GlassAdaptiveScope — Android false-negative quality downgrade** · Mid-range Android devices with Impeller/Vulkan can report inflated warmup P75 values (17–18 ms) due to GPU clock-scaling and JIT shader cache warm-up — not actual slowness. The previous `premium` threshold of `< 16 ms` (the raw 60-fps frame budget) was too strict and incorrectly demoted capable hardware to `standard` or `minimal`. Thanks @hank205 for the detailed diagnostic log. 🙏
- **GlassModalSheet / `.show()` / `GlassModalSheetScaffold` — `dragIndicatorWidth`** · The drag handle pill width was previously hardcoded at 36 (iOS native). A new `dragIndicatorWidth` parameter lets you customise it — e.g. `64` for sheets where a more prominent handle better suits the layout. Defaults to `36`, no breaking change. Thanks @jfhair (#46). 🙏

## Changes

- **`GlassQualityAdapter` / `GlassAdaptiveScopeConfig` / `GlassAdaptiveScope` — configurable warmup thresholds** · Two new parameters let you tune (and help us calibrate) the Phase 2 warmup classification thresholds:
  - `warmupPremiumThresholdMs` — P75 below this → `premium`. Default raised from `16.0` to **`20.0`** to account for Android GPU warm-up inflation. *(Calibration status: 1 device report — please share yours!)*
  - `warmupStandardThresholdMs` — P75 at or below this (and above premium) → `standard`. Default **`28.0`**. *(Calibration status: provisional — no real-device data for this band yet.)*
  - `skipInitialFrames` raised from **60 → 90** (≈1.5 s at 60 Hz) to give Android more time for GPU clocks and shader caches to settle before the benchmark begins.

> **Phase 3 hysteresis remains the safety net.** If a device cannot sustain its warmup-assigned quality, it steps down automatically within ~6 seconds — the new thresholds only affect the initial classification, not runtime correction.

> ⚠ **Community calibration needed** — especially for `warmupStandardThresholdMs`. If your device produces a warmup P75 in the 20–28 ms range, please enable `debugLogDiagnostics: true` and post your P75 + device model to the [Threshold Calibration Discussion](https://github.com/sdegenaar/liquid_glass_widgets/discussions).

# 0.10.1

Big thanks to @yukinoaruu (#43) and @jfhair (#44, #45) for three excellent contributions this release. 🙏

## Fixes

- **GlassModalSheet — child State preservation** · Removed `GlobalObjectKey` from the internal `Focus` bridge. The key was changing every rebuild, quietly tearing down child `State` (scroll positions, controllers, etc.) on each expand/collapse. (#44)
- **GlassModalSheet — `onStateChanged` skipped on slow drag** · Introduced `_settledState` to track the last published state separately from the in-flight animation target. Side-effects (haptics, callbacks, scroll-to-top) now fire reliably after a drag that crosses a snap threshold mid-gesture. (#45)
- **GlassModalSheet — ghosting and jitter** · Fixed visual artefacts during sheet transitions. (#43)
- **GlassModalSheet — element subtree stability** · `LiquidStretch` now always returns a consistent widget type regardless of `interactionScale`/`stretch` values, preventing a full subtree teardown on the frame the sheet reaches full expansion.
- **LightweightLiquidGlass — null-shader passthrough** · The widget tree shape is now stable while the fragment shader loads asynchronously; a tinted passthrough is painted instead of switching widget types.

# 0.10.0

## ⚠️ Breaking — Pre-v1 API Cleanup

### `LiquidGlassWidgets.wrap()` — `child` is now a required named parameter

Before:
```dart
LiquidGlassWidgets.wrap(const MyApp(), adaptiveQuality: true)
```
After:
```dart
LiquidGlassWidgets.wrap(child: const MyApp(), adaptiveQuality: true)
```
This aligns with Flutter widget conventions where `child` is always named.

### `GlassModalSheetScaffold` — parameter renames

| Old | New | Reason |
|-----|-----|--------|
| `background:` | `body:` | Matches Flutter `Scaffold.body` — it's the primary content, not a visual property |
| `sheetChild:` | `sheet:` | Cleaner, matches Flutter naming patterns |

Before:
```dart
GlassModalSheetScaffold(
  background: MyMapWidget(),
  sheetChild: MySheetContent(),
)
```
After:
```dart
GlassModalSheetScaffold(
  body: MyMapWidget(),
  sheet: MySheetContent(),
)
```

### `GlassQualityAdapter.skipStaticProbeForTesting` — `@visibleForTesting` annotated

The static field is now annotated `@visibleForTesting`. Production code referencing it
will receive an analyzer hint. Usage in test files is unchanged.

## 🐛 Fix — Android glass fallback on capable devices

`GlassQualityAdapter` was applying the static probe result (`GlassQuality.minimal`) without
respecting `minQuality`. On some Android devices `ImageFilter.isShaderFilterSupported`
returns a false negative, causing the glass shader to be skipped even though the hardware
supports it — the only workaround being `adaptiveQuality: false`.

`minQuality` is now honoured as a true floor even when the static probe fires:

```dart
// Prevents fallback on Android devices with a false-negative static probe
LiquidGlassWidgets.wrap(
  child: const MyApp(),
  adaptiveQuality: true,
  adaptiveConfig: const GlassAdaptiveScopeConfig(
    minQuality: GlassQuality.standard,
  ),
)
```

## ✨ New — Community contributions

### `GlassSearchBarConfig.searchIcon` — custom search icon (PR #41)

Thanks to [@jfhair](https://github.com/jfhair) for [PR #41](https://github.com/sdegenaar/liquid_glass_widgets/pull/41).

The search pill now accepts a fully custom `Widget` in place of the default `CupertinoIcons.search` glyph:

```dart
GlassSearchBarConfig(
  onSearchToggle: (active) { … },
  searchIcon: const Icon(CupertinoIcons.sparkles, color: Colors.white),
)
```

When `searchIcon` is `null` (default) the behaviour is unchanged.

### `indicatorExpansion` — tunable jelly-stretch on bottom bars (PR #40)

Thanks to [@jfhair](https://github.com/jfhair) for [PR #40](https://github.com/sdegenaar/liquid_glass_widgets/pull/40).

Both `GlassBottomBar` and `GlassSearchableBottomBar` now expose `indicatorExpansion`
to control how far the active-tab pill stretches during a drag gesture:

```dart
GlassBottomBar(
  tabs: myTabs,
  selectedIndex: _index,
  onTabSelected: _onTab,
  indicatorExpansion: 8,   // default 14; lower = tighter morph
)
```

### `GlassModalSheet` — two-phase organic interpolation (PR #39)

Thanks to [@yukinoaruu](https://github.com/yukinoaruu) for [PR #39](https://github.com/sdegenaar/liquid_glass_widgets/pull/39).

The sheet's corner-radius animation now uses a two-phase curve that separates the
rapid initial expansion from the final settle, eliminating the snapping artifacts
that were visible at the `half → full` transition on some devices.

The fix also corrects `resolveAdaptiveRadius` to use **logical screen height**
(`MediaQuery.size.height`) instead of `viewPadding.top` as the primary Pro Max
detector, preventing false-positive 54 dp radii on some non-Pro-Max iPhones with
unusually high status-bar padding.

### Asymmetric top/bottom corner radii in premium pipeline (PR #42)

Thanks to [@jfhair](https://github.com/jfhair) for [PR #42](https://github.com/sdegenaar/liquid_glass_widgets/pull/42).

`LiquidVerticalRoundedSuperellipse` now feeds independent top/bottom corner radii
into the premium SDF shader via a 7-float-per-shape stride, enabling sheets that
hug the device chassis curve at the bottom while keeping a tighter radius at the
top — matching the Apple Music / Apple Maps card style:

```dart
LiquidGlass(
  shape: const LiquidVerticalRoundedSuperellipse(
    topRadius: 20,
    bottomRadius: 54, // tracks iPhone 15 Pro Max chassis
  ),
  child: myContent,
)
```

> **Shader note**: all shaders continue to pass `glslangValidator` SPIR-V
> validation. The new stride-7 path is gated on `type == 3` in `sdf.glsl`
> and leaves the existing stride-6 path untouched.

---

# 0.9.6

## 🐛 Fix — `GlassModalSheet` interaction glow in full state

Thanks to [@yukinoaruu](https://github.com/yukinoaruu) for [PR #38](https://github.com/sdegenaar/liquid_glass_widgets/pull/38).

- **Haptic & glow suppression in full state:** `HapticFeedback.selectionClick()` and
  `_saturationController.forward()` were firing on every touch when the sheet was in
  `SheetState.full` — where the glass surface is fully opaque and neither effect is visible.
  Both are now gated on `!isFull`, eliminating spurious haptic feedback and redundant
  animation ticks.
- **Background glass hides when content glass is active:** Added an `Opacity(0.0)` on the
  background `AdaptiveGlass` layer when `expandProgress > 0.98` and `maintainContentGlass`
  is enabled. Prevents "glass on glass" shader conflicts in Premium mode at full expansion.
- **Interaction glow threshold tightened:** `GlassGlow` pulse guard lowered from
  `expandProgress < 0.98` to `< 0.9` to match the existing saturation gate — consistent
  behaviour across all glow signals.
- **`GlassModalSheet` geometry defaults refined:** `topBorderRadius` defaults to `56`
  (was `null`), `horizontalMargin` to `5.0` (was `8.0`), `bottomMargin` to `6.0`
  (was `8.0`) for tighter, more native-feeling geometry.
- **`InteractionNotification` exported:** `InteractionNotification` is now part of the
  public API surface, enabling consumers to dispatch Smart Silence events from their own
  widgets.
- **Corner radius tuning:** `GlassThemeHelpers.resolveAdaptiveRadius` values updated to
  54 / 46 / 46 (Pro Max / Pro / Notch) for a more conservative, closer-to-system look.

## 🧪 Tests — Coverage improvements (1,573 tests)

Extended branch coverage across five previously under-tested subsystems.
Full test count grew from 1,491 → 1,573 (+82 tests).

---

# 0.9.5

## ✨ Feature — Asymmetric corner radii & floating peek geometry for `GlassModalSheet`

Thanks to [@yukinoaruu](https://github.com/yukinoaruu) for [PR #37](https://github.com/sdegenaar/liquid_glass_widgets/pull/37).

- **Shader fix:** `lightweight_glass.frag` now supports per-quadrant corner radii via a new `uData6` uniform (slots 24–27). A sentinel of `uCornerRadius = -1.0` enables asymmetric mode; all existing symmetric shapes fall through unchanged.
- **Clip gap fix:** `ClipPath` geometry on the Skia/Web path is now aligned to `RoundedRectangleBorder` (circular arc) to match the shader SDF — eliminates the sub-pixel transparent notch at sheet corners.
- **Peek geometry:** Five new optional params on `GlassModalSheet` / `GlassModalSheetScaffold` — `peekWidth`, `peekHorizontalMargin`, `peekBottomMargin`, `peekTopBorderRadius`, `peekBottomRadius` — for Apple Maps-style floating pill peek states.
- **Cleanup:** `forceSpecularRim` removed from `AdaptiveGlass`, `GlassSheet`, `GlassModalSheet`, and `GlassModalSheetScaffold`. The shader renders the specular rim natively; no migration needed.

## 🐛 Fix — `GlassSearchableBottomBar` dismiss pill focus & keyboard restoration

The dismiss (×) pill was calling `FocusScope.of(context).unfocus()` which left the `FocusNode` in a "previously focused" state. This caused Flutter to restore the keyboard on back-navigation, and made the first post-dismiss tap get swallowed by focus routing.

**Fixed by:**
- Replacing `FocusScope.unfocus()` with `FocusManager.instance.primaryFocus?.unfocus()` in the DismissPill, fully clearing focus state.
- The × button now **only dismisses the keyboard** — it does not collapse the search state. This matches the real Apple Music / Apple News behaviour where the search bar remains visible (unfocused/ready) after tapping ×. The caller explicitly collapses search by tapping the home pill or switching tabs.
- `onCancelTap` fires first (before the unfocus) so callers can react (clear results, analytics, etc.) before focus is released.

A new `onCancelTap: VoidCallback?` on `GlassSearchBarConfig` gives callers a hook into the × tap.

## ✨ Demo — Apple Music mini-player refinements

High-fidelity improvements to the Apple Music demo to match the real Apple Music app:

- **Play pill visibility:** The floating play pill now stays visible when the search bar is in the "search ready" state (keyboard dismissed). It only hides when the keyboard is actively up (`_searchFieldFocused`), matching real Apple Music behaviour.
- **Dynamic icon colour:** `collapsedLogoBuilder` now shows the selected (red) icon in scroll-collapse mini mode and the unselected (white) icon when search is active, via a static `_kTabs` field so tab definitions aren't duplicated.
- **Play pill positioning:** `aboveBarBottom` is now responsive to the bar's current height — switching to `collapsedNavBarH` when search is active so the pill doesn't drop excessively when the bar shrinks.
- **Play pill animates on search from mini mode:** When search is activated from the scroll-collapsed mini state, the play pill animates from the mini gap position back to its full-width position above the expanded search bar, matching real Apple Music.
- **Home pill restores full bar from any state:** Tapping the home pill now always calls `_dismissMiniMode()` when in mini mode — whether arriving from scroll-collapse or from search — scrolling to top and restoring the full 3-tab bar.
- **Library default preserved:** `collapsedLogoBuilder` in the library remains `unselectedIconColor` — the Apple Music colour logic is isolated to the demo's `GlassSearchBarConfig`.
- **Multi-tab scroll fix:** `_dismissMiniMode` now uses `_activeScrollController` (per active tab) instead of hardcoding the home tab's controller, fixing a bug where tapping Radio/Library in mini mode would leave the bar stuck.

---

# 0.9.4


## ✨ Feature — `GlassSearchableBottomBar` programmatic interaction callbacks

Addresses two community-requested quality-of-life gaps for `GlassSearchableBottomBar`.

### 1. `onBarTap` — tap-to-restore after scroll-to-hide

A new `onBarTap: VoidCallback?` parameter on `GlassSearchableBottomBar` fires whenever the user taps anywhere on the bar. The callback is wired through a **translucent** `GestureDetector` wrapper, so all internal handlers (tab selection, search toggle, indicator drag) continue to work normally — there is zero interference.

Primary use-case is restoring the bar after a scroll-to-hide animation that is managed in the caller's code:

```dart
GlassSearchableBottomBar(
  onBarTap: () => setState(() => _barVisible = true),
  ...
)
```

When `onBarTap` is `null` (the default) no extra widget is inserted into the tree — zero overhead.

### 2. `onSearchFieldTap` — detect taps on the active search field

A new `onSearchFieldTap: VoidCallback?` parameter on `GlassSearchBarConfig`, passed directly to `TextField.onTap`. Fires on every tap of the expanded search field body, including re-focus taps after the keyboard was dismissed.

Useful for navigating to a dedicated search screen, showing a suggestion overlay, or logging an analytics event without needing to own the `FocusNode`:

```dart
GlassSearchBarConfig(
  onSearchToggle: ...,
  onSearchFieldTap: () {
    showSuggestions();
    analytics.log('search_field_tapped');
  },
)
```

Zero breaking changes. Both parameters are optional with `null` defaults.

---

# 0.9.3

## ✨ Feature — `GlassModalSheet` system & rendering performance refinement

Big thanks to [@yukinoaruu](https://github.com/yukinoaruu) for [PR #33](https://github.com/sdegenaar/liquid_glass_widgets/pull/33) — a comprehensive and beautifully engineered contribution that brings a whole new class of interactive modal sheet to the library.

### 1. `GlassModalSheet` system

A new, comprehensive modal sheet implementation supporting three interactive states: `peek`, `half`, and `full`.

- **Physics-Driven Transitions:** Spring physics for fluid, organic state changes.
- **Asymmetric Geometry:** Morphs from a rounded floating pill to a sharp-bottomed full-screen container using the new `LiquidVerticalRoundedSuperellipse`.
- **Isolated Mechanics:** Logic separated into a robust state machine (`glass_modal_sheet_state.dart`) and physics handler (`glass_modal_sheet_mechanics.dart`) — a clean architectural blueprint for future complex components.

### 2. Device-Aware Adaptive Radius

An intelligent radius resolution algorithm that infers the ideal corner curvature from the device's physical safe area — Dynamic Island vs. Notch vs. Android Home Bar — automatically matching glass curvature to device hardware without manual updates.

### 3. Advanced Visual Feedback — Pulse System

A global pulse synchronisation system in the rendering layer allows `GlassModalSheet` to trigger coordinated saturation and lighting pulses during high-velocity interactions, giving the glass surface a "living", organic feel.

### 4. Smart Silence — `suppressInteractionOnChildren`

`InteractionNotification` support prevents the "double-reacting" artifact where both a button **and** the sheet scale simultaneously on a single tap. Child buttons/switches can seamlessly suppress the parent sheet's scaling and glow effects when tapped.

### 5. New shapes & `LiquidStretch` constraints

- **`LiquidVerticalRoundedSuperellipse`**: Enables asymmetric corner radii (top-rounded, bottom-flat) essential for the modal sheet's full-screen morphing animation.
- **Axis constraints**: `allowPositive` / `allowNegative` pivot support prevents the sheet from "collapsing" downward when dragged — it only stretches upward as a tactile response.

### Documentation & Testing

- `docs/assets/GLASS_MODAL_SHEETS_GUIDE.md` — comprehensive developer guide covering the full parameter surface and state behaviours.
- `test/widgets/overlays/glass_modal_sheet_test.dart` — 679 lines of rigorous unit and widget tests covering state transitions, gesture arena logic, and physics edge cases.

Zero breaking changes. `GlassModalSheet` is additive — all existing `GlassSheet` usages are unaffected.

---

## 🐛 Fix — Selected icon colour washed out by glass indicator

A huge shoutout and thanks to [@jfhair](https://github.com/jfhair) for spotting this issue and putting together [PR #29](https://github.com/sdegenaar/liquid_glass_widgets/pull/29) — it was a fantastic catch, and you had exactly the right instinct on the fix!

The active-tab icon was visually muted ("dull") at rest because the `AnimatedGlassIndicator` glass lens was painting *over* the icon layer. Simply moving the indicator behind the icons restores vibrancy but kills the refraction effect — the glass shader needs icons beneath it to warp them as the pill moves.

The fix uses a split-pass sandwich: the pill's solid background renders *below* the icons (full vibrancy at rest), while the glass shader renders *above* them (refraction preserved during animation). Both `GlassBottomBar` and `GlassSearchableBottomBar` are updated. Zero breaking changes.

---

## 🐛 Fix — `GlassSheet` specular rim artifact & washed-out inner elements

Inspired by [@yukinoaruu](https://github.com/yukinoaruu)'s work in PR #33, who introduced the `forceSpecularRim` flag and first surfaced this class of visual fidelity issue with the lightweight glass renderer.

### The problem & fix

On the Skia/Web (lightweight) rendering path, a `refractiveIndex` of `0.7` on a large `GlassSheet` produced a hard, visible border around the sheet — a bright "line" that looked like an artifact rather than a premium glass surface. 

Lowering it globally to fix the sheets caused components **inside** the sheet to lose their specular highlights and become washed out.

We've introduced semantic preset separation via two distinct `RecommendedGlassSettings` presets to solve this:
- **`RecommendedGlassSettings.overlay`** (`refractiveIndex: 0.7`): For cards, buttons, and small interactive widgets.
- **`RecommendedGlassSettings.sheet`** (`refractiveIndex: 0.15`): For large bottom sheets and modal overlays.

All `GlassSheet.show()` calls in the demo app now use the `sheet` preset, while every `GlassButton.custom` and `GlassCard` **inside** a sheet explicitly passes `settings: RecommendedGlassSettings.overlay`. The package-level default for `GlassSheet` (`glass_sheet_defaults.dart`) has also been updated to use `refractiveIndex: 0.15` for a better out-of-the-box experience.

Zero breaking changes.

---

# 0.9.2


## 🐛 Fix — `GlassSwitch` initial-state bloom anchor & polish

- **First-click bloom anchored correctly.** A switch initialised with `value: true`
  now anchors the bloom to the right edge on the very first tap, matching all
  subsequent interactions. Previously `_isMovingForward` was hardcoded to `true`
  at construction regardless of `widget.value`.

- **`_justEndedDrag` race condition eliminated.** The flag is now consumed
  atomically inside `didUpdateWidget` rather than being reset one frame later via
  `addPostFrameCallback`, preventing a rare double-bloom after a drag toggle.

- **Floating-point guard hardened.** Animation controller resets now use `>= 0.99`
  instead of `== 1.0`, making the bloom sequence robust against sub-epsilon drift
  during rapid consecutive toggles.

- **Dead code removed** (`glassOverlay` no-op widget).

- **Haptic feedback added.** `GlassSwitch` now emits `HapticFeedback.lightImpact()`
  on tap-toggle, when the thumb crosses the 50 % midpoint during a drag, and on
  drag-release snap (when the midpoint was never crossed, e.g. a fast flick).
  Opt out with `enableHaptics: false`.

- **3 new regression tests** added; `GlassSwitch` test count now 24.

Zero breaking changes.

---

# 0.9.1

## 🐛 Fix — Adaptive quality system calibration

Three coordinated improvements to `GlassAdaptiveScope` / `GlassQualityAdapter` that
prevent modern flagship devices from being incorrectly demoted to `standard` quality
during app startup.

### 1. Startup-skip window (`skipInitialFrames = 60`)

Phase 2 now discards the **first 60 frames** (≈ 1 second at 60 Hz) before collecting
warmup data. Those frames capture shader compilation, the first route transition, and
provider/localisation initialisation — all artificially inflated and unrepresentative of
steady-state glass rendering. Discarding them means the warmup benchmark reflects actual
glass workload, not cold-start overhead.

The constant is tunable for testing: `GlassQualityAdapter.skipInitialFrames = 0`.

### 2. Raised premium threshold: 12 ms → 16 ms

The old threshold of 12 ms (75 % of a 60 fps frame budget) was too tight.
The new threshold is **16 ms — one full 60 fps frame budget** — which has a cleaner
semantic meaning: "can the device render a premium glass frame within the 60 fps
budget at P75? Yes → premium."

| P75 raster time | Before | After |
|---|---|---|
| < 12 ms | premium | — |
| **< 16 ms** | standard | **premium** |
| 16–20 ms | standard | standard |
| > 20 ms | minimal | minimal |

### 3. `allowStepUp` defaults to `true`

Previously `allowStepUp` defaulted to `false`, meaning a Phase 2 decision could never
be corrected at runtime. If Phase 2 still makes a conservative call (e.g. on a device
under thermal load at startup), Phase 3 can now self-correct after 10 consecutive
under-budget windows (≈ 20 seconds) + an 8-second cooldown.

The step-up is deliberately slow and invisible to users. Set `allowStepUp: false`
explicitly if you need to lock quality for the session.

### Zero breaking changes (adaptive fix)

All three changes are additive or alter defaults in a user-beneficial direction.
Explicit constructor overrides (`allowStepUp: false`, `skipInitialFrames`, custom
threshold via `targetFrameMs`) continue to take precedence.

---

## 🐛 Fix — `GlassSwitch` drag interaction

`GlassSwitch` now supports tap and horizontal drag simultaneously without either
interaction interfering with the other.

**What was fixed:**

- **Tap animation restored** — registering both `onTap` and `onHorizontalDrag*`
  on the same `GestureDetector` caused Flutter's gesture arena to drop one
  interaction after the first touch. Taps now use `onTapDown` / `onTapUp` so
  they share the gesture stream cleanly with drags.
- **Slow drag no longer cancels** — Flutter fires `onTapCancel` before
  confirming a horizontal drag, which was deflating the "liquid bloom" pill
  prematurely. `_onDragStart` now stops any in-progress deflation and restores
  the plump state immediately.
- **Animation resets between interactions** — the thickness animation controller
  was left at `1.0` after its first cycle and silently skipped the bloom on
  subsequent taps. It now resets to `0.0` before each new forward pass.

**Gesture behaviour unchanged from the user's perspective:** tap = full liquid
jump animation; drag = thumb tracks finger with symmetric pill stretch; flick =
velocity-based snap.

### Zero breaking changes

No API changes. All existing `GlassSwitch` usages continue to work without
modification.

---

## 🐛 Fix — `interactionGlowColor` now reads from `GlassThemeData`

`GlassBottomBar` and `GlassSearchableBottomBar` (including its `collapsedLogoBuilder`
state and `SearchPill`) previously used a hardcoded white glow (`0x33FFFFFF`) when
no explicit `interactionGlowColor` was set, silently ignoring any `GlassThemeData`
override on the ancestor tree.

**Resolution order is now:**

```
interactionGlowColor param → GlassThemeData.glowColorsFor(context).primary → internal fallback
```

This means setting the primary glow color in `GlassThemeData` now takes effect
on the press-interaction highlight across both bar variants, including the collapsed
logo pill, without requiring any code changes at the call site.

### Affected widgets

| Widget | Location |
|---|---|
| `GlassBottomBar` | `TabIndicator` interaction glow |
| `GlassSearchableBottomBar` | `SearchableTabIndicator` (normal + collapsed/logo state) |
| `GlassSearchableBottomBar` | `SearchPill` expanded glow |

### Zero breaking changes

Explicit `interactionGlowColor` parameters continue to win with highest priority.
This only changes what happens when the parameter is left `null`.

---

## ✨ Feature — `glowBlurRadius`, `glowSpreadRadius`, `glowOpacity` on `GlassGlowColors`

Three new appearance fields on `GlassGlowColors` give fine-grained control over the
shape of the directional press-glow across all glass widgets:

| Field | Type | Default | Effect |
|---|---|---|---|
| `glowBlurRadius` | `double` | `4.0` | Gaussian blur sigma via `MaskFilter.blur` — softens the glow edge into a natural liquid-glass halo |
| `glowSpreadRadius` | `double` | `0` | Extra circle radius as a fraction of the layer's shortest side |
| `glowOpacity` | `double` | `1` | Master opacity multiplier (0–1) applied on top of the glow color's own alpha |

### Usage

Set them globally via `GlassThemeData` to affect all glass widgets at once:

```dart
GlassTheme(
  data: GlassThemeData(
    light: GlassThemeVariant(
      glowColors: GlassGlowColors(
        primary: Color(0x55FFFFFF),
        glowBlurRadius: 8,       // soft, diffuse halo
        glowSpreadRadius: 0.15,  // bleeds 15 % beyond touch radius
        glowOpacity: 0.75,       // 75 % of the color's own alpha
      ),
    ),
  ),
  child: ...,
)
```

Or override per-widget via `GlassButton.glowBlurRadius` / `glowSpreadRadius` /
`glowOpacity` — widget-level values take precedence over the theme.

### Defaults preserve existing visual behaviour

`glowSpreadRadius` and `glowOpacity` default to `0` and `1` respectively,
preserving previous rendering. `glowBlurRadius` defaults to **`4.0`** —
a soft, natural halo that better fits the liquid-glass aesthetic.
`MaskFilter.blur` is guarded at zero so there is no GPU cost when the value
is left at `0`. Set `glowBlurRadius: 0` explicitly for a hard-edge disc.

### Affected widgets

All widgets that render `GlassGlow` consume these fields, including:
`GlassButton`, `GlassBottomBar`, `GlassSearchableBottomBar`
(both the tab pill and the search pill), `GlassSlider`, `GlassSwitch`.

### Zero breaking changes

Existing code that does not set these fields continues to render identically.
`copyWith`, `==`, and `hashCode` all include the three new fields.

---



# 0.9.0

## ✨ New — `tabWidth` on `GlassBottomBar`

**`tabWidth` is now available on both `GlassBottomBar` and `GlassSearchableBottomBar`.**
Both bar variants share identical compact-sizing semantics and the same default.

### API

```dart
GlassBottomBar(
  // Default (no tabWidth): expand — pill fills available space.
  // tabWidth: 88.0 → iOS 26 compact sizing
  tabWidth: 88.0,
  ...
)
```

| `tabWidth` | Behaviour | 2 tabs | 3 tabs | 4 tabs |
|---|---|---|---|---|
| `null` *(default)* | Expand — fills available space | fills bar | fills bar | fills bar |
| `88.0` | Compact — iOS 26 style | 176 px | 264 px | 352 px |

The pill is automatically **clamped** so it never overflows its container,
regardless of how many tabs are present or how narrow the screen is.

### Zero breaking changes

`tabWidth` defaults to `null` (expand) on both `GlassBottomBar` and
`GlassSearchableBottomBar`. Existing code that does not pass `tabWidth`
continues to behave exactly as before — the tab pill fills the bar.
Pass `tabWidth: 88.0` to opt-in to iOS 26 compact sizing.

### Shared infrastructure (internal)

- **`bar_layout_utils.dart`** — new pure-Dart file containing
  `resolveTabPillWidth`. Both `GlassBottomBar` and
  `SearchableBottomBarController` delegate to this single function, eliminating
  two separate inline implementations of the same arithmetic.
- **`kBottomBarGlassDefaults`** — the 9-field `LiquidGlassSettings` constant
  that was previously copy-pasted into both bar state classes is now defined
  once in `bottom_bar_internal.dart` and referenced from both locations.

### Production hardening

- **Extra button pinned to trailing edge in `GlassBottomBar`.**
  Previously the extra button sat immediately adjacent to the tab pill when
  using compact `tabWidth` sizing, leaving empty space to its right. It is now
  always pinned to the far-right edge (using `Expanded` + `Align(centerRight)`)
  to match the searchable bar's layout. The `maxTabW` arithmetic is unchanged;
  only the Row structure changed. Works correctly in both compact and expand modes.
- `resolveTabPillWidth` guards against negative `maxAvailable` values
  (`math.max(0.0, maxAvailable)` before the `clamp`) to prevent a `RangeError`
  in unusual layout constraint environments.
- Both constructors now assert `tabWidth == null || tabWidth > 0` — passing a
  negative value previously produced a zero-width pill silently.
- Golden regression sentinel added for `tabWidth: null` (expand mode), so a
  layout regression in legacy behaviour is caught by the pixel-test suite.


### Example

`example/lib/tab_width_demo.dart` — covers both `GlassBottomBar`
and `GlassSearchableBottomBar` via a **Bar variant** chip, with live metrics
showing the computed pill width in real time.

---

# 0.8.4


## CI & Tooling

- **CI: Multi-platform test matrix.** The CI pipeline now runs the full test suite
  on `ubuntu-latest`, `macos-latest`, and `windows-latest` across both `stable`
  and `beta` Flutter channels. Previously only `macos-latest / stable` was tested,
  which silently allowed the three Windows shader regressions shipped in 0.7.9–0.7.12.
  Fail-fast is disabled so all platform failures are visible in a single run.

- **CI: Windows shader validation gate.** `glslangValidator` (the same SPIR-V
  compiler core Flutter uses on Windows) now runs in CI on every push and PR via
  the `shader-validation` job. Any shader that would produce a
  _"index expression must be constant"_ or _"loop bounds must be compile-time
  constants"_ error is caught before it reaches `main`. Previously this check only
  ran locally via `bash scripts/validate_shaders.sh` on macOS.

- **CI: pub.dev publish dry-run gate.** A dedicated `pub-check` job runs
  `dart pub publish --dry-run` on every push and PR. Catches missing dartdoc
  comments, `pubspec.yaml` issues, platform declaration gaps, and score regressions
  before they land in a release.

- **CI: Coverage threshold guard (≥ 90 % effective).** The pipeline now fails if
  effective line coverage drops below 90 % on the stable channel. _Effective_
  coverage is computed after stripping `lib/src/renderer/*` — 16 GPU
  `CustomPainter` / `RenderObject` files that cannot execute in a headless VM (no
  GPU rasterizer; documented as untestable in `ARCHITECTURE.md`). Current effective
  coverage is **91.8 %** (4 146 / 4 514 lines). A `.codecov.yml` config now mirrors
  this exclusion so the pub.dev / GitHub badge agrees with the CI gate rather than
  showing the raw ~81 % figure that included the untestable renderer paths.

- **CI: Run concurrency cancel.** Added `concurrency` group so redundant
  in-progress runs on the same branch are cancelled automatically, saving CI
  minutes on rapid-push workflows.

- **Tooling: `scripts/validate_shaders.sh` cross-platform update.** The shader
  validation script now resolves `glslangValidator` / `glslangValidator.exe`
  automatically, works on Windows (Git for Windows bash), and prints correct
  install instructions for macOS (`brew`), Ubuntu (`apt-get`), and Windows
  (`choco` / `winget`). Path resolution is now robust regardless of which
  directory the script is called from.

## GlassAdaptiveScope Diagnostics *(experimental)*

- **`GlassAdaptiveDiagnostic` — rich quality change event.** A new immutable
  data class is emitted whenever `GlassAdaptiveScope` changes quality tier.
  It carries the full context of *why* the change happened: `from`/`to` quality,
  `reason` (`warmupComplete`, `thermalDegradation`, `thermalRecovery`,
  `restoredFromCache`, `staticProbe`), `phase`, and the P75/P95 raster timing
  that triggered the decision.

- **`GlassAdaptiveScope.onDiagnostic`** — a new optional callback that receives
  a `GlassAdaptiveDiagnostic` alongside the existing `onQualityChanged`. The old
  callback is unchanged — this is purely additive.

- **`GlassAdaptiveScope.debugLogDiagnostics: true`** — zero-wiring diagnostic
  mode. Add this flag to print a structured console block on every quality change
  in debug builds (no-op in profile/release). Designed to lower the barrier for
  community threshold calibration reports:

  ```
  ┌─ 📊 GlassAdaptiveScope ─────────────────────────────────────────
  │  Change  : premium → standard
  │  Reason  : warmupComplete
  │  Phase   : runtime
  │  P75     : 14.2 ms
  │  Frames  : 10
  │
  │  📬 Post to: github.com/sdegenaar/liquid_glass_widgets/discussions
  └──────────────────────────────────────────────────────────
  ```

- **`GlassQualityChangeReason` enum** — exported publicly so analytics pipelines
  can filter on specific event types (e.g. only log `warmupComplete` and skip
  `restoredFromCache` noise).

- **Adapter diagnostic tracking** — `GlassQualityAdapter` now records
  `lastP75Ms`, `lastP95Ms`, `lastFramesMeasured`, and `lastChangeReason` before
  every quality decision so the scope can snapshot them synchronously before the
  async `addPostFrameCallback` gap.

## Bug Fixes

- **FIX: Refraction inverted on Android (Pixel 7, Mali GPU, OpenGL ES emulator).** On all
  devices where Impeller uses the OpenGL ES backend, the liquid glass refraction effect
  appeared to bend inward rather than outward — content beneath the glass lens distorted
  toward the centre instead of away from it. The glass bottom bar, segmented control
  indicator, and all premium-quality glass surfaces were affected.

  **Root cause:** OpenGL ES stores render-to-texture outputs with a bottom-left Y origin
  (Y increases upward), whereas Flutter's widget coordinate system uses Y-down. The shaders
  already flip `screenUV.y` and `geometryUV.y` with `1.0 − y` to compensate when _sampling_
  textures. However, the `displacement` vector (in `liquid_glass_final_render.frag`) and
  `edgeOffsetLogical` (in `interactive_indicator.frag`) were computed in Flutter's Y-down
  space and added directly to the Y-up UV without correcting the Y component. A positive Y
  displacement (outward at the bottom edge) therefore moved the sample _toward_ the centre
  in UV space — the exact opposite of the intended direction.

  **Fix:** Under `#ifdef IMPELLER_TARGET_OPENGLES`, negate the Y component of the
  displacement/offset vector before applying it to the sampled UV. This re-aligns the
  Y-down displacement with the Y-up UV coordinate space.

  The Metal (iOS/macOS) and Vulkan (Samsung S22 / Adreno / AMD Xclipse) code paths are
  unchanged — the fix is gated entirely by `IMPELLER_TARGET_OPENGLES` and verified against
  both a Pixel 7 API 35 emulator and a physical Samsung Galaxy S22.

---




# 0.8.3

## Performance & Bug Fixes


- **`GlassBottomBar` / `GlassSearchableBottomBar` — glass lens now correctly refracts active tab icons.** Previously the selected icon layer was rendered *above* the `AnimatedGlassIndicator` in a separate compositor layer, making it invisible to the `BackdropFilter`. The glass pill swept over a blank canvas, producing a flat, unrefracted active icon. Both the selected and unselected icon layers are now combined into a single `RepaintBoundary` placed *behind* the glass lens, so all icon colours are physically sampled and warped by the chromatic aberration as the pill moves — matching iOS 26 behaviour.

- **Performance improvement.** The fix eliminates 5–9 redundant GPU compositor layers per bar render frame: the per-tab `RepaintBoundary` nodes on both the selected and unselected icon rows have been removed in favour of a single shared compositor texture for the entire icon canvas. Fewer texture uploads, one `BackdropFilter` sample — net improvement at 120 Hz.

---

# 0.8.2


## Bug Fixes

- **`GlassQuality.premium` no longer crashes outside a `LiquidGlassLayer`.** Previously caused an opaque `Null check operator` crash. Now throws a descriptive `AssertionError` in debug builds and falls back gracefully (renders child without glass) in release. Fix: add `useOwnLayer: true` to any standalone `GlassButton` using `premium` quality.

- **`GlassBottomBar` / `GlassSearchableBottomBar` — repeat-tap on active tab now fires `onTabSelected` ([#22](https://github.com/sdegenaar/liquid_glass_widgets/issues/22)).** Previously the `index != widget.tabIndex` guard silently suppressed callbacks when the user tapped the already-selected tab, making it impossible to implement scroll-to-top or refresh-on-retap patterns. The guard has been removed; `onTabSelected` is now always called once per gesture lifecycle regardless of whether the tab index changes.

- **`GlassBottomBar` / `GlassSearchableBottomBar` — drag-end snaps to correct tab ([#23](https://github.com/sdegenaar/liquid_glass_widgets/pull/23)).** A coordinate-space mismatch in `_onDragEnd` caused the indicator to snap to the wrong tab: dragging to the centre of a 5-tab bar landed on tab 3 instead of tab 2. The fix corrects the inversion formula to `i = round(relX × (n − 1))`, which is the exact inverse of the alignment space `computeAlignment(i, n) = −1 + 2i/(n−1)`.

- **`GlassBottomBar` / `GlassSearchableBottomBar` — `onTabSelected` no longer fires twice per tap.** `BottomBarTabItem` had its own `onTap: () => onTabSelected(i)` callback that fired independently of the outer `TabIndicator`'s `onTapDown` handler, causing every tap to call `onTabSelected` twice. The item-level callback is now `null`; the outer indicator is the single source of truth for all selection events.

  > **Credit:** These interaction fixes were identified and originally patched by [@qinshah](https://github.com/qinshah) in [PR #23](https://github.com/sdegenaar/liquid_glass_widgets/pull/23). The implementation was refactored to preserve the existing jelly physics, desktop tap support, and fling-based navigation that the PR removed, and extended to cover `GlassSearchableBottomBar` with shared logic via the new internal `TabDragGestureMixin`.

## API

- **`GlassSearchBarConfig.expandWhenActive`** *(new)*. Controls whether the search pill expands when `isSearchActive` is `true`. Default `true` — no change needed for standard usage. Set to `false` for advanced layouts (e.g. Apple Music Play Pill pattern) where the search pill should remain compact while `isSearchActive` drives a non-search transition independently.

## Examples

- **`apple_music_demo`** — added as a reference for the Play Pill pattern: a floating `GlassButton` (`useOwnLayer: true`, `GlassQuality.premium`) that animates between a full-screen player and a mini-mode docked pill using `AnimatedPositioned` + `AnimatedOpacity`, synchronized with `GlassSearchableBottomBar`'s spring morph via `expandWhenActive`.

---


# 0.8.1

## New Features

### `GlassInteractionBehavior` — precise, orthogonal control of press interactions

A new first-class enum that independently controls the two dimensions of press
feedback on `GlassBottomBar`, `GlassSearchableBottomBar`, and `GlassTextField`
(as well as its derivative inputs):

| Value | Glow | Scale |
|---|---|---|
| `none` | ✗ | ✗ |
| `glowOnly` | ✓ | ✗ |
| `scaleOnly` | ✗ | ✓ |
| `full` *(default)* | ✓ | ✓ |

The *glow* is the iOS 26-style directional light spotlight that follows the
touch position across the glass surface. The *scale* is the spring-physics
size pulse on press.

```dart
// Glow only — light follows your finger, no bounce:
GlassBottomBar(
  interactionBehavior: GlassInteractionBehavior.glowOnly,
  ...
)

// Scale only — spring bounce, no glow:
GlassSearchableBottomBar(
  interactionBehavior: GlassInteractionBehavior.scaleOnly,
  pressScale: 1.06,
  ...
)

// Disable both for a completely static bar:
GlassBottomBar(
  interactionBehavior: GlassInteractionBehavior.none,
  ...
)
```

**Zero overhead when disabled.** When `interactionBehavior` suppresses glow (`none`
or `scaleOnly`), the `GlassGlow` sensor widget is removed from the tree entirely —
saving 3 widget allocations and 3 `RenderBox` nodes per tab indicator per frame.
Scale is resolved at build time to a scalar `1.0` with no animation controller
overhang.

### New parameters on `GlassBottomBar`, `GlassSearchableBottomBar`, and `GlassTextField`

`GlassTextField` now shares the same `interactionBehavior` API as the bar-family
widgets. The *scale* dimension maps onto the subtle press-bounce animation
(field squishes slightly when pressed down); the *glow* dimension is the directional
spotlight that tracks touch position across the glass surface.

`GlassPasswordField` and `GlassTextArea` delegate to `GlassTextField` and inherit
the new parameter automatically.

| Parameter | Widget(s) | Type | Default |
|---|---|---|---|
| `interactionBehavior` | All three | `GlassInteractionBehavior` | `.full` |
| `pressScale` | Bar widgets / Inputs | `double` | `1.04` (bars) / `1.03` (inputs) |
| `interactionGlowColor` | Bar widgets | `Color?` | `null` (theme default) |
| `glowColor` | `GlassTextField` | `Color?` | `null` (~12% white) |
| `interactionGlowRadius` | Bar widgets | `double` | `1.5` |
| `glowRadius` | `GlassTextField` | `double` | `1.5` |

All defaults preserve existing `0.8.0` visual behaviour — **no migration required**.

#### Migration from `enableGlow` / `enableFocusAnimation`

`GlassTextField.enableGlow` and `GlassTextField.enableFocusAnimation` have been
replaced by `interactionBehavior`. The mapping is direct:

```dart
// Before (0.8.0):
GlassTextField(enableGlow: false, enableFocusAnimation: false)

// After (0.8.1):
GlassTextField(interactionBehavior: GlassInteractionBehavior.none)

// Before: glow only
GlassTextField(enableGlow: true, enableFocusAnimation: false)
// After:
GlassTextField(interactionBehavior: GlassInteractionBehavior.glowOnly)
```


## Bug Fixes

- **FIX**: `SearchPill` was silently ignoring `interactionBehavior`. The `interactionGlowColor`
  parameter was never passed to the `SearchPill` constructor, so the search pill always rendered
  with a visible glow regardless of the bar's `interactionBehavior` setting. The glow was
  hardcoded to `Color(0x1FFFFFFF)` even when `behavior = none`.

- **FIX**: `SearchPillState` had no glow short-circuit on the expanded pill path. Added
  `_wrapWithGlow` helper (matching the pattern already in `TabIndicatorState` and
  `SearchableTabIndicatorState`) to skip `GlassGlow` allocation when glow is suppressed.

---

# 0.8.0

## New Features

### `GlassAdaptiveScope` *(experimental)* — automatic runtime quality adaptation

A new scope widget that automatically adjusts `GlassQuality` for its subtree
based on real raster performance observed from `SchedulerBinding` frame timings.
Handles the three device scenarios that are impossible to test on a developer
device:

- **Broken / slow shader drivers** (e.g. Pixel 4a, Galaxy A22 class): detected
  synchronously at startup via `ImageFilter.isShaderFilterSupported` and capped
  immediately to `minimal`.
- **Warm-up jank** ("wrong quality at startup"): resolved by a ~180-frame
  benchmark that measures real P75 raster durations and sets the initial quality
  tier before the user notices.
- **Thermal throttling** ("fine at launch, janky after 10 minutes"): detected
  and corrected by a continuous runtime hysteresis engine.

**Three-phase adaptation:**

| Phase | Trigger | Action |
|---|---|---|
| Phase 1 — Static probe | Mount | Forces `minimal` on unsupported hardware; caps at `standard` on web |
| Phase 2 — Warm-up | First ~180 frames (~3 s at 60 fps) | Sets initial quality from real P75 raster durations |
| Phase 3 — Runtime hysteresis | Ongoing | Degrades after 3 bad windows; recovers after 10 good windows (8 s cooldown) |

The scope acts as a **quality ceiling** — widgets with an explicit `quality:`
parameter are unaffected. The ceiling is enforced by
`GlassThemeHelpers.resolveQuality`, which reads `GlassAdaptiveScopeData` from
the nearest ancestor scope.

```dart
// Per-screen control:
GlassAdaptiveScope(
  child: Scaffold(...),
)

// Advanced — conservative start for fragmented Android market:
GlassAdaptiveScope(
  initialQuality: GlassQuality.standard, // earn your way up to premium
  allowStepUp: true,
  onQualityChanged: (from, to) => analytics.log('glass_quality_changed'),
  child: child,
)
```

> **Experimental in 0.8.0.** `GlassAdaptiveScope` and `GlassAdaptiveScopeConfig` are
> annotated `@experimental`. The three-phase adaptation logic is architecturally sound
> and fully tested, but the Phase 2 timing thresholds (P75 < 12 ms → premium,
> 12–20 ms → standard, > 20 ms → minimal) have been validated by reasoning, not yet
> by broad real-device data across the Android fragmentation landscape.
>
> **How to enable it:** `LiquidGlassWidgets.wrap(myApp, adaptiveQuality: true)`
> (opt-in, default `false`).
>
> **If you observe unexpected behaviour** — quality too low on a mid-range device,
> or stuck at `standard` on a flagship — please file an issue with your device model
> and raster timings from Flutter DevTools. Your data will be used to tune the
> thresholds for a future release.

### `GlassAdaptiveScopeConfig` *(experimental)* — portable configuration value object

Bundles all `GlassAdaptiveScope` parameters into a single `const`-constructible,
equality-comparable value object. Used by `LiquidGlassWidgets.wrap()` and useful
for passing scope configuration through APIs that cannot accept widget parameters
directly.

```dart
const config = GlassAdaptiveScopeConfig(
  initialQuality: GlassQuality.standard,
  allowStepUp: true,
  targetFrameMs: 8, // 120 Hz ProMotion
);
```

## API Refactor — `initialize()` and `wrap()` separation

The responsibilities of `initialize()` and `wrap()` have been clarified and
made consistent with the broader Flutter ecosystem (cf. `easy_localization`,
`MaterialApp`):

| Method | Responsibility |
|---|---|
| `initialize()` | Async platform / engine setup only (shader prewarming, Impeller pipeline, debug monitor) |
| `wrap()` | Widget-tree composition and all behavioral configuration |

### `wrap()` — new parameters

```dart
runApp(LiquidGlassWidgets.wrap(
  const MyApp(),
  respectSystemAccessibility: false, // moved from initialize()
  adaptiveQuality: true,             // new — inserts GlassAdaptiveScope
  adaptiveConfig: GlassAdaptiveScopeConfig(
    initialQuality: GlassQuality.standard,
    allowStepUp: true,
  ),
));
```

### Scope nesting order inserted by `wrap()`

`GlassAdaptiveScope` → `GlassBackdropScope` → `child`

## Breaking Changes

### `initialize(respectSystemAccessibility:)` removed

`respectSystemAccessibility` has moved from `initialize()` to `wrap()`.

**Migration** (one-line change):

```dart
// Before (0.7.x):
await LiquidGlassWidgets.initialize(respectSystemAccessibility: false);
runApp(LiquidGlassWidgets.wrap(const MyApp()));

// After (0.8.0):
await LiquidGlassWidgets.initialize();
runApp(LiquidGlassWidgets.wrap(const MyApp(), respectSystemAccessibility: false));
```

The `LiquidGlassWidgets.respectSystemAccessibility` getter and setter remain
available as an escape hatch for tests and advanced runtime overrides. In
production code, set it through `wrap()`.

## Bug Fixes

### Glass invisible on white / light backgrounds (transparency regression)

- **FIX**: Standalone glass widgets (`GlassButton`, `GlassContainer`, `GlassTextField`,
  `GlassCard`, and all widgets that delegate to them) rendered with zero opacity on
  light backgrounds when no explicit `settings:` were provided. Root cause: these
  widgets fell through to `InheritedLiquidGlass.ofOrDefault()`, which returns
  `LiquidGlassSettings()` — a default with `glassColor: Color(0x00FFFFFF)` (alpha = 0).
  The lightweight shader computes `body tint = glassColor.alpha × 0.15`, so
  `0 × 0.15 = 0` — the glass body was literally transparent regardless of `thickness`
  or `blur`.

  **Fix**: Replaced all `InheritedLiquidGlass.ofOrDefault()` call sites with the new
  `GlassThemeHelpers.resolveSettings()`, which traverses the full 5-level priority chain:

  1. Widget-level `settings:` parameter (explicit wins)
  2. `InheritedLiquidGlass` — nearest parent `AdaptiveLiquidGlassLayer`
  3. `LiquidGlassWidgets.globalSettings` — app-level override
  4. `GlassThemeData` — brightness-aware theme variant (light / dark)
  5. `LiquidGlassSettings()` — absolute last resort

  Standalone widgets now correctly resolve to the theme's `glassColor` and are
  always visible out of the box.

### Light theme defaults rebalanced

- **TWEAK**: `GlassThemeVariant.light` updated for an icy-frosted aesthetic that
  reads clearly on white backgrounds:

  | Property | Before | After |
  |---|---|---|
  | `blur` | 10.0 | 6.0 |
  | `glassColor` | `0x73FFFFFF` (45% neutral white) | `0x4AD2DCF0` (~29% cool blue-white) |
  | `chromaticAberration` | 0.1 | 0.3 |
  | `thickness` | 16.0 | 20.0 |
  | `lightIntensity` | 1.0 | 1.2 |

  The cool blue-white tint (`D2DCF0`) matches the icy tone of iOS 26 frosted glass.
  Blur 6 gives visible background diffusion without obscuring content.

## API

### `GlassBackdropScope` now exported from the main barrel

- **FIX**: `GlassBackdropScope` was missing from `liquid_glass_widgets.dart`. Consumers
  had to use the internal path
  `package:liquid_glass_widgets/widgets/shared/glass_backdrop_scope.dart`, which is
  fragile and undocumented. It is now a first-class public export.

  **Migration** — update any direct internal imports:
  ```dart
  // Before (workaround, fragile):
  import 'package:liquid_glass_widgets/widgets/shared/glass_backdrop_scope.dart';

  // After (correct):
  import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
  ```

- **CHORE**: add CI and Codecov badges.

# 0.7.16

### Bug Fixes

- **FIX**: `GlassSearchableBottomBar` — memory leak when `controller` was swapped at runtime. The old controller's listener was never removed before attaching to the new controller. Now correctly removed in `didUpdateWidget`.
- **FIX**: `DraggableIndicatorPhysics` — velocity NaN/Infinity guard. A zero-size render box (e.g. during widget tree warm-up) could produce `Infinity` or `NaN` for `velocityX`, which propagated into the spring physics and caused erratic snapping. Now clamped to 0 when the box has no size.

### Refactor (zero breaking changes)

- **REFACTOR**: Extracted `GlassSearchBarConfig` from `glass_searchable_bottom_bar.dart` into a dedicated file `lib/widgets/surfaces/shared/glass_search_bar_config.dart`. Resolves a circular import between the public widget and its internal sub-widgets. `GlassSearchBarConfig` is re-exported from the barrel file — no consumer-facing API change.
- **REFACTOR**: Extracted `_TabIndicator` / `_TabIndicatorState` from `glass_bottom_bar.dart` into `shared/bottom_bar_internal.dart` as `TabIndicator` / `TabIndicatorState` (package-internal, not exported). Follows the same pattern used for `GlassSearchableBottomBar`. `glass_bottom_bar.dart` reduced from **1,406 → ~895 lines**.
- **REFACTOR**: Extracted `_TabBarContent`, `_TabBarContentState`, and `_TabItem` from `glass_tab_bar.dart` into `shared/tab_bar_internal.dart`. `glass_tab_bar.dart` reduced from **728 → ~310 lines**. Architecture is now consistent across all bar-family widgets.

### Test Coverage

- **TEST**: Reached **91.85% effective coverage** (up from 89.6% in 0.7.15 — excluding GPU/shader renderer paths that are physically untestable in a headless VM). Total: **1,031 tests**, all passing, 0 analyzer warnings.
- **TEST**: New `test/widgets/surfaces/glass_bottom_bar_drag_test.dart` — 7 regression tests covering `_onDragEnd` physics snapping, `_onDragCancel` (mid-drag and no-drag), slow drags, fast flings, and full-bar sweeps. These paths are the highest-risk regressions in navigation UX.

# 0.7.15


### Bug Fixes

- **FIX**: `lib/theme/glass_theme_settings.dart` was accidentally omitted from version control in 0.7.14. All consumers of `GlassThemeSettings` received a compile error (`type 'GlassThemeSettings' is not a subtype`). This release commits the missing file. No API change — `GlassThemeSettings` was already exported from `liquid_glass_widgets.dart`.
- **FIX**: `GlassPerformanceMonitor._emitWarning` — division-by-zero crash when `rasterBudget` was sub-millisecond (< 1 ms). Protected with a `max(1, ...)` guard.

### Refactor (zero breaking changes)

- **REFACTOR**: Consolidated 18 quality-resolution chains (`widgetQuality ?? inherited?.quality ?? themeData.qualityFor(context) ?? GlassQuality.standard`) into a single canonical helper: `GlassThemeHelpers.resolveQuality(context, widgetQuality: ..., fallback: ...)`. Surface widgets (`GlassAppBar`, `GlassToolbar`, `GlassBottomBar`, `GlassSearchableBottomBar`, `GlassSideBar`) pass `fallback: GlassQuality.premium` to preserve their documented defaults. All other widgets default to `GlassQuality.standard`.
- **REFACTOR**: Extracted `_buildIconShadows` from `BottomBarTabItem` to a `@visibleForTesting` top-level function `buildIconShadows(...)` in `bottom_bar_internal.dart`. No behaviour change — enables isolated unit testing of the shadow-outline geometry.

### Test Coverage

- **TEST**: Reached **90%+ effective test coverage** (90.15% — excluding `src/renderer` GPU/shader layer where headless simulation is impossible). Total: **949 tests**, all passing.
- **TEST**: New `test/theme/glass_theme_helpers_test.dart` — 5 widget tests covering all 4 priority levels of `GlassThemeHelpers.resolveQuality()`.
- **TEST**: New `test/widgets/surfaces/build_icon_shadows_test.dart` — 6 unit tests covering `buildIconShadows()`: null thickness, active-icon suppression, shadow count, 45° offset math, and color propagation.
- **TEST**: Added `test/theme/`, `test/renderer/`, `test/types/`, `test/constants/`, `test/utils/`, and `test/widgets/` test suites (committed for the first time — these were written during the 0.7.13–0.7.14 coverage push but never staged).

# 0.7.14

### Bug Fixes


- **FIX**: `GlassSearchableBottomBar` — `extraButton` now fades out smoothly when search activates instead of being visually clipped/shrunk between the collapsing tab pill and the expanding search pill. Layout space is still reserved during the morph (no pills jump), only the visual opacity transitions. Taps on the extra button are also correctly blocked while hidden. Fades in when search closes.
- **FIX**: `GlassSearchableBottomBar` — spring morph animations no longer produce a visible jump when reversing direction. Previously the three spring controllers (`tabW`, `searchLeft`, `searchW`) were each started in separate `addPostFrameCallback` calls, introducing a 1-frame desync at reversal. All three are now started in a single batched callback, so the morph is perfectly synchronized in both directions.
- **FIX**: Indicator fade animation in `GlassBottomBar` / `GlassSearchableBottomBar` — replaced `Opacity` wrapper with `LiquidGlassSettings.visibility` fading. Wrapping a `BackdropFilter` in `Opacity` composites into an offscreen buffer, breaking backdrop sampling and causing the indicator to snap in/out instead of fading. The `visibility` path is a single GPU pass — no offscreen buffer — improving drag animation performance and working uniformly for all `blur` values.
- **FIX**: `GlassBottomBar`, `GlassSearchableBottomBar`, `GlassAppBar`, `GlassToolbar`, and `GlassSideBar` resolved to `GlassQuality.standard` instead of their documented `GlassQuality.premium` default. Fixed by setting `quality: null` in the built-in light/dark variants so each widget's documented default is respected.
- **FIX**: Setting any property in `GlassThemeVariant.settings` silently zeroed out all unset properties (e.g. setting only `thickness: 50` also reset `glassColor` to fully transparent). Fixed by introducing `GlassThemeSettings`: a parallel class with all-nullable fields that merges onto each widget's own defaults. Only the fields you explicitly set are applied; everything else inherits from the widget. `GlassThemeVariant.settings` now accepts `GlassThemeSettings?`.
- **FIX**: `GlassSearchableBottomBar` — multiple layout-math regressions in the morph animation corrected:
  - Reserved layout width now correctly scales to `min(size, searchBarHeight)` during search, eliminating the bloated gap when `searchBarHeight < barHeight`.
  - Extra button rendered width now matches the layout reserve (`extraTargetW`), preventing a 14 px overflow into the search pill when `searchBarHeight < barHeight`.
  - Restored `+ widget.spacing` in `targetSearchLeft`; an erroneous `tabToNextGap` variable had suppressed the gap between the tab pill and search pill when no extra button was present.
  - `collapseOnSearchFocus` now exclusively controls visibility/opacity — it no longer affects layout geometry. Toggling it mid-animation no longer triggers the spring or causes the button to jump inside the collapsed tab circle.
- **FIX**: `BottomBarTabItem` — removed a fixed `vertical: 4` padding wrapping the tab column. The padding consumed constraint space before `FittedBox` could scale, causing a 2 px `RenderFlex` overflow when the bar morphed to `searchBarHeight`.

### New

- **NEW**: `GlassThemeSettings` — a partial settings type for use in `GlassThemeVariant`. Accepts the same parameters as `LiquidGlassSettings` but all are nullable. Only non-null fields override the target widget's defaults, enabling precise single-property theme overrides without disturbing others.
- **NEW**: `GlassTabPillAnchor` enum + `GlassSearchableBottomBar.tabPillAnchor` — controls how the tab pill is anchored during the morph animation. `GlassTabPillAnchor.start` (default) preserves existing left-anchor behaviour. `GlassTabPillAnchor.center` makes both edges collapse symmetrically from the pill's centre for a more balanced look. The search pill position adjusts automatically in center mode.
- **NEW**: `GlassSearchBarConfig.showsCancelButton` now defaults to `true`. Tapping the dismiss pill unfocuses the keyboard and collapses search, matching the system-level behaviour seen across iOS apps (Weather, App Store, Apple News). Pass `showsCancelButton: false` to opt out.
- **NEW**: `GlassSearchBarConfig.collapsedTabWidth` is now nullable. When omitted, the collapsed tab pill automatically matches `GlassSearchableBottomBar.searchBarHeight`, ensuring it morphs into a geometric circle with no leftover horizontal margin. Pass an explicit value to override.
- **NEW**: `GlassBottomBarExtraButton.collapseOnSearchFocus` (default `true`) — controls whether the extra button collapses when the search field is focused. When `true`, the button fades out and its layout space spring-animates to zero, giving the search input the full available width (matching native iOS behaviour). When `false`, the button remains fully visible and tappable alongside the search input — useful for contextually relevant actions like a Filter button that applies to search results.
- **EXAMPLE**: `searchable_bar_repro.dart` added to the example app — exercises `GlassSearchableBottomBar` edge cases (extra-button fade, spring desync, bar-height scale, dismiss pill) in isolation. Run standalone: `flutter run -t example/lib/searchable_bar_repro.dart`.

# 0.7.13

### New — `GlassQuality.minimal`

- **FEAT**: `GlassQuality.minimal` — third quality tier: a crisp frosted glass surface with
  zero custom fragment shader execution on any platform. Uses `BackdropFilter` blur
  + Rec. 709 saturation matrix + a light-angle specular rim stroke. No refraction
  warping or chromatic aberration — a deliberately flat, clean aesthetic that looks
  excellent on any background and never adds GPU shader cost.

  Two distinct use cases:

  **Device fallback** — for hardware where even [standard] is too heavy:
  very old Android devices with limited shader driver support, or any device where
  `ImageFilter.isShaderFilterSupported` returns `false`.

  **GPU budget management** — for shader-dense screens: use [minimal] for background
  panels, list cards, and decorative containers while keeping [standard] or [premium]
  on the focal element. A screen with 15 glass list cards running [minimal] fires
  zero shader invocations during scroll — only `BackdropFilter` compositing.

  ```dart
  AdaptiveGlass(
    quality: GlassQuality.minimal,
    child: child,
  )
  ```

- **FEAT**: `GlassThemeVariant.minimal` — static preset that applies `.minimal` quality globally via
  `GlassThemeData`:

  ```dart
  GlassTheme(
    data: GlassThemeData(
      light: GlassThemeVariant.minimal,
      dark:  GlassThemeVariant.minimal,
    ),
    child: child,
  )
  ```

### New — `GlassPerformanceMonitor`

- **FEAT**: Debug/profile-only performance monitor that watches raster frame durations while
  `GlassQuality.premium` surfaces are active. When frames exceed the GPU budget
  for 60 consecutive frames, a single `FlutterError` is emitted with actionable guidance
  (specific widget parameters, device compatibility notes, and alternative quality tiers).

  **Zero production overhead** — the monitor never registers a callback in release builds.
  Enabled by default in debug/profile builds via `LiquidGlassWidgets.initialize()`:

  ```dart
  // Default: auto-enabled in debug/profile, zero-cost in release
  await LiquidGlassWidgets.initialize();

  // Opt out:
  await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);

  // Custom thresholds (advanced):
  GlassPerformanceMonitor.rasterBudget = const Duration(microseconds: 8333); // 120 fps
  GlassPerformanceMonitor.sustainedFrameThreshold = 120; // 2 seconds at 60 fps
  ```

  The monitor correctly attributes slowdowns to premium glass by counting active
  `GlassQuality.premium` surfaces. It stays silent when no premium widgets are mounted,
  avoiding false positives from other parts of the app.

---

# 0.7.12

### Bug Fixes

- **FIX**: Interactive blend-group stretch asymmetry — `LiquidStretch` now expands geometry symmetrically from the widget centre, fixing the left-leans-in / right-resists imbalance during touch-drag on button groups.

- **FIX**: Erroneous highlight bias — removed a legacy shader hack that skewed surface normals horizontally. Normals are now derived accurately from the SDF gradient, eliminating optical hotspots that made straight groups look crooked.

- **PERF**: Zero-jitter animation bounds — geometry texture mapping is now strictly bound to the physical size it was rasterised for, stopping frame-lag wobble when buttons change scale during interactive drags.

- **FIX**: Theme quality cascade — audited 15+ widgets (`GlassBottomBar`, `GlassSwitch`, `GlassTextField`, and others) that were silently overriding the global `GlassThemeVariant` quality setting with `GlassQuality.premium`. All widgets now correctly inherit and respect the global quality profile, protecting frame rate and thermal limits on older devices (e.g. iPhone 12 and below).

- **FIX**: Zero-thickness blur — setting `thickness: 0` no longer makes the glass fully transparent. Backdrop blur now renders correctly on glass surfaces regardless of geometric thickness, restoring backward-compatible behaviour.

- **FEAT**: `GlassSearchBarConfig.focusNode` — optional `FocusNode` for `GlassSearchBarConfig`. When provided, the caller has full programmatic focus control (`requestFocus()`, `unfocus()`, `addListener()`) independent of `autoFocusOnExpand`. The widget adopts the caller-provided node without disposing it (caller owns lifecycle), matching Flutter's own `TextField.focusNode` contract.

- **FEAT**: `GlassSearchBar.focusNode` — same `FocusNode` support added to the standalone `GlassSearchBar` for consistency. `GlassTextField` already had this.

- **FIX**: `ExtraButtonPosition` — new enum on `GlassBottomBarExtraButton`. Set `.position = ExtraButtonPosition.afterSearch` to pin the extra button to the **right** of the search pill. Spring geometry calculations reserve space correctly to prevent `RenderFlex` overflows during expand/collapse. Default is `ExtraButtonPosition.beforeSearch` — fully backwards-compatible.

- **FIX**: Windows / SkSL shader compilation — eliminated all dynamic array index expressions from `sdf.glsl`. The previous `getShapeSDFFromArray(int index)` computed offsets at runtime, which SkSL/glslang on Windows rejects with *"index expression must be constant"*. Replaced with literal-indexed `sdf0()`…`sdf15()` helpers and a fully-unrolled `sceneSDF` for 1–16 shapes. `MAX_SHAPES` stays 16; no API or visual change.

- **TOOLING**: `scripts/validate_shaders.sh` — macOS script that validates all shaders against Windows/SkSL compiler rules using `glslangValidator`. Run `bash scripts/validate_shaders.sh` before releasing. Requires `brew install glslang` (one-time).

---

# 0.7.11

### Bug Fixes

- **FIX**: Windows/Android build failure — three shader compilation errors on the SPIR-V/glslang path: loop bounds must be compile-time constants; `dFdx`/`dFdy` on a scalar `float` is rejected by glslang (geometry shader now uses `#ifdef IMPELLER_TARGET_METAL` to keep hardware derivatives on iOS/macOS and fall back to ±0.5 px finite differences on Vulkan/OpenGL ES); global non-constant initialisers at file scope in `liquid_glass_final_render.frag` moved into `main()`.

- **FIX**: Blend-group asymmetry — the liquid-glass merge neck between grouped buttons leaned toward the left button. Fixed with a bidirectional smooth-union pass (L→R + R→L, averaged 50/50) that cancels the directional bias exactly.

---

# 0.7.10

### Bug Fixes

- **FIX**: Windows build (`flutter build windows`) — two shader issues fatal on SkSL/glslang but silently accepted on Metal: `no match for min(int, int)` (replaced with a ternary) and global non-constant initialisers (moved into `main()`). No visual change on any platform.

---

# 0.7.9

### Bug Fixes

- **FIX**: Windows build failure — `uShapeData[MAX_SHAPES * 6]` was passed as a by-value function parameter, which glslang rejects. Fixed by accessing it as a global uniform. No visual change.

### Tweaks

- **TWEAK**: `GlassSearchableBottomBar` iOS 26 Apple News parity — animated inline `×` clear button replaces microphone when text is present; simplified hit-testing layout replaces `Overlay` layers; guaranteed GPU liquid-glass merging between the search and dismiss pills in a single shader pass.

---

# 0.7.8

### Tweaks

- **TWEAK**: `GlassThemeVariant.light` now defaults to a cool-tinted `glassColor` (`Color(0x32D2DCF0)`), stronger `refractiveIndex`, and boosted `ambientStrength` to ensure premium specular rendering and visible refraction on flat white backgrounds.

### Examples

- **Apple News demo** — replaced `Image.network` calls with pre-sized bundled assets (`example/assets/news_images/`) to fix Impeller GPU command-buffer overflow on iOS 26 physical devices.
- **Apple News demo** — `collapsedLogoBuilder` now mirrors the active tab icon instead of a static badge.

---

# 0.7.7

### Refactor

- **Internal**: Removed `GlassIndicatorTapMixin` and migrated `GlassTabBar` and `GlassSegmentedControl` fully to raw `Listener` pointer events, matching `GlassBottomBar`'s robust drag-cancel and press-and-hold handling. No API change.

---

# 0.7.6

### Bug Fixes

- **FIX**: `LiquidGlassBlendGroup` asymmetry — left buttons attracted their neighbours more strongly than right buttons in groups of 3+. Fixed with a bidirectional smooth-union pass (L→R + R→L, averaged 50/50). Two-shape groups are mathematically identical to before.

- **FIX**: `GlassButtonGroup` — glass effect could bleed as a dark rectangle on Impeller with `GlassQuality.premium` and `useOwnLayer: true`. A `ClipRRect(antiAlias)` now hard-clips the bleed at the superellipse boundary without forcing a quality downgrade.

---

# 0.7.5

### Bug Fixes

- **FIX**: `GlassBottomBar` / `GlassSearchableBottomBar` — added `HitTestBehavior.opaque` to the root `GestureDetector` so the full bar height reliably consumes pointer events on simulator and desktop.

- **FIX**: `GlassSearchableBottomBar` — keyboard no longer flickers on physical devices; focus is requested after the expansion animation completes.

- **FIX**: `GlassSearchableBottomBar` — dead zone at expanded search pill edges resolved; the full glass surface now claims taps and routes them to the search field.

### New — `GlassSearchBarConfig` parameters

Seven new parameters (all backwards-compatible):

| Parameter | Type | Default | Description |
|---|---|---|---|
| `autoFocusOnExpand` | `bool` | `false` | Keyboard opens automatically on expand. |
| `trailingBuilder` | `WidgetBuilder?` | `null` | Replaces the mic icon with any custom widget. |
| `textInputAction` | `TextInputAction?` | `null` | Keyboard action key (`search`, `done`, `go`, …). |
| `keyboardType` | `TextInputType?` | `null` | Keyboard layout (`url`, `emailAddress`, …). |
| `autocorrect` | `bool` | `true` | Disable for codes, usernames, etc. |
| `enableSuggestions` | `bool` | `true` | Controls QuickType bar on iOS. |
| `onTapOutside` | `TapRegionCallback?` | `null` | Called when user taps outside the field. |

---

# 0.7.4

### New Components

- **`GlassSearchableBottomBar`** — `GlassBottomBar` with a morphing search pill that shares the same `AdaptiveLiquidGlassLayer` as the tab pill, producing iOS 26 liquid-merge blending. When `isSearchActive` is `true` the tab pill collapses and the search pill expands via spring animation. Configured via `GlassSearchBarConfig`.

### Examples

- **Apple News demo** (`example/lib/apple_news/apple_news_demo.dart`) — iOS 26 Apple News replica showcasing `GlassSearchableBottomBar`.

### Visual Fixes

- **FIX**: Default glow color on press changed from iOS system blue to a brightness-adaptive neutral white (~35% light / ~22% dark), matching iOS 26 glass press behaviour.

---

# 0.7.3

### Performance

- **PERF**: Deleted unused `rotate2d()` from `render.glsl` — it was compiled into every shader binary but never called.
- **PERF**: Eliminated a redundant `normalize()` in `interactive_indicator.frag` by reusing an already-computed length.
- **PERF**: Removed a no-op `canvas.save()`/`canvas.restore()` pair in `GlassGlow` paint.

### Bug Fixes

- **FIX**: `GlassGlow` tracking — glow gradient is now correctly recreated each frame when `glowOffset` changes, fixing the spotlight freezing at its initial position.
- **FIX**: Glow on Skia/Web — `LightweightLiquidGlass` now wraps in `GlassGlowLayer`, giving the Skia path the same light-follows-touch behaviour as Impeller.
- **FIX**: Glow on first touch — spotlight now appears immediately at the tap position instead of sliding in from the widget's top-left corner.
- **FIX**: Glow tracking inside button groups — converted from widget-local to global coordinates so the spotlight correctly follows touches regardless of nesting depth.
- **FIX**: Glow radius on wide buttons — switched from `shortestSide` to `√(width × height)` so the spotlight scales proportionally to the button area.

---

# 0.7.2

### Performance & Polish

- **PERF**: Lightweight shader (`lightweight_glass.frag`) — reduced ALU instruction count ~10–15 ops per fragment; restored the `normalZ` Fresnel ramp to `sqrt(1 − dot(n,n))`.
- **PERF**: Impeller final render shader — eliminated `length()`/`normalize()` from anisotropic specular; made `getHeight()` fully branchless; collapsed four `step()` multiplications into one.
- **PERF**: Dart side — cached light direction trig in `LiquidGlassRenderObject` (only recomputed when `lightAngle` changes); changed `GlassGroupLink.shapeEntries` from `List` to `Iterable` to eliminate per-frame heap allocation.
- **FIX**: Adjusted `GlassBottomBar`, `GlassTabBar`, and `GlassSegmentedControl` spring from 500ms `bouncySpring` to 350ms `snappySpring`, matching iOS 26 segment-indicator physics.

---

# 0.7.1

### Bug Fixes

- **FIX**: `GlassBottomBar`, `GlassTabBar`, `GlassSegmentedControl` — rapid taps no longer prematurely snap the indicator, killing spring physics. Removed pixel-snapping from `onHorizontalDragDown` so taps correctly use spatial distance for the iOS 26 jump animation.

---

# 0.7.0

### New Components

- **`GlassDivider`** — iOS 26-style hairline separator, horizontal and vertical. Theme-adaptive opacity (dark: 20% white / light: 10% black).
- **`GlassListTile`** — iOS 26 Settings-style row with leading icon, title, subtitle, trailing widget, and automatic grouped dividers. Use inside a zero-padding `GlassCard`. Convenience constants: `GlassListTile.chevron`, `GlassListTile.infoButton`.
- **`GlassStepper`** — iOS 26 `UIStepper` equivalent. Compact `−`/`+` glass pill with auto-repeat on hold, `min`/`max` clamping, `wraps` cycling, fractional `step`, and haptic feedback.
- **`GlassWizard` + `GlassWizardStep`** — multi-step flow with numbered indicators, checkmarks, and expandable step content.

### Accessibility

- **`GlassAccessibilityScope`** — reads platform Reduce Motion and Reduce Transparency preferences and propagates them to all glass widgets in its subtree:
  - **Reduce Motion**: spring animations snap instantly.
  - **Reduce Transparency**: replaces the full glass shader pipeline with a plain `BackdropFilter(blur)` + frosted container.
- Semantics updated across all remaining widgets to match iOS `UIAccessibility` conventions.

### Performance

- **PERF**: `GlassSpecularSharpness` enum — replaces `pow(lightCatch, exponent)` (two transcendentals per fragment) with a pure squaring chain in `lightweight_glass.frag`. Zero transcendentals. Default: `.medium`.
- **PERF**: `pow(x, 1.5)` → `x·√x` in Impeller edge lighting — `sqrt()` is a single hardware SFU instruction.
- **PERF**: Anisotropic specular and Fresnel rim brightening ported from the Impeller path to `lightweight_glass.frag`, closing the largest visual gap between rendering paths.
- **PERF**: Content-adaptive glass strength — intensity auto-adjusts based on backdrop luminance on Impeller, or `MediaQuery.platformBrightness` on Skia/Web.

### Developer Experience

- **`GlassRefractionSource`** — renamed from `LiquidGlassBackground` to better reflect its role. `LiquidGlassBackground` remains as a deprecated `typedef` (removed in 1.0.0).
- **Synchronous background capture** — rebuilt using `boundary.toImageSync()` on native (zero CPU↔GPU readback) and async `toImage()` on web.

---

# 0.6.1

### Visual Quality

- **FIX**: True surface normal storage in geometry texture — the geometry pass now stores the SDF-gradient-derived surface normal instead of the refraction displacement vector. The render shader decodes and recomputes displacement via `refract()`. Specular highlights on blended glass shapes (e.g. two overlapping pills) now correctly follow true surface curvature rather than the refraction direction. Single-shape surfaces are visually identical to 0.6.0.
- **FIX**: Anisotropic specular highlights (Impeller) — specular lobe stretched 20% along the surface tangent, producing the horizontal oval highlight that matches iOS 26.
- **FIX**: Fresnel edge luminosity ramp (Impeller) — gentle brightness ramp at grazing angles matching iOS 26's centre-to-edge luminosity gradient.
- **FIX**: Luminosity-preserving glass tint in lightweight shader — replaced additive tint with the same `applyGlassColor()` model as the Impeller path: achromatic glass lifts toward white, chromatic glass shifts hue while preserving luminance.

### Performance

- **PERF**: Branchless `smoothUnion` — eliminated a conditional branch that caused warp divergence when glass shapes transition between merged and separate.
- **PERF**: `if/else if` dispatch in shape SDF — GPU now short-circuits after the first type match; default changed to `0.0` for a clearly visible failure mode.
- **PERF**: Single texture fetch when chromatic aberration is disabled — `interactive_indicator.frag` previously sampled the background three times unconditionally; 66% fewer texture reads in the common case.
- **PERF**: Flat-interior early-exit in final render shader — pixels where `normalXY ≈ 0` skip `refract()` and all texture samples, replaced with a single background sample. Lossless.

---

# 0.6.0

### Breaking Changes

- **`LiquidGlassLayer.useBackdropGroup` removed.** Glass layers now automatically detect a `BackdropGroup` ancestor. Remove `useBackdropGroup: true` from any `LiquidGlassLayer(...)` calls.

### New Features

- **`LiquidGlassWidgets.wrap()`** — wraps your app in a `GlassBackdropScope` in one line:
  ```dart
  runApp(LiquidGlassWidgets.wrap(const MyApp()));
  ```
- **`GlassMotionScope`** — drives glass specular angle from any `Stream<double>` (e.g. device gyroscope). No new dependencies required.

### Performance

- **PERF**: `GlassBackdropScope` auto-activation — glass layers automatically share a single GPU backdrop capture when a scope ancestor is present.
- **PERF**: Local-space geometry rasterization — geometry texture cached until pill size or shape changes, eliminating per-frame rebuilds during animation.
- **PERF**: Shader UV bounds check — discards fragments where geometry UV falls outside `[0, 1]`, preventing the thin "protruding line" artifact during jelly-physics expansion.

### Visual

- **FIX**: Refraction UV — uses `uSize` uniform (always valid on first frame) instead of `textureSize()` which returns `(0,0)` on the first frame in Impeller.
- **FIX**: `precision highp float` in final render shader (was `mediump`, risking colour banding on mobile).
- **FIX**: iOS 26 glass tint model — preserves backdrop luminance while shifting chroma. Replaces Photoshop Overlay mode.
- **FIX**: Leading-dot rim artifact — `x / (1 + x)` soft-clamping on highlight intensity prevents bright corner artifact during drag.
- **FIX**: Impeller indicator clipping — jelly physics animations no longer clip at the static bounding box (`clipExpansion` parameter added).
- **FIX**: Web & WASM — removed `dart:io` imports from shader resolution logic.

### Dependencies

- **Removed `motor` dependency** — replaced with self-contained `glass_spring.dart`. Zero third-party runtime dependencies beyond the Flutter SDK.

---

# 0.5.0

### Breaking Changes

**`LiquidGlass` removed from the public API.**
It was inadvertently exposed and silently renders nothing on Skia/Web. Use `AdaptiveGlass` instead:

```dart
// Before
LiquidGlass(settings: LiquidGlassSettings(...), child: ...)

// After
AdaptiveGlass(settings: LiquidGlassSettings(...), child: ...)
```

`LiquidGlassLayer`, `LiquidGlassBlendGroup`, `LiquidGlassSettings`, `LiquidShape`, `GlassGlow`, and `debugPaintLiquidGlassGeometry` remain public.

### New Features

- **`GlassBackdropScope`** — halves GPU blur capture cost when multiple glass surfaces are on screen simultaneously. Wrap your `MaterialApp` or `Scaffold` to activate:

```dart
GlassBackdropScope(
  child: MaterialApp(
    home: Scaffold(
      appBar: GlassAppBar(...),
      bottomNavigationBar: GlassBottomBar(...),
    ),
  ),
)
```

### Renderer

The renderer from `liquid_glass_renderer` (whynotmake.it, MIT) is now vendored directly, giving full control over the rendering pipeline with no user-facing API changes.

---

# 0.4.1

### Bug Fixes

- **FIX**: `GlassBottomBar` and other surfaces now correctly respond to dynamic `glassSettings` changes on `GlassQuality.standard` — `AdaptiveGlass` in grouped mode now inherits settings from `InheritedLiquidGlass` instead of using empty defaults.
- **FIX**: Luminance-aware ambient floor for white glass on `GlassQuality.standard` — high-opacity white glass no longer renders as dark grey.

### New

- **FEAT**: `GlassBottomBar.iconLabelSpacing` — configurable vertical gap between tab icon and label (default: `4.0`). Thanks @baneizalfe (#11).

### Breaking Changes

**Library-wide `IconData` → `Widget` API migration.** All icon parameters now accept any `Widget`:

```dart
// Before
GlassButton(icon: CupertinoIcons.heart, onTap: () {})

// After
GlassButton(icon: Icon(CupertinoIcons.heart), onTap: () {})
// Or any custom widget:
GlassButton(icon: SvgPicture.asset('assets/heart.svg'), onTap: () {})
```

`GlassBottomBarTab.selectedIcon` renamed to `activeIcon` to match Flutter's `BottomNavigationBarItem` convention.

---

# 0.4.0

### New Components

- **`GlassMenu` / `GlassMenuItem` / `GlassPullDownButton`** — iOS 26 morphing context menu with spring physics and position-aware expansion.
- **`GlassButtonGroup`** — joined-style container for related actions (e.g. Bold/Italic/Underline toolbar).
- **`GlassFormField`** / **`GlassPasswordField`** / **`GlassTextArea`** / **`GlassPicker`** — full iOS 26 input suite.
- **`GlassSideBar`** — vertical navigation surface with header, footer, and scrollable items.
- **`GlassToolbar`** — standard iOS-style action toolbar.
- **`GlassTabBar`** — horizontal tab navigation bar with animated indicator and scrollable mode for 5+ tabs.
- **`GlassProgressIndicator`** — circular and linear variants (indeterminate and determinate), iOS 26 specs.
- **`GlassToast` / `GlassSnackBar`** — 5 notification types, 3 positions, auto-dismiss, swipe-to-dismiss.
- **`GlassBadge`** — count and dot status badges, 4 positions.
- **`GlassActionSheet`** — iOS-style bottom-anchored action list.

### Performance

- **Universal Platform Support** — `AdaptiveGlass` and `AdaptiveLiquidGlassLayer` introduced. All 26 widgets deliver consistent glass quality on Web, Skia, and Impeller.
- **Batch-blur optimisation** — glass containers share a single `BackdropFilter` (was: one per widget). ~5× faster in common multi-widget layouts.
- **Impeller pipeline warm-up** — shaders pre-compile at startup to eliminate first-frame jank.

### Theme System

- **`GlassTheme` / `GlassThemeData` / `GlassThemeVariant`** — global styling and quality inheritance across all widgets. Set once, inherited everywhere.

---

# 0.3.0 — 0.1.0

Early access and preview releases establishing the core widget library, initial glass rendering pipeline (`LiquidGlass`, `LiquidGlassLayer`, `LiquidGlassBlendGroup`), and foundational components (`GlassBottomBar`, `GlassButton`, `GlassSwitch`, `GlassCard`, `GlassSearchBar`, `GlassSlider`, `GlassChip`, `GlassSegmentedControl`, `GlassSheet`, `GlassDialog`, `GlassIconButton`).
