#!/bin/sh
set -eu
export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"
export TVOS_DEPLOYMENT_TARGET="${TVOS_DEPLOYMENT_TARGET:-13.0}"
task_root="$(cd "$PODS_TARGET_SRCROOT/../.." && pwd -P)"
case "$PLATFORM_NAME" in
  appletvos) task_target=aarch64-apple-tvos ;;
  appletvsimulator)
    case "${CURRENT_ARCH:-${ARCHS%% *}}" in
      x86_64) task_target=x86_64-apple-tvos ;;
      *) task_target=aarch64-apple-tvos-sim ;;
    esac ;;
  *) echo "Unsupported television platform: $PLATFORM_NAME" >&2; exit 1 ;;
esac
export SDKROOT="$(xcrun --sdk "$PLATFORM_NAME" --show-sdk-path)"
if ! rustup run nightly rustc --version >/dev/null 2>&1; then
  echo 'Install nightly Rust with rust-src before building tvOS.' >&2
  exit 1
fi
cargo +nightly build --manifest-path "$task_root/rust/tvos/Cargo.toml" \
  --locked --release --target "$task_target" -Z build-std=std,panic_unwind
cp "$task_root/rust/tvos/target/$task_target/release/libnipaplay_tvos_native.a" \
  "$BUILT_PRODUCTS_DIR/libnipaplay_tvos_native.a"
