# MusikKu — Non-API Features Update (4 November 2026)

This update consolidates the previously added local/native features and extends Android Auto browsing. It does not add a third-party API, backend endpoint, API key, Flutter package, or new Android permission.

## Implemented in source

- Bluetooth auto-resume: existing Android audio-device callback and 60-second reconnect window remain enabled by the existing Settings switch. It only arms after playback was active and does not intentionally resume after a manual pause.
- Audio output selection: user can save Default Android or a detected output device. Media3 playback uses `ExoPlayer.setPreferredAudioDevice`; an iframe/WebView fallback remains routed by Android's system audio policy.
- Floating Lyrics: Android overlay with draggable position, close action, and current synchronized lyric-line updates. Requires the user to grant Android's Display over other apps permission.
- Home Screen Widget: title/artist and previous/play-pause/next/open controls, refreshed on metadata/play-state changes and throttled during progress snapshots. Next now advances directly within an active native local gapless queue; after its local successors are exhausted, it delegates to Flutter instead of silently stopping a mixed playlist.
- PCM Visualizer: receives peak samples from decoded Media3 PCM buffers, not microphone capture. It only works while the active playback path is Media3.
- Adaptive volume leveler (Beta): RMS target with peak-aware gain limiting and smoothed gain changes in the Media3 PCM processor. This is not an EBU R128 LUFS or ReplayGain analyser and does not affect iframe/WebView playback.
- True Gapless: native Media3 playlist transitions for consecutive local/offline tracks under the constraints documented in `TRUE_GAPLESS_UPDATE.md`.
- Smart Queue 2.0: local ranking from musical similarity, listening history, skips, likes/dislikes, mood hints, recency and artist cooldown. It does not add requests or rely on external recommendation APIs.

## Android Auto browse update

`PlaybackService` now exposes a browsable tree through its existing `MediaBrowserServiceCompat` session:

- Now Playing (when a session exists)
- All local songs
- Recently added local songs
- Artists and their tracks
- Albums and their tracks

The service handles MediaBrowser play-from-id and play-from-search for local audio. The browse tree supports standard page/page-size options for all songs, recently added, artists, albums, and their tracks, so it is not limited to one fixed first page. Each track ID preserves its parent list and absolute position; selecting a song rebuilds the queue from that point. A selected list is sent to Media3 as one native queue (current track plus up to 60 successors). When only eight successors remain, the service asynchronously reads and appends the next page, allowing Android Auto playback to continue through larger local collections without requiring the Flutter activity to stay open. Android Auto previous/next/seek controls operate on that native queue. The queue uses the current native queue for Android Auto, while normal app/widget Next falls back to Flutter after the preloaded local successors end, allowing mixed local/online playlists to continue according to the existing queue rules. The browse tree refreshes when MediaStore audio content changes. MediaStore access requires the app's existing audio-library permission.

The browse tree currently covers audio indexed by Android MediaStore. It does not yet expose MusikKu's online YouTube catalogue or custom online playlists from Flutter. The existing Now Playing MediaSession metadata and transport controls continue to work for the active session.

## Platform limits that remain intentional

- Android output-device routing, PCM visualization, adaptive volume processing and True Gapless require playback to be handled by Media3. They cannot intercept raw samples or force a specific media route for a separate WebView/iframe playback engine.
- The adaptive volume feature is intentionally labelled Beta; it is not advertised as LUFS/ReplayGain compliant.
- True Gapless is for local/offline Media3 tracks only. Online iframe/YouTube and iOS paths retain their existing auto-next behavior.
- Android Auto needs a real compatible head unit/emulator test. The browser-service code is present, but source-level checks do not prove device-level Android Auto certification or rendering.

## Validation still required on the developer machine

Run from the project root:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build apk --debug
flutter build apk --release
```

Then test Android Auto on a compatible car/head-unit emulator or device and test Bluetooth, overlay permission, widget controls, output switching, native PCM visualizer, adaptive leveler, and a multi-track local playlist on a physical Android device.
