#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

WEB_ASSETS_DIR="assets/web"

# Keep the generated web bundle out of the web build input. Otherwise each
# rebuild embeds the previous bundle under assets/assets/web.
echo "Preparing empty web assets directory..."
rm -rf "$WEB_ASSETS_DIR"
mkdir -p "$WEB_ASSETS_DIR"
touch "$WEB_ASSETS_DIR/.gitkeep"

# Build the Flutter web application
echo "Building Flutter web application..."
flutter build web

# Remove the old web assets directory if it exists
if [ -d "$WEB_ASSETS_DIR" ]; then
  echo "Removing old web assets..."
  rm -rf "$WEB_ASSETS_DIR"
fi

# Copy the new build to the assets directory
echo "Copying new build to assets/web..."
cp -r build/web "$WEB_ASSETS_DIR"

echo "Build and copy complete!"
