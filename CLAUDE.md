# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NipaPlay-Reload is a cross-platform video player built with Flutter/Dart (SDK ≥3.5.3). It targets Windows, macOS, Linux, Android, and iOS. The app integrates with Emby/Jellyfin media servers, provides danmaku (bullet comments), Bangumi tracking, and supports multiple player kernels through pluggable abstraction layers.

**Language**: Always communicate in Chinese (中文) with users.

## Build & Development Commands

```bash
# Standard Flutter builds
flutter run -d <device>          # Run on device
flutter build windows --release
flutter build macos --release
flutter build linux --release
flutter build android --release
flutter build ios --release
flutter build web

# Web build (copies output to assets/web/ for embedded server)
./build_and_copy_web.sh

# Linux ARM64 deb package
./build-arm64.sh

# Lint (only report errors)
flutter analyze 2>&1 | grep -E "error"

# Tests (test/ is minimal — only a handful of unit tests exist)
flutter test                          # Run all tests
flutter test test/some_test.dart      # Run single test

# Dependencies
flutter pub get
flutter pub add <package>
```

## Architecture

### Pluggable Abstraction Layers (Core Design Pattern)

**Player Kernel** (`lib/player_abstraction/`):
- `AbstractPlayer` interface — all player kernels implement this
- Adapters: `mdk_player_adapter.dart`, `media_kit_player_adapter.dart`, `video_player_adapter.dart`
- `PlayerFactory` creates instances based on `PlayerKernelType` enum from SharedPreferences
- Platform-specific: `_io.dart` / `_unsupported.dart` suffixes for conditional imports

**Danmaku Engine** (`lib/danmaku_abstraction/`):
- `DanmakuRenderEngine` enum (CPU/GPU/Canvas/Next/DFM+)
- `DanmakuKernelFactory` manages kernel selection
- Implementations: `danmaku_gpu/`, `danmaku_next/`, `danmaku_dfm/`, `packages/danmaku_canvas/`

To add a new player/danmaku kernel: create adapter → implement interface → add to enum → register in factory → add UI option in settings.

### Service Layer (`lib/services/`)

Singleton services (pattern: `static final instance = Service._internal();`):
- **Media Servers**: `jellyfin_service.dart`, `emby_service.dart` with `media_server_service_base.dart` as shared base, plus `multi_address_server_service.dart` for multi-address support
- **Transcode**: `jellyfin_transcode_manager.dart`, `emby_transcode_manager.dart`
- **Playback Sync**: `jellyfin_playback_sync_service.dart`, `emby_playback_sync_service.dart`
- **Danmaku**: `dandanplay_service.dart` (弹弹play API), `danmaku_cache_manager.dart`
- **Infrastructure**: `debug_log_service.dart`, `web_server_service.dart` (embedded HTTP via `shelf`)

### State Management (`lib/providers/`)

Provider pattern with `MultiProvider` registered in `main.dart`:
- `ServiceProvider` centralizes service singletons
- `WatchHistoryProvider`, `UIThemeProvider`, `JellyfinTranscodeProvider`, etc.
- Services can extend `ChangeNotifier` for reactive state

### Key Initialization Sequence (`lib/main.dart`)

1. `HttpClientInitializer.install()` — self-signed cert trust (desktop)
2. `DebugLogService().initialize()` / `FileLogService().initialize()`
3. Platform-specific: `hotKeyManager.unregisterAll()` (desktop), file association handlers
4. `PlayerFactory.initialize()` / `DanmakuKernelFactory.initialize()`
5. Provider setup → `runApp()`

### Rust FFI Bridge (`rust/`, `rust_builder/`)

Uses `flutter_rust_bridge` (v2.12.0) for native functionality:
- Rust crate: `rust_lib_nipaplay` (Cargo.toml in `rust/`)
- Build wrapper: `rust_builder/` (Flutter plugin wrapping Cargo via cargokit)
- Key Rust modules: torrent download (`librqbit`), GPU danmaku rendering (`wgpu`), font rendering (`fdsm`)
- FFI bindings: `rust/src/api/`, generated code in `rust/src/frb_generated.rs`

