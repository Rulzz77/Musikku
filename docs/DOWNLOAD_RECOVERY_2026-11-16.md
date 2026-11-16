# Download Recovery — 16 November 2026

## Goal

Keep the Android foreground-download queue and the user's download-manager outcome visible across process death and app restarts. This is separate from the already-persisted catalogue of completed files in `Downloads.saved`.

## What is persisted

The app stores a versioned `DownloadRecoverySnapshot` in the existing `bitchord_settings` SharedPreferences file:

- Spotify-/catalogue-independent track identity and the metadata needed to retry or render the manager row;
- queue order, release label, and the "download from Cached songs" preference;
- queued, running, completed, and failed states;
- the manager's seen/settled markers.

All unsettled foreground-queue rows are retained. The latest 200 settled rows are retained so a long-running install does not grow the manager snapshot without bound. WorkManager-owned `PlaylistSync.downloadNow` rows are excluded because their worker owns their lifecycle.

The snapshot is updated at state transitions and uses a synchronous preference commit for those checkpoints. Intermediate byte-progress ticks remain in memory only, to avoid a preference write for every chunk.

## Restart behaviour

1. `Downloads.init` restores the snapshot before the Activity starts.
2. A saved `Running` row is converted to `Queued`; rows that were already queued stay queued; completed and failed rows remain visible.
3. The pending queue is rebuilt in original ask order.
4. When the Activity enters the foreground, it restarts the existing foreground `DownloadService` to drain the recovered queue.
5. The existing completed-file check adopts a file that was fully committed just before process death, instead of downloading another copy.
6. The user's cached-copy preference is restored so a retry can still use an available complete cache file.

## Temporary destination cleanup

The downloader intentionally publishes files only after their bytes and tags are complete:

- MediaStore rows use `IS_PENDING=1`; recovery lookup now only adopts rows with `IS_PENDING=0`. A retry removes stale pending rows for that exact filename before creating a new one.
- Legacy and app-private single-file downloads use `.part` files, which are discarded when a new attempt begins.
- Offline HLS/DASH packages clean their private package directory before a new attempt.

This prevents an interrupted destination from being mistaken for a completed file.

## Important limitation: retry from the beginning, not byte-range resume

The current writer does not persist stream URLs, request headers, encryption/session details, or a committed byte offset. Those values can expire or change, and resuming a different rendition at a prior offset could corrupt the result. Therefore a track interrupted while it was running is resolved again and downloaded from byte zero. Other tracks already completed remain completed and are not fetched again.

This stage does **not** claim OS-guaranteed completion after force-stop, reboot-time auto-start, or true partial-byte resume. The queue resumes when MusikKu is opened again and the Activity can start its foreground service.

## Regression coverage

`DownloadRecoveryTest` covers DTO round-trip, preservation of track/source metadata and cache preference, conversion of Running to Queued, preservation of Done/Failed outcomes, bounded settled history, and unknown-schema handling.

`DownloadSessionTest` covers process-restart restoration, exclusion of non-recoverable worker-owned rows, sequence-clock monotonicity, and avoiding persistence on every progress tick.
