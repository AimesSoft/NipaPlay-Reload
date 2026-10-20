# Embedded Codex host

X49 keeps memory in the harness Git repository. `memory/preferences.md` is the
resident preference file (8192 UTF-8 bytes); `memory/MEMORY.md` is a resident
one-line-per-topic index with the same injection limit. Other Markdown files
are read on demand. Preferences carry dates and sources and changes replace
the original entry. Settings-backed preferences use `settings.set` and its
reason; `SettingsRegistry.preferences()` supplies changed user settings and
their latest provenance, rather than copying them into memory.
Preferences are authoritative in this file and live settings; topic notes
must not revive a preference removed from them.

The seed `.codex/hooks.json` runs `python3 hooks/session_start.py` on Codex
SessionStart startup/resume/clear/compact. It reads files afresh and adds
preferences, settings, index and up to 3000 Unicode characters of verbatim
recent facts. `memory.context {threadId?}` exposes the same resident files,
settings and recent text, sourceThreadId, truncation and omitted counts. Recent
facts come from the newest nonempty Codex session (last six user/assistant
messages), unfinished tasks/followups and recent activity; they are projections
of existing fields, with no generated handoff or second transcript store.
Per-section limits and omission messages disclose clipped tails. More history
is available through session selection and the existing task/followup/activity
interfaces. No memories feature is enabled in Codex.

Project trust and hook hash trust are separate in Codex 0.144.1. Both must be
registered by the launcher (X50); untrusted hooks are listed but do not execute.
SessionStart(compact) runs at the following turn, including after a local
compaction. Resuming after restarting the app-server runs SessionStart(resume);
switching to an already loaded thread in the same app-server does not run it
again in 0.144.1, so pending memory changes survive thread selection.
The seed script uses Python 3 and the existing `nipa` client; it
does not alter the client's output budget.

`NextCore.memory` implements `MemoryData` for the settings page “Nipa 记得的事”.
Equivalent Actions:

- `memory.list {}` returns `files` with relative path, bytes and revision.
- `memory.read {path}` returns content, bytes and a SHA-256 revision.
- `memory.edit {path, content, revision}` replaces an existing file; remove one
  preference by submitting the remaining text. Resident writes over 8192 bytes
  are rejected; direct Agent file edits are bounded and reported on injection.
- `memory.delete {path, revision}` deletes a file. The index is user/Agent owned;
  after deleting a topic, remove its index line with `memory.edit`.

The UI passes `Invocation(origin: 'gui')` to edit/delete: Git author is
`NipaPlay User <user@localhost>` and activity records the user operation, path
and commit. Agent Actions retain their actual caller. Only the target file is
committed; unrelated staged changes are preserved. A stale revision or a
staged target file prevents replacement. Paths stay under `memory/`, with no
symbolic links. Recognizable secrets (including private keys) are rejected on
API writes and redacted on reads/injection; the Agent must not store secrets
through direct file writes either. Git deletion retains earlier versions,
and forgetting a preference does not delete Codex's conversation history.

Before each new turn the host compares memory file revisions per thread. If
they changed, it prepends one short change notice to that turn's input, asking
the Agent to reread changed files and stop using removed or superseded entries.
It never replaces previous context. This also covers files edited directly in
the harness and background threads; helper conversation selection is unchanged.
This infrastructure is inactive when Next chat is disabled.

`NextRuntime.chat` owns one login-shell `codex app-server` while Next's local
endpoint is enabled. Changing harness or disabling Next closes it. Initialization
errors are in `NextRuntime.chatError`; desktop exit calls `closeChat()`.

The app-server starts with `-c model_instructions_file=<Next root>/agent/nipa-base.md`,
written from `assets/next/agent/nipa-base.md` on every start. It replaces Codex's
base instructions, which describe a coding agent that keeps going until a task
is resolved, with Nipa's place in NipaPlay: who is watching, when a turn should
end, and that a refusal from NipaPlay is a fact to report. It belongs to the
build, not the harness; AGENTS.md files still arrive as before. In the eleventh
end-to-end run (against the ninth, Codex's base) followup turns took 6–12 s
instead of 16–17 s and answering an interjection stayed at 10 s. The probe host
used by the model check does not set it.

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

`agent.dispatch {title, instruction, threadId?}` accepts a host-dispatched task and
returns `{jobId, parentThreadId, helperLimit: 2}`. The instruction is opaque:
goal, context and requested result come from the Agent. The caller's conversation
is the return target; terminal calls default to main. Each helper gets its own
Codex thread and thread-local `NIPAPLAY_CHAT=helper-<jobId>` configuration, sharing
the same harness cwd. Calls and X33 process records use
`harness_cli:helper:<jobId>`. Only two helpers run at once. Other tasks use the
existing waiting_retry state as a FIFO capacity queue (checked every two
seconds); NextUiData projects them as queued, without percentage or ETA.
`agent.dispatch.report {currentActivity, jobId?}` updates a short viewer-facing
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

## Native helpers (X38)

Codex `collabAgentToolCall` items are included in the display stream. A completed
`spawnAgent` adopts every receiver thread as a persisted helper; NipaPlay never
starts a duplicate turn or waits in the parent's turn. `pendingInit` precedes the
child's `turn/started`, so history is read only once that turn exists. The title
is the first short sentence of the redacted prompt. Native tasks retain the
existing executor type `agent.helper`, with `source: codexNative` (host dispatch
uses `source: host`), child and parent thread IDs, actual start time, latest
assistant sentence or infrastructure activity, and the complete final answer.
Reusing a child with `sendInput` creates another execution receipt in that same
thread without rewriting the previous terminal task. Native concurrency belongs
to Codex, not the host's two dispatch slots.

`task.cancel` reconciles the child turn and sends `turn/interrupt`. Adoption marks
the already existing effect as committed, including before the local executor
starts; cancellation cannot falsely claim there was no model turn. Restart
reconciles native thread history, never sends another `turn/start`, and preserves
the task, return condition and receipt.

One task-terminal followup returns the result to the parent when idle. A completed
parent `wait` that contains that child's completed result consumes this return,
persisting `consumedBy` with the wait item, parent turn and helper turn. Timeouts,
running states and other senders do not consume it. Before delivery, parent
history is checked again to reconcile wait events missed at shutdown. Consumption
cancels only the return condition; the task's final answer remains intact.

The public X37 dispatch actions were renamed to `agent.dispatch` and
`agent.dispatch.report`: scripts/hooks can open an independent model turn even
without a running parent turn, which native model tools cannot do. Stored
`agent.helper` jobs are unchanged; old harness scripts must use the new action
IDs after merging the seed. There is no deprecated second delegation alias.

Native tasks, return origins and turn-process records use `codex_native:<threadId>`.
Codex's native child shell currently inherits its parent's `NIPAPLAY_CHAT`, so
individual `nipa` calls still carry that inherited CLI origin; these calls are
not relabelled by guessing from command text. X38 does not claim thread-local
native card/call attribution where Codex has not supplied it.

The lab-only debug VM extension `ext.nipaplay.chat` supports start/resume/list,
turn/steer/interrupt/answer/status/close. `scripts/next/x23_vm.py` calls it via
the private VM service URI in the instance log. It is not a harness Action or
MCP tool and is not registered outside Debug lab profiles. The lab event log is
redacted and exists only inside the disposable profile.
