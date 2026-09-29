#!/usr/bin/env bash
# Build in Linux's filesystem, keeping Windows Flutter caches undisturbed.
set -euo pipefail
source_dir=$(cd "$(dirname "$0")/.." && pwd)
: "${ERIKA_SOURCE_DIR:?Set ERIKA_SOURCE_DIR to the adapted Erika checkout}"
if [[ ! -f "$source_dir/third_party/media-kit-upstream/media_kit/pubspec.yaml" &&
      ! -f "$source_dir/third_party/media-kit-upstream/libs/universal/media_kit_libs_video/pubspec.yaml" ]]; then
  echo "Initialize the media-kit submodule: git submodule update --init third_party/media-kit-upstream" >&2
  exit 1
fi
flutter=${FLUTTER_LINUX_BIN:-flutter}
build_dir=${NIPAPLAY_LINUX_BUILD_DIR:-$HOME/.cache/nipaplay-erika/source}
mkdir -p "$build_dir"
rsync -a --exclude=.git --exclude=.dart_tool --exclude=build --exclude=ephemeral \
  --exclude=Pods --exclude=node_modules --exclude=pubspec_overrides.yaml "$source_dir/" "$build_dir/"
python3 - "$build_dir" "$ERIKA_SOURCE_DIR" <<'PY'
import pathlib, re, sys
root, erika = map(pathlib.Path, sys.argv[1:])
profile = root / 'pubspec_overrides.linux.yaml'
source = profile.read_text() if profile.exists() else (root / 'pubspec.yaml').read_text()
block = re.search(r'^dependency_overrides:\n(.*?)(?=^\S|\Z)', source, re.M | re.S)
overrides = block.group(0).rstrip() if block else 'dependency_overrides:'
overrides += '\n  erika_flutter:\n    path: ' + str(erika.resolve() / 'packages/erika_flutter') + '\n'
(root / 'pubspec_overrides.yaml').write_text(overrides)
PY
export CARGO_TARGET_DIR=${ERIKA_TARGET_DIR:-$HOME/.cache/erika-target}
if [[ ${ERIKA_SKIP_BUILD:-0} != 1 ]]; then
  (cd "$ERIKA_SOURCE_DIR" && cargo build --locked --release -p erika_capi)
fi
export ERIKA_LIBRARY_DIR=${ERIKA_LIBRARY_DIR:-$CARGO_TARGET_DIR/release}
cd "$build_dir"
export NIPAPLAY_RUST_LIBRARY="$CARGO_TARGET_DIR/release/librust_lib_nipaplay.so"
cargo rustc --locked --release --manifest-path rust/Cargo.toml --lib -- \
  -C link-arg=-Wl,-soname,librust_lib_nipaplay.so
"$flutter" pub get
"$flutter" build linux --release --dart-define=NIPAPLAY_LINUX_ERIKA=true
install_dir=${NIPAPLAY_INSTALL_DIR:-$HOME/.local/opt/nipaplay-erika}
mkdir -p "$install_dir" "$HOME/.local/bin" "$HOME/.local/share/applications"
rsync -a build/linux/x64/release/bundle/ "$install_dir/"
cat > "$HOME/.local/bin/nipaplay-erika" <<EOF
#!/usr/bin/env bash
set -e
if [[ -e /dev/dxg ]]; then
  export GDK_BACKEND=\${GDK_BACKEND:-x11}
  export GALLIUM_DRIVER=\${GALLIUM_DRIVER:-d3d12}
  export WGPU_BACKEND=\${WGPU_BACKEND:-gl}
fi
export ERIKA_REQUIRE_HARDWARE_GPU=\${ERIKA_REQUIRE_HARDWARE_GPU:-1}
export ERIKA_REQUIRE_HARDWARE_DECODE=\${ERIKA_REQUIRE_HARDWARE_DECODE:-1}
exec "$install_dir/NipaPlay" "\$@"
EOF
chmod +x "$HOME/.local/bin/nipaplay-erika"
cp "$source_dir/icons/new-icon-win.png" "$install_dir/icon.png"
cat > "$HOME/.local/share/applications/nipaplay-erika.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=NipaPlay (Linux · Erika)
Exec=$HOME/.local/bin/nipaplay-erika %f
Icon=$install_dir/icon.png
Terminal=false
Categories=AudioVideo;Player;
MimeType=video/mp4;video/x-matroska;video/webm;
EOF
echo "Installed: $HOME/.local/bin/nipaplay-erika"
