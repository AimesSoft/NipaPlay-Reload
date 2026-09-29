# DFM+ iOS frame pacing

## Findings

The continuous DFM+ path submits scene membership approximately every 50 ms;
Rust advances positions independently between those updates. Three separate
iOS issues prevented that design from producing uniformly spaced motion:

1. `Next2NativeVsync` and `next2_engine_vsync` were Windows-only. On iOS,
   `CADisplayLink` only polled completed frames; Rust's `FramePacer` rendered on
   its own timer. The producer and consumer could drift in phase, repeating one
   frame and then skipping another even when CPU render time was small.
2. `build_vertices` sampled `Instant::now()` after command/atlas work. Variation
   in worker scheduling therefore became variation in the scroll displacement.
3. The Swift method-channel handler called `next2_engine_set_frame` on the main
   thread. That FFI waits on a Rust reply, so a busy render worker also delayed
   UIKit/Flutter display callbacks. The display link additionally never requested
   the screen's maximum refresh rate.

## Change

On iOS, CADisplayLink now requests the supported refresh range and supplies its
`targetTimestamp` to Rust through a nonblocking FFI command. Rust converts that
monotonic target into the presentation time used for position sampling. Once a
native display link connects, it is the only frame producer for both continuous and snapshot modes;
scene messages cannot create extra frames and no competing fallback timer runs.
Queued ticks coalesce to the newest target, and duplicate/older targets are
ignored. Existing timer/Dart-vsync paths remain available on other platforms.

Swift submits scenes on the existing serial native-work queue and returns the
method-channel reply on the main thread. Scene reset uses that queue as well,
so it cannot overtake a previously submitted frame. Ordering with resize/disposal is
preserved. The high-refresh display link pauses when no texture surfaces exist.

This addresses pacing and scheduling, without changing scroll speed, density,
font resolution, supersampling or the public playback settings.

The overlay now receives the player's explicit `seekRevision`. Previously a
paused 8.0 → 8.1 second seek stayed at 8.0 because the normal clock-drift
threshold is 0.15 seconds. Explicit seeks now start a new timeline epoch and
invalidate in-flight scene work regardless of distance. Ordinary clock updates
retain the smoothing policy. The player's seek and loop paths update the media
time before notifying the revision.

## Verification

- iPhone 17 Pro simulator, iOS 26.5: native Swift/Rust application build succeeds.
- 14 Rust motion tests pass, including delayed sampling at 60/120 Hz and
  pause/rate/seek behavior.
- 9 targeted Dart payload/style tests pass.
- The iOS comparison harness passes static analysis. See
  `tool/dfm_benchmark/README.md` for reproduction and measurement limitations.
- The marketplace Titan 1.0.6 bundle used in the comparison has SHA-256
  `f0c4a8ab2b2a02f2c4474918e630f12928a03ae8d50b96f88dc9078584ce0eca`.
- On the unlocked iOS simulator, the production overlay passed paused seeks
  to 20, 8, 8.1 and 8 seconds; pause stability; +2-second offset; hidden seek
  then show; empty segment then return; consecutive seeks; 0.5/1/2x playback.
  `tool/dfm_benchmark/verify.py` reproduces these checks through the debug VM.
- Rendered screenshots of the paused 8.0 → 8.1 second seek move by 43 physical
  pixels, matching 142.3307 logical pixels/s × 0.1 s × DPR 3 = 42.7 pixels.
  Thus the short-seek check also reaches the native texture, beyond layout data.

No release-device FPS or percentage improvement is claimed from debug/capture
measurements.

## Unlocked iOS simulator observations (2026-09-29)

Each renderer ran in a fresh app process with the same built native library.
After glyph warmup, cumulative process CPU time was sampled over 15 seconds,
starting eight seconds into the deterministic scene. No recording or build ran
during the sample. Titan includes its simulator WebContent, GPU and Networking
processes; unrelated macOS WebKit processes are excluded.

| Renderer/state | CPU (100% = one host core) | Process RSS sum |
| --- | ---: | ---: |
| DFM+ playing | 58.3% | 142.8 MiB |
| DFM+ paused | 3.5% | 94.3 MiB |
| Titan playing | 20.2% | 658.8 MiB |
| Titan paused | 12.2% | 418.0 MiB |

DFM's Flutter build/raster p95 during the playing sample was 1.641/1.503 ms.
That measures Flutter work, not the full native Metal pipeline. Titan animates
in WebKit and produces no comparable Flutter timing samples. The harness has
a 10 Hz clock timer and a WebKit rAF observer, including during paused samples.

These are debug simulator observations, **not evidence of equal workload or
release efficiency**: DFM reported eight layout items in this scene while Titan
visibly filled many more rows. Rust uses an unoptimized dev build, whereas the
browser executes the distributed Titan bundle. Host load and memory compression
affect results; RSS sums can double-count shared pages. No matching pre-change
CPU sample was collected, so these data cannot quantify CPU savings from this
patch. They also do not establish smoothness parity with Titan. A GPU trace was
attempted but Instruments did not attach to the simulator process; GPU time and
power remain unmeasured.

Cold debug runs spent substantial time in `fdsm::generate_mtsdf` during glyph
preparation. Those startup samples are excluded from the table. The patch
addresses display pacing and main-thread blocking, and preserves the existing
glyph quality, caching and layout policies.

Machine-readable samples, functional assertions and the rendered short-seek
check are saved in `docs/dfm_ios_measurements.json`.
