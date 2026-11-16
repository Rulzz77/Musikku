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

- Optional case-insensitive artist-name substring.
- Minimum completed play count (1–100).
- Sort by play count, recent playback, or total listening time.

The Library editor currently exposes a practical minimum-play range of 1–20. Rules are saved as JSON in app-private SharedPreferences, included in Backup & Restore schema v4, and re-evaluated against the listening aggregates when the Library loads or the stats revision changes. Schema v1–v3 backups do not contain these rules, so importing one leaves the rules already on the device unchanged. Deleting a rule removes only that rule; it does not remove any track or playlist.

## Data and compatibility

The source of truth is `ListeningStats`, which already records aggregate plays, listening milliseconds, and the last playback timestamp in monthly files. Smart Playlists reads the all-time aggregate and runs its sort/filter locally; it does not send listening history to a server.

The listening-stat `TrackEntry` format now also preserves optional playback metadata needed to reconstruct playable tracks, including local content URIs and paths, duration text, source quality, and video flags. Every added field has a default, so monthly JSON written by older versions remains readable. New metadata is populated as tracks are listened to on the updated app; an older entry that never stored a local URI cannot be retroactively given one.

## Current scope

Artist filtering, minimum plays, and the three sort modes are supported now. Genre, release year, duration ranges, and complex AND/OR rule groups are not exposed in this first iteration because the current aggregate format does not consistently retain those fields for every source. Those can be added separately after the source metadata is normalized.
