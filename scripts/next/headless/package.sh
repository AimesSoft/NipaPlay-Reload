#!/usr/bin/env bash
# 打 NipaPlay 无界面版的 Linux 安装包。
#
#   scripts/next/headless/package.sh <amd64|arm64> <version>
#
# 产物：build/headless-package/NipaPlay-Headless_<version>_Linux_<arch>.tar.gz
#
# 在已经 `flutter pub get` 过的仓库根目录运行，需要 dart（Flutter 自带的即可）和 Rust 工具链。
# 环境变量（都可选）：
#   DART=路径            dart 可执行文件（默认 PATH 里的 dart）
#   HEADLESS_EXE=路径    已经编好的 nipaplay-headless（跳过 dart compile）
#   HEADLESS_NATIVE_LIB=路径   已经编好的 libnipaplay_headless_native.so（跳过 cargo）
#   RUST_TARGET=三元组   交叉编译原生库，例如 aarch64-unknown-linux-gnu
#   HEADLESS_OUT=目录    输出目录（默认 build/headless-package）
# 不带 HEADLESS_EXE 时，dart 的 AOT 编译总是按 <arch> 交叉编译，所以在任何系统上都能出两种架构的程序。
set -euo pipefail

arch=${1:-}
version=${2:-}
case "$arch" in
  amd64) dart_arch=x64 ;;
  arm64) dart_arch=arm64 ;;
  *) echo "用法：$0 <amd64|arm64> <version>" >&2; exit 64 ;;
esac
[[ "$version" =~ ^[0-9A-Za-z._+-]+$ ]] || { echo "版本号只能含字母、数字和 . _ + -：'$version'" >&2; exit 64; }

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)
here=$root/scripts/next/headless
out=${HEADLESS_OUT:-$root/build/headless-package}
dart=${DART:-dart}
name=NipaPlay-Headless_${version}_Linux_${arch}
stage=$out/stage/nipaplay-headless
mkdir -p "$out"
rm -rf "$out/stage"
mkdir -p "$stage/bin" "$stage/libexec" "$stage/assets/next"

cd "$root"

# Knowledge provenance is generated from this checkout. Binary provenance is
# compiled separately, so HEADLESS_EXE cannot silently inherit this source SHA.
python3 scripts/next/build_knowledge.py --version "$version"
knowledge_commit=$(python3 -c 'import json; print(json.load(open("assets/next/knowledge/catalog.json"))["sourceCommit"] or "")')
knowledge_dirty=$(python3 -c 'import json; print(str(json.load(open("assets/next/knowledge/catalog.json"))["sourceDirty"]).lower())')

# ---- 程序 ----
exe=${HEADLESS_EXE:-}
if [ -z "$exe" ]; then
  [ -f .dart_tool/package_config.json ] || { echo "缺少 .dart_tool/package_config.json：先运行 flutter pub get。" >&2; exit 1; }
  exe=$out/nipaplay-headless-$arch
  echo "== dart compile exe（linux/$dart_arch）"
  "$dart" compile exe --target-os linux --target-arch "$dart_arch" \
    --packages=.dart_tool/package_config.json \
    -DNIPAPLAY_VERSION="$version" \
    -DNIPAPLAY_SOURCE_COMMIT="$knowledge_commit" \
    -DNIPAPLAY_SOURCE_DIRTY="$knowledge_dirty" \
    bin/nipaplay_headless.dart -o "$exe"
fi
[ -f "$exe" ] || { echo "找不到程序：$exe" >&2; exit 1; }

# ---- 原生库 ----
lib=${HEADLESS_NATIVE_LIB:-}
if [ -z "$lib" ]; then
  echo "== cargo build --release（rust/headless）"
  cargo_args=(build --release --locked --manifest-path rust/headless/Cargo.toml)
  if [ -n "${RUST_TARGET:-}" ]; then
    cargo_args+=(--target "$RUST_TARGET")
    lib=rust/headless/target/$RUST_TARGET/release/libnipaplay_headless_native.so
  else
    lib=rust/headless/target/release/libnipaplay_headless_native.so
  fi
  cargo "${cargo_args[@]}"
fi
[ -f "$lib" ] || { echo "找不到原生库：$lib" >&2; exit 1; }

install -m 0755 "$exe" "$stage/libexec/nipaplay-headless-host"
install -m 0644 "$lib" "$stage/libexec/libnipaplay_headless_native.so"
if command -v strip >/dev/null 2>&1 && [ -z "${RUST_TARGET:-}" ] && [ "$arch" = "$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')" ]; then
  strip --strip-unneeded "$stage/libexec/libnipaplay_headless_native.so" 2>/dev/null || true
fi

# ---- 运行时读的种子资源：harness（--seed）和 agent（--agent-assets）----
# 主机从 harness 读种子、agent 读 DSH 资源、knowledge 读版本化文档。
copy_tree() {
  mkdir -p "$2"
  (cd "$1" && find . -type f ! -path './.codex/*' ! -name '__pycache__' ! -path '*/__pycache__/*' ! -name '.DS_Store' -print0) |
    while IFS= read -r -d '' file; do
      mkdir -p "$2/$(dirname "$file")"
      cp -p "$1/$file" "$2/$file"
    done
}
copy_tree assets/next/harness "$stage/assets/next/harness"
copy_tree assets/next/agent "$stage/assets/next/agent"
copy_tree assets/next/knowledge "$stage/assets/next/knowledge"

# ---- 脚本与说明 ----
install -m 0755 "$here/package/nipaplay-headless" "$stage/bin/nipaplay-headless"
install -m 0755 "$here/package/install.sh" "$stage/install.sh"
install -m 0755 "$here/package/uninstall.sh" "$stage/uninstall.sh"
install -m 0644 "$here/package/README.md" "$stage/README.md"
[ -f LICENSE ] && install -m 0644 LICENSE "$stage/LICENSE"
printf '%s\n' "$version" > "$stage/VERSION"
printf '%s\n' "$arch" > "$stage/ARCH"

# ---- 打包 ----
archive=$out/$name.tar.gz
rm -f "$archive"
if tar --version 2>/dev/null | grep -q 'GNU tar'; then
  tar --owner=0 --group=0 --numeric-owner --sort=name -C "$out/stage" -czf "$archive" nipaplay-headless
else
  tar --uid 0 --gid 0 -C "$out/stage" -czf "$archive" nipaplay-headless
fi

echo "== 包内容"
tar -tzvf "$archive"
echo "== 产物"
ls -l "$archive"
if command -v sha256sum >/dev/null 2>&1; then sha256sum "$archive"; else shasum -a 256 "$archive"; fi
echo "archive_path=$archive"
if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "archive_path=$archive" >> "$GITHUB_OUTPUT"; fi
