# MusikKu 5.5.6+50 — fix invalid const in Spotify import UI

## Fix
- Removed `const` from the `InputDecoration` that contains a runtime-interpolated `snapshot.tracks.length` value in `lib/pages/custom_playlists_page.dart`.
- Kept the dynamic label text. The supplementary-track entry field was later removed in Build 51 so users only need to paste one Spotify playlist link.
- Bumped the build number to 50 and synchronized `lib/app_info.dart` with `pubspec.yaml`.

## Validation
- Confirmed the reported `InputDecoration` is no longer declared `const`.
- Confirmed `tool/sync_app_version.py --check` passes.
- Flutter/Dart SDK is unavailable in the packaging environment, so run `flutter analyze`, `flutter test`, and an APK build locally.
