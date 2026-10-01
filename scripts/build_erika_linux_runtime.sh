#!/usr/bin/env bash
# Build the package-pinned Erika runtime on the same distro as the Flutter app.
set -euo pipefail
project_root=$(cd "$(dirname "$0")/.." && pwd)
output=${1:-"$project_root/build/erika-linux-runtime"}
mkdir -p "$output"
output=$(cd "$output" && pwd)
erika_commit=70f12bf325ce8d020d2155635f5992eff4654321
nvcodec_commit=e844e5b26f46bb77479f063029595293aa8f812d
work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/nipaplay-erika.XXXXXX")
trap 'rm -rf "$work"' EXIT

git clone --depth 1 --branch v0.2.1 https://github.com/AimesSoft/Erika.git "$work/Erika"
test "$(git -C "$work/Erika" rev-parse HEAD)" = "$erika_commit"
git -C "$work/Erika" apply "$project_root/.github/patches/erika-linux-native-deps.patch"

git clone --depth 1 --branch n13.0.19.0 https://github.com/FFmpeg/nv-codec-headers.git "$work/nv-codec-headers"
test "$(git -C "$work/nv-codec-headers" rev-parse HEAD)" = "$nvcodec_commit"
make -C "$work/nv-codec-headers" install PREFIX="$work/nvcodec"
export ERIKA_LINUX_PKG_CONFIG_DIRS="$work/nvcodec/lib/pkgconfig:$(pkg-config --variable pc_path pkg-config)"
export ERIKA_USE_SYSTEM_LIBS=0
# CMake static dependencies are linked into the shared Erika runtime.
export CFLAGS="${CFLAGS:-} -fPIC"
export CXXFLAGS="${CXXFLAGS:-} -fPIC"
export CARGO_TARGET_DIR="$work/target"
# Keep native and Rust builds within the memory budget of both hosted runners.
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-2}
cd "$work/Erika"
cargo run --locked -p xtask -- deps build --all --profile lgpl --jobs "${ERIKA_BUILD_JOBS:-4}"
cargo rustc --locked --release -p erika_capi --lib -- \
  -C link-arg=-Wl,-soname,liberika_capi.so \
  -C link-arg=-lva -C link-arg=-lva-drm -C link-arg=-lva-x11 \
  -C link-arg=-ldrm -C link-arg=-ldl -C link-arg=-lm

# Use Erika's own packaging to include every dependency/asset license.
GITHUB_SHA="$erika_commit" GITHUB_REF_NAME=v0.2.1 ERIKA_NATIVE_PROFILE=lgpl \
  bash packaging/bundle.sh erika-linux "$work/erika-linux.zip" "$CARGO_TARGET_DIR/release/liberika_capi.so"
unzip -q "$work/erika-linux.zip" -d "$work/bundle"
mkdir -p "$output"
cp -a "$work/bundle/erika-linux/." "$output/"
cp third_party/src/fribidi-1.0.16/COPYING "$output/licenses/LICENSE.FriBidi"
python3 - "$work/nv-codec-headers/include/ffnvcodec" "$output/licenses/LICENSE.nv-codec-headers" <<'PYLICENSE'
from pathlib import Path
import sys
headers, notice = map(Path, sys.argv[1:])
notice.write_text("\n\n".join(
    p.name + "\n" + p.read_text().split("*/", 1)[0] + "*/"
    for p in sorted(headers.glob("*.h"))
) + "\n")
PYLICENSE
printf 'erika_ref=v0.2.1\nerika_source=%s\nnvcodec_source=%s\nnative_deps_patch=%s\n' \
  "$erika_commit" "$nvcodec_commit" \
  "$(sha256sum "$project_root/.github/patches/erika-linux-native-deps.patch" | cut -d ' ' -f1)" \
  >> "$output/MANIFEST.txt"
ldd "$output/lib/liberika_capi.so"
