# Spotify import album-context fallback — 16 November 2026

## What changed

When the standard title/artist lookup, secondary credited-artist search, and optional language lookup have not produced a confident match, Android Spotify import now tries one bounded album-qualified query:

- `<primary artist> <track title> <Spotify album>`

The title/artist query remains the first choice. The album-qualified fallback tries the same TRACK filter first, then widens to ALL and VIDEO only while the track is still unmatched. Album text is whitespace-normalized, limited to 100 characters, and the final query is bounded to 250 characters.

## Matching safety

Album metadata improves discovery only. It does not add score, lower confidence thresholds, or override the existing title, credited-performer, duration, and recording/version checks. Every result is merged with the prior candidates and evaluated by the same strict `LinerSpotifyMatcher`.

A confident standard match skips the album request, so ordinary successful imports do not pay an extra network round trip. The request also flows through the per-playlist query cache, allowing duplicate album-qualified searches to share the same request.

## Regression coverage

`SpotifyImporterAlbumFallbackTest` covers:

- discovering a track only after adding its Spotify album to the search query;
- skipping the album request when the standard query already has a confident result;
- rejecting a remix returned by the album-qualified search when Spotify requests the unmodified recording.
