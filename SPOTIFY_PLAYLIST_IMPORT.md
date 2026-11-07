# Spotify Public Playlist Import (Build 49)

MusikKu imports metadata from a **public Spotify playlist embed** and then searches for matching audio through MusikKu's existing YouTube Music catalogue. It does not use the Spotify Web API, a developer key, OAuth, Spotify login, anonymous access tokens, hidden/private endpoints, or Spotify audio/preview URLs.

## User flow

1. Open **Koleksi / Ruang playlist**.
2. Tap **Spotify** (or **Impor dari Spotify** when the collection is empty).
3. Paste a public `open.spotify.com/playlist/...` or `spotify.link/...` playlist URL.
4. Review the title, artist credits, and partial-list warning read from the public embed HTML.
5. MusikKu searches YouTube Music and saves only confident matches to a local playlist.

## Matching, display metadata, and order

- Track title, ordered artist credits, track ID, and duration are read from public embed JSON, including the `state.data.entity.trackList` layout.
- Empty `artists` arrays no longer mask a usable `subtitle` artist credit. Comma-separated subtitle credits are split in Spotify display order, so `OMWAWES, Guyon Waton` makes OMWAWES the primary artist and Guyon Waton a collaborator.
- Candidate search tries primary artist + title, title alone, title + all collaborator credits, reversed title/artist order, and a final primary-artist fallback. Results from different queries are deduplicated by YouTube video ID.
- Query filtering accepts reversed word order when query tokens are present across title, channel, and description. The importer matcher then independently verifies the Spotify primary artist; casual name mentions in promotional descriptions do not qualify.
- YouTube Music's structured `Provided to YouTube by` description can be used as an artist signal only when the expected title and performer appear together in the generated track-credit block.
- Candidate ranking uses title similarity, primary-artist evidence, alternate-version markers, and Spotify track duration. Duration is a ranking hint, not a hard rejection rule, because official videos may have extra intros/outros.
- Soundtrack attribution suffixes such as `- From "Cidro Asmoro"` stay in the imported Spotify display title but are ignored for core-title comparison when the YouTube upload omits that attribution.
- Karaoke, cover, AI-generated, compilation, album/playlist uploads, and other candidates rejected by the shared MusikKu policy are not imported.
- Imported display titles and singer credits are taken exactly from Spotify metadata. The selected YouTube video ID, channel ID, thumbnail, and playback source are retained. This keeps the playlist's visible singer credit aligned with Spotify even when the audio is hosted by a label channel.
- Tracks are assembled in Spotify order. Repeated entries remain repeated. An unmatched song is skipped rather than silently replaced with another singer or version.
- After import, MusikKu shows the exact Spotify title and artist credits for every unmatched song, with an option to copy the complete list. If no songs match, it does not create an empty playlist.

## Playlist Jawa checked for this change

The user-provided public embed at `https://open.spotify.com/playlist/53WQhvRzDCJPKBdqOUPGM6` was readable during this audit. The visible embed contained 100 numbered track entries, including `Cundamani — Denny Caknan`, `Dumes — OMWAWES, Guyon Waton`, `Satru — Denny Caknan, Happy Asmara`, `Koyo Jogja Istimewa - From Cidro Asmoro — Ndarboy Genk`, `Mencintai Dengan Ngeyel — E Woro Widowati`, and `CiDRO 3 — Happy Asmara`. These real-world examples motivated parser and matcher regression tests.

The 100 visible embed rows do not prove that the underlying Spotify playlist has exactly 100 tracks. The current public page supplied for this audit visibly ends at row 100 (`Sinarengan — Denny Caknan, Bella Bonita`). The public embed is a preview surface, not a documented paginated export. MusikKu does not call private or undocumented pagination endpoints.

## Large playlist limitation

The parser does not impose a 50- or 100-track truncation in app code. If the public HTML contains 125 or more track rows, all parsed rows are retained. It reads an advertised total count only when it is larger than the returned rows. If the embed returns exactly 100 rows and its metadata also says 100, MusikKu treats that as a possible embed cap—not proof that the actual playlist contains only 100 tracks. The preview explicitly says that the real count is unknown.

If Spotify only sends the first portion of a large playlist in its public embed, link-only API-free import cannot obtain the missing rows. The official playlist-items paging interface requires Spotify Web API authorization and is intentionally not used in this no-API build. MusikKu automatically imports every track row that Spotify actually supplies and clearly reports when the public embed appears partial. There is no supplementary text field and users are never asked to enter track names one by one. A complete import above the public embed limit requires Spotify-supported authorized access; it cannot be guaranteed from a public link alone.

## Other limits

