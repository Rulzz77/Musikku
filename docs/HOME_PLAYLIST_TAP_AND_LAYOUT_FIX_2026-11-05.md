# MusikKu – Home playlist navigation and card sizing fix (5 November 2026)

## Changes

- Tapping a user-created playlist card on Beranda now opens `CustomPlaylistsPage` directly at that playlist's detail/song list.
- The playlist is not started automatically when the card is tapped.
- Users can explicitly start playback by selecting a song or choosing **Putar semua** on the playlist detail screen.
- Smart playlist cards and entries in the smart-playlist picker open the song list first. The song-list sheet has an explicit **Putar semua** action.
- Removed the obsolete `YoutubeHub.onPlayCustomPlaylist` callback to prevent accidental direct playback from home cards.
- Increased the custom/smart playlist carousel height from 118dp to 148dp and made card width responsive to device width, improving the artwork/text/action balance.
- The empty-playlist card continues to open the playlist library so users can create their first playlist.

## Files changed

- `lib/pages/home_page/playlists.dart`
- `lib/pages/home_page/ui_layout.dart`
- `lib/pages/custom_playlists_page.dart`
- `lib/widgets/youtube_hub.dart`
- `lib/widgets/youtube_hub/home_views.dart`
- `lib/widgets/youtube_hub/library_views.dart`

## Verification limits

- Static checks confirmed the new callback declarations and call sites match, the obsolete direct-play callback is no longer used by `YoutubeHub`, and the home cards route to the playlist detail/list flow.
- Flutter Analyzer, widget tests, and APK build were not run in this environment because the Flutter/Dart SDK is not available here. Run `flutter analyze`, `flutter test --reporter expanded`, and `flutter build apk --debug` in the local project before release.
