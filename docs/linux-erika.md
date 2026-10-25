# Linux NipaPlay + Erika

NipaPlay 1.11.9 uses Erika Flutter 0.2.1. Linux release packages bundle the
matching `liberika_capi.so` and enable `NIPAPLAY_LINUX_ERIKA`; fresh installs
default to Erika, while existing saved kernel choices remain available.

On Wayland, Erika renders into a native video subsurface below transparent
Flutter controls, including native subtitles and danmaku. X11 uses the SDR
Flutter texture path. Set `ERIKA_LINUX_PRESENTATION=texture` to use that path
on Wayland too.

## Release builds

The Linux workflow builds amd64 and arm64 independently on their existing
Ubuntu runners. It compiles the pinned Erika 0.2.1 source and statically links
FFmpeg 8, dav1d, patched libass and its font libraries. PulseAudio, Vulkan and
VA-API use the desktop system libraries. The dependency build enables NVDEC
and VA-API with Vulkan interop; CUDA drivers are loaded at runtime. The build
uses pinned Vulkan headers while keeping the system Vulkan loader.

The runtime is cached by architecture, build scripts and workflow configuration.
A C ABI smoke check opens a real video and exports a GIF before packaging.
The Flutter bundle includes the runtime and its licenses, so users can select
Erika after installing the regular DEB, RPM, AppImage or tar.gz package.

To reproduce the native build on Linux, install the dependencies from
[the build action](../.github/actions/build-linux/action.yml), then run:

```sh
bash scripts/build_erika_linux_runtime.sh "$PWD/build/erika-linux-runtime"
export ERIKA_LIBRARY_DIR="$PWD/build/erika-linux-runtime/lib"
python3 scripts/smoke_erika_linux_runtime.py "$ERIKA_LIBRARY_DIR"
dart run tool/configure_flutter_dependencies.dart linux
flutter pub get
flutter build linux --release --dart-define=NIPAPLAY_LINUX_ERIKA=true
```

## Build (Ubuntu 26.04 x86_64)

Use the Linux Flutter SDK version in `.flutter-version-linux`, Cargo,
and the Linux Erika checkout with FFmpeg 8 and patched libass already built.
The published Erika 0.2.1 package includes the Linux plugin. This source-build
installer can also use a local Erika checkout for kernel development.
Install these additional packages:

