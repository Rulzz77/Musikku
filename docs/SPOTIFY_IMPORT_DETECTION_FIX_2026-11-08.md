# Spotify import detection fix — 2026-11-08

## Root causes addressed

- Spotify import previously reused `YoutubeMusicPolicy.isMusicCandidate`, which rejects explicit covers before the Spotify matcher can evaluate them.
- The matcher required an authority rank of at least 3. A real label upload such as `Dian Anic - Kecewa (Official Music Video)` could have exact artist/title metadata but still be rejected when the label was not in the matcher's known-label list and the description did not use YouTube's `Provided to YouTube` template.
- `Official Live Music` releases such as `Rena Movies ft Ageng Music - Keloas` were penalized as an alternate `live` version and could fall below the combined score threshold.

## Behavior changes

- Added `YoutubeMusicPolicy.isSpotifyImportCandidate`, used only by Spotify import search. The ordinary MusikKu catalogue remains strict and continues excluding covers.
- Explicitly attributed covers may enter Spotify import candidate results. They are a fallback tier below artist-owned, Topic/VEVO, distributor-credit, and known-label matches.
- Cover fallback requires a strong title match plus either a duration match within 90 seconds or at least 1,000 views. Karaoke, AI, fan-made/unofficial, nightcore, slowed, sped-up, bootleg, tribute, Shorts, live streams, non-music, collections, and very short clips remain blocked.
- Added direct description credit parsing for labels using `Artist: ...`, `Singer: ...`, or equivalent fields, even when the description does not say `Provided to YouTube`.
- Added Indonesian label/channel recognition for Musik Proaktif, Global Musik Era Digital, Pelita Utama, Henny Adella, and Milady Record.
- `Official Live Music` is treated as a valid official upload marker. Plain `live` is no longer penalized like a remix or instrumental alternate.
- Added unmatched-candidate diagnostics to help identify future cases where YouTube search returns candidates but the matcher rejects them.
- Bumped Spotify search cache namespace so previous candidate filters do not hide cover results.

## Regression tests added

- Dian Anic — Kecewa official Musik Proaktif upload.
- Dian Anic — Kecewa Fanny Sabila cover fallback.
- Original Kecewa is preferred over a more popular cover.
- Keloas official live music upload from Global Musik Era Digital.
- Keloas cover fallback when the upload performer differs from Spotify metadata.
- Karaoke and AI covers remain excluded.

The Flutter test suite and analyzer still need to be run in a local Flutter SDK environment.

## Follow-up fix for the 20-track regional playlist report

- Fixed a title-normalization bug that removed all text after `feat.` even when the featured-artist credit appeared **before** the song title in a YouTube title (for example, `Northsle feat. Agiff - Bubrah`). Spotify title normalization and YouTube candidate normalization now use separate paths; candidate normalization preserves the full title and treats performer names as extra tokens.
- Applied the same candidate-aware tokenization to title matching, similarity scoring, metadata shortlisting, and structured distributor-description matching.
- Added a penalty for `Live Concert` / `Live Performance` / `Concert Version` when the Spotify release is a studio version, without penalizing regional `Official Live Music` releases.
- Added regression cases for the full 20-track Javanese playlist sample, featured artists before the title, and multi-artist credits before the title.
- Bumped the search cache namespace to V12 so the expanded title normalization does not reuse older cached candidate pools.

The 20-track test uses synthetic official-channel result records to exercise all names and title patterns. It does not prove that a live YouTube search returned all 20 videos; that still needs to be tested on the user's device with the per-query diagnostics from `SPOTIFY SEARCH POOL` and `SPOTIFY IMPORT MATCH`.
- Added compact artist-name matching for official channel/title spellings such as `GUYONWATON` vs `Guyon Waton` and `NDX AKA` vs `NDX A.K.A.`. This compact comparison only applies to performer names of at least six characters to avoid short-name false positives.
- Added regression coverage for NDX A.K.A. punctuation variants and concatenated Guyon Waton channel names.
- Added a lower-confidence, evidence-backed fallback for regional label/third-party uploads that lack an `Official` marker: the complete song title must match closely, a Spotify-credited performer must be present in the candidate, and duration must be within 25 seconds or views must be at least 100,000. This tier remains below verified official/Topic/VEVO/distributor sources; explicitly marked covers remain the last-resort tier.
