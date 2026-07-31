# NipaPlay tvOS development

NipaPlay's Apple TV target uses the community
[`fluttertv/flutter-tvos`](https://github.com/fluttertv/flutter-tvos) fork. It
is intentionally versioned independently from the mainline, Linux, and
HarmonyOS Flutter toolchains.

## Pinned toolchain

- flutter-tvos: `v3.44.8-tvos.1.4.3`
- bundled Flutter: `3.44.8`
- deployment target: tvOS 13.0
- application identifier: `com.aimessoft.nipaplay.tvos`

The exact fork tag is stored in `.flutter-version-tvos`. Do not replace the
mainline `.fvmrc` with this version. HarmonyOS keeps its Flutter 3.35-compatible
package interfaces in `pubspec_overrides.ohos.yaml`; adding tvOS does not move
that platform onto the tvOS or mainline toolchain.

## Local setup

Xcode and CocoaPods are required. From the tvOS worktree, run:

```bash
./tool/setup_tvos.sh
```

The setup script installs the pinned fork next to the repository by default:

```text
FlutterProject/
  flutter-tvos/
  nipaplay-tvos/
```

Set `FLUTTER_TVOS_ROOT` before running the script to use another location.
Use the repository wrapper for subsequent commands so the normal Flutter SDK
is never changed:

```bash
./tool/flutter_tvos.sh doctor -v
./tool/flutter_tvos.sh pub get
./tool/flutter_tvos.sh build tvos --simulator --debug
```

To run the app, install a tvOS Simulator runtime in **Xcode > Settings >
Components**, create an Apple TV simulator, and then use:

```bash
./tool/flutter_tvos.sh devices
./tool/flutter_tvos.sh run -d <apple-tv-device-id>
```

For a physical Apple TV, select a Development Team for the Runner target in
`tvos/Runner.xcworkspace`, then build or run against the paired device. The
team is deliberately not committed because signing identities are
developer-specific.

## Platform behavior

The fork reports both `Platform.isIOS == true` and
`Platform.operatingSystem == 'tvos'`. NipaPlay uses the latter to keep Apple TV
out of phone-only code paths and to select the television display surface.

Only Flutter plugins with an explicit `tvos:` implementation are registered.
The current target pins the official fluttertv implementations for
SharedPreferences, path provider, package info, SQLite, wakelock, and video
playback. The Apple TV build therefore uses the `Video Player` kernel. FVP,
Media Kit, Erika, the Rust texture renderer, file pickers, URL launcher, and
camera-based features remain unavailable until they gain native tvOS ports.

The CI workflow builds an unsigned simulator app. App Store or physical-device
artifacts require Apple signing credentials and should be added as a separate
release step rather than embedding a personal team in the project.