```sh
sudo apt install cmake ninja-build clang pkg-config rsync python3 \
  libgtk-3-dev liblzma-dev libmpv-dev libmimalloc-dev libsqlite3-dev \
  libayatana-appindicator3-dev libkeybinder-3.0-dev libsecret-1-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libevdev-dev \
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

### Optional WSL decoded-frame GPU copy

Erika now provides an experimental Mesa D3D12 VA-API → GPU plane copy → Vulkan
path. Build the isolated Mesa drivers first using Erika's
[`docs/wsl-gpu-copy.md`](https://github.com/AimesSoft/Erika/blob/v0.2.1/docs/wsl-gpu-copy.md),
then run this source-build installer with `NIPAPLAY_WSL_GPU_COPY=1`:

```sh
NIPAPLAY_WSL_GPU_COPY=1 bash scripts/build_erika_linux.sh
~/.local/bin/nipaplay-erika /path/to/video.mp4
```

The flag compiles Erika's optional bridge, installs its scoped driver wrapper
and enables it in the generated launcher. A runtime `NIPAPLAY_WSL_GPU_COPY=0`
selects the ordinary OpenGL path again. Custom driver installations use
`ERIKA_WSL_MESA_PREFIX`. The default installer remains compatible with ordinary
Linux and does not install experimental Mesa automatically.

The RTX 5070 passed 4K60 HEVC Main10 playback with zero **decoded-frame** CPU
fallback; GPU copies are counted as shared imports, never direct zero-copy.
`ERIKA_REQUIRE_ZERO_COPY=1` rejects this path. Dozen's Linux software WSI may
still read back the rendered output, so this does not establish end-to-end
zero-copy. Physical HDR and native Linux NVIDIA direct NVDEC import remain
outstanding. These limits also apply to the counter shown in NipaPlay's HUD.

The deployed 1.11.9 build loaded the new library. Nested Weston screenshots
verified Main10 video, progress danmaku, paused seek, resume near 59.9 fps,
fullscreen enter/exit and thumbnail capture. CPU fallback and import/render
failure counters were zero; whole-session audio underflow counts were nonzero.
Erika's separate C ABI benchmark measured 960 source frames over 16 seconds,
zero decoded-frame CPU transfers and P99 tick time of 4.149 ms. That benchmark
does not measure full NipaPlay or physical display latency.

### Ordinary launcher and direct-import paths

The launcher requires both hardware rendering and hardware decoding. WSL uses
Wayland with Mesa D3D12/OpenGL; native Linux can use Vulkan/EGL. Erika selects NVIDIA NVDEC
or Intel/AMD VA-API. Use `ERIKA_HWDEC=cuda` / `vaapi` and optionally
`ERIKA_CUDA_DEVICE=0` / `ERIKA_VAAPI_DEVICE=/dev/dri/renderD128` for explicit
selection. Unsupported videos report an error in strict mode. To deliberately
allow software fallback, run `ERIKA_REQUIRE_HARDWARE_DECODE=0 nipaplay-erika`.

NVIDIA RTX 5070 on WSLg has passed H.264, HEVC Main10 and AV1 hardware decoding.
Intel/AMD implementations still need physical-device validation. Decoder frames
on the tested WSL OpenGL path are transferred through CPU memory. The native
Wayland output removes the additional Flutter RGBA readback, but does not make
decoder import zero-copy. Erika now implements direct VA-API/DRM NV12/P010
sampling with compatible Vulkan drivers. Its GPU image/synchronization tests
passed on Dozen, but Intel/AMD decoder-to-display validation is outstanding.
NVIDIA NVDEC direct zero-copy is not implemented; CUDA/Vulkan copy transfer is blocked on FFmpeg 8 because its
failure cleanup can crash (fixed upstream in FFmpeg 9; integration unverified).
`ERIKA_REQUIRE_GPU_FRAMES=1` rejects CPU transfers and
`ERIKA_REQUIRE_ZERO_COPY=1` accepts direct VA-API import and rejects CPU uploads,
CUDA copies and failed imports. This flag will still reject the deployed WSL
OpenGL/NVDEC path; it does not switch the renderer or install another driver.

Native Wayland presentation requests automatic HDR/SDR output. HDR requires an
FP16 scRGB Vulkan WSI surface and a supporting compositor/display. SDR-only
surfaces tone-map HDR; `ERIKA_REQUIRE_HDR=1` makes that an explicit error.
The tested WSLg output does not expose HDR. An isolated Mesa Dozen experiment
enabled Vulkan hardware rendering on the RTX 5070, but CUDA external memory
import returned `CUDA_ERROR_NOT_SUPPORTED`. No HDR or zero-copy result is claimed.
The ordinary launcher uses OpenGL unless the WSL GPU-copy option above is selected.
Linux MPRIS is not provided.

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

The earlier runtime results above describe the installed 1.10.12 texture build
and must not be read as a full current-main regression.
On main `70a45645` (NipaPlay 1.11.9), using the required Flutter
3.47.0-0.3.pre SDK, focused analysis of the changed Dart files and new test
reported no errors (existing warnings and info remain). The kernel policy test
passed all four cases both with and without
`--dart-define=NIPAPLAY_LINUX_ERIKA=true`, covering fresh defaults, saved
alternative kernels, saved Erika settings and the Windows default.

Both Rust and Flutter release builds of 1.11.9 now succeed. A separate Wayland
Weston session verified native video below Flutter UI, Chinese external SRT,
CUDA/NVDEC selection, progress danmaku, pause, fullscreen enter/exit and 427x240
screenshot capture. The separate native-view
probe also exercised pause, resize, detach/reattach and seek with the paused
picture preserved on OpenGL and experimental Dozen Vulkan. These are SDR runtime checks, not HDR/zero-copy
hardware acceptance. The test environment's remote audio underflow counters
were nonzero; smooth audio on a native Linux desktop remains to be verified.
The updated 1.11.9 bundle was installed with the source-build script; the earlier
1.10.12 installation was retained in a separate backup directory.

The Linux plugin preserves GTK's EGL/GLX context around Erika calls. On WSLg,
paused audio keeps the remote transport running with silence without consuming
the media ring; resuming does not wait for the RDP sink to uncork. Ordinary Linux
PulseAudio/PipeWire sessions retain cork-based pause behavior.

The release plugins resolve sibling libraries through `$ORIGIN`; `ldd` resolves
Erika from the installed `lib/` directory, and its SHA256 matches the release
build. Intel/AMD physical-device validation, native Linux desktop validation and
ARM64 execution remain outstanding. These results do not imply zero-copy or HDR.

For a diagnostic HUD, start with `ERIKA_DEBUG_HUD=1 nipaplay-erika`.
