# Smart Playlists

Smart Playlists are dynamic views over this device's existing listening statistics. They are not copies of songs and do not modify ordinary playlists, downloads, Spotify imports, or playlist folders.

## Built-in lists

- **Most played** sorts tracks by completed play count, then listening time.
- **Recently played** sorts by the timestamp of the last playback sample.
- **Most listened** sorts by accumulated listening milliseconds.
- **Forgotten tracks** includes tracks whose last recorded playback was at least 30 days ago, oldest first.

Each generated list is capped at 100 tracks. Lists without matching tracks are omitted until they have results.

## Custom rules

A listener can create up to 20 named Smart Playlists. Each rule supports:

- Optional case-insensitive artist-name and genre substrings.
- Minimum completed play count (1–100; the Library slider exposes 1–20).
- Optional release-year range, minimum/maximum duration in minutes, and a last-played-within-days filter.
- Combine optional criteria with **ALL (AND)** or **ANY (OR)**. Minimum plays remains a required baseline in either mode.
- Sort by play count, recent playback, or total listening time.

Genre matches use the on-device ArtistFacts cache (Last.fm artist tags) and depend on genre lookup being enabled and an artist tag being available. Release year comes from YouTube Music release metadata where supplied. Duration comes from the track runtime. A track missing metadata required by an active criterion does not match that criterion; unknown values are never guessed. Rules are saved in app-private SharedPreferences and included in Backup & Restore schema v5. Existing schema v4 rules import with their new criteria empty, while schema v1–v3 backups do not contain Smart Playlist rules and leave the rules on the device unchanged. Deleting a rule removes only that rule; it does not remove any track or playlist.

## Data and compatibility

The source of truth is `ListeningStats`, which already records aggregate plays, listening milliseconds, and the last playback timestamp in monthly files. Smart Playlists reads the all-time aggregate and runs its sort/filter locally; it does not send listening history to a server.

The listening-stat `TrackEntry` format now also preserves optional playback metadata needed to reconstruct playable tracks, including local content URIs and paths, duration text, source quality, download format, track number, podcast-episode state, and video flags. Every added field has a default, so monthly JSON written by older versions remains readable. New metadata is populated as tracks are listened to on the updated app; an older entry that never stored a local URI cannot be retroactively given one.

## Current scope

Artist, cached genre, release-year, duration, and last-played filters are supported for metadata available to the listening aggregate. Year and duration are optional because remote and local sources do not all supply the same tags; a missing value simply fails an active filter. AND/OR applies to optional criteria, while minimum completed plays is always enforced.