- Playlist must be publicly accessible and embeddable. Private, restricted, removed, or region-limited playlists may fail.
- Spotify can change public embed HTML. If its data format changes, import fails clearly instead of creating an empty playlist.
- A YouTube result that cannot be matched to the Spotify primary artist and song title is reported as unmatched. This is intentional: missing a song is safer than importing another singer.
- Audio is played through MusikKu's existing YouTube Music playback path, not Spotify.

## Album artwork

- `artistName` is retained separately from YouTube channel title, so imported Spotify tracks and listening-stat tiles use their primary artist for album-cover lookup while preserving all Spotify visible credits.
- `UnifiedArtwork` and player artwork share MusicBrainz/Cover Art Archive lookup. When a genuine album title is available, it is searched first; otherwise the exact recording is matched by title and artist. Only approved front covers with a strong title and artist match are accepted; among the valid front images, the resolver chooses the best available 1200px thumbnail, then 500px or 250px.
- If no verified catalog cover exists, the fallback is the selected track’s own best thumbnail supplied by YouTube (the search adapter now prefers `maxres`, then `high`, `standard`, `medium`, and `default`). It never uses an unrelated image-search result. Auto-generated `Provided to YouTube by` descriptions are parsed conservatively for an exact title-linked artist credit and explicit `Album:` line, improving album matching for label-uploaded tracks.

## Code

- `lib/services/spotify_playlist_import_service.dart` — public embed fetch, parsing, and partial-list metadata.
- `lib/services/spotify_youtube_track_matcher.dart` — strict title, primary-artist, generated-credit, duration, and canonical display matching.
- `lib/services/youtube_music_policy.dart` — broader search-query candidate admission, with final performer verification kept in the importer matcher.
- `lib/pages/custom_playlists_page.dart` — paste-link, preview, progress, search retries, and unmatched report.
- `test/spotify_playlist_import_test.dart` — parser/matcher regression tests for the supplied playlist's collaboration and title patterns, 100+ tracks, wrong singers, generated credits, album metadata, alternate versions, and canonical display metadata.

## Verification

Run on a machine with the Flutter SDK:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Build 49 changes

- Public track-count metadata is merged by maximum across scripts and recognized playlist fields, instead of accepting the first count encountered.
- At the 100-row embed boundary with unknown total, the UI displays `≥100` and explicitly says that the embed does not provide the true playlist total. The manual supplement field is relative to the count actually parsed.
- Artwork lookup cache is versioned to v5. The shared resolver continues to require approved front images and strong artist/title match, preferring 1200px artwork and rendering it with high-quality filtering in the player. Generated YouTube Music descriptions now support more artist separators and strip `From ...` soundtrack suffixes for exact-title credit parsing.

- Build 49 also tests that a 100-row preview count in one embed script does not mask a larger playlist total advertised by another script.
- Build 51 removes the supplementary manual song-entry field and processes all tracks available from the pasted Spotify link automatically.
- The release/recording candidate search inspects a broader set of exact artist/title results before falling back to the selected YouTube video thumbnail.


## Build 54 — playlist membership and official-source audit

- Playlist membership now compares normalized song title plus explicit primary-artist metadata when YouTube video IDs differ.
- Structured YouTube Music credits are reparsed for older saved entries. Label channel names are not treated as performer names.
- If both entries contain explicit artist credits and those credits disagree, they are never considered the same track.
- Spotify import matching now requires a high-confidence source tier (artist channel, Topic/VEVO, known label with an official upload marker, or structured distributor credits). A known label name by itself is no longer sufficient.
- Fan, lyrics, tribute, karaoke, cover, re-upload, archive, slowed/nightcore, reaction, and AI channel patterns are rejected.
- Two new playlist-identity regression scenarios and two official-source regression scenarios were added.

## Build 55 — playlist identity and official-source priority

- Playlist checkmarks and add/remove actions now use a shared track identity helper instead of relying only on the YouTube video ID.
- Different video IDs can represent the same playlist track when the normalized title and reliable performer credits agree. Spotify collaborator credits are considered, so a collaboration can still match if YouTube surfaces a secondary credited performer.
- A same-title result from a different singer, an obvious cover/karaoke/AI/alternate upload, or an untrusted re-upload is not treated as the same playlist track.
- For identity fallback, a title mentioning an artist is not sufficient on an arbitrary uploader. The match also needs performer metadata, the artist's own/Topic channel, or the same exact source label stored on the imported item.
- YouTube candidate ranking now prioritizes the artist's own channel and Topic/VEVO above distributor/label fallbacks. A structured distributor credit can be selected when no artist-owned source appears, and a known exact label with an official-title marker is the final fallback.
- The importer keeps searching after it finds a distributor/label fallback, so a later query can still surface the artist's own channel.

Existing imported playlists are not silently rewritten. Re-import the Spotify link after updating the app to create a fresh list using the stricter source ranking; this avoids deleting any songs the user may have manually added.
