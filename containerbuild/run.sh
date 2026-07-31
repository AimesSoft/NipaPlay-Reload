#!/usr/bin/env bash
# Host-side wrapper: builds the image and runs the AppImage build in a container.
# Usage: containerbuild/run.sh [podman|docker]
set -euo pipefail
cd "$(dirname "$0")/.."

RUNTIME="${1:-}"
if [ -z "${RUNTIME}" ]; then
  if command -v podman >/dev/null 2>&1; then RUNTIME=podman
  elif command -v docker >/dev/null 2>&1; then RUNTIME=docker
  else
    echo "Neither podman nor docker found." >&2
    exit 1
  fi
fi

IMAGE=nipaplay-linux-build

"${RUNTIME}" build -t "${IMAGE}" -f containerbuild/Dockerfile containerbuild

# Under rootless podman, root-in-container == host user, so ownership is fine.
# Under docker, the container runs as real root: hand it the host uid/gid so the
# build script can chown everything it touched back to the invoking user.
"${RUNTIME}" run --rm \
  -v "${PWD}:/work" \
  -v nipaplay-pub:/root/.pub-cache \
  -v nipaplay-cargo-reg:/root/.cargo/registry \
  -e "HOST_UID=$(id -u)" -e "HOST_GID=$(id -g)" \
  "${IMAGE}" \
  bash containerbuild/build-appimage.sh

echo "Done. Output in build/linux/"
