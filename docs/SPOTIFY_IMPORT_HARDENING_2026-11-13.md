# Spotify import hardening — 13 November 2026

This note records the safety rules shared by the Android and Web Spotify import paths.

## Loading the Spotify source list

- Advance Spotify pages by the raw entry count, not the count of successfully parsed rows.
- A zero-sized page before the advertised total is reached is an incomplete read, not success.
- Reject invalid page metadata (negative counts, non-advancing pages, or a page count larger than the advertised total).
- The public-link embed exposes up to 100 entries. When the raw page reaches that boundary, the Android importer must fetch the remaining pages. Missing continuation credentials or a failed continuation is reported as an import error; the embed's first page is not accepted as the whole playlist.

## Matching Spotify rows to YouTube Music

- Use the cleaned title, exact primary Spotify artist credit, runtime, album, and recording/version markers.
- Keep DJ styles and language versions distinct, but do not interpret generic genre/packaging words such as “House Music” as an alternate recording unless the label identifies a DJ/edit take.
- Prefer audio catalogue results. Never substitute the first search hit when no candidate passes identity checks.
- Keep temporary search failures retryable; only a completed search with no safe match is labelled missing.
- Preserve structured artist names so names containing commas (for example, “Earth, Wind & Fire”) are not split into separate people.

## Saving the destination playlist

- De-duplicate by YouTube video ID, not by title alone.
- Web import remains unavailable until all source pages have loaded and matching has stopped.
- Unmatched public-link rows can be retried before saving the already matched rows.
- Retrying adds only new video IDs to the in-memory result.

## Regression coverage

The Kotlin and TypeScript tests cover premature empty pages, inconsistent page totals, strict title/artist identity, DJ/genre separation, language versions, temporary search failures, and duplicate-safe import behaviour.
