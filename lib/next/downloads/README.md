# Download completion and identification

`download.preview` accepts a magnet, local .torrent path/file URI or HTTP(S)
torrent URL. File/URL previews reuse add's prepared bytes and metadata cache,
preserve torrent file indices and do not create a native task or download media.
GUI `download.delete` returns NeedsDecision with the current file manifest;
the returned `download.delete.request` option creates a persistent user-consent
task. Caller-bound previews are single-use and target changes invalidate them.
The application asks its existing local user dialog before deleting any files.
`download.delete {jobId, fileIndices}` (single jobId) deletes only those files
of a download: the preview and the dialog list only them, through the same
user-consent task and the same fingerprint check. On approval the files are
first removed from the engine selection, then their data is deleted; the other
files keep downloading or seeding. The files must be local, inside the output
directory and are never directories. The result carries `task` (readback:
`included` false, `actualSize` null for the deleted files) and `deletedFiles`.
The library keeps work, episode and watch progress; the episode simply has no
playable local file. `media.mesh_files` delete/overwrite decisions are confirmed
by the caller, not by the user in NipaPlay.

Agent controls use the same Classic torrent session and preferences. Discover
jobs with `task.list` (`type: download`); `download.read` accepts `jobId` or
`jobIds` and returns live backend state, rates, output paths and indexed files.
Each file reports `completedBytes` (checked piece bytes; null while metadata/checking
is unavailable), `complete`, disk-ready `playable`, and engine `streamable`.
`health` reports live/seen/connecting/queued/dead peers, observation start,
last observed increase, checked-byte delta and sample interval. Time without
progress counts from the first observation until an increase is seen; it does not
claim anything about earlier process history. The public librqbit API exposes
neither seeder counts nor peer piece availability, so those fields are explicitly
null. `health.sources` includes the live per-peer counters and counts peers that
have supplied bytes / checked pieces on their current retained peer record. That
is evidence of data supplied, not a promise of future availability or a seeder
classification. `lastProgressAt` is null until an increase is actually observed.
When an unfinished download goes `stallAfter` (5 minutes) without progress, the
worker appends one entry to `checkpoint.stalls` with the bytes and peer counts it
saw. The entry closes (`resumedAt`) only on an observed increase after it began,
since the counter restarts with the process. An open stall of a download started
from a conversation returns there at once as a `download.stalled` fact; passed
stalls and stalls of finished tasks are not sent.
`disk.availableBytes` uses statvfs (Unix) or GetDiskFreeSpaceExW (Windows)
for the actual task output directory; failures carry an error and a null value.
The job receipt remains a historical completion observation; live seeding pause
state comes from `task.paused` in this read result.

The `download` settings domain exposes `enabled`, `directory`,
`createFolderForTask` and `autoScanCompletedTasks`. Disabling preserves Classic
semantics: it hides the downloader tab and prevents Agent adds, without pausing
existing native tasks. `download.add.downloadDirectory` and
`createFolderForTask` override defaults only for new tasks. Hash deduplication
returns the original job without moving its data. Directory permission requests
reuse `playback.authorize_directory`.

`download.preview` reuses Classic magnet metadata resolution and releases its
temporary handle without adding a task. `download.directories` returns the
default and recent choices; `download.forget_directories` removes recent choices
without changing the default or touching downloaded data.

`download.play` takes `jobId` and `fileIndex` from `download.read.files`. Complete
local files play from size/path-verified disk locations, even while the parent is
unfinished or paused, without resuming the remaining download. Unfinished paused
files retain Classic's resume-and-stream playback source.
`playback.open` also accepts a completed local path after the session is removed.
`download.add.fileIndices` supplies the initial inclusion selection atomically.
`download.select_files` replaces inclusion for one or several tasks, retaining
paths/data and reading back the result. Empty includes no files; omitted on add
includes all. Indices come from the full manifest, including unselected files.
The engine has no ordinary file-priority API. Controls quiesce the observation
worker and pause/reopen native storage for selection changes. Expanding a
completed selection returns a new observation job; the prior receipt stays
immutable and duplicate add returns the current hash's job. Classic calls omit
the optional selection and keep their prior behavior.

