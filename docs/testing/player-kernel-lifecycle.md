# Player teardown regression checks

Run `flutter test test/player_lifecycle_test.dart test/mdk_disposal_test.dart` for
memoization, media reuse, timeout and error gating. These tests use controlled
completion signals and do not load a native player.

Native checks are opt-in because ordinary Flutter test runners do not bundle
MDK/fvp/libmpv. Supply the platform libraries and set:

- `NIPAPLAY_TEST_NATIVE_MDK=1` for `test/fvp_native_lifecycle_test.dart`. The
  `fvp` library must be built from the patched `third_party/fvp` sources; a
  hosted binary will not exercise the callback ownership fix. On macOS, build
  `lib/src/callbacks.cpp` with `clang++ -dynamiclib -std=c++17`, the MDK SDK
  framework search path (`-F`), `-framework mdk`, and its runtime search path.
  Make `fvp.framework/fvp` and `mdk.framework/mdk` available to the test runner.
- `NIPAPLAY_TEST_NATIVE_MPV=/absolute/path/to/libmpv` for
  `test/media_kit_native_disposal_test.dart`.

Both native suites generate their own one-second PCM file. They check repeated
loaded-player teardown, pending texture requests and event-loop shutdown. The
MDK suite enables reply callbacks to exercise native waiters during disposal.

For device playback/surface coverage, run
`flutter test integration_test/kernel_hotswap_smoke_test.dart -d <device>`.
iOS and Windows decoder/GPU handoff still require testing on those platforms.

The shared, Linux and tvOS profiles use `third_party/fvp` 0.33.1; the HarmonyOS
0.37.3 fork carries the same lifecycle and callback ownership changes.
