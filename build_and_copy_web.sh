#!/bin/bash

# Build the Flutter web application and copy it to assets/web.
# If the web build fails (e.g. due to dart:ffi incompatibility on Web),
# the script prints a warning and leaves an empty assets/web directory
# so that the desktop build can still proceed.

WEB_ASSETS_DIR="assets/web"

# Keep the generated web bundle out of the web build input. Otherwise each
# rebuild embeds the previous bundle under assets/assets/web.
echo "Preparing empty web assets directory..."
rm -rf "$WEB_ASSETS_DIR"
mkdir -p "$WEB_ASSETS_DIR"
touch "$WEB_ASSETS_DIR/.gitkeep"

# Build the Flutter web application
echo "Building Flutter web application..."
if flutter build web 2>&1; then
  # Remove the old web assets directory if it exists
  if [ -d "$WEB_ASSETS_DIR" ]; then
    echo "Removing old web assets..."
    rm -rf "$WEB_ASSETS_DIR"
  fi

  # Copy the new build to the assets directory
  echo "Copying new build to assets/web..."
  cp -r build/web "$WEB_ASSETS_DIR"

  echo "Build and copy complete!"
else
  echo "WARNING: Flutter web build failed."
  echo "The desktop application will be built without embedded web assets."
  echo "The remote web UI feature will not be available in this build."
  # Ensure assets/web exists with .gitkeep so the desktop build can proceed.
  mkdir -p "$WEB_ASSETS_DIR"
  touch "$WEB_ASSETS_DIR/.gitkeep"
fi
