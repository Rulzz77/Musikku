# MusikKu 5.5.6+44

## Spotify playlist import

- Parse comma-separated Spotify embed artist subtitles into ordered primary and collaborator credits. For example, `OMWAWES, Guyon Waton` becomes `OMWAWES` as the primary artist and `Guyon Waton` as a collaborator.
- Tighten YouTube candidate matching: the full Spotify title must match and the primary Spotify artist must be present in the YouTube title/channel or a direct structured performer credit. A casual mention in description text, tags, or promotional copy no longer qualifies.
- Preserve meaningful parenthetical title text such as `From Cidro Asmoro` during title comparison.
- Retry low-confidence/unmatched songs with `primary artist + title`, then with the primary artist. Each candidate must still pass the same strict matcher and the shared single-track, no-cover, no-karaoke, no-AI policy.
- Store the Spotify title and all Spotify artist credits as the imported playlist display metadata, while preserving the selected YouTube video ID, channel ID, thumbnail, and playback source.
- Show a detailed list of unmatched Spotify songs after import; the user can copy the complete title/artist list. If no tracks match, show the unmatched list and do not create an empty playlist.
- Keep duplicate tracks and original Spotify ordering.

## User-provided Playlist Jawa check

The public embed page for the supplied Playlist Jawa link was readable during this audit and exposed 100 numbered track entries. The visible data includes collaborations such as `Dumes` (OMWAWES, Guyon Waton) and `Satru` (Denny Caknan, Happy Asmara), as well as title text with parenthetical/source subtitles such as `Koyo Jogja Istimewa - From "Cidro Asmoro"`. These cases motivated the parser and matching regression tests.

The embed page showing 100 rows does not prove that the underlying Spotify playlist contains only 100 tracks. Build 44 continues to show a partial-list warning whenever Spotify's public embed reports/indicates omitted rows. It does not use private or undocumented playlist pagination.

## Verification limitation

The source was inspected and ZIP integrity/version synchronization can be checked locally. Flutter SDK is not installed in this execution environment, so `flutter analyze`, `flutter test`, and release APK build must still be run on the user's machine.
