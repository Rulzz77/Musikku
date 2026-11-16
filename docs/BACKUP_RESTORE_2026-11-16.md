# MusikKu backup and restore — 16 November 2026

## Backup schema

The JSON backup schema is version 2. Version 1 exports made by the earlier
BitChord-branded build remain readable; their playlist sections default to
empty.

## Included

- All exportable app preferences, preserving Android primitive types.
- Search history and addon search history, which share the settings preference file.
- Listening statistics and Replay aggregates.
- Device-local Spotify-imported playlists, including titles, order, track metadata and cover URLs.
- The stored YouTube Music video-ID membership mappings used by imported Spotify tracks on remote playlists.
- Device playlists, including the local Liked songs playlist, their order, metadata and cover URLs.

Restore first previews the backup contents. The user then chooses one of two playlist operations:

- **Merge playlists:** existing playlists remain. Matching playlist IDs are combined and duplicate tracks are ignored by video ID (or local file identity for device playlists); new playlists are added.
- **Replace playlists:** the Spotify-imported and device playlist collections are replaced by the backup copies.

Both restore choices replace settings and listening history, matching the previous restore behavior. The preview warns about this before the write.

## Intentionally excluded

- YouTube, Spotify, Discord, scrobbling, WebDAV, SMB and other account credentials or API secrets. Sign in again after moving to another device.
- Downloaded audio files, the download index and device-specific download collection records. Audio files remain where they were saved on the original device and can be copied separately.
- Audio/artwork caches, permission grants and the selected local music folder.
- YouTube Music account-owned playlists and account Liked Music; those belong to the signed-in account and are loaded from the service.
- Spotify per-track manual replacement decisions are not yet persistent data: the current positive match cache is process-local. Persisting those decisions is tracked separately from this backup work.

Device playlists keep content:// and file:// references so they can restore on the same device. Those references are not portable file copies; after restoring on another phone, some local tracks may need to be relinked or re-added. Playlist cover URLs are preserved, but referenced image files are not embedded.

## Safety and compatibility

- Import validates the app marker, schema version, file size, setting value types, playlist identities, track identities and listening month keys before writing.
- Exported settings continue to use AppSettings.exportPrefs(), which excludes credentials and device-local preferences.
- Playlist store writes commit before their restored state is published.
- The v2 codec has unit coverage for v1 compatibility, playlist sections, remote playlist mappings and typed preferences.

Run the Android unit tests and build from the repository root:

```powershell
.\gradlew.bat :shared:jvmTest testDevDebugUnitTest assembleDevDebug
```
