# Player volume and dark theme update — 2026-11-03

- Removed the permanent volume slider from the player screen.
- Added compact volume down/up buttons; each tap changes volume by 5%.
- Long-press volume down mutes; long-press volume up sets 100%.
- Volume changes are persisted through the existing HomePage callback.
- Replaced the green-black dark palette with Midnight Slate: navy/graphite surfaces, soft mint primary accent, lavender secondary accent, and warm-sand tertiary accent.
- Kept playback, queue, seek, shuffle, repeat, and native volume service behavior unchanged.

Run `flutter analyze` and `flutter build apk --release` in the Flutter environment to complete validation.
