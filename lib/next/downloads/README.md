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
`download.remove` and `download.delete` of a download that had already ended
(succeeded, failed or cancelled) and still had a session keep its state but
amend its receipt: `files` are re-read (`actualSize`, `retained`, `imported`;
`imported` is read-only: true only for a file still on disk whose path is
already registered in the media library, so a file that was never registered,
never downloaded or has been deleted reads false and re-reading registers
nothing),
`sessionPresent` is false, `removedAt` is the UTC time and `dataDeleted` says
whether the data went too. The amendment is a `receipt_amended` task event and
does not raise a new completion follow-up. A removed download that is added
again is a new job; the old one keeps its amended record.
A session that disappears without Next (Classic removes it straight from the
engine) is noticed by the runtime's existing refresh, at Next start and every few
seconds from then on, using the listing it already reads: an ended job that had a
session and whose receipt lacks `sessionPresent: false` gets the same amendment,
with `removedAt` the time it was noticed and `observedMissingAt` the same time
marking it as observed. `dataDeleted` is not written: who removed it, and whether
the data went, is unknown; the re-read `retained` says whether the files remain.
Classic itself is unchanged, and with Next off nothing runs.

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
since the counter restarts with the process. Not getting metadata counts too:
a magnet whose metadata does not resolve keeps retrying the add, and retrying is
not progress, so once `stallAfter` has passed since submission with no metadata
and no byte, the entry is appended with `metadata: false`, the last `error`
(code and message), `completedBytes` 0 and `totalBytes`, `connectedPeers`,
`seenPeers` and `deadPeers` null (the engine has no session to count). It is
detected at a retry, so up to one retry delay late, and written once; getting
the metadata closes it (`resumedAt`), and a later stretch without bytes is a new
entry. An open stall of a download started
from a conversation returns there at once as a `download.stalled` fact; passed
stalls and stalls of finished tasks are not sent. Every open stall, whoever
started the download, is also the public event `download.stalled`
(see followups/README.md).
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

A registered local video's library entry (`media`: `fileId`, `workIds`,
`episodes`) is on its `download.file_completed` event and on its row of
`download.read`; `download.read` looks the entry up again, so its episode links
are the ones the file has now, and the event carries the entry as it was when the
file was registered. Each episode entry has `identitySources`: one item per
accepted file binding standing behind that link, `{bindingId, source, boundBy,
origin?}` (`source: classic_match` with `boundBy: null` is Classic's automatic
match; any other `source` is a binding written through `media.identity.bind_batch`,
with `boundBy` `agent` or `user` and the `origin` of the invocation that wrote
it), plus `{source: local_catalog}` for a link made through `localEpisodeIds`.
A file with no links has `episodes: []` and `identificationPending: true`. The
download writes no identity itself: binding downloaded files is done with the
`media.identity` primitives like any other file.

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

## HTTP backend

`download.add {source, backend: {kind: "http"}}` downloads one http:// or https://
file (other schemes are refused) with `HttpDownloadBackend`, registered in Next
only; Classic's download page lists the native session and never sees these
tasks. The job is an ordinary `type: download` task with
`details.backend = {kind: "http"}`.

Identity: `input.infoHash` is `http-` plus the SHA-1 of the request URL without
fragment (scheme and host lower-cased, default port dropped), so it never equals a
BT hash; the session handle is the hex part. Adding the same URL again follows the
usual hash deduplication. Sessions are kept as JSON under `DATA/http_downloads/`
and resume after a restart when the downloader is enabled.

Output: `downloadDirectory`, else the download directory setting; a folder named
after the file only when `createFolderForTask` is true. The file name is the
`Content-Disposition` filename, else the last path segment of the final URL
(percent-decoded; directory parts and control characters dropped; `download` if
nothing is left). An existing file, partial file or other session's target is
never overwritten: a taken name gets ` (1)`, ` (2)` before the extension. Data is
written to `NAME.nipaplay-part` and renamed when complete and, if requested,
verified. `fileIndices` is refused. A removed session leaves its
`.nipaplay-part` file (like removing a torrent keeps data); `download.delete`
removes it with the final file.

Transfer: GET with `Accept-Encoding: identity`; resumption sends
`Range: bytes=N-` (plus `If-Range` with the ETag or Last-Modified), unless the
server advertised `Accept-Ranges: none`. A 206 whose `Content-Range` starts at N
continues; a 200 or an unexpected range restarts from byte 0 (`health.http.resume`
is `confirmed`, `ignored` or `rejected`). Connection errors, timeouts (30 s to
connect, 60 s without a byte), 5xx, 408 and 429 are retried with 1, 2, 5, 10, then
30 s pauses and count as no progress, so `health.secondsWithoutProgress` grows and
the usual `stallAfter` rule appends `checkpoint.stalls`; `health.http.lastError`
and `retries` say why. 404/410 (`not_found`), other 4xx and certificate errors
fail the task at once (`unavailable`, not retryable); a failing first request at
`download.add` is a retryable `unavailable` (or the 4xx failure) like an
unresolved magnet. Time without progress starts at session start or resume, not
at pause.

Checksum: `checksum {algorithm: md5|sha1|sha256, value}` is compared after the last
byte (hashed off the UI isolate). `task.checksum` and `receipt.checksum` are
`{algorithm, requested, expected, actual, matched}`; `matched` is null when
nothing was requested (then `algorithm` is sha256). A mismatch fails the task
(`conflict`, with `details.checksum`) and keeps the data as `.nipaplay-part`
(`checksum.file`). A failed session is not resumed; remove it and add again.

Proxy: the HTTP client uses `AppHttpProxy` (the player/media-server proxy setting),
else `SystemProxyService`, loopback excepted, plus the global certificate trust
overrides; the same resolution as the other Next clients.

`download.preview {source, backend: {kind: "http"}}`: HEAD, or `GET` with
`Range: bytes=0-0` closed after the headers if HEAD is answered with an error
status or fails. Returns `url`, `finalUrl`, `redirects`, `statusCode` (an HTTP
error status is reported, not thrown), `method`, `contentLength`, `contentType`,
`acceptRanges`, `fileName`, `lastModified`, `etag`. Nothing is downloaded or
created.

`task.health` for an HTTP download has null peer fields; `files[0].completedBytes`
is null while the size is unknown. A finished file is a video when its extension
is one the torrent backend also treats as video; otherwise it is reported as
`not_video` and left alone.