`download.add.fileBindings` (single `source` only) declares, at order time,
which episodes a file index is: entries `{fileIndex, workRef, releaseRef?,
episodeRefs, reason?}` use the catalogue-mode refs of `media.identity.bind_batch`.
Add validates them and rejects the whole call when an index is declared twice,
lies outside `fileIndices`, does not exist in a torrent file's manifest (magnets
have no manifest before the engine fetched metadata, so their out-of-range
indices are not detected at add), or an entry is malformed. The declaration is
stored in the job input with the invocation's origin. When a declared local
video passes verification, the executor saves its `completedFiles` row with
`binding: {status: pending}`, then runs `DownloadLibrary.bindFile`, which calls
`MediaService.bindBatch` (kind=file, `entityId` = the file id, requestId
`download:JOB_ID:file:INDEX`) with that origin. The outcome replaces `pending` on
the row, the row's `media` is read again, and `download.file_completed` carries it
as `file.binding`; the fact is not published while the row is pending. A pending
row found after a restart is bound again under the same requestId, which returns
the saved result. Statuses: `bound` (`workId`, `releaseId`, `episodeIds`, and
`supersededClassic` when the declaration took the place of Classic's automatic
match, see below), `already_identified` (the file already had episodes from a user
or agent binding, or a `local_catalog` link; `existingEpisodeIds`; nothing is
changed), `not_applied` (`file_not_registered`),
`failed` (`error`). One attempt per file; a failure never fails or retries the
download. Receipts list declared indices that never reached a binding attempt in
`details.unboundDeclarations` (`no_such_file`, `not_selected`, `not_video`,
`not_completed`). A duplicate add returns the existing job and keeps its
original declarations; `download.declare_files` changes them. Both the application
and the headless host implement `bindFile` through the same `bindDownloadedFile`,
and both register `download.declare_files` with the rest of the download family.

`download.declare_files {jobId, fileBindings}` declares or replaces declarations
of an existing download, with the entries and checks of `download.add` (for a
known manifest, indices must exist and be among the currently selected files).
Declarations merge by `fileIndex`: listed indices replace their earlier
declaration, others stay. They are stored in `checkpoint.fileBindings` (over
those of the job input) with the invocation's origin, so they survive restarts
and are carried into the observation job that expanding a selection creates.
The write goes through `TaskEngine.amendCheckpoint`: it changes neither job state,
phase, retry time nor the torrent, so it works while the download is running,
paused, queued, waiting to retry or waiting for a decision. A file that is not
completed yet is bound by the executor when it completes, as with `add`. A file
whose `completedFiles` row exists is bound at once, with the same logic, and the
outcome replaces `binding` on its row (also when it was `failed`, or when there
was no declaration). The response is `{job, declarationsSaved, bindings}`, one
`bindings` entry per declared index: the statuses above plus `declared` (saved,
the file is not completed yet; `reason`) and `not_applied` with `reason`
`not_video`, `requires_transfer`, `not_selected`, or `not_completed` for a
finished job. No `download.file_completed` event is published for a row that was
already complete. A cancelling download returns `conflict`. A finished download's
receipt is immutable: completed files are still bound and reported, but
`declarationsSaved` is false and nothing is written.

The requestId of a declaration made with `declare_files` is
`download:JOB_ID:file:INDEX:DIGEST`, where `DIGEST` derives from the declaration's
content: the same declaration replays the saved `bind_batch` result (and a file
whose row says it was bound by that request keeps `bound`), a changed one is a new
request, so the earlier result cannot reject it. Declarations from `add` keep
`download:JOB_ID:file:INDEX`. A file whose episodes come from a user's or an
agent's binding is never overwritten (`already_identified`).

A declaration takes precedence over NipaPlay's own automatic match of the same
file, that is the Classic scanner's filename/hash match of dandanplay, which the
Next identity store holds as `source=classic_match`. When every episode a file has
comes from such a match (`DownloadLibrary.lookup` reports
`classicMatchOnly: true`), the declaration is bound and the outcome is `bound` with
`supersededClassic: {source: "classic_match", workIds, episodeIds, emptiedWorkIds}`:
the work(s) and episode(s) the file was under, and the works that held nothing but
automatic matches and were taken out of the library (`library.merged`,
`library.works`; their records stay stored and show again when something is bound to
them). The file is then only under the declared episodes. Only declarations do this
(`bindDownloadedFile` passes `supersedeClassicMatch: true` to
`MediaService.bindBatch`); a plain `media.identity.bind_batch` leaves the match
beside the binding. Classic's own watch-history row (animeId, episodeId)
is not changed, and a later `syncClassicHistory` records the observation as
`classic_superseded` without attaching the file or recreating the work, for as long
as the declaration's binding is accepted. The Classic projection outbox only
carries explicit dandanplay bindings, so a declared Bangumi or TMDB identity writes
nothing to Classic.

Everything that rewrites a job's `completedFiles` rows takes the job's turn
(`DownloadExecutor.exclusive`): the executor's per-file stage and
`declare_files`. A `declare_files` that arrives while the worker is registering a
file waits for it, then reads the rows. The worker's other checkpoint writes
(`stalls`, `files`, the session facts) use `checkpointPatch`, which sets only
their keys on the checkpoint as stored when the write is applied.

