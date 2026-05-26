---
name: nipaplay-theme-ui
description: Use when creating, refactoring, or reviewing UI for the Nipaplay Flutter theme. Always inspect the developer-options Nipaplay UI preview and reuse controls from lib/themes/nipaplay/widgets before writing new UI.
---

# Nipaplay Theme UI

Use this skill for any task that creates, changes, or reviews UI in the
Nipaplay theme.

## Required Workflow

1. Inspect the UI reference page first:
   - `lib/themes/nipaplay/pages/settings/nipaplay_ui_preview_window.dart`
   - In the app, it is opened from Developer Options as `Nipaplay 设计 UI 预览`.
2. Identify the UI pattern needed from the preview:
   - Main tabs
   - Fluent-style switches
   - Project dropdowns
   - Hover-scale text/icon buttons
   - Settings rows
   - Settings cards and divided containers
   - Nipaplay windows/dialogs
3. Find and reuse the matching widget under:
   - `lib/themes/nipaplay/widgets/`
4. Only create a new widget when no suitable widget exists.
5. If a missing pattern is reusable, add it under `lib/themes/nipaplay/widgets/`
   first, then use it from the page.

## Reuse Rules

- Do not hand-write a duplicate `MouseRegion + GestureDetector + AnimatedScale`
  button in a page. Use `HoverScaleTextButton`.
- Do not use Flutter default `TabBar` styling directly for Nipaplay UI. Use
  `NipaplayMainTabBar` and `HoverZoomTab`.
- Do not inline settings-row/card visuals in pages when `SettingsItem`,
  `SettingsCard`, `NipaplayDemoSection`, or existing Nipaplay widgets cover the
  pattern.
- Do not keep one-off UI state in a page solely for hover color/scale if an
  existing widget already handles it.
- All Nipaplay-theme-specific reusable controls must live in
  `lib/themes/nipaplay/widgets/`.

## Common Widgets

- Tabs: `NipaplayMainTabBar`, `HoverZoomTab`
- Hover text/icon button: `HoverScaleTextButton`
- Dropdown: `BlurDropdown`
- Switch: `FluentSettingsSwitch`
- Settings rows: `SettingsItem`
- Settings cards/containers: `SettingsCard`, `NipaplayDemoSection`
- Windows/dialog shells: `NipaplayWindow`, `NipaplayWindowScaffold`,
  `BlurDialog`

## Review Checklist

- Did the implementation check the developer-options UI preview first?
- Does the page import reusable widgets from `lib/themes/nipaplay/widgets/`?
- Are there duplicated hover buttons, tabs, cards, switches, or dropdowns?
- If a new widget was added, is it under `lib/themes/nipaplay/widgets/`?
- Does the UI preview need to be updated to show the new reusable component?
