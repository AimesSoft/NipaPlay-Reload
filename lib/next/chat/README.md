# Embedded Codex host

`NextRuntime.chat` owns one login-shell `codex app-server` while Next's local
endpoint is enabled. Changing harness or disabling Next closes it. Initialization
errors are in `NextRuntime.chatError`; desktop exit calls `closeChat()`.

The host exposes `startThread`, `resumeThread`, `listThreads` (cwd and cursor),
`startTurn`, `interrupt`, `steer`, and `answerUserInput`. Thread selection returns
Codex's history; it creates no second transcript store. `header` contains the
actual model/provider returned by Codex, the cwd, session and thread IDs.

X31 adds `getMainSession`, `newConversation`, `listSessions` (isMain/isCurrent)
and `switchSession`. The app-owned `harness_sessions` table stores only main and
current thread identifiers per absolute harness path. Startup resumes main;
an unavailable persisted thread reports an error rather than replacing history.
Codex owns the transcript and context compression. `ChatPort.mainThread` is the
default for home/⌘K/avatar conversation entry; `newThread` is explicitly new.
`ChatPort.listThreads` and `switchThread` expose the same session controls.
Equivalent Actions are `chat.session.main/new/list/switch`.
Codex 0.144.1 defers writing an empty rollout until its first content. On creation
the host sets a plain session name through `thread/name/set` before storing the
identifier; this materializes an empty session without a synthetic user turn.

`chat.turn.process {threadId, turnId}` reads `{found, process}` from the active
harness, even if its model host is unavailable. The process contains actual
origin, start/end/status/durationMs and ordered commandExecution/reasoning items.
Commands retain command, exitCode, durationMs, status and redacted
aggregatedOutput. Reasoning retains the summary supplied by Codex, never raw
reasoning content. Missing or evicted records return found=false.

The host saves these facts at turn boundaries and item start/completion, after
secret inspection/redaction, by atomically replacing a file under the Next data
directory's `turn-process/` (one file per absolute harness path). Each file keeps
at most 60 turns and 4 MiB. Each turn keeps at most 128 items, with commands capped
at 4096 Unicode characters, outputs at 8192 and up to eight summary parts at
2048 each; truncation is recorded. Oldest turns are evicted first. Output deltas
are not persisted: an abruptly stopped command retains its started fact and
unknown exit status, with its final output unavailable. Earlier runs cannot be
reconstructed from the invocation journal.

`readThread` supplements Codex history with these retained items, preserving
Codex's messages and replacing its folded process items rather than duplicating steps.
Y3's existing `TurnActivity.fromHistory` therefore restores expandable steps
after restarting without a second sidebar protocol.

`agent.wake` persists an immediate followup with instruction and arbitrary facts;
missing threadId always targets main. `followup.register` in embedded chat keeps
its registering thread; missing threadId outside chat targets main. Both use
the same one-shot queue, idle-host checks and acknowledgement reconciliation.
`activity.report` persists source/title/facts plus actual invocation origin;
it does not open a turn. Scripts inherit the hook task origin through `nipa`.
These primitives make no content, polling or decision policy.

Streams:

- `events`: redacted protocol messages and `host/stderr`; do not render this
  stream directly. Secret prefixes may be held across deltas and released as a
  final delta. Liveness counts actual wire events, before these transformations.
- `display`: supported items, text/tool output, coalesced `host/reasoning` updates
  (100 ms), and a `host/liveness` snapshot every second. Unknown item kinds are
  ignored here. The reasoning key identifies item, method and content index;
  delta text is appended to that section. Completed items contain final content.
- `threadDisplay`: the same display events for every thread. `host/reasoning`
  and `host/liveness` carry `params.threadId`; coalescing and liveness are isolated
  by thread. `display` keeps foreground-only host reasoning/liveness updates for
  the existing UI, which already routes normal protocol events by threadId.
- `userInputRequests`: `item/tool/requestUserInput` requests, retaining their RPC
  ID and questions. Answer with `{questionId: [answer, ...]}`. Other server
  requests receive JSON-RPC error -32601.

