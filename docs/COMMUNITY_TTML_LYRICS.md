# Community TTML lyrics

MusikKu can use a listener-provided TTML file as a local lyrics override for
the track that is currently playing.

## Import

1. Open the expanded player and open **Lyrics**.
2. Open the lyrics source drawer.
3. Choose **Import community TTML** and select a `.ttml` file.
4. MusikKu validates the document, saves it in app-private storage, and reloads
   the current track's lyrics.

The imported file is keyed to the current track ID. When that track is played
again, the imported TTML takes priority over embedded lyrics and online lyric
providers. The existing renderer handles the timing and vocal metadata.

## Remove

Open the lyrics source drawer and choose **Remove imported TTML**. MusikKu
removes only that track's local TTML override; normal embedded and online
provider lookup resumes.

## File handling

- Only valid TTML documents containing lyric text are accepted.
- The maximum imported file size is 1 MiB.
- Files are copied into the app's private files directory; no broad storage
  permission is requested and the original document is not modified.
- The filename is derived from a SHA-256 hash of the track ID.
- Imported files remain local to the device and are not uploaded or synced.

Spicy Lyrics' online service is not queried by MusikKu. Its current desktop
extension lookup depends on a Spotify desktop session, while this import flow
works with TTML files selected by the listener. Compatibility depends on the
document using TTML elements and timing metadata supported by MusikKu's parser.
