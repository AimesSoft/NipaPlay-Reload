# Task Engine

The M2 kernel is exported by `nipa_harness.dart` and remains pure Dart.
`TaskEngine` accepts a `JobStore`, the local installation ID, and one
`JobExecutor` per task type. Call `start()` before dispatching work and
`close()` when its host shuts down. The application owns the SQLite adapter
and stores it at `<AppStorage>/next/next.db`.

`submit()` persists acceptance and returns a queued snapshot; it does not
wait for completion. A domain action can use a deterministic `jobId` or
its own content identity to deduplicate submissions. The store rejects
duplicate IDs rather than replacing a job.

## Executor lifecycle

`execute(context)` starts a newly accepted job. `recover(context)` reconciles
an interrupted execution, a retry, a resumed pause, a resolved decision, or
a cancellation with no active worker. The engine never invokes `execute`
to replay interrupted work. A missing executor leaves a persisted job
available for inspection instead of marking it successful or replaying it.

Use `context.report` for phase, progress and durable checkpoint updates.
Progress describes the current phase; the engine does not add unlike units
across phases. After an external effect commits, persist its stable handle
using `markSideEffectCommitted`. Recovery must still check the actual effect:
a process can stop between external commit and local checkpoint persistence.

Finish with `succeed` and a `verified` receipt after readback, or `fail` with
an error and an honest receipt. `acknowledged` and `unverified` receipts can
describe failed or cancelled work; they cannot certify success. Returning a
Future without a persisted disposition produces a failed, unverified job.
`needsDecision` and `retryAt` persist blocked states; return from the worker
after recording either disposition. Retry deadlines survive restart, and
the retry enters recovery before further work.

`stopRequested` signals cancellation, pause or shutdown; inspect the job
snapshot to distinguish them. `task.cancel` acknowledges a request, while
`context.cancelled` acknowledges an actual stop before effects commit.
Committed effects must still be verified. Terminal receipts record the
cancellation time, phase, whether an effect had committed when cancellation
arrived, and whether an effect ultimately committed. On pause and shutdown,
old contexts lose write access. Resume waits for the old worker to return,
then reconciles. Executors must cooperate with controls and stop their domain
operation; fencing database writes cannot stop external operations by itself.

The engine invokes workers through a private Harness Action so Harness
remains the catch-all exception boundary. Worker errors become failed jobs
with unverified receipts. Storage failures propagate; they are not converted
into fabricated durable results.

## Decisions and task actions

Decision options contain domain `ActionCall`s. The domain action applies the
choice by calling `resolveDecision(jobId, revision: ..., call: ...,
checkpoint: ...)`. Include the resulting decision revision in the option's
input (normally the current revision plus one). The engine checks both that
revision and the exact JSON call, independent of object key ordering, and
persists the choice before invoking recovery. Repeated or stale calls fail
with `conflict`; no extra generic `task.resolve` Action is introduced.

`task.list` accepts optional `state` and `type` filters and returns `jobs`.
`task.get`, `task.cancel` and `task.wait` accept `jobId` and return `job`.
`task.wait` additionally accepts `afterRevision` and `timeoutMs` (0–60000,
default 60000). Pass the last observed revision to catch changes between
requests; omit it to wait for the next change. Terminal states return
immediately. Change and timeout both return the current snapshot. The
returned revision identifies a persisted event; raw input and checkpoints
stay in storage rather than appearing in task Action results.

`JobStore.commit` atomically writes a snapshot and its event, using the
previous revision as a compare-and-swap condition. Receipts and pending
decisions are part of that snapshot and the event history. Consumers may
replay `events(jobId, afterRevision: ...)` to observe durable transitions.

## Validation

Use Flutter/Dart from `~/development/flutter-3.44.6`. Flutter analyze/test
commands use `--no-pub`. This SDK's `dart test` rejects `--no-pub`; run it
inside this package using the existing `.dart_tool/package_config.json`
without changing dependencies or running `pub get`.
