#!/bin/bash

version=$(head -n 19 pubspec.yaml | tail -n 1 | cut -d ' ' -f 2)
dmg_name="NipaPlay_${version}_macOS_Universal.dmg"

# Create a temporary directory for the DMG layout
temp_dir=$(mktemp -d)
mkdir -p "${temp_dir}/.background"

# Copy the app to the temporary directory
cp -R "build/macos/Build/Products/Release/NipaPlay.app" "${temp_dir}/"

# Create a symbolic link to Applications
ln -s /Applications "${temp_dir}/Applications"

# Create the background image with arrow
convert -size 800x450 xc:transparent \
  -fill none -stroke '#666666' -strokewidth 3 \
  -draw "path 'M 350,225 L 450,225 L 440,215 M 450,225 L 440,235'" \
  # 绘制虚线（每5像素一个短线）
  -draw "line 350,225 355,225" \
  -draw "line 360,225 365,225" \
  -draw "line 370,225 375,225" \
  -draw "line 380,225 385,225" \
  -draw "line 390,225 395,225" \
  -draw "line 400,225 405,225" \
  -draw "line 410,225 415,225" \
  -draw "line 420,225 425,225" \
  -draw "line 430,225 435,225" \
  -draw "line 440,225 445,225" \
  -font Arial -pointsize 13 -fill '#666666' \
  -draw "text 250,200 'NipaPlay' text 460,200 'Applications'" \
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