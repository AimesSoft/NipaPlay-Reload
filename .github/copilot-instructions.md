# NipaPlay-Reload AI Agent Guidelines

## Project Overview
NipaPlay-Reload is a cross-platform video player built with Flutter/Dart supporting Windows, macOS, Linux, Android, and iOS. The app integrates with Emby/Jellyfin media servers, provides danmaku (bullet comments), and supports multiple player kernels through an abstraction layer.

## Communication
**CRITICAL**: Always communicate in Chinese (中文) with users unless explicitly requested otherwise.

## Architecture Fundamentals

### Abstraction Layer Pattern (Core Design Philosophy)
The project uses **pluggable architecture** for both video players and danmaku engines:

#### Player Abstraction (`lib/player_abstraction/`)
- **Interface**: `abstract_player.dart` defines `AbstractPlayer` - all player kernels must implement this
- **Adapters**: `mdk_player_adapter.dart`, `media_kit_player_adapter.dart`, `video_player_adapter.dart` wrap specific SDKs
- **Factory**: `player_factory.dart` creates player instances based on `PlayerKernelType` enum from SharedPreferences
- **Adding a new player**: Create adapter → Implement `AbstractPlayer` → Add to `PlayerKernelType` enum → Register in factory → Add UI option in settings

#### Danmaku Abstraction (`lib/danmaku_abstraction/`)
- Similar pattern: `DanmakuRenderEngine` enum (CPU/GPU/Canvas)
- `danmaku_kernel_factory.dart` manages kernel selection
- Three implementations: `danmaku_gpu/`, `danmaku_canvas/`, CPU renderer

### Service Layer Architecture (`lib/services/`)
Singleton services handle external integrations and core functionality:
- **Media Server Services**: `jellyfin_service.dart`, `emby_service.dart` (API clients with auth, library management)
  - Multi-address support via `multi_address_server_service.dart` 
  - Transcode management: `jellyfin_transcode_manager.dart`, `emby_transcode_manager.dart`
  - Playback sync: `jellyfin_playback_sync_service.dart`, `emby_playback_sync_service.dart`
- **Danmaku Services**: `dandanplay_service.dart` (弹弹play API integration), `danmaku_cache_manager.dart`
- **Infrastructure**: `debug_log_service.dart`, `web_server_service.dart` (embedded HTTP server using `shelf`)
- **Platform-specific**: `file_association_service.dart`, `windows_file_association_service.dart`

### State Management
- **Provider pattern** for global state (`lib/providers/`)
  - `ServiceProvider` - centralizes service singletons
  - `WatchHistoryProvider`, `UIThemeProvider`, `JellyfinTranscodeProvider`, etc.
  - All registered in `main.dart` with `MultiProvider`
- Services can extend `ChangeNotifier` (e.g., `ScanService`) for reactive state

### Data Layer (`lib/models/`)
- **Models**: `jellyfin_model.dart`, `emby_model.dart`, `bangumi_model.dart`, `playable_item.dart`
- **Database**: `watch_history_database.dart` (SQLite via `sqflite`/`sqflite_common_ffi` for desktop)
- **Configuration**: Settings stored in `SharedPreferences`

### UI Structure (`lib/pages/`)
- Main navigation: `main.dart` (Material) and `fluent_main_page.dart` (Fluent UI for Windows)
- Key pages: `play_video_page.dart`, `anime_page.dart`, `settings_page.dart`, `media_server_detail_page.dart`
- Reusable components: `lib/widgets/` (organized by theme: `nipaplay_theme/`)

## Development Workflows

### Building
```bash
# Standard Flutter builds
flutter build windows --release
flutter build macos --release
flutter build linux --release
flutter build android --release
flutter build ios --release
flutter build web  # See build_and_copy_web.sh for web assets handling

# Custom scripts
./build-arm64.sh        # Linux ARM64 build
./build_and_copy_web.sh # Builds web + copies to assets/web/
```

### Running & Debugging
```bash
flutter run -d <device>
# Launch arguments supported for file association (desktop/Android)
flutter run lib/main.dart
```

### Testing
- Test directory: `test/` (minimal - contributions welcome)
- Debug logs: Use `DebugLogService()` - initialized early in `main.dart`
  - Accessible via developer options in settings UI

### Key Initialization Sequence (`main.dart`)
1. `HttpClientInitializer.install()` - Self-signed cert trust (desktop)
2. `DebugLogService().initialize()` - Enable logging from startup
3. Platform-specific: `hotKeyManager.unregisterAll()` (desktop), file association handlers
4. `PlayerFactory.initialize()` / `DanmakuKernelFactory.initialize()` - Preload settings
5. Provider setup → `runApp()`

## Project-Specific Conventions

