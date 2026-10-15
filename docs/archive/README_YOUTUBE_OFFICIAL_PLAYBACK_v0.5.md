# MusikKu 2.5.5 — YouTube in-app player

This iteration keeps playback inside MusikKu using `youtube_player_iframe`, a Flutter package built on YouTube's official IFrame Player API. Tapping a YouTube search/recommendation item opens a MusikKu player page with the embedded YouTube player, title/channel details, favorites, queue reorder/select, next/previous, shuffle, and repeat-mode controls.

## How to run

From the `MusikKu` folder in VS Code PowerShell:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Search for a song under Jelajah and tap a result. The in-app player route should appear; it does not hand the URL off to the separate YouTube app. The official player controls remain visible and handle playback inside its embedded frame.

## Important limits

- The embedded player plays YouTube audiovisual content in MusikKu; it is not an audio-only extractor.
- YouTube's official player does not grant MusikKu a reliable background-only audio session. Screen-off/background playback is not guaranteed for an embedded player.
- YouTube's official player can open external YouTube links using its own UI; this app does not force that handoff.
- Search/metadata still uses `youtube_explode_dart`, which is unofficial/reverse-engineered. Use YouTube Data API for an officially supported catalog integration.
- Source/archive checks were performed, but Flutter analyze, tests, and APK build must be run on the user's development PC because Flutter/Dart SDKs are unavailable in the authoring environment.


## Fix v0.5.1 (compile)
Pada `youtube_player_iframe` 6.0.2, method untuk melanjutkan pemutaran adalah `playVideo()`, bukan `play()`. Tiga pemanggilan terkait repeat/previous sudah diperbaiki di versi ini.
