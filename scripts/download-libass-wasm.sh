#!/usr/bin/env bash
# Downloads @jellyfin/libass-wasm (SubtitlesOctopus) into web/ so that
# the Flutter web build can serve the worker and wasm files.
#
# Usage:
#   bash scripts/download-libass-wasm.sh [version]
#
# Default version: 4.2.1
#
# Files downloaded to web/:
#   subtitles-octopus.js
#   subtitles-octopus-worker.js
#   subtitles-octopus-worker-legacy.js
#   subtitles-octopus.wasm            (fetched by the worker at runtime)
#   subtitles-octopus-worker.wasm
set -euo pipefail

VERSION="${1:-4.2.4}"
DIST_BASE="https://cdn.jsdelivr.net/npm/@jellyfin/libass-wasm@${VERSION}/dist/js"
WEB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/web"

echo "Downloading @jellyfin/libass-wasm@${VERSION} → ${WEB_DIR}"

download() {
  local url="${DIST_BASE}/$1"
  local dest="${WEB_DIR}/$1"
  echo "  GET $url"
  curl -fsSL "$url" -o "$dest"
}

download "subtitles-octopus.js"
download "subtitles-octopus-worker.js"
download "subtitles-octopus-worker-legacy.js"
# WASM binary used by the worker scripts at runtime (must live in the same directory)
download "subtitles-octopus-worker.wasm"
# Fallback font bundled with the library
download "default.woff2"

echo "Done. Files in ${WEB_DIR}:"
ls -lh "${WEB_DIR}"/subtitles-octopus* 2>/dev/null || true
