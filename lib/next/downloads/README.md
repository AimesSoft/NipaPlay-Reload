# Download completion and identification

Agent controls use the same Classic torrent session and preferences. Discover
jobs with `task.list` (`type: download`); `download.read` accepts `jobId` or
`jobIds` and returns live backend state, rates, output paths and indexed files.
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

`download.play` takes `jobId` and `fileIndex` from `download.read.files` and uses
Classic's selected-video playback source. Completed files play from disk even
without a recognized library entry; unfinished paused files resume and stream.
`playback.open` also accepts a completed local path after the session is removed.
File selection here means selecting a video to play. Classic currently has no
download inclusion editor, priority control or rate-limit setter.

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
