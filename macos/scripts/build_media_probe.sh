#!/bin/bash
set -euo pipefail
OUTPUT="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
mkdir -p "$OUTPUT"
arch_flags=()
for arch in $ARCHS; do arch_flags+=(-arch "$arch"); done
xcrun clang++ -std=c++17 -Os "${arch_flags[@]}" \
  -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET:-10.15}" \
  "$PROJECT_DIR/../native/media_probe/main.cpp" -o "$OUTPUT/nipa_media_probe"
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$OUTPUT/nipa_media_probe"
