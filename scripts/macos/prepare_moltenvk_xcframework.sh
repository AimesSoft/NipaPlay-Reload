#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

OUTPUT_PATH="${MOLTENVK_XCFRAMEWORK:-${REPO_ROOT}/third_party/media-kit-upstream/libs/macos/media_kit_libs_macos_video/macos/Frameworks/MoltenVK.xcframework}"
SOURCE_DYLIB="${MOLTENVK_DYLIB:-}"

if [[ -z "${SOURCE_DYLIB}" ]]; then
  for candidate in \
    /opt/homebrew/lib/libMoltenVK.dylib \
    /usr/local/lib/libMoltenVK.dylib; do
    if [[ -f "${candidate}" ]]; then
      SOURCE_DYLIB="${candidate}"
      break
    fi
  done
fi

if [[ -z "${SOURCE_DYLIB}" || ! -f "${SOURCE_DYLIB}" ]]; then
  echo "Missing libMoltenVK.dylib. Set MOLTENVK_DYLIB=/absolute/path/to/libMoltenVK.dylib." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FRAMEWORK_DIR="${TMP_DIR}/MoltenVK.framework"
FRAMEWORK_BINARY="${FRAMEWORK_DIR}/Versions/A/MoltenVK"

mkdir -p "${FRAMEWORK_DIR}/Versions/A/Resources"
cp "${SOURCE_DYLIB}" "${FRAMEWORK_BINARY}"
chmod u+w "${FRAMEWORK_BINARY}"
install_name_tool -id "@rpath/MoltenVK.framework/Versions/A/MoltenVK" "${FRAMEWORK_BINARY}"

cat >"${FRAMEWORK_DIR}/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>MoltenVK</string>
  <key>CFBundleIdentifier</key>
  <string>org.khronos.moltenvk</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>MoltenVK</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>NSPrincipalClass</key>
  <string></string>
</dict>
</plist>
PLIST
plutil -convert binary1 "${FRAMEWORK_DIR}/Versions/A/Resources/Info.plist"

ln -s A "${FRAMEWORK_DIR}/Versions/Current"
ln -s Versions/Current/MoltenVK "${FRAMEWORK_DIR}/MoltenVK"
ln -s Versions/Current/Resources "${FRAMEWORK_DIR}/Resources"

codesign --force --sign - "${FRAMEWORK_BINARY}" >/dev/null

mkdir -p "$(dirname "${OUTPUT_PATH}")"
rm -rf "${OUTPUT_PATH}"
xcodebuild -create-xcframework \
  -framework "${FRAMEWORK_DIR}" \
  -output "${OUTPUT_PATH}"

echo "Created ${OUTPUT_PATH} from ${SOURCE_DYLIB}"
