# MusikKu — Final Pending Fix Pack (2026-11-05)

Project baseline: MusikKu 5.4.1+21. This package consolidates the previous native features, Android Auto browse improvements, Smart Queue 2.0, home/local-music UX, playlist-size estimate, Kotlin compatibility fix, and the latest offline-transfer hardening.

## Final downloader changes

- Resume only accepts a valid `206 Content-Range` beginning at the exact requested byte and ending at the final byte declared by the resource (`end == total - 1`) for an open-ended `bytes=<offset>-` request.
- Response `Content-Length` must match the advertised range length when present.
- A server that ignores Range and responds with `200` causes a safe restart/truncate rather than appending a full body to partial bytes.
- A stale URL is refreshed once. Resume bytes are kept only when the selected format/codec/bitrate fingerprint is unchanged.
- Redirects are manually followed with a strict HTTPS GoogleVideo host allow-list and a limit of five.
- Connect/request/idle timeouts, 768 MB per-track cap, 48 MB storage reserve, and storage rechecks every 8 MiB are enforced.
- MIME and audio magic-byte checks run before a completed file is recorded.
- Download files remain in the app-private MusikKu/Offline directory; path checks reject symlinks and external paths.
- Queue restore is resilient to a corrupt row; duplicate, already queued, already downloaded, and failed additions are counted separately.
- Preference writes are serialized; an active paused/resuming track is not enqueued twice.

## Other consolidated improvements

- Smart Queue 2.0 scoring and tests.
- Local music active-track indicator and media scan/artwork UX improvements.
- Home playlist cards navigate to detail before playback.
- Playlist download-size estimate shows an estimated range and unknown-duration count.
- Android native controls: Bluetooth auto resume, output selection for Media3, Floating Lyrics overlay, home widget, PCM visualizer, RMS adaptive leveler, and MediaBrowser-based Android Auto local catalogue browsing.
- Native gapless-capable queues for compatible Android Media3 local and remote audio sequences.
- Kotlin Media3 compatibility fix (`onFlush()` and `setEnableAudioTrackPlaybackParams`).

## Remaining limitations (not hidden)

- The offline downloader is still owned by the Flutter app process. It can preserve partial bytes and resume after reopening, but it is not yet an Android foreground download worker; OS process termination stops the active transfer.
- PCM visualizer, output selection, adaptive leveler, and native gapless apply only to Media3 playback. They cannot process an iOS embedded iFrame player.
- Android Auto browses the local MediaStore catalogue; the online YouTube catalogue and custom cloud playlists are not browse categories.
- Loudness processing is an adaptive RMS leveler, not standards-compliant EBU R128 LUFS or ReplayGain.
- Gapless-capable queues are not a guarantee of silence-free transitions on every CDN/network/device. Verify on hardware.
- Smart Queue's official-release filter remains metadata heuristic, not definitive channel/rights verification.
- Downloader use must remain within the scope of written authorization for download, local storage, and offline playback.

## Verification status

Static archive/XML checks were run for this package. Flutter Analyzer, `flutter test`, Gradle builds, and physical-device tests were not run because the working environment has no Flutter/Dart SDK or Android SDK.

Run from the project root on Windows:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build apk --debug
flutter build apk --release
```
