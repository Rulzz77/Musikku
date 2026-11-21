# Storage Manager — 2026-11-16

The Storage settings page now reports the sizes of five app-managed areas:

- **Downloaded files** — unique saved download URIs plus app-private artwork sidecars kept with those downloads. File-backed HLS/DASH packages are measured recursively; MediaStore downloads are measured from their content URI metadata.
- **Audio cache** — the persistent no-backup audio cache. This is deliberately reported separately because complete cached songs can be played offline and clearing it removes the Cached songs collection.
- **Artwork cache** — Coil's disk cache under the app cache directory.
- **Canvas cache** — cached looping clips under the Canvas cache directory.
- **Automix AI models** — extracted ONNX model copies under the disposable `cacheDir/automix_models` directory. They are recreated from APK assets when needed and may be reclaimed by Android.

The page also reports the free space visible from the app data volume. The managed subtotal includes extracted Automix model files but does not include the model assets embedded in the APK. The total is a managed-area subtotal, not a claim that it measures every byte attributed to the application by Android.

Cleanup boundaries are intentionally conservative:

- Clear song cache continues to use AudioCache.clear, with its existing confirmation and warning.
- Clear artwork cache uses Coil's memory and disk cache APIs.
- Clear Canvas cache removes only Canvas SimpleCache resources.
- Downloaded tracks and their sidecar artwork are never bulk-deleted by the Storage page.
- Local music selected through the document picker, playlists, backups, app settings and databases are not part of the cleanup target.

The storage scan runs on Dispatchers.IO, counts duplicate download URIs once, and reads content-provider file lengths without loading audio data into memory.
