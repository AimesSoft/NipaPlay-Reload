#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
flutter_sdk_path="${FLUTTER_ROOT:-$project_root/.dart_tool/ios-flutter-sdk}"
framework_root="$flutter_sdk_path/bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64"
plugin_root="$project_root/packages/adaptive_platform_ui/macos"
native_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/nipaplay-native-controls.XXXXXX")"
native_sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
trap 'rm -rf "$native_test_dir"' EXIT

# One compilation unit permits focused tests of the private AppKit control
# without starting the app or changing user settings.
cat "$plugin_root/Classes/AdaptivePlatformUiPlugin.swift" \
    "$plugin_root/Tests/MediaControlSmoke.swift" > "$native_test_dir/main.swift"
xcrun swiftc -sdk "$native_sdk_path" \
  -target "$(uname -m)-apple-macos12.0" \
  -module-cache-path "$native_test_dir/module-cache" \
  -F "$framework_root" -framework FlutterMacOS \
  -Xlinker -rpath -Xlinker "$framework_root" \
  "$native_test_dir/main.swift" -o "$native_test_dir/check"
"$native_test_dir/check"

# Reproduce the missing SDK 27 declaration even when testing with Xcode 27.
# A temporary VFS overlay hides just this accessor; the installed SDK is never
# changed. This guards the specific compatibility regression, not an entire
# Xcode 26 build (which still needs CI with the actual older SDK).
python3 - "$native_sdk_path" "$native_test_dir" <<'PY'
import json
import pathlib
import sys

sdk, output = map(pathlib.Path, sys.argv[1:])
header = sdk / 'System/Library/Frameworks/AppKit.framework/Headers/NSGlassEffectView.h'
contents = header.read_text()
lines = contents.splitlines(keepends=True)
filtered = [line for line in lines if not ('@property' in line and 'effectIsInteractive' in line)]
if filtered != lines:
    replacement = output / 'NSGlassEffectView-without-interaction.h'
    replacement.write_text(''.join(filtered))
    roots = [{'type': 'file', 'name': str(path), 'external-contents': str(replacement)}
             for path in sorted({header, header.resolve()})]
    (output / 'sdk-without-interaction.json').write_text(json.dumps({'version': 0, 'roots': roots}))
    (output / 'require-new-sdk.swift').write_text('''import AppKit
@available(macOS 27.0, *)
func requireNewSDK(_ view: NSGlassEffectView) { view.effectIsInteractive = true }
''')
PY
if [[ -f "$native_test_dir/sdk-without-interaction.json" ]]; then
  # Verify the overlay really reproduces the CI error before trusting the pass.
  if xcrun swiftc -typecheck -sdk "$native_sdk_path" \
      -target "$(uname -m)-apple-macos12.0" \
      -module-cache-path "$native_test_dir/compatibility-module-cache" \
      -vfsoverlay "$native_test_dir/sdk-without-interaction.json" \
      "$native_test_dir/require-new-sdk.swift" > "$native_test_dir/probe.log" 2>&1; then
    echo "SDK compatibility overlay did not hide the new accessor." >&2
    exit 1
  fi
  python3 - "$native_test_dir/probe.log" <<'PY'
import pathlib
import sys
assert "has no member 'effectIsInteractive'" in pathlib.Path(sys.argv[1]).read_text()
PY
  xcrun swiftc -sdk "$native_sdk_path" \
    -target "$(uname -m)-apple-macos12.0" \
    -module-cache-path "$native_test_dir/compatibility-module-cache" \
    -vfsoverlay "$native_test_dir/sdk-without-interaction.json" \
    -F "$framework_root" -framework FlutterMacOS \
    -Xlinker -rpath -Xlinker "$framework_root" \
    "$native_test_dir/main.swift" -o "$native_test_dir/check-without-sdk-accessor"
  "$native_test_dir/check-without-sdk-accessor"
  echo "Native controls passed with the SDK 27 accessor declaration hidden."
fi
