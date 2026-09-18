#!/bin/bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /path/to/NipaPlay.app" >&2
  exit 64
fi

app_path="$1"
entitlements_path="$(cd "$(dirname "$0")/../.." && pwd)/macos/Runner/Release.entitlements"

if [ ! -d "$app_path/Contents" ]; then
  echo "Application bundle not found: $app_path" >&2
  exit 66
fi

if [ ! -f "$entitlements_path" ]; then
  echo "Release entitlements not found: $entitlements_path" >&2
  exit 66
fi

# Local unsigned builds may contain unsigned binaries from prebuilt frameworks.
# Sign the deepest bundles first, then seal the complete application bundle.
while IFS= read -r -d '' nested_bundle; do
  codesign --force --deep --sign - "$nested_bundle"
done < <(find "$app_path/Contents/Frameworks" -depth \( -name '*.framework' -o -name '*.bundle' \) -type d -print0)

while IFS= read -r -d '' dylib_path; do
  codesign --force --sign - "$dylib_path"
done < <(find "$app_path/Contents" -type f -name '*.dylib' -print0)

codesign \
  --force \
  --deep \
  --sign - \
  --entitlements "$entitlements_path" \
  "$app_path"

codesign --verify --deep --strict --verbose=2 "$app_path"
