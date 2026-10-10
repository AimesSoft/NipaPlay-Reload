# Download completion and identification

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

The current Classic adapter uses the existing scanner and recognized history
entries. A completed scan attempt is recorded even if some files remain
unidentified, so session observation and application restart cannot repeatedly
scan the same torrent. Busy scanners and backend/file access failures still
retry as operational errors; missing identities do not schedule download retries.

The media intelligence work in `next/media-ma` owns file identity storage,
registration, and identification jobs/Decisions. Its integration point is
`AppDownloadLibrary.importFiles` and `lookup` behind `DownloadLibrary`: register
the verified local paths, read back their entries (including unidentified
entries), and let a separate identification task consume pending identities.
An unidentified registered entry returned by `lookup` carries
`identificationPending: true` in its media map. The executor then reports
`imported: true` together with `identificationPending: true`, without rescanning
the entry for recognition. This download implementation does not create
an alternative identity store or launch identification tasks. Historical download
receipts remain snapshots; identification results belong to those later tasks.

Cancellation pauses the backend and reads back the preserved files and any
already submitted import. Its receipt records `paused`, per-file `retained` and
actual sizes, and finishes as `cancelled` even after side effects committed.
Download controls are serialized: repeated pause/resume and removal are harmless,
missing resume sessions return `not_found`, and resume during active cancellation
returns `conflict`. Native error-channel failures and source I/O errors are
translated to domain failures rather than `internal`.
