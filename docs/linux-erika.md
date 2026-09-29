# Linux NipaPlay + Erika

Source builds with Erika's Linux Flutter texture plugin support the Erika kernel.
The build script enables `NIPAPLAY_LINUX_ERIKA`; fresh installs of that build
default to Erika, and existing saved kernel choices remain selectable. Standard
builds using the published Erika 0.2.0 package retain their existing kernel setup.
The Linux view uses a Flutter texture, including native subtitles/danmaku and
the normal NipaPlay controls. Windows overlay support remains available.

## Build (Ubuntu 26.04 x86_64)

Use the Linux Flutter SDK version in `.flutter-version-linux`, Cargo,
and the Linux Erika checkout with FFmpeg 8 and patched libass already built.
The required Linux plugin is introduced by
[Erika PR #147](https://github.com/AimesSoft/Erika/pull/147); it is not included
in the published Erika 0.2.0 package.
Install these additional packages:

```sh
sudo apt install cmake ninja-build clang pkg-config rsync python3 \
  libgtk-3-dev liblzma-dev libmpv-dev libmimalloc-dev libsqlite3-dev \
  libayatana-appindicator3-dev libkeybinder-3.0-dev libsecret-1-dev \
  fonts-noto-cjk fonts-noto-color-emoji
export ERIKA_SOURCE_DIR=/path/to/Erika
export FLUTTER_LINUX_BIN=/path/to/linux-flutter/bin/flutter
git submodule update --init third_party/media-kit-upstream
bash scripts/build_erika_linux.sh
```

The script builds inside the Linux filesystem, preserving the Windows source
checkout's Flutter caches and dependency files. It applies the upstream Linux
dependency profile and adds the local Erika package in the build copy. It builds real
Erika and NipaPlay Rust libraries with Cargo, then packages the release bundle.
The plugin reads `ERIKA_LIBRARY_DIR`; NipaPlay's Rust plugin can also consume
`NIPAPLAY_RUST_LIBRARY` from a distro Cargo build without requiring rustup.

Run `~/.local/bin/nipaplay-erika`, or the **NipaPlay (Linux · Erika)** desktop entry.
Installation directory: `~/.local/opt/nipaplay-erika`.
`NIPAPLAY_LINUX_BUILD_DIR`, `ERIKA_TARGET_DIR`, and `NIPAPLAY_INSTALL_DIR` override
the build/cache/install locations. `PUB_HOSTED_URL` and
`FLUTTER_STORAGE_BASE_URL` can select an accessible Flutter mirror.

## GPU requirements

The launcher requires both hardware rendering and hardware decoding. WSL uses
Mesa D3D12/OpenGL; native Linux can use Vulkan/EGL. Erika selects NVIDIA NVDEC
or Intel/AMD VA-API. Use `ERIKA_HWDEC=cuda` / `vaapi` and optionally
`ERIKA_CUDA_DEVICE=0` / `ERIKA_VAAPI_DEVICE=/dev/dri/renderD128` for explicit
selection. Unsupported videos report an error in strict mode. To deliberately
allow software fallback, run `ERIKA_REQUIRE_HARDWARE_DECODE=0 nipaplay-erika`.

NVIDIA RTX 5070 on WSLg has passed H.264, HEVC Main10 and AV1 hardware decoding.
Intel/AMD implementations still need physical-device validation. Decoder frames
are transferred through CPU memory and the Flutter output uses RGBA readback;
this does not provide zero-copy, HDR output or Linux MPRIS media keys.

## Local validation (2026-09-29)

The initial integration was tested with NipaPlay 1.10.12, Flutter 3.44.5 /
Dart 3.12.2 on Ubuntu 26.04 / WSLg with an RTX 5070 and
Mesa 26.0.8 D3D12. The actual player reports `CUDA / NVDEC`; the diagnostic HUD
reports hardware decode, zero decoder fallback, zero render failures and no
audio underflow. H.264, HEVC Main10 and AV1 decoder fixtures passed.

The NipaPlay UI passed playback, a pause of several minutes followed by resumed
audio/video, seeking to the middle of a ten-minute fixture, and entering/leaving
fullscreen (2560×1440). Chinese external SRT subtitles, progress danmaku and
427×240 RGBA thumbnail capture were exercised in the installed application.
The native texture lifecycle test also passed a 12.5-second pause: 200 hardware
frames, zero software frames, zero audio/render errors. The final focused
presenter unit tests passed 24 cases.

The PR is ported to the current main branch; the runtime results above describe
the installed 1.10.12 build and must not be read as a full current-main regression.
On main `70a45645` (NipaPlay 1.11.9), using the required Flutter
3.47.0-0.3.pre SDK, focused analysis of the changed Dart files and new test
reported no errors (existing warnings and info remain). The kernel policy test
passed all four cases both with and without
`--dart-define=NIPAPLAY_LINUX_ERIKA=true`, covering fresh defaults, saved
alternative kernels, saved Erika settings and the Windows default.

The Linux plugin preserves GTK's EGL/GLX context around Erika calls. On WSLg,
paused audio keeps the remote transport running with silence without consuming
the media ring; resuming does not wait for the RDP sink to uncork. Ordinary Linux
PulseAudio/PipeWire sessions retain cork-based pause behavior.

The release plugins resolve sibling libraries through `$ORIGIN`; `ldd` resolves
Erika from the installed `lib/` directory, and its SHA256 matches the release
build. Intel/AMD physical-device validation, native Linux desktop validation and
ARM64 execution remain outstanding. These results do not imply zero-copy or HDR.

For a diagnostic HUD, start with `ERIKA_DEBUG_HUD=1 nipaplay-erika`.
