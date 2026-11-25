# Player vertical balance adjustment — 2026-11-03

- Reduced the artwork stage from a full remaining-height `Expanded` region to a responsive, bounded stage (50% of available body height on regular screens; 42% on compact screens, capped relative to the cover width).
- This moves the album artwork closer to the header and reduces the empty space above it.
- Track metadata, seek bar, transport controls, and collapsed volume affordance now sit higher as a group.
- Added a flexible spacer immediately before the Playlist / Lyrics / Timer / Queue dock, preserving the dock's bottom-safe-area position while creating breathing room above it.
- The existing tap-to-expand volume slider, Midnight Slate colors, and all playback callbacks remain unchanged.
- No playback service, queue, shuffle, repeat, or seek logic was modified.

Flutter SDK was not available in the editing environment; run `flutter analyze` and `flutter build apk --release` in the project environment to validate compilation.
