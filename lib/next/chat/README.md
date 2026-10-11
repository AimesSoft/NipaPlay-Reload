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

The lab-only debug VM extension `ext.nipaplay.chat` supports start/resume/list,
turn/steer/interrupt/answer/status/close. `scripts/next/x23_vm.py` calls it via
the private VM service URI in the instance log. It is not a harness Action or
MCP tool and is not registered outside Debug lab profiles. The lab event log is
redacted and exists only inside the disposable profile.
