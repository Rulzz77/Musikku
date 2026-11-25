# Spotify import lookup diagnostics — 16 November 2026

## What changed

The Android Spotify import review now distinguishes two outcomes:

- **No confident match:** YouTube Music searches completed, but no candidate passed the existing strict identity matcher. The track remains unmatched and can be searched manually or retried.
- **Lookup incomplete:** one or more catalogue requests failed and no confident match was found. These Spotify rows are reported separately in the review message and remain retryable.

A successful empty catalogue response is treated as a completed search with no match, not as a network failure. If one or more requests fail while no confident result exists, the lookup is marked incomplete even when another search returned unrelated candidates.

## Matching safety

This does not relax or change title, artist, duration, album, or recording-version checks. A confident match still wins even if an optional fallback request fails. Only tracks without a confident match are counted as lookup failures.

The original `resolveToSongs` API remains available and delegates to the detailed resolver. The import UI uses the detailed result callback to show the count of rows that could not be checked, while the existing Retry and manual replacement actions remain unchanged.

## Regression coverage

`SpotifyImporterLookupDiagnosticsTest` covers:
- successful empty results remaining ordinary unmatched rows;
- failed searches being surfaced as retryable lookup failures;
- a transient failure not being hidden by an unrelated candidate.

