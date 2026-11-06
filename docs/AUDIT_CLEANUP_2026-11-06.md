# MusikKu source audit and cleanup — 6 November 2026

## Confirmed cleanup

- Removed `lib/widgets/lyrics_panel.dart`: it was not reachable from `lib/main.dart`, had no import/export references, and `LyricsPanel` had no call sites. After removal, all 101 remaining Dart files are reachable from `lib/main.dart`.
- Removed the write-only video-detail cache from `YoutubeSearchService`. It had no read path, so its writes, cache queue, disk key, and SHA-256 dependency were dead code. Other search, channel, radio, artwork, and playlist caches remain in place.
- Removed unused `YoutubeSearchService` compatibility helpers (`describeSearch`, `searchPopular`, and the no-op `isShortVideo`) and the single-value `YoutubeSearchMode` abstraction. All active callers now use the active search path directly.
- Removed the unused search `filter` argument/state that was not affecting results.
- Removed direct dependencies `google_sign_in` and `flutter_local_notifications`: no Dart source used either package. MusikKu uses its own native media notification bridge, and account sign-in has no active app flow. `audio_service` remains because Android's `MainActivity` extends `AudioServiceActivity`.

## Catalogue fixes

- Normal catalogue search no longer automatically appends `official`, which was narrowing artist searches and dropping independent releases.
- Known artist searches are no longer automatically restricted with an `Indonesia` suffix. Generic music searches such as `lagu pop` still receive the Indonesian context.
- Added a query-scoped allowance for normal-length original tracks from a channel whose name matches the searched artist. Generic genre searches remain on the stricter official-release policy.
- Covers, karaoke, AI-labelled uploads, Shorts, non-music videos, and album/compilation-labelled results remain excluded by the fallback rule.
- Search result cap increased from 16 to 30 outside data-saver mode.
- Channel discovery now ranks channels matching the artist name earlier, and an artist card may be built from one matching result rather than requiring three.
- Artist profile fallback and upload-list filtering now accept ordinary singles from the matched artist channel even if the title/channel description does not contain `Official`, `Topic`, or `Music` markers.

## Regression coverage added

`test/music_catalog_policy_test.dart` covers Fiersa Besari, Tulus, Raisa, and Hindia artist-channel results; query qualifiers; known-artist query localization; generic genre strictness; unrelated channels; covers; and album-labelled uploads.

## Validation limitation

The Flutter and Dart SDK executables were not available in the audit environment. Therefore `dart format`, `flutter analyze`, `flutter test`, and APK compilation were not run here. Run `flutter pub get`, `dart format lib test`, `flutter analyze`, and `flutter test` after extracting this project. `flutter pub get` will also refresh `pubspec.lock` and generated plugin registrants after the unused direct dependencies were removed.
