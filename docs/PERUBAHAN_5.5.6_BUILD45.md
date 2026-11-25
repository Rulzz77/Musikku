# MusikKu 5.5.6+45 — Spotify playlist matching

## What changed

- Spotify subtitle artist credits are parsed into ordered names; an empty `artists` list no longer blocks valid `subtitle` data.
- Import searches now try artist + title, title, title + collaborators, reverse title/artist order, and artist fallback. Candidate IDs are deduplicated before the strict matcher runs.
- YouTube search-query filtering now allows the requested artist/title tokens to appear across the title, channel, and description regardless of order. The importer still applies a separate primary-artist check so a loose search result cannot be imported just because the words were present.
- YouTube Music auto-generated `Provided to YouTube by` track-credit blocks are accepted only when both the expected song title and primary artist appear together. Casual promotional mentions remain rejected.
- Spotify track duration helps rank similar candidate videos without becoming a hard gate.
- Soundtrack source suffixes such as `- From "Cidro Asmoro"` remain in the Spotify display title and are ignored only for core-title comparison.
- Imported playlist items keep Spotify's exact title and full ordered artist credits while retaining the selected YouTube video ID and playback metadata.
- Fixed multiple-underscore callback lint patterns in `custom_playlists_page.dart`.
- Version bumped to `5.5.6+45`.

## Playlist checked

The public embed for the user-supplied `Playlist Jawa` was accessible during review and showed 100 numbered rows. Sample credits include `Dumes` — OMWAWES, Guyon Waton; `Satru` — Denny Caknan, Happy Asmara; `Mencintai Dengan Ngeyel` — E Woro Widowati; and `Koyo Jogja Istimewa - From Cidro Asmoro` — Ndarboy Genk. The embed's 100 visible rows do not establish the actual total playlist size.

## Tests added

- Spotify subtitle fallback when `artists` is empty.
- YouTube generated credit blocks for official label uploads.
- Reversed query token order for artist + title.
- Duration-based ranking of otherwise equivalent candidates.
- Soundtrack attribution suffix omitted from YouTube title.
- One-letter initial alias such as `E Northsle` vs `Northsle`.
- Existing wrong-singer, casual-description, karaoke, cover, AI, live-version, partial-title, duplicate-order, and 125-track parser tests retained.

## Verification limits

The project ZIP can be structurally checked and version synchronization can be verified here. Flutter/Dart SDK is not installed in this execution environment, so `flutter analyze`, `flutter test`, and APK compilation cannot be honestly reported as run. Actual YouTube search matching must be checked on-device because network search results are dynamic and are not available to this offline build environment.
