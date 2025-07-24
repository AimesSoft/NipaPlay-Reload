#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Build the Flutter web application
echo "Building Flutter web application..."
flutter build web

# Remove the old web assets directory if it exists
if [ -d "assets/web" ]; then
  echo "Removing old web assets..."
  rm -rf assets/web
fi

# Copy the new build to the assets directory
echo "Copying new build to assets/web..."
cp -r build/web assets/web

echo "Build and copy complete!" 