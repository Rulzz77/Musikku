# MusikKu — Premium Minimal + Immersive (Implementation Pass 2)

Baseline: `musikku_premium_immersive_redesign_v12_reapplied.zip`.

## Screens and interactions refined in this pass

- Lyrics: ambient artwork blur and theme-aware overlay while retaining the existing synchronized lyric list, manual scrolling, and line-centering behavior.
- Queue: polished sheet surface, explicit `Next Up` hierarchy, duration labels, and existing reorder/remove/undo behavior retained.
- Album detail: new Editorial Album Focus page with artwork-led header, play/shuffle actions, tracklist, and responsive two-column tablet layout. Album search cards now open this page.
- Artist detail: responsive two-column layout on wide screens, while phone layout remains editorial and vertically scrollable.
- Playlist detail: responsive Editorial header, cover editing, playlist metadata, and existing playlist actions retained.
- Radio: editorial mood grid and recent-radio seeds. Mood actions search for a suitable music result before starting the existing radio callback; recent radio cards start radio from the selected seed.
- Collection: recent playlists are surfaced as artwork-led cards above the collection list.
- Spotify import: the progress surface now lists each imported Spotify track with a live status (`Menunggu`, `Mencari`, `Ditemukan`, `Alternatif`, `Belum cocok`) alongside overall progress. The existing staged matcher and unmatched-track report are retained.
- Downloads: the download manager now surfaces active/offline/failed counts before the existing per-track progress and retry controls.
- Listening Together: connected rooms show the current shared track, its artist, and local playback progress in the Music Room panel.

## Important behavior retained

- Existing player, Spotify importer, download service, queue manager, artist search, radio service, and Listening Together service remain the source of playback/business logic.
- Cover/alternate candidates remain visibly distinct in Spotify import; unmatched tracks are not silently substituted.
- Playlist and album actions continue to call existing playback callbacks.
- Download All remains explicit; adding a song to a playlist does not auto-download it.
- Listening Together remains code-based and does not add account/login requirements.

## Validation in this environment

- ZIP structure and package paths checked.
- Android Manifest XML parsed.
- `pubspec.yaml` parsed and registered asset paths checked.
- Android launcher icon aliases/resources retained from v12.
- Dart delimiter scan and import/path checks performed.
- A patch from v12 was generated and checked against a clean v12 tree.

## Validation not performed

Flutter/Dart SDK executables are unavailable in this environment. Therefore `flutter analyze`, `flutter test`, Android Gradle/Kotlin compilation, and APK build have not been run. Please run on the development machine:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```