Liveness counts protocol events, non-reasoning text events (assistant replies and
command/file output), and reasoning deltas separately. It includes start/end
times, elapsed milliseconds, time since the last event/content, and the latest
error. `hasContent=false` means none has arrived this turn. There is no timeout
that interrupts, retries, classifies a pause, or claims an upstream failure.
The future UI can render the three-minute threshold from these facts and ask
the user before interrupting on exit.

Provenance is `harness_cli:chat:<sessionId>` in both the invocation journal and
existing domain records. `nipa` sends `X-NipaPlay-Chat` from `NIPAPLAY_CHAT`.
The journal also records `chat.turn_boundary` with threadId, turnId, phase,
status and time, so consumers can associate a historical turn with its actual
session and time range. These records contain no conversation text. Rotation
records use `chat.endpoint_token_rotated` and contain no credential value.

Lab profiles require `<root>/codex-home/config.toml` prepared before launch,
credential files copied with their original permissions, and a read-only skills
link. The host reapplies CODEX_HOME/TMPDIR after login-shell startup. Production
leaves the user's CODEX_HOME, model, provider and proxy configuration intact.
Launch is implemented for POSIX login shells; Windows reports an explicit host
error without disabling the NipaPlay endpoint.

In macOS lab profiles, blocking Keychain access also prevents Codex's default
TLS trust loading. X23 used a public `/etc/ssl/cert.pem` copy in the profile and
set CODEX_CA_CERTIFICATE and SSL_CERT_FILE to it when launching the lab instance.
No TLS verification or write restriction was relaxed.

X37 uses concurrent threads in this one app-server (verified with Codex
0.144.1). `threadLiveness` / `livenessFor(id)` and `busyFor(id)` describe each
thread; `liveness` / `busy` still mean the selected foreground conversation.
`startThreadTurn`, `steer(onThread:)`, and `interrupt(onThread:)` target one
thread. Helpers never change the main/current durable session pointers.

`agent.helper {title, instruction, threadId?}` accepts a background task and
returns `{jobId, parentThreadId, helperLimit: 2}`. The instruction is opaque:
goal, context and requested result come from the Agent. The caller's conversation
is the return target; terminal calls default to main. Each helper gets its own
Codex thread and thread-local `NIPAPLAY_CHAT=helper-<jobId>` configuration, sharing
the same harness cwd. Calls and X33 process records use
`harness_cli:helper:<jobId>`. Only two helpers run at once. Other tasks use the
existing waiting_retry state as a FIFO capacity queue (checked every two
seconds); NextUiData projects them as queued, without percentage or ETA.
`agent.helper.report {currentActivity, jobId?}` updates a short viewer-facing
sentence from that running helper. `task.cancel` interrupts only its thread;
cancelling before dispatch creates no model turn.

Each helper automatically registers one durable X25/X31 task-terminal followup.
Success, failure and cancellation return to the original conversation, waiting
while that conversation is busy. The receipt records actual threadId, turnId,
turnStatus and a redacted final reply (up to 8192 characters). A verified helper
receipt verifies that its Codex turn completed; `resultVerification: unverified`
explicitly leaves its claimed domain result for the parent to check. It does
not prove that danmaku, downloads or other delegated goals succeeded.

Helper `ui.present` cards initially belong to its own thread/turn. At result
delivery they are also copied as references to the parent's actual followup
turn, idempotently, so the viewer sees them in the result conversation. Live
task/card state is still resolved by UiDataService. No UI files changed.

Jobs and return conditions persist through restart. Recovery reads the existing
helper thread and its marked turn, never repeats an ambiguous dispatch. An
interrupted model turn is reported as failed with its actual interrupted status;
continuing its goal is an Agent decision. Switching harness or disabling Next
detaches the helper host; it waits for that harness to be available. Helpers
share files, settings and body facts: thread isolation is not a separate working
copy or a lock on Agent edits.

The lab-only debug VM extension `ext.nipaplay.chat` supports start/resume/list,
turn/steer/interrupt/answer/status/close. `scripts/next/x23_vm.py` calls it via
the private VM service URI in the instance log. It is not a harness Action or
MCP tool and is not registered outside Debug lab profiles. The lab event log is
redacted and exists only inside the disposable profile.
