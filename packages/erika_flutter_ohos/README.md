# Erika Flutter for HarmonyOS

This is the HarmonyOS portion of `erika_flutter` 0.3.5 (MPL-2.0).
The Dart API, native header and platform bridge are copied from that release.
Only `pubspec_overrides.ohos.yaml` selects this package.

The OHOS CMake build uses liberika revision
`13014fe11f34ba7fc9c164b7f764f827258c26ba` with
the included renderer patch, `ERIKA_OHOS_GLES_ONLY=1` and
`ERIKA_OHOS_VULKAN_VIDEO=0`. Both Vulkan video paths crash the Mali shader
compiler on nova 14. The compatibility build uses GLES GPU rendering and
hardware video decoding, with a frame upload between them.

The first build needs Git, Rust with the `aarch64-unknown-linux-ohos` target,
the DevEco native SDK, and network access for pinned native dependencies.
CMake caches the source and build output locally. `ERIKA_REPO_ROOT` can point
to an existing checkout at the exact revision to reuse its build cache.
