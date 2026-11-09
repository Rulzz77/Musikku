# MusikKu 5.5.6+49 — Spotify count clarity & album artwork

## Spotify playlist count
- Playlist total metadata is now aggregated across every public embed payload/script instead of accepting the first count encountered.
- Additional public count field variants are recognized inside playlist/track-list metadata.
- When the embed exposes 100 rows but does not provide a larger total, the UI explicitly renders `≥100` and says the total is unknown; it no longer reads like the playlist total is exactly 100.
- The supplementary paste field is worded relative to the number of rows actually read, not hardcoded to track 101. Order and duplicates remain preserved.
- This still cannot retrieve rows Spotify does not include in the public embed. It does not use Spotify API, login, OAuth, hidden endpoints, or undocumented pagination.

## Album artwork
- Album-art cache is bumped to v5 so previous results are looked up again under the stricter resolver.
- Every non-local music tile/player using `UnifiedArtwork`/`AlbumArtworkImage` shares the MusicBrainz + Cover Art Archive resolver.
- Resolver requires a close recording title and artist-credit match, only accepts approved front covers, and prefers 1200px then 500px/250px artwork.
- If an album title is available it is tried first; otherwise the exact recording title and primary artist are searched. Candidate errors are isolated so another matching release can be tried.
- YouTube Music auto-generated credits now handle more title/artist separators and soundtrack title suffixes. The primary performer is used for metadata lookup, while Spotify's full ordered credits remain the display label on imported tracks.
- If no verified cover is in the catalog, fallback remains the selected track's own best YouTube thumbnail. No random image-search result is used. MusicBrainz/Cover Art Archive does not have complete artwork coverage for every regional release, so an album-cover match cannot be guaranteed for every track.

## Validation
- Flutter SDK was not available in the build environment. Run `flutter analyze`, `flutter test`, and `flutter build apk --release` locally.
