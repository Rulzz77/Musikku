# MusikKu 2.5.4 — YouTube official playback handoff

This build intentionally does not extract an audio-only stream from YouTube. It keeps the current YouTube search/metadata workflow and opens the selected video in the official YouTube app (or the system handler/browser if no app can handle the link). This avoids sending reverse-engineered stream URLs to `just_audio`, which was the path producing HTTP 403 in v0.3.

## What changes

- Selecting a YouTube result opens `https://www.youtube.com/watch?v=<videoId>` externally.
- Mini player and full player buttons for YouTube items are labelled as open-in-YouTube actions, not fake in-app play/pause controls.
- Queue next/previous picks a metadata result and opens it in YouTube.
- MusikKu no longer tries to resolve YouTube audio-only stream URLs for this page.
- The local music sleep timer and equalizer clearly do not claim to control audio that is playing in the separate YouTube app.

## Important limitation

Song discovery/metadata remains YouTube-based, and the actual playback is handled by YouTube, not by MusikKu's `just_audio` player. Background playback and lock-screen behaviour are therefore governed by the YouTube application/account and may require YouTube Premium/YouTube Music Premium. MusikKu cannot pause the external YouTube player, seek its timeline, or control its queue.

Search in this redesigned page currently uses `youtube_explode_dart` to retrieve search/metadata without an API key. That library is unofficial and reverse-engineered. A fully official YouTube catalog integration should use the YouTube Data API and a configured `YOUTUBE_API_KEY`; playback should still be handed off to the official player.

## Test on your PC

From the directory containing `pubspec.yaml`, run in VS Code PowerShell:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Then search a title and tap a result. Android should open the official YouTube player; verify sound in YouTube itself. This source was not compiled or tested on a physical device in the authoring environment because Flutter/Dart SDKs are not available there.