`download.import` scans completed local videos, including when automatic scan is
off. It checks containment and actual sizes, reuses the Classic scanner and
completed-scan marker, and returns actual recognized entries. An attempted scan
does not imply `imported: true`; unmatched or unauthenticated scans remain
`identificationPending`. The action never rewrites the original receipt. For
unidentified files, existing `media.library.scan` can register native files under
a configured media root without inventing work or episode identity.

A download succeeds when its selected files have been read back and checked
against the backend manifest. Identification does not certify or block download
success. Each receipt file contains `path`, `expectedSize`, `actualSize`, and
`imported`; a confirmed library entry also includes `media`.

Selected local videos without a confirmed library entry have
`identificationPending: true`. After an unsuccessful identification attempt their
`reason` is `not_identified`. Other reasons, such as `auto_import_disabled` or
`previous_import_record_missing`, retain the context for skipping import. The
receipt never claims an entry was registered merely because the scanner returned
success. Remote files retain `requires_transfer` before any local registration.

The Classic adapter registers completed local videos in Next and reads their
current episode/work links as well as Classic matching. A completed scan attempt is recorded even if some files remain
unidentified, so session observation and application restart cannot repeatedly
scan the same torrent. Busy scanners and backend/file access failures still
retry as operational errors; missing identities do not schedule download retries.

The media intelligence work in `next/media-ma` owns file identity storage,
registration, and identification jobs/Decisions. Its integration point is
`AppDownloadLibrary.importFiles` and `lookup` behind `DownloadLibrary`: register
the verified local paths, read back their entries (including unidentified
entries), and let a separate identification task consume pending identities.
An unidentified registered entry returned by `lookup` carries
`identificationPending: true` in its media map. The executor reports
`imported: true` together with `identificationPending: true`. The application
adapter also reports `classicScanPending` when no Classic history entry exists;
enabled automatic scanning still gets its one identification attempt. This implementation does not create
an alternative identity store or launch identification tasks. Historical download
receipts remain snapshots; identification results belong to those later tasks.

Before whole-task completion, checked individual files are size/path verified,
registered through the same library adapter and persisted under
`checkpoint.completedFiles`. Enabled Classic identification attempts use separate
per-file scan markers and are not repeated by the final batch. These facts
authorize only their canonical local files, including while the task is paused
or later cancelled. Removing the session preserves that access; a missing file
or a symlink replaced with a different target does not inherit it.
`download.file_completed` has objectId `JOB_ID:FILE_INDEX` and data
`{jobId, infoHash, file}`. Hooks and followups consume the same persisted fact;
no hook program is needed for a followup. Hook submission is once per file object
across restart, and followups recover post-registration completion from task
checkpoints if publication was interrupted. Selection expansion carries prior
file observations with their original event objects, so it does not republish them.

Conversation downloads added through the Action capture a durable `returnTo` target
at submission. Next's followup observer automatically returns registered video
completion facts and terminal receipts to that conversation (helper sources return
to the recorded parent), including when the original turn has ended. Scripts,
hooks and GUI additions have no implicit return target. The first batch is eligible
immediately, subsequent files coalesce within a one-minute dispatch interval, and
termination flushes remaining facts. Matching explicit followups take precedence;
file object coverage persists across restart and expanded selection. This does not
choose notification wording, playback, identity binding, or further download work.

Completion receipts retain `fileIds` and the then-known `workIds`, including
per-file `media.fileId/workIds`. UI task/work association can follow those files'
current episode links after later identification. Verified, successful receipts
authorize their included completed local files by canonical path, even outside
library roots. This does not authorize the download directory or unfinished
neighbours, add a scan root, or invent an identity. `imageUrl` is a poster for a
work and a still for an episode; separate image roles remain independent facts.

Cancellation pauses the backend and reads back the preserved files and any
already submitted import. Its receipt records `paused`, per-file `retained` and
actual sizes, and finishes as `cancelled` even after side effects committed.
Download controls are serialized: repeated pause/resume and removal are harmless,
missing resume sessions return `not_found`, and resume during active cancellation
returns `conflict`. Native error-channel failures and source I/O errors are
translated to domain failures rather than `internal`.

The headless host uses the same Rust librqbit implementation via a portable C
ABI and its own vault/session directory. It exposes metadata preview and the
default directory, verified per-file progress, selection and task controls;
library registration uses Next's identity store without a Classic scanner.
Unidentified files retain that fact. Headless has no player, recent-directory
history or destructive disk-delete Action. Its health includes native peer
facts and selection support; Classic's in-process observation timing fields
are not synthesized. DHT/tracker/local discovery/public peers remain normal
defaults; host-only switches are documented in `docs/next/HEADLESS.md`.

Cross-device conversation returns use authenticated host-issued tickets and
durable batches; see `../followups/README.md`. Files remain on the downloading
body. Delivery never copies media or treats a remote playable path as local.
