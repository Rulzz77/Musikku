# MusikKu 5.5.6+43

## Perbaikan

- Fixed analyzer lint `unnecessary_underscores` in `custom_playlists_page.dart` by using Dart wildcard callback parameters.
- Spotify public embed parser no longer relies on an app-side 50/100 item cap; every track row present in the parsed HTML payload is retained, including payloads containing more than 100 rows.
- Reads the advertised playlist total count when the public embed exposes it and reports the known number of rows that are not present in the embed.
- Import preview and summary now distinguish tracks read from the public embed from tracks successfully matched on YouTube Music.
- Added a regression test using a 125-row public embed payload with an advertised total of 180 tracks.

## Known limitation

This build still does not implement Spotify pagination. Spotify's public embed does not provide a documented, reliable public next-page cursor. Retrieving later pages through Spotify's playlist-tracks endpoint requires the Spotify Web API access route, which is outside the no-API/no-login scope of this feature. Build 43 therefore warns when the available embed data appears partial rather than claiming a complete import.
