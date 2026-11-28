# MusikKu v0.1.97

## What's changed

- Blend the fullscreen lyrics Canvas into the blurred artwork background with a native TextureView edge fade, removing the visible seam at the Canvas boundary.
- Keep fullscreen lyrics player actions accessible by presenting the More menu above the fullscreen surface.
- Organize the fullscreen More menu into compact popup categories: Playback & Lyrics, Queue Actions, Library & Downloads, and Song Details.
- Keep lyric-selection controls visible while selecting lines, until the selection is cancelled or shared.
- Add the new menu labels to the Android locale resource catalogs.

## Validation

- Android unit tests passed.
- Android development APK built successfully.
- Android TV development APK built successfully.
- Backend Go build, vet, and tests passed.
- Security scan passed.

The final Canvas blend and touch interactions still need confirmation on a physical device.
