# MusikKu 5.5.6+52 — Official Source Matching

- Spotify import searches the primary artist and title, then targeted official-audio and official-music-video variants.
- Import no longer stops at the first plausible candidate. It pools candidates from later queries until a high-confidence official source is found or focused variants are exhausted.
- Matcher ranks YouTube Topic, VEVO, structured `Provided to YouTube by` distributor credits, the artist-named channel, and recognized music-label channels above ordinary mirrors when title and primary artist already match.
- Duration and title similarity remain tie-breakers within the same source-authority tier.
- Existing title, primary-artist, duration, alternate-version, karaoke, cover, AI, and album/playlist checks remain in place.
- Added regression tests for artist channels, Topic channels, structured label credits, and safe early-stop behavior.

Note: YouTube search results do not expose a consistent verified/official badge to this parser. Source ranking uses channel names and structured release metadata as evidence; it cannot guarantee that every upload is officially authorized.
