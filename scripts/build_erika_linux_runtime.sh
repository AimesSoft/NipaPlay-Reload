#!/usr/bin/env bash
# Fetch the official Erika Linux runtime that matches the package version.
# The bundled variant embeds FFmpeg and the subtitle stack (LGPL profile) and is
# built on Ubuntu 22.04 / glibc 2.35, so it runs on that baseline and newer.
set -euo pipefail
project_root=$(cd "$(dirname "$0")/.." && pwd)
output=${1:-"$project_root/build/erika-linux-runtime"}
erika_version=0.3.8
case "$(uname -m)" in
  x86_64|amd64) arch=x64; sha256=269d3ef114905ba2520ad4dbec41e5539f42eeffd8b99c4e47543089df19e19f ;;
  aarch64|arm64) arch=arm64; sha256=fa9d75186f7f07aaeeaf00eb804869d793be543d4ebdc3e0b842ddc87eb89f78 ;;
  *) echo "Unsupported Linux architecture: $(uname -m)" >&2; exit 1 ;;
esac
name="erika-capi-linux-${arch}-bundled"
work=$(mktemp -d "${RUNNER_TEMP:-/tmp}/nipaplay-erika.XXXXXX")
trap 'rm -rf "$work"' EXIT

curl -fsSL --retry 3 -o "$work/$name.zip" \
  "https://github.com/AimesSoft/liberika/releases/download/v${erika_version}/${name}.zip"
echo "$sha256  $work/$name.zip" | sha256sum -c -
unzip -q "$work/$name.zip" -d "$work"
rm -rf "$output"
mkdir -p "$output"
cp -a "$work/$name/." "$output/"
# Only the shared runtime is loaded by the Flutter plugin.
rm -f "$output/lib/liberika_capi.a"
ldd "$output/lib/liberika_capi.so"
