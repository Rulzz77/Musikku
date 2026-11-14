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
- Android artist-page fallback may accept one unique near-exact artist page when exactly one character in one long token differs and all other name tokens match. The track matcher applies the same spelling guard only with an exact title/version and a known runtime within 30 seconds; ambiguous, short, multi-token, or durationless variants stay unmatched.
- Prefer audio catalogue results. Never substitute the first search hit when no candidate passes identity checks.
- Keep temporary search failures retryable; only a completed search with no safe match is labelled missing.
- Preserve structured artist names end-to-end across public playlist links, Spotify Library, Liked Songs, and the Web extension. Names containing commas (for example, “Earth, Wind & Fire”) remain one artist.
- Search the raw title with the full credit and each individual credited artist (bounded to the first three query variants); use every credited performer and every matching structured YouTube artist browse id for artist-page fallback discovery on Android and Web.
- Web import also opens up to three YouTube Music artist pages when global Search returns no safe match; artist cards must identify a structured Spotify credit or a catalogue alias sharing that complete credit, and every returned song still passes the strict track matcher.
- Recognize upload titles where the credited performers precede the song (for example, “Lead feat. Guest - Song”) without weakening the final artist check.
- Treat `feat`, `ft`, `featuring`, or `with` as a credit suffix only when the following name matches a known artist credit. Words such as “With” inside real song titles must remain part of the title.

## Saving the destination playlist

- De-duplicate by YouTube video ID, not by title alone.
- Web import remains unavailable until all source pages have loaded and matching has stopped.
- Unmatched public-link rows can be retried before saving the already matched rows.
- Retrying adds only new video IDs to the in-memory result.

## Regression coverage

The Kotlin and TypeScript tests cover premature empty pages, inconsistent page totals, structured artist credits, comma-containing artist names, composite performer aliases with strict runtime checks, featured-artist title prefixes, real titles containing “with”, strict title/artist identity, DJ/genre separation, language versions, “Official Live Music” packaging versus real live versions, temporary search failures, and duplicate-safe import behaviour.
