# Build environment for NipaPlay-Reload Linux AppImage.
# Mirrors .github/actions/build-linux (ubuntu-24.04 runner) so nothing needs
# to be installed on the host beyond podman/docker.
FROM docker.io/library/ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget unzip zip xz-utils ca-certificates file python3 \
    clang cmake ninja-build pkg-config libgtk-3-dev \
    libayatana-appindicator3-dev \
    libmpv-dev libmpv2 mpv \
    libmimalloc-dev libmimalloc2.0 \
    libasound2-dev libass-dev libkeybinder-3.0-dev \
    p7zip-full desktop-file-utils patchelf \
    && rm -rf /var/lib/apt/lists/*

# Rust toolchain (cargokit builds rust_lib_nipaplay; preinstalled on GitHub runners)
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable
ENV PATH=/root/.cargo/bin:$PATH

# Flutter SDK pinned to the version in .fvmrc
ARG FLUTTER_VERSION=3.44.6
RUN git clone --depth 1 -b ${FLUTTER_VERSION} https://github.com/flutter/flutter /opt/flutter
ENV PATH=/opt/flutter/bin:$PATH
RUN git config --global --add safe.directory '*' \
    && flutter --version \
    && flutter precache --linux --web

# linuxdeployqt + appimagetool, pre-extracted so no FUSE is needed in the container
RUN wget -q https://github.com/probonopd/linuxdeployqt/releases/download/continuous/linuxdeployqt-continuous-x86_64.AppImage -O /opt/linuxdeployqt.AppImage \
    && cd /opt && chmod +x linuxdeployqt.AppImage \
    && ./linuxdeployqt.AppImage --appimage-extract >/dev/null \
    && mv squashfs-root linuxdeployqt && rm linuxdeployqt.AppImage \
    && ln -s /opt/linuxdeployqt/AppRun /usr/local/bin/linuxdeployqt
RUN wget -q https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage -O /opt/appimagetool.AppImage \
    && cd /opt && chmod +x appimagetool.AppImage \
    && ./appimagetool.AppImage --appimage-extract >/dev/null \
    && mv squashfs-root appimagetool && rm appimagetool.AppImage \
    && ln -s /opt/appimagetool/AppRun /usr/local/bin/appimagetool

# make: media_kit_libs_linux builds mimalloc with the Unix Makefiles generator.
# llvm: cmake's IPO/LTO probe needs llvm-ar/llvm-ranlib alongside clang.
# g++: the flutter_js plugin invokes it by name instead of ${CMAKE_CXX_COMPILER}.
RUN apt-get update && apt-get install -y --no-install-recommends make llvm g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
