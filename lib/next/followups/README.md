# Agent followups

`followup.register` accepts `when: {jobId}` or `when: {event, objectId?}`,
`instruction`, optional `title` and optional `threadId`. Task conditions include
every terminal state, including failures and cancellations. Hook conditions
await the next application event after registration; no hook program is needed.
`download.completed` can also be recovered from persisted successful downloads.
`download.file_completed` uses objectId `JOB_ID:FILE_INDEX`, carries checked file
facts and media registration, and is recovered from `checkpoint.completedFiles`.
Its occurrence is persisted once per object; other hook events keep their
occurrence semantics. Registration waits for a completion after its creation.

`download.stalled` is a public event like `download.file_completed`: objectId
`stalled:JOB_ID:INDEX`, data `jobId`, `infoHash`, `title`, `at`, `secondsWithoutProgress`,
`completedBytes`, `totalBytes`, `connectedPeers`, `seenPeers`, `deadPeers` (a download whose
metadata never arrived has `metadata: false`, `error` and null counts). It is published
once per open stall (never for a passed stall or a finished task) and runs the
`hooks/download.stalled` program when present. `when: {event: 'download.stalled',
objectId}` accepts a stall objectId or a bare job id (that download's next stall);
without objectId any download's next stall. A download's automatic return carries a
stall only after its public event is recorded, so a matching registration has already
been triggered and owns it; the same stall is never delivered twice.

Conversation-originated `download.add` stores `returnTo` in the new task input.
Chat CLI sources return to the selected thread at submission; host/native helper
sources return to their recorded parent. Scripts, hooks and GUI submissions have
no implicit conversation. Repeated add does not take ownership of an existing task.
The observer publishes verified, registered video files, open stalls and every
non-cancelled terminal outcome as factual automatic followups, without prescribing
Agent actions. The first batch is immediately eligible; later batches wait until
ten minutes after the preceding dispatch, accumulating all file facts, since the
download page already shows progress. Stalls and terminal outcomes flush the
pending batch immediately. Busy/unavailable hosts keep accumulating in one pending batch.
Coverage and due times live in existing followup snapshots, survive restart, and
include file object IDs inherited by expanded selections. Before dispatch, matching
Agent registrations in the same repository/thread own their occurrences instead;
cancelled or failed registrations do not suppress new automatic delivery. Playback
and identity in this input describe the verified completion time, not a later disk
or binding change. The Agent can read current state when it acts.
Playback is an occurrence in NipaPlay, rather than a predicate on an offline
player. File-added refers to the existing library event, rather than filesystem
watching.

An embedded CLI call resolves `harness_cli:chat:<NIPAPLAY_CHAT>` against the live
host and records its selected thread. With no session and no explicit target, a
thread is created in the harness active at registration when delivery becomes
possible. A change of harness does not move old followups into another repository.
One host serializes selection and turn start. A followup never interrupts a
turn. When its conversation has a turn running on DSH, the same text is put into
that turn as next-step input (`turn/steer`) instead of waiting: the row goes
`dispatching`, then `started` with the running turn's id, and the ordinary
reconciliation completes it when that turn ends (or redelivers it if the provider
failed the turn). If the runner refuses (the turn just ended, another turn id) the
row returns to `ready` and waits for idle as before; an unknown outcome is never
resent. Codex followups still wait for idle.

`followup.list`, `followup.cancel` and the `followups` public view expose titles,
waiting conditions, origin, trigger evidence, actual thread/turn IDs and reasons.
Cancel is idempotent until delivery begins. Registration, triggering, pending
delivery, dispatch, accepted turn and turn outcome are in `activity`, with the
registrant's provenance retained in each snapshot. `started` means Codex accepted
the turn; `completed` means that turn completed, rather than proof the Agent's
requested media operation succeeded.

Database version 10 appends snapshots, transactional followup events and hook
occurrences without changing existing rows. A service in NextCore observes tasks
even without an embedded host. It reevaluates pending conditions on startup and
on task changes, and checks delivery/turn results every two seconds. Instructions
are opaque text; the Agent decides and verifies its next action.

Turn start and SQLite cannot share a transaction. Persist `dispatching` before
the RPC, and place the unique followup marker in its input. If acknowledgement is
lost, look for the marker in Codex's existing thread history. A matching turn is
adopted, never replayed. If no turn can be verified, retain `execution_failed`
with the ambiguity explained. Host unavailability keeps undelivered work `ready`
with its cause; later availability drains it. No timeout retries `turn/start`.

Mesh downloads carry a host-issued return ticket and the conversation target
resolved before submission. The receiving node binds that target to the mTLS
caller identity. Immutable batches return over authenticated `mesh/delivery`;
the conversation host validates its issued ticket, peer, repository and thread
before persisting the facts. Delivery is deduplicated by source device/batch ID,
including after restart. A lost ACK cannot mutate an already sent batch; new
completed files form a new batch. Transport failure retries after 30 seconds.

The destination stores `automatic: meshDownload`, sourceDeviceId and file event
facts; existing explicit event subscriptions and idle-host dispatch rules still
apply there. Source `state: completed` with `deliveryState: forwarded` records
durable destination acknowledgement, not a completed model turn. Destination
turnId/turnStatus remain the evidence of actual conversation execution.
Remote paths/local/playable are facts about the source device. Remote job IDs
are read through that device; they are not local task IDs for `when: {jobId}`.

Host `mesh.json.agentDeviceId` routes headless script/schedule `agent.wake` to
the configured Nipa device. That destination requires the host role `agent`;
an unspecified thread uses its main conversation, a specified thread targets
that destination's conversation. Mesh trust and Classic receiver/device approval
still apply. No conversation starts on a transfer-only host.
