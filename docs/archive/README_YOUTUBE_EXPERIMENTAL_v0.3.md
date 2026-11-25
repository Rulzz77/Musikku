# MusikKu 2.5.2 — YouTube Explode experimental build

This build adds an **experimental, unofficial** YouTube search and audio-stream adapter using `youtube_explode_dart: ^3.1.0`, connected to the app's `just_audio` / `audio_service` playback foundation.

## What is included

- Search YouTube videos by song title, artist, or keywords without a YouTube Data API key.
- Display title, channel/author, thumbnail, and duration from search results.
- Resolve the selected item's audio-only stream URL in memory and submit it to the `just_audio` queue.
- Basic queue pre-resolution for a small set of adjacent search results.
- Background playback/media session controls via the existing `audio_service` handler when the resolved stream is accepted by the platform player.
- Real seek slider in the full player, plus the existing favourites/history/preferences UI.
- Recent metadata cache only; ephemeral audio stream URLs are not persisted.

## Run in VS Code (Windows)

Open the folder containing `pubspec.yaml` in VS Code, connect your Android phone with USB debugging enabled, then run:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

To make an APK after verifying it runs:

```powershell
flutter build apk --debug
```

The APK is not included because this source was not compiled in the authoring environment.

## Important limitations

- This is an unsupported experiment. `youtube_explode_dart` uses reverse-engineered YouTube endpoints rather than the official YouTube Data API. It may break when YouTube changes its implementation, may be rate-limited, or may fail to resolve/play some streams.
- Stream URLs are short-lived and must not be stored; the app resolves them when preparing playback. A queued URL may expire before it is played.
- An HTTPS URL check is not a licensing or policy check. YouTube's official API/embedded-player policies do not support extracting separate audio streams for a third-party background player. The personal nature of the app does not make the unofficial integration officially supported.
- This build has not been validated with `flutter analyze`, `flutter test`, or an Android build because Flutter/Dart SDKs are not installed in the authoring environment. Those commands must be run on the development PC, and any first errors should be corrected before relying on the app.
- The catalogue fallback tiles are still preview data until live search succeeds. Lyrics, real account/cloud sync, true EQ DSP, Wi-Fi-only enforcement, and full queue persistence are not completed by this experiment.
