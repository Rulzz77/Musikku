# MusikKu

MusikKu is a personal Android music-player fork based on the open-source BitChord project.

## Upstream and license

- Upstream: https://github.com/kushagrasinghx/BitChord
- License: GNU General Public License v3.0 (GPL-3.0)
- The original `LICENSE` file and upstream source notices are kept in this repository.
- This fork must continue to comply with GPL-3.0 when redistributed. Provide the corresponding source and preserve required notices.

## What this setup changes

- Android app display name: MusikKu
- Production application ID: `id.musikku.player`
- Development application ID: `id.musikku.dev`
- Gradle root project name: `MusikKu`
- Initial fork version: `0.1.0` (versionCode `1`)
- Launcher icon: simple MusikKu mark

The upstream Kotlin package namespace is intentionally retained to minimize risky mass refactoring. It is an internal code namespace, distinct from the installed Android application ID.

## Open in Android Studio

1. Install Android Studio, JDK 17 or the JDK required by the current upstream Gradle/AGP combination, Android SDK 37, Android NDK, and CMake 3.22.1.
2. Open this folder (`MusikKu`) in Android Studio.
3. Let Gradle sync and install any missing SDK components.
4. Connect an Android device with USB debugging enabled.
5. Run the `app` configuration, or build from PowerShell:

```powershell
.\gradlew.bat :app:assembleProdDebug -Pbitchord.bundleWear=false
```

The APK is normally produced under `app\build\outputs\apk\prod\debug\`.

For a separate development install:

```powershell
.\gradlew.bat :app:assembleDevDebug -Pbitchord.bundleWear=false
```

## Before making a public release

- Review all upstream service dependencies and configure your own release/update repository.
- Some upstream-hosted services (including addon authentication and the Listen Together default server) are controlled by the original project and may not be available or appropriate for a fork.
- Re-check the original project's current README, docs, license, privacy behavior, and third-party service terms.
- Do not claim affiliation with YouTube, Google, BitChord, or music rights holders.
- Ensure every music source and artwork source is used with the necessary permissions.

## Branding follow-up

This setup performs a conservative first-pass rebrand. It does not redesign all screens, remove every upstream product reference, or change the internal Kotlin package namespace. Search the project for `BitChord`, `bitchord`, and `kushagrasinghx` before a public release and review each remaining match rather than blindly replacing code identifiers.