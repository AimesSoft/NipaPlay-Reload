# DFM+ / Titan iOS comparison

This entry point runs the production `DfmPlusOverlay` (Rust layout, Metal texture,
emoji pipeline and Flutter compositor) or the marketplace Titan bootstrap in
`WKWebView`. It supplies the same deterministic 30 comments/second and 100 ms
media-clock updates, without video decoding/network playback obscuring renderer
behavior. Each engine still applies its own collision/density policy; this is
not a claim that they display the same number of simultaneous comments.

Only iOS is accepted by the entry point. Use the same simulator, orientation,
settings and host load for every run. Keep the Mac unlocked and the simulator
visible. Simulator debug timings are useful for regressions, not device/release
performance or battery-life claims. Recording adds overhead.

## Run

From the repository root, start the localhost server:

```sh
python3 tool/dfm_benchmark/serve.py --renderer dfm
```

It downloads the marketplace plugin and verifies its required Titan bundle's
SHA-256. The generated HTML, exact source, checksum and results are saved in
`/tmp/nipaplay-dfm-benchmark`; third-party binaries are not committed.

In another terminal:

```sh
flutter run -d <iOS-simulator-UDID> -t tool/dfm_benchmark/main.dart
```

The scene warms up for eight seconds, then plays for thirty seconds. Results
exclude the first five playback seconds. Cold, unoptimized Rust builds may need
additional warmup; exclude glyph rasterization startup from steady-state motion
comparisons. Test cold startup separately.

To compare Titan without changing the native source, change the
server's `config.json` to `{"renderer":"titan"}` and restart the app.
Use `{"renderer":"dfm"}` to switch back. Hot restart (`R`) is sufficient for
functional exploration, but use a full process restart for CPU/memory samples:
Flutter hot restart can leave native texture surfaces from the old isolate.
After modifying Swift/Rust, quit and
rerun `flutter run` so the native library is rebuilt; hot restart alone is not
enough. Use an explicit server directory/port via `--directory`/`--port`, and
`--dart-define=DFM_BENCH_HOST=http://127.0.0.1:<port>` if necessary.

Capture the screen, starting before hot restart and stopping after completion:

```sh
xcrun simctl io <iOS-simulator-UDID> recordVideo --codec=h264 comparison.mp4
```

Inspect consecutive scrolling positions, repeated frames, pause/resume and
seek behavior, not just average FPS. Simulator video timestamps describe the
capture stream and can jitter/drop frames; they are not Metal presentation
measurements. In particular, do not report velocity estimates from these
recordings as device performance numbers.

Flutter build/raster percentiles only cover Flutter's pipeline. Titan can
animate without producing Flutter frames; zero Flutter samples does not mean
zero rendering cost or infinite performance. The harness separately records
WebKit `requestAnimationFrame` intervals, which describe callback cadence, not
GPU completion. No Flutter/Titan FPS ranking should be inferred by comparing
these two different counters.

## Regression coverage

After the DFM glyph atlas is warm, copy the VM Service URL from `flutter run`:

```sh
python3 tool/dfm_benchmark/verify.py <VM-Service-URL> --output /tmp/dfm-functional.json
```

This exercises large and 0.1-second paused seeks in both directions, pause,
time offset, visibility, empty segments, consecutive seeks and 0.5/1/2x rates
against the real production overlay. It asserts the layout clock, not GPU
presentation; inspect screenshots as a separate check.

The debug VM extensions `ext.dfmBench.control` and `ext.dfmBench.snapshot`
accept the main `isolateId`. Control supports `restart=true` (a new manual run),
`finish=true` (stop and write timing results), `position` in seconds, `playing`,
`rate`, `visible` and `offset`. Visibility and offset controls exercise DFM only.
Manual runs continue past 30 seconds; seek back into the comment segment when
needed. CPU samples should use cumulative CPU time differences over a measured
wall interval, counting the app and its simulator WebKit processes for Titan.
Exclude unrelated macOS WebKit processes; report 100% as one CPU core. RSS sums
are resident process memory and can double-count shared pages.

`measure.py` implements that sampling method and automatically finds the app
PID from the VM. For Titan, identify the WebKit processes belonging to the same
simulator runtime and pass their PIDs explicitly:

```sh
python3 tool/dfm_benchmark/measure.py <VM-Service-URL> --output /tmp/dfm-playing.json
python3 tool/dfm_benchmark/measure.py <VM-Service-URL> --paused --output /tmp/dfm-paused.json
python3 tool/dfm_benchmark/measure.py <VM-Service-URL> --webkit-pids <content-pid> <gpu-pid> <network-pid> --output /tmp/titan-playing.json
```

Both scripts require only Python's standard library. The default 15-second
playing sample starts after eight seconds, within the 30-second input segment.
The eight-second delay is not a cold-atlas readiness check: warm DFM first and
ensure its layout and rendered output have caught up before measuring.

`rust/src/next2_engine/engine/motion.rs` tests presentation-time sampling at
60/120 Hz with variable worker delays, missed/duplicate callbacks, coalescing,
pause, playback-rate changes and seeks. Existing Dart payload/style tests cover
media-unit lifetime and applying playback rate once.
