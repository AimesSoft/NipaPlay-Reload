#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/macos/Build/Products/Debug/NipaPlay.app"
DEFAULT_SAMPLE="$ROOT_DIR/(HDR HEVC 10-bit BT.2020 24fps) Exodus Sample.mp4"
SAMPLE_PATH="${1:-$DEFAULT_SAMPLE}"
RUN_NAME="${2:-run_hdr_probe_$(date +%Y%m%d_%H%M%S)}"
RUN_PREFIX="$ROOT_DIR/$RUN_NAME"
HDR_LOG="$RUN_PREFIX-hdr.log"
FLICKER_LOG="$RUN_PREFIX-flicker.csv"
CONTAINER_SAMPLE_DIR="$HOME/Library/Containers/com.aimessoft.nipaplay/Data/tmp/hdr_validation"
CONTAINER_SAMPLE_PATH="$CONTAINER_SAMPLE_DIR/$(basename "$SAMPLE_PATH")"
WARMUP_SECONDS="${NIPAPLAY_PROBE_WARMUP_SECONDS:-10}"
PROBE_SECONDS="${NIPAPLAY_PROBE_SECONDS:-8}"
PROBE_FPS="${NIPAPLAY_PROBE_FPS:-60}"
PROBE_INSET_TOP="${NIPAPLAY_PROBE_INSET_TOP:-60}"
APP_PID=""

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  echo "Run: /Users/sakiko/development/flutter/bin/flutter build macos --debug" >&2
  exit 1
fi

if [[ ! -f "$SAMPLE_PATH" ]]; then
  echo "Sample not found: $SAMPLE_PATH" >&2
  exit 1
fi

mkdir -p "$CONTAINER_SAMPLE_DIR"
cp -f "$SAMPLE_PATH" "$CONTAINER_SAMPLE_PATH"

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

pkill -f "NipaPlay.app/Contents/MacOS/NipaPlay" >/dev/null 2>&1 || true
sleep 1

: >"$HDR_LOG"
NIPAPLAY_MACOS_HDR_VALIDATE=1 \
NIPAPLAY_MACOS_HDR_RENDER_FPS=1 \
NIPAPLAY_MACOS_HDR_GL_BLACK_FRAME_LOG=1 \
NIPAPLAY_MACOS_HDR_VIDEO_ONLY="${NIPAPLAY_MACOS_HDR_VIDEO_ONLY:-0}" \
NIPAPLAY_AUTOPLAY_FILE="$CONTAINER_SAMPLE_PATH" \
  "$APP_PATH/Contents/MacOS/NipaPlay" >"$HDR_LOG" 2>&1 &
APP_PID="$!"

sleep "$WARMUP_SECONDS"

SWIFT_MODULE_CACHE_PATH="$ROOT_DIR/.build/swift-module-cache" \
  swift "$ROOT_DIR/tools/macos_flicker_probe.swift" \
    --window NipaPlay \
    --auto-video \
    --inset-top "$PROBE_INSET_TOP" \
    --duration "$PROBE_SECONDS" \
    --fps "$PROBE_FPS" \
    >"$FLICKER_LOG"

echo "HDR log: $HDR_LOG"
echo "Flicker CSV: $FLICKER_LOG"
tail -n 1 "$FLICKER_LOG" || true
grep -E "MediaKitOpenGLVideoLayer|HDR|NIPAPLAY_AUTOPLAY_FILE|FileAssociation" "$HDR_LOG" | tail -n 60 || true
