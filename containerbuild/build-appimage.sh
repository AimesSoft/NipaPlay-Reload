#!/usr/bin/env bash
# Runs INSIDE the build container (see containerbuild/Dockerfile).
# Mirrors the packaging recipe in .github/actions/build-linux/action.yml,
# with one improvement: host-sensitive libs are pruned BEFORE the AppImage
# is assembled (CI prunes after -appimage, so its cleanup never lands).
set -euo pipefail
cd /work

APP_NAME="NipaPlay"
ARCH="amd64"
VERSION="$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
BUILD_OUTPUT_DIR="build/linux/x64/release/bundle"
LINUX_BUILD_DIR="build/linux"
APPDIR="${LINUX_BUILD_DIR}/${APP_NAME}-AppDir"
APPIMAGE_NAME="${APP_NAME}-${VERSION}-Linux-${ARCH}.AppImage"
DESKTOP_FILE_NAME="io.github.MCDFsteve.NipaPlay-Reload.desktop"
ICON_NAME="io.github.MCDFsteve.NipaPlay-Reload.png"

# libmdk is fetched by the vendored fvp's cmake (third_party/fvp/cmake/deps.cmake)
export FVP_DEPS_URL="${FVP_DEPS_URL:-https://github.com/wang-bin/mdk-sdk/releases/latest/download}"

# Docker runs us as real root on a bind mount; give files back to the host user
# even when the build fails partway.
fixup_ownership() {
  if [ -n "${HOST_UID:-}" ] && [ "$(id -u)" = "0" ] && [ "${HOST_UID}" != "0" ]; then
    chown -R "${HOST_UID}:${HOST_GID:-${HOST_UID}}" /work || true
  fi
}
trap fixup_ownership EXIT

git config --global --add safe.directory '*'

echo "--- flutter pub get ---"
flutter pub get

echo "--- web assets (optional, failure tolerated by the script itself) ---"
chmod +x build_and_copy_web.sh
./build_and_copy_web.sh

echo "--- build info ---"
python3 .github/workflows/scripts/generate-build-info-json.py assets/build_info.json || true

echo "--- flutter build linux --release ---"
flutter build linux --release

echo "--- assemble AppDir ---"
rm -rf "${APPDIR}"
mkdir -p "${APPDIR}/lib" "${APPDIR}/data"
cp "${BUILD_OUTPUT_DIR}/${APP_NAME}" "${APPDIR}/"
cp -r "${BUILD_OUTPUT_DIR}/lib/." "${APPDIR}/lib/"
cp -r "${BUILD_OUTPUT_DIR}/data/." "${APPDIR}/data/"

if find "${APPDIR}/lib" -maxdepth 1 -name "libmpv*.so*" -type f | grep -q .; then
  echo "Bundled libmpv detected; skipping system libmpv copy."
else
  echo "Copying system libmpv into AppDir"
  find /usr/lib/x86_64-linux-gnu /usr/lib -maxdepth 1 -name "libmpv*.so*" -type f 2>/dev/null | while read -r mpv_lib; do
    cp -n "${mpv_lib}" "${APPDIR}/lib/" || true
  done
fi
(cd "${APPDIR}/lib" && if [ ! -f libmpv.so.1 ] && [ -f libmpv.so.2 ]; then ln -sf libmpv.so.2 libmpv.so.1; fi)

# dart's sqlite3 package dlopens 'libsqlite3.so'; hosts usually only ship .so.0
if [ ! -e "${APPDIR}/lib/libsqlite3.so" ]; then
  SQLITE_LIB="$(find /usr/lib/x86_64-linux-gnu /usr/lib -maxdepth 1 -name 'libsqlite3.so.0*' -type f 2>/dev/null | head -1)"
  if [ -n "${SQLITE_LIB}" ]; then
    cp "${SQLITE_LIB}" "${APPDIR}/lib/libsqlite3.so.0"
    ln -sf libsqlite3.so.0 "${APPDIR}/lib/libsqlite3.so"
  else
    echo "WARNING: libsqlite3.so.0 not found in container; watch history will need host sqlite3"
  fi
fi

cp "assets/linux/${DESKTOP_FILE_NAME}" "${APPDIR}/"
cp assets/images/logo512.png "${APPDIR}/${ICON_NAME}"
chmod +x "${APPDIR}/${APP_NAME}"

echo "--- linuxdeployqt (bundle dependencies) ---"
export LD_LIBRARY_PATH="${PWD}/${APPDIR}/lib:${LD_LIBRARY_PATH:-}"
export LINUXDEPLOYQT_EXCLUDE_LIBS="libgio-2.0.so*;libglib-2.0.so*;libgobject-2.0.so*;libgmodule-2.0.so*;libgthread-2.0.so*;libgdk_pixbuf-2.0.so*;librsvg-2.so*;libEGL.so*;libGL.so*;libGLESv2.so*;libGLX.so*;libOpenGL.so*;libGLdispatch.so*;libgbm.so*;libdrm.so*;libvulkan.so*"
linuxdeployqt "${APPDIR}/${APP_NAME}" -unsupported-allow-new-glibc -bundle-non-qt-libs

echo "--- prune host-sensitive libraries (GLib/GIO + GPU stack) ---"
find "${APPDIR}" -type f \( \
  -name "libgio-2.0.so*" -o -name "libglib-2.0.so*" -o -name "libgobject-2.0.so*" -o \
  -name "libgmodule-2.0.so*" -o -name "libgthread-2.0.so*" -o -name "libgdk_pixbuf-2.0.so*" -o \
  -name "librsvg-2.so*" -o -name "libEGL.so*" -o -name "libGL.so*" -o -name "libGLESv2.so*" -o \
  -name "libGLX.so*" -o -name "libOpenGL.so*" -o -name "libGLdispatch.so*" -o \
  -name "libgbm.so*" -o -name "libdrm.so*" -o -name "libvulkan.so*" \
\) -print -delete
find "${APPDIR}" -type d \( -path "*/gio/modules" -o -path "*/gdk-pixbuf-2.0" \) -prune -print -exec rm -rf {} + || true
if [ -f "${APPDIR}/AppRun" ] && head -n 1 "${APPDIR}/AppRun" | grep -q "^#!"; then
  sed -i \
    -e '/GDK_PIXBUF_MODULE_FILE/d' -e '/GDK_PIXBUF_MODULEDIR/d' \
    -e '/GIO_MODULE_DIR/d' -e '/GIO_EXTRA_MODULES/d' \
    "${APPDIR}/AppRun" || true
fi

echo "--- appimagetool ---"
ARCH=x86_64 appimagetool --no-appstream "${APPDIR}" "${LINUX_BUILD_DIR}/${APPIMAGE_NAME}"

echo "AppImage created: ${LINUX_BUILD_DIR}/${APPIMAGE_NAME}"
