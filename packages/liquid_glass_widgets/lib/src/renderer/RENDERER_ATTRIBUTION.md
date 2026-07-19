# Vendored: liquid_glass_renderer

This directory contains source code vendored from
[`liquid_glass_renderer`](https://github.com/whynotmake-it/flutter_liquid_glass/tree/main/packages/liquid_glass_renderer)
by **whynotmake.it**, licensed under the **MIT License**.

Vendored version: **0.2.0-dev.4** (vendored 2026-03-28)

---

## Why vendored

Vendoring the renderer source gives `liquid_glass_widgets` full control over the
rendering pipeline — bug fixes, improvements, and shader changes can be shipped
in lock-step with the widget layer without waiting on a separate package release
cycle. The original work by whynotmake.it remains the foundation; this is a
continuation of that effort within a single package.

---

## Public API surface

The renderer barrel (`liquid_glass_renderer.dart`) exports more types than
users of `liquid_glass_widgets` should interact with directly. The main package
barrel (`lib/liquid_glass_widgets.dart`) uses an explicit `show` clause to
control exactly what is public:

| Type | Public? | Reason |
|------|---------|--------|
| `LiquidGlassSettings` | ✅ | Core customisation — used everywhere |
| `LiquidShape` + subtypes | ✅ | Shape argument for all glass widgets |
| `LiquidGlassLayer` | ✅ | Advanced: building custom glass widgets |
| `LiquidGlassBlendGroup` | ✅ | Advanced: custom blend groups |
| `GlassGlow` | ✅ | Impeller glow effect |
| `LiquidGlass` | ❌ | **Replaced by `AdaptiveGlass`** — Impeller-only, silently renders nothing on Skia/web |
| `LiquidStretch`, `RawLiquidStretch` | ❌ | Internal utility |
| `GlassGlowLayer` | ❌ | Internal |

**Rule of thumb:** If a user needs a glass shape, they should use `AdaptiveGlass`
or one of the `Glass*` widgets — never `LiquidGlass` directly.

### Future: two-library architecture (post-v1)

For v1+, consider splitting into:
- `liquid_glass_widgets.dart` — the opinionated widget kit (current)
- `liquid_glass_widgets/renderer.dart` — raw primitives for power users

This is the pattern used by `go_router`, `riverpod`, and `dio`. It keeps
autocomplete clean for 95% of users while giving escape hatches to the 5%
building custom glass widgets.

---

## Syncing upstream changes

Use the sync script for new upstream releases:

```bash
./tools/sync_renderer.sh <version>
# e.g. ./tools/sync_renderer.sh 0.2.0-dev.5
```

The script automatically:
- Copies and import-fixes the 11 "clean" Dart files
- Syncs the 6 shaders we use
- Stages the 5 structurally-modified files for manual diff
- Updates this file's version/date
- Runs `flutter analyze`

After the script: manually reconcile the 5 staged structural files
(`liquid_glass.dart`, `liquid_glass_render_scope.dart`,
`liquid_glass_blend_group.dart`, `rendering/liquid_glass_layer.dart`,
`shaders.dart`), then delete `.upstream_<version>/` and run `flutter test`.

Mark any local deviations with `// [LOCAL PATCH]: <reason>` so they are
obvious during the next sync.

---

## Local patches applied

### B1 — `LiquidGlassBlendGroup` Skia/web crash
**File:** `liquid_glass_blend_group.dart`
Added `ImageFilter.isShaderFilterSupported` guard so `ShaderBuilder` is never
built on non-Impeller backends. Without this, Skia/web threw an "Invalid SkSL"
exception at runtime.

### B2 — `shared.glsl` dead code
**File:** `shaders/shared.glsl` (deleted)
Was an orphaned copy of shared utilities. `liquid_glass_final_render.frag` was
already using `render.glsl` (our optimised version); nothing included `shared.glsl`.

### B3 — Geometry shader banding on mobile
**File:** `shaders/liquid_glass_geometry_blended.frag`
Changed `precision mediump float` → `precision highp float`. Mediump's 10-bit
mantissa caused ~1.5px displacement quantisation banding at typical thickness values.

### B5 — `calculateDispersiveIndex` dead function
**File:** `shaders/render.glsl`
Deleted full Cauchy wavelength dispersion formula that was defined but never
called by `calculateRefraction`.

### B6 — `blurRadius` dead parameter
**File:** `shaders/render.glsl`
Removed unused `blurRadius` parameter from `calculateRefraction` signature and
its call site in `renderLiquidGlass`.

### A1 — `markRebuilt` inverted naming
**File:** `rendering/liquid_glass_render_object.dart`,
`internal/render_liquid_glass_geometry.dart`
Renamed `GeometryRenderLink.markRebuilt` → `notifyGeometryChanged`. The old
name implied the object was clean; the method actually sets `_dirty = true`.

### V4 — Duplicate highlight colour implementations
**File:** `shaders/liquid_glass_final_render.frag`
Replaced 8-line inline highlight colour block with a call to `getHighlightColor()`
from `render.glsl`, which is already `#include`d by the same shader.

### PP2 — `GlassSpecularSharpness` import in `liquid_glass_settings.dart`
**File:** `liquid_glass_settings.dart`
`GlassSpecularSharpness` is our own enum (not vendored). It lives in
`lib/types/glass_specular_sharpness.dart`. The import in `liquid_glass_settings.dart`
was updated from the local `'glass_specular_sharpness.dart'` to
`'../../types/glass_specular_sharpness.dart'` and marked `// [LOCAL PATCH]`.

**Sync note:** If upstream ever adds a `GlassSpecularSharpness`-equivalent, prefer
ours and keep the `lib/types/` location. Do **not** restore the old import.
