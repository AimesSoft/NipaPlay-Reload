#!/usr/bin/env bash
# Build a Release/AOT Apple TV application without developer credentials.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
case "${1:-}" in
  simulator) sdk_name=appletvsimulator; shift; set -- --simulator "$@" ;;
  device) sdk_name=appletvos; shift ;;
  *) echo "Usage: $0 simulator|device [Flutter build options]" >&2; exit 2 ;;
esac

unsigned_config="$(mktemp "${TMPDIR:-/tmp}/nipaplay-tvos-unsigned.XXXXXX")"
trap 'rm -f "$unsigned_config"' EXIT
cat > "$unsigned_config" <<'CONFIG'
CODE_SIGNING_ALLOWED = NO
CODE_SIGNING_REQUIRED = NO
CODE_SIGN_IDENTITY =
DEVELOPMENT_TEAM =
PROVISIONING_PROFILE_SPECIFIER =
CONFIG

if [[ "$sdk_name" == appletvsimulator ]]; then
  # Xcode must emit simulated Keychain entitlements. This uses no developer
  # certificate or provisioning profile; disabling signing drops them.
  "$script_dir/flutter_tvos.sh" build tvos --release --no-pub "$@"
else
  XCODE_XCCONFIG_FILE="$unsigned_config" \
    "$script_dir/flutter_tvos.sh" build tvos --release --no-pub "$@"
fi

# The fork reuses flutter_assets across Debug and Release builds. AOT loads
# App.framework; never ship a stale JIT kernel or snapshot beside it.
app_path="$script_dir/../build/tvos/Release-$sdk_name/Runner.app"
test -s "$app_path/Frameworks/App.framework/App"
if [[ "$sdk_name" == appletvsimulator ]]; then
  # The simulator cannot create IOSurface-backed XR10 drawable textures.
  # Keep the physical Apple TV's gamut setting unchanged.
  /usr/libexec/PlistBuddy -c 'Set :FLTEnableWideGamut false' \
    "$app_path/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Add :FLTEnableWideGamut bool false' \
      "$app_path/Info.plist"
fi
rm -f "$app_path/flutter_assets/kernel_blob.bin" \
  "$app_path/flutter_assets/vm_snapshot_data" \
  "$app_path/flutter_assets/isolate_snapshot_data"
