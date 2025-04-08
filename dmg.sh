#!/bin/bash

version=$(head -n 19 pubspec.yaml | tail -n 1 | cut -d ' ' -f 2)
dmg_name="NipaPlay_${version}_macOS_arm64.dmg"

# Create a temporary directory for the DMG layout
temp_dir=$(mktemp -d)
mkdir -p "${temp_dir}/.background"

# Copy the app to the temporary directory
cp -R "build/macos/Build/Products/Release/NipaPlay.app" "${temp_dir}/"

# Create a symbolic link to Applications
ln -s /Applications "${temp_dir}/Applications"

# Create the background image with arrow
convert -size 800x450 xc:transparent \
  -stroke white -strokewidth 2 \
  -draw "path 'M 400,225 L 500,225'" \
  -draw "path 'M 500,225 L 490,215'" \
  -draw "path 'M 500,225 L 490,235'" \
  "${temp_dir}/.background/background.png"

# Create the DMG
create-dmg \
  --volname "NipaPlay-${version}" \
  --window-pos 200 120 \
  --window-size 800 450 \
  --icon-size 100 \
  --icon "NipaPlay.app" 200 185 \
  --icon "Applications" 600 185 \
  --background "${temp_dir}/.background/background.png" \
  --no-internet-enable \
  "${dmg_name}" \
  "${temp_dir}"

# Clean up
rm -rf "${temp_dir}"