### Theme System (`lib/themes/`)

- `ThemeDescriptor` + `ThemeRegistry` for theme registration
- Current themes: `nipaplay/` (default glassmorphism), `cupertino/`
- `UIThemeProvider` controls active theme
- `AppearanceSettingsProvider` manages custom backgrounds

### Plugin System (`lib/plugins/`)

- `PluginService` manages plugin lifecycle
- JS runtime via `flutter_js` with platform-specific implementations (`_io.dart` / `_web.dart`)
- Plugin assets: `assets/plugins/builtin/`, `assets/plugins/custom/`

### Embedded Web Server

- `web_server_service.dart` using `shelf` + `shelf_static` + `shelf_router`
- Serves Flutter web build from `assets/web/`
- REST API for browser-to-app communication
- See `docs/WEB_SERVER_IMPLEMENTATION.md` for details

## File Naming Conventions

- Services: `*_service.dart`
- Providers: `*_provider.dart`
- Models: `*_model.dart`
- Pages: `*_page.dart`
- Platform conditionals: `*_io.dart` (native), `*_web.dart` (web), `*_stub.dart` (unsupported)

## Platform Handling

- `globals.isDesktop` for desktop detection, `globals.isPhone` for phone detection
- `kIsWeb` for web detection
- Conditional imports: `import 'path_provider.dart' if (dart.library.html) 'mock_path_provider.dart';`

## Custom Forks (dependency_overrides in pubspec.yaml)

- `media_kit` → local `packages/media_kit` (custom fork)
- `media_kit_video` → local `packages/media_kit_video`
- `media_kit_libs_video` → local `third_party/media-kit-upstream/libs/universal/media_kit_libs_video`
- `adaptive_platform_ui` → local `packages/adaptive_platform_ui`
- `danmaku_canvas` → local `packages/danmaku_canvas`
- `smb_connect` → local `third_party/smb_connect`

## Data Layer

- **Database**: SQLite via `sqflite` (mobile) / `sqflite_common_ffi` (desktop) — `lib/models/watch_history_database.dart`
- **Settings**: `SharedPreferences` via `lib/utils/settings_storage.dart`
- **Models**: `lib/models/` (jellyfin, emby, bangumi, playable_item)

## Contributing

See `CONTRIBUTING_GUIDE/` for detailed docs:
- `01-Environment-Setup.md` — dev environment setup
- `02-Project-Structure.md` — detailed folder breakdown
- `03-How-To-Contribute.md` — git workflow (fork → branch → commit → PR)
- `04-Coding-Style.md` — code conventions
- `08-Adding-a-New-Player-Kernel.md` — step-by-step adapter guide
- `09-Adding-a-New-Danmaku-Kernel.md` — danmaku engine integration

## Code Style Rules

1. Follow SOLID principles; each function does one thing
2. All exceptions must be handled
3. Use descriptive variable names (`userList` not `data`)
4. Do not "optimize away" existing code without justification — if code exists, it's needed
5. Chinese comments encouraged for complex logic

## Key External APIs

- **弹弹play** (`dandanplay_service.dart`): danmaku matching & fetching
- **Bangumi** (`bangumi_service.dart`): anime metadata, progress sync; spec at `docs/bangumi番组计划api接口.json`
- **Jellyfin/Emby**: media server integration; OpenAPI specs at `docs/jellyfin-openapi-stable.json` and `docs/emby-openapi.json`
- **GitHub Releases** (`update_service.dart`): version update checks
- **Subtitles**: `subtitle_service.dart` (ASS/SRT)

## Working with the User

- **Do not run `flutter build` or full compilation** to verify changes — the user handles compilation/hot-reload themselves and observes the result. Use `flutter analyze 2>&1 | grep -E "error"` for static checks only.
- When proposing changes, give alternative approaches with trade-offs rather than picking silently.
- Flag reusable code opportunities and edge cases you notice.
