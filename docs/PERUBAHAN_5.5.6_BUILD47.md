# MusikKu 5.5.6+47 — Spotify cap warning and album artwork

- A 100-row public Spotify embed is now treated as a lower bound/possible truncation, not proof that the real playlist contains exactly 100 tracks. If an advertised count equals 100 rows at the boundary, the UI shows the true count as unknown.
- The Spotify importer keeps every row actually present in the embed and can append supplementary user-pasted rows (`Title<TAB>Artist` or `Title — Artist`), preserving order and duplicates. This does not bypass Spotify embed restrictions or retrieve hidden pages.
- Added a separate `artistName` field to track metadata. Spotify-imported tracks now preserve the primary artist for artwork lookup while keeping the full visible Spotify credit.
- MusicBrainz/Cover Art Archive artwork lookup is now used by `UnifiedArtwork` on all shared track tiles, not only the player. It requires a strong title/artist match and an approved front cover, prefers 1200px artwork, caches results, and falls back to the current YouTube thumbnail only when no verified cover is available.
- Channel-page song/video cards now use the shared artwork widget as well.
- Bumped build to 5.5.6+47.

Flutter Analyze/Test and APK build must still be run on a machine with the Flutter SDK.
