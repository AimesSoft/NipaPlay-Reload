#!/bin/bash

version=$(head -n 19 pubspec.yaml | tail -n 1 | cut -d ' ' -f 2)

# Detect architecture from build directory
if [ -d "build/macos/Build/Products/Release/NipaPlay.app/Contents/MacOS/NipaPlay" ]; then
  arch=$(file build/macos/Build/Products/Release/NipaPlay.app/Contents/MacOS/NipaPlay | grep -o "x86_64\|arm64")
else
  # Default to current system architecture if build doesn't exist yet
  arch=$(uname -m)
  if [ "$arch" = "x86_64" ]; then
    arch="x64"
  fi
fi

dmg_name="NipaPlay_${version}_macOS_${arch}.dmg"

# Install create-dmg if not already installed
if ! command -v create-dmg &> /dev/null; then
  brew install create-dmg
fi

create-dmg \
  --volname "NipaPlay-${version}" \
  --window-pos 200 120 \
  --window-size 800 450 \
  --icon-size 100 \
  --app-drop-link 600 185 \
  "${dmg_name}" \
  "build/macos/Build/Products/Release/NipaPlay.app"