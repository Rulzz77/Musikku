# Spotify import hardening — 13 November 2026

This note records the safety rules shared by the Android and Web Spotify import paths.

## Loading the Spotify source list

- Advance Spotify pages by the raw entry count, not the count of successfully parsed rows.
- A zero-sized page before the advertised total is reached is an incomplete read, not success.
- Reject invalid page metadata (negative counts, non-advancing pages, or a page count larger than the advertised total).
- The public-link embed exposes up to 100 entries. When the raw page reaches that boundary, the Android importer must fetch the remaining pages. Missing continuation credentials or a failed continuation is reported as an import error; the embed's first page is not accepted as the whole playlist.

## Matching Spotify rows to YouTube Music

- Use the cleaned title, Spotify's structured artist credits, runtime, album, and recording/version markers. The primary artist remains preferred. When it differs, an exact full-name match to another structured Spotify performer is accepted only with an exact title/version match and runtime within three seconds. A flattened alias combining meaningful tokens from at least two distinct Spotify credits uses the same guard. Do not split display strings to invent artist identities.
- Keep DJ styles and language versions distinct, but do not interpret generic genre/packaging words such as “House Music” as an alternate recording unless the label identifies a DJ/edit take.
- Treat the exact “Official Live Music” phrase as regional upload/channel packaging; actual “Live at …” or other explicit live-performance titles remain a separate take.
- If global Search misses an audio match, search up to three exact Spotify artist names for their artist pages, then pass the artist Top Songs through the same strict matcher. Do not depend on a global result containing an artist card or linked browse id.
- Android artist-page fallback may accept one unique near-exact artist page when exactly one character in one long token differs and all other name tokens match. The track matcher applies the same spelling guard only with an exact title/version and a known runtime within 8 seconds; ambiguous, short-name, multiple-token, or durationless variants stay unmatched. Exact secondary Spotify credits and composite credits keep their stricter 3-second guard.
- Android title matching additionally ignores diacritic-only differences. For strict Spotify imports, it may accept one one-character typo in one title token only when the primary artist is exact, the runtime is within 3 seconds, and the version markers still agree. Short tokens and multiple edits do not qualify.
- Android import checks up to ten bounded raw/normalized title, artist, and album query variants. Once a high-confidence result exists, it still samples the first page of remaining query variants rather than skipping them altogether.
- If global Search returns an album card instead of a song row, Android import can open up to five matching-query album pages and run their songs through the same strict matcher. It then falls back to up to five artist pages when no high-confidence audio candidate is present.
- Spotify's Android artist-page fallback reads the complete linked Top Songs playlist and also checks up to eight linked album releases from the artist's Albums & Singles shelves. A failed continuation or page-cap truncation is an incomplete lookup, not proof that a song is absent; the normal display-oriented artist page may still show its first few songs.
- Android caches completed album pages while importing a playlist and serializes concurrent reads per album, so different tracks from one release do not repeatedly download the same catalogue.
- Prefer audio catalogue results. Never substitute the first search hit when no candidate passes identity checks.
- A match accepted only by the exact-runtime composer/uploader override is a last resort, not a reason to stop searching. Android continues bounded alternate query spellings and album/artist-page fallback until a high-confidence candidate is available.
- Keep temporary search failures retryable; only a completed search with no safe match is labelled missing.
- Preserve structured artist names end-to-end across public playlist links, Spotify Library, Liked Songs, and the Web extension. Names containing commas (for example, “Earth, Wind & Fire”) remain one artist.
- Search the raw title with the full credit and each individual credited artist (bounded to the first three individual-credit variants); Android additionally searches raw title/lead artist/album combinations, while both platforms use structured YouTube artist credits for artist-page fallback discovery.
- Web import also opens up to three YouTube Music artist pages when global Search returns no safe match; artist cards must identify a structured Spotify credit or a catalogue alias sharing that complete credit, and every returned song still passes the strict track matcher.
- Recognize upload titles where the credited performers precede the song (for example, “Lead feat. Guest - Song”) without weakening the final artist check.
- Treat `feat`, `ft`, `featuring`, or `with` as a credit suffix only when the following name matches a known artist credit. Words such as “With” inside real song titles must remain part of the title.

## Saving the destination playlist

- De-duplicate by YouTube video ID, not by title alone.
- Web import remains unavailable until all source pages have loaded and matching has stopped.
- Unmatched public-link rows can be retried before saving the already matched rows.
- Retrying adds only new video IDs to the in-memory result.

## Regression coverage

The Kotlin and TypeScript tests cover premature empty pages, inconsistent page totals, structured artist credits, comma-containing artist names, composite performer aliases with strict runtime checks, one-character regional artist spelling variants with a guarded eight-second Android runtime ceiling, joined featured-artist bylines, duration-only fallback search continuation, raw album-qualified query variants, album-card fallback classification, guarded one-character title spelling and diacritic variants, featured-artist title prefixes, real titles containing “with”, strict title/artist identity, DJ/genre separation, language versions, “Official Live Music” packaging versus real live versions, temporary search failures, and duplicate-safe import behaviour.
