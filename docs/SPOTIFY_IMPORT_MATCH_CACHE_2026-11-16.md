# Spotify import match cache persistence — 16 November 2026

## Purpose

Keep confirmed Spotify-track to YouTube Music-track decisions across Android process
restarts. This includes both high-confidence automatic matches and deliberate
manual replacements selected in the import review screen.

The strict matcher remains the source of new decisions. A cache miss still runs
the existing candidate searches and identity checks; a failed or unmatched
search is not persisted as a negative result.

## Stored data

- Spotify track ID plus the normalized language key, so language-specific
  matches do not overwrite the default or another language's result.
- The selected YouTube Music video ID and the catalogue metadata needed to
  reuse the resolved Song row (title, artists, artwork, duration, album and
  media/source flags).
- At most 512 confirmed matches, maintained as a least-recently-used cache.

Automatic imports checkpoint after every 16 new matches and flush after the
batch completes or is cancelled. A manual replacement is flushed immediately,
because it is an explicit listener decision.

## Storage and privacy boundaries

Android stores this cache in private SharedPreferences under
bitchord_spotify_match_cache. The shared importer depends only on a small
storage interface; the Android application supplies the SharedPreferences
implementation during startup.

This is device-local optimization data, not account synchronization. It
contains no Spotify/Google login credentials, cookies, API keys or audio files.
It is deliberately excluded from the portable Backup & Restore file: restoring
a cache entry on another device could point at a catalogue item that is not
available there. Playlist contents themselves remain part of the separate
playlist backup feature.

Other JVM hosts that do not install a persistence adapter retain the existing
process-local cache behaviour.

## Regression coverage

SpotifyImportMatchCacheTest covers:

- restoring confirmed matches after constructing a new cache instance;
- keeping language-keyed matches isolated;
- preserving least-recently-used order and capacity after restore;
- checkpointing larger imports in batches and flushing the remaining entries.
