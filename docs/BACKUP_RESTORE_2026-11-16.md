# MusikKu backup and restore — 16 November 2026

## Backup schema

The current JSON backup schema is version 5. Backups from schema versions 1
through 4 remain readable; fields introduced in later versions use safe
defaults when they are absent from an older file.

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

Both restore choices replace settings and listening history, matching the previous restore behavior. The current playback queue remains device-local and is not included in this portable backup. The preview warns about settings/history replacement before the write.

Version 1 backups remain readable. Because they predate playlist sections, importing one leaves the current playlist collections untouched rather than interpreting missing fields as empty data.

## Intentionally excluded

- YouTube, Spotify, Discord, scrobbling, WebDAV, SMB and other account credentials or API secrets. Sign in again after moving to another device.
- Downloaded audio files, the download index and device-specific download collection records. Audio files remain where they were saved on the original device and can be copied separately.
- Audio/artwork caches, permission grants and the selected local music folder.
- Playback recovery state and the temporary Listen Together party queue stash remain device-local. The current live queue also has Smart Queue context that is not yet represented by this portable backup format.
- YouTube Music account-owned playlists and account Liked Music; those belong to the signed-in account and are loaded from the service.
- Spotify per-track manual replacement decisions are not yet persistent data: the current positive match cache is process-local. Persisting those decisions is tracked separately from this backup work.

Device playlists keep content:// and file:// references so they can restore on the same device. Those references are not portable file copies; after restoring on another phone, some local tracks may need to be relinked or re-added. Playlist cover URLs are preserved, but referenced image files are not embedded.

## Android device backup versus in-app backup

Android's cloud backup and device-to-device transfer rules exclude the full
`bitchord_settings.xml` SharedPreferences file and the `app_webview/`
Chromium profile. Android backup rules cannot exclude individual keys in a
SharedPreferences file, and older app versions stored provider credentials
in that same file. The WebView profile holds persistent Google, Spotify and
other website cookies/session data, so it must not be copied to another device.
The exclusions also mean Android will not automatically carry ordinary
settings and search history to a replacement phone.

Before reinstalling or moving to another device, use **Settings → Backup &
Restore** in MusikKu, save the exported JSON somewhere safe, install MusikKu
on the new device, then restore the file. The in-app export keeps supported
settings, search history, listening statistics and playlists while excluding
account credentials, API secrets, caches and device-local download records.
Sign in to third-party services again on the new device.

The app migrates older Last.fm, ListenBrainz, Spotify Canvas, and lyric-provider
credentials from the legacy settings file into Keystore-backed storage at
startup. Listen Together and addon-verification sessions are likewise migrated
from their legacy preferences into encrypted storage; those credentials are
not portable and are not included in either Android or in-app backups.

## Safety and compatibility

- Import validates the app marker, schema version, file size, setting value types, playback speed and repeat mode ranges, playlist identities, track identities and listening month keys before writing.
- Exported settings continue to use AppSettings.exportPrefs(), which excludes credentials and device-local preferences.
- Playlist store writes commit before their restored state is published.
- The current codec has unit coverage for legacy v1 compatibility, playlist sections, remote playlist mappings and typed preferences.

Run the Android unit tests and build from the repository root:

```powershell
.\gradlew.bat :shared:jvmTest testDevDebugUnitTest assembleDevDebug
```