### Code Style
- **SOLID principles**: Functions do one thing, exceptions handled, meaningful variable names
- **No "optimizations" without justification**: If code exists, assume it's needed unless proven otherwise
- **Chinese comments encouraged** for complex logic (team is Chinese-speaking)

### File Naming
- Services: `*_service.dart`
- Providers: `*_provider.dart` 
- Models: `*_model.dart`
- Pages: `*_page.dart`
- Platform conditionals: `*_io.dart` (native), `*_web.dart` (web), `*_stub.dart` (unsupported)

### Platform Handling
- Conditional imports: `import 'path_provider.dart' if (dart.library.html) 'mock_path_provider.dart';`
- Check `kIsWeb` and `globals.isDesktop` before platform-specific code
- Desktop checks: Use `globals.isDesktop` or `PlatformUtils` helper

### Dependencies
- **Custom forks**: `media_kit` uses git dependency from `Shinokawa/media-kit` (see `pubspec.yaml` overrides)
- **Web assets**: Flutter web build output copied to `assets/web/` for embedded server
- Adding deps: `flutter pub add <package>` → Update `pubspec.yaml` → Run `flutter pub get`

## Common Tasks

### Adding a Media Server Feature
1. Extend service: `jellyfin_service.dart` or `emby_service.dart`
2. Update model if needed: `jellyfin_model.dart` / `emby_model.dart`
3. Add UI in settings or detail page: `media_server_detail_page.dart`
4. Test with both Emby and Jellyfin instances

### Modifying Playback Behavior
- **Player control**: Work through `AbstractPlayer` interface, not directly with SDKs
- **State**: Check `VideoPlayerState` provider
- **Sync**: Modify `*_playback_sync_service.dart` for progress reporting to servers

### UI Theming
- Theme system: `lib/utils/app_theme.dart`, controlled by `UIThemeProvider`
- Background: `AppearanceSettingsProvider` manages custom backgrounds
- Glassmorphism: Use `glassmorphism` package wrapper widgets in `widgets/nipaplay_theme/`

### Danmaku/Subtitle Work
- Danmaku parsing: `dandanplay_service.dart` (XML/JSON)
- Rendering: Switch between engines via `DanmakuKernelFactory`
- Subtitles: `subtitle_service.dart` (ASS/SRT support)

## Integration Points

### Media Server APIs
- Jellyfin: OpenAPI spec at `docs/jellyfin-openapi-stable.json`
- Emby: OpenAPI spec at `docs/emby-openapi.json`
- Authentication: Token-based, stored in services + SharedPreferences
- Profile support: `server_profile_model.dart` for multi-address endpoints

### External APIs
- 弹弹play: `dandanplay_service.dart` - danmaku matching & fetching
- Bangumi: `bangumi_service.dart` - anime metadata (API at `docs/bangumi番组计划api接口.json`)
- Update checks: `update_service.dart` - GitHub releases

### Embedded Web Server
- Implementation: `web_server_service.dart` using `shelf` + `shelf_static`
- Serves Flutter web build from `assets/web/`
- REST API for browser-to-app communication
- See `docs/WEB_SERVER_IMPLEMENTATION.md` for architecture

## Troubleshooting Common Issues

### Platform-Specific Compilation
- **Desktop**: Ensure MDK or libmpv libraries present
- **Android**: Check `android/app/src/main/jniLibs/` for native libs
- **iOS/macOS**: CocoaPods dependencies, security bookmarks (`security_bookmark_service.dart`)
- **Web**: Force `VideoPlayerAdapter`, no native players available

### State Sync Issues
- Check provider registration in `main.dart`
- Ensure services use singleton pattern: `static final instance = Service._internal();`
- Verify `notifyListeners()` called after state changes

### File Association
- Desktop: Handled by `file_association_service.dart` + platform channels
- Android: Intent handling in `AndroidManifest.xml` + `FileAssociationService.getOpenFileUri()`
- Check debug logs for file path reception

## Contributing Guidelines
See `CONTRIBUTING_GUIDE/` for comprehensive developer docs:
- `00-Introduction.md` - Project vision, AI-assisted contribution workflow
- `02-Project-Structure.md` - Detailed folder breakdown
- `03-How-To-Contribute.md` - Git workflow (fork → branch → commit → PR)
- `04-Coding-Style.md` - Code conventions
- `08-Adding-a-New-Player-Kernel.md` - Step-by-step adapter pattern guide
- `09-Adding-a-New-Danmaku-Kernel.md` - Danmaku engine integration

## Key Files to Reference
- Architecture: `lib/player_abstraction/player_factory.dart`, `lib/danmaku_abstraction/danmaku_kernel_factory.dart`
- Initialization: `lib/main.dart` (lines 1-150)
- Service pattern: `lib/services/jellyfin_service.dart` (singleton + multi-address)
- Provider setup: `lib/providers/service_provider.dart`
- Build scripts: `build-arm64.sh`, `build_and_copy_web.sh`
