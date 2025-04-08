#!/bin/bash

version=$(head -n 19 pubspec.yaml | tail -n 1 | cut -d ' ' -f 2)
dmg_name="NipaPlay_${version}_macOS_arm64.dmg"

flutter build macos --release \
&& brew install create-dmg \
&& create-dmg \
  --volname "NipaPlay-${version}" \
  --window-pos 200 120 \
  --window-size 800 450 \
  --icon-size 100 \
  --app-drop-link 600 185 \
  "${dmg_name}" \
  "build/macos/Build/Products/Release/NipaPlay.app"