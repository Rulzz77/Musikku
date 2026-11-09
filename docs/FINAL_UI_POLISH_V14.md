# MusikKu — Final UI Polish Pass (v14)

Baseline: `musikku_premium_immersive_redesign_v13.zip` (app version remains `5.6.5+45`).

## Final polish in this pass

- Applied the app's **Reduce Motion** preference consistently to the remaining high-visibility transitions in local music rows, channel-tab indicators, data-usage totals, lyric line transitions, lyric auto-scroll, and karaoke word-fill interpolation.
- Kept the existing Premium Minimal + Immersive design system, System/Light/Dark/AMOLED modes, Ocean Blue default accent, alternate accent choices, Android launcher icon color variants, floating navigation, mini-player, responsive tablet foundations, and the v13 screen refinements intact.
- Lyrics track-specific preferences are now scheduled after the frame rather than starting an asynchronous SharedPreferences load directly during every `ValueListenableBuilder` build. A pending video ID guard prevents an obsolete scheduled load from overwriting the active track's settings.
- Constrained long-form settings and lyric content to a readable maximum width on large displays.
- No playback, Spotify matching, playlist, offline-download, Radio, or Listening Together service contract was intentionally changed in this polish pass.

## Included screen coverage from v12/v13

- Home editorial layout and global navigation / mini-player.
- Search tabs: All, Songs, Artists, Albums, Videos.
- Full player and responsive tablet layout.
- Lyrics, Queue, Playlist detail, Artist detail, Album detail.
- Radio and Collection surfaces.
- Spotify import per-track progress state and unmatched-track reporting.
- Download Manager progress / summary surface.
- Listening Together Music Room now-playing surface.
- Grouped Settings, accent themes, reduced motion, and Android home-screen icon recolors.

## Static validation performed for v14

- `pubspec.yaml` parsed.
- All registered asset paths exist.
- Android manifest XML parsed and 8 launcher activity aliases found.
- All relative Dart imports / exports / parts resolve.
- Dart delimiter, string, and comment scan passed for 123 Dart files.
- Key Spotify import status labels and Listening Together shared now-playing panel are present.
- Album duration model conversion check passed.
- ZIP integrity test performed on the final archive.

## Validation not performed

Flutter and Dart SDK executables are not installed in the build environment, and the environment could not resolve the Flutter SDK download host. Therefore this pass has **not** been verified by `dart format`, `flutter analyze`, `flutter test`, Gradle/Kotlin compilation, or APK build. Static checks do not prove successful Flutter compilation or runtime behavior.

Run on the development machine:

```bash
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

Then test on a physical Android device or emulator: theme switching, launcher icon switching, audio playback, queue operations, lyrics sync, playlist import, downloads, and Listening Together on mobile data/Wi-Fi.
