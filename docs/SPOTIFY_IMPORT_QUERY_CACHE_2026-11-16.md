# Spotify import query reuse — 16 November 2026

## What changed

A single Spotify playlist import now owns a bounded query-response cache shared by
all four concurrent track-resolution workers. If two Spotify rows produce the same
normalized YouTube Music query and the same search filter (TRACK, ALL, or VIDEO),
they share one request instead of making duplicate InnerTube calls.

The cache is limited to 128 query/filter pairs and follows least-recently-used
eviction. Query keys collapse surrounding and repeated whitespace and ignore case;
the search filter remains part of the key because it changes which media rows are
returned and how those rows are normalized.

## Safety boundaries

- The cache exists only for one `resolveToSongs` batch. It is not persisted across
  imports, accounts, app launches, or language changes.
- TRACK, ALL, and VIDEO results are kept separate.
- Successful empty results can be reused within the same batch.
- Failed requests are not cached, so a retry can recover from a transient error.
- Search scoring, artist/version/runtime checks, ambiguity rejection, and manual
  replacement behavior are unchanged.
- Results are copied before being retained so later callers cannot mutate the
  cached list.

## Regression tests

`SpotifyImportSearchCacheTest` covers normalized keys, distinct filters,
successful empty responses, concurrent request coalescing, retry after failure,
and LRU eviction.
