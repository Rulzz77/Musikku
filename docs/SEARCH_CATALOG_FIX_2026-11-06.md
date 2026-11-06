# MusikKu — Search catalogue follow-up fix (2026-11-06)

## Root causes addressed

- Query filtering previously matched the searched artist only against the upload channel. Official releases uploaded by a label/distributor were discarded when the artist name appeared in the title instead.
- Artist-page filtering repeated the same restriction and also required a music-profile signal from the upload channel, suppressing label uploads even after the search policy accepted them.
- Empty search results were persisted in the device cache and treated as valid for a long period.
- Cached search results were stored after filtering, so a later policy correction could not restore candidates that had already been removed.
- Cached lists were discarded wholesale if any one result lacked a channel ID, even though the track itself was still playable.
- Search considered only the first page, which could leave too few songs after filtering.

## Changes

- Artist-scoped search now accepts a normal-length single when the artist is credited in its title or description, even if the uploader is a label channel. Explicit cover, karaoke, AI, album/compilation, short-form and non-music exclusions remain.
- Artist profile filtering no longer requires a label-uploaded track to come from a channel whose name looks like a music channel when the title clearly credits the searched artist.
- Search cache key advanced to V4, is scoped to both the original and normalized query, and stores raw candidates rather than already-filtered results. Empty searches and empty channel lookups are not persisted; channel-search cache version also advanced.
- Search inspects one additional YouTube result page when fewer than twelve acceptable songs are found, and no longer truncates explicit search results to six or ten just because Data Saver is enabled.
- Cached songs are retained if channelId metadata is absent; the channel avatar may be unavailable, but the playable track is not dropped.
- App version advanced to 5.5.6+36.

## Verification

Added regression tests for label-channel uploads credited to Fiersa Besari, artist-name suffixes in track titles, and cache results without channelId. Flutter analyze/test/build must still be run in an environment with the Flutter SDK.
