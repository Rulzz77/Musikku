# MusikKu fork information

- Upstream repository: https://github.com/kushagrasinghx/BitChord
- Upstream branch cloned: `main` (shallow clone at the time this script runs)
- Upstream license: GPL-3.0; original `LICENSE` is retained.
- App label: MusikKu
- Production application ID: `id.musikku.player`
- Development application ID: `id.musikku.dev`
- Internal Android namespace: `com.music.bitchord` (retained intentionally for the first low-risk fork)
- Fork version: `0.1.0`, versionCode `1`

## Important upstream dependencies

The upstream app README advertises YouTube Music search/playback, configurable module sources, local files, background media session, offline downloads, lyrics providers, and additional services. This fork retains those code paths as far as the upstream source allows; this branding script does not independently test or guarantee the availability of any source or hosted service.

The upstream `app/build.gradle.kts` points addon authentication at a BitChord-operated service and notes that a fork cannot gain addon access merely by pointing to that server. The Listen Together default is also an upstream-hosted URL. Review these before enabling or shipping related features. The upstream update checker/release configuration also needs to be reviewed and moved to the fork owner's release repository before distributing updates.

## Build

The upstream source currently specifies Gradle wrapper 8.11.1, Kotlin plugins 2.3.20, Android Gradle Plugin 8.10.1, compileSdk 37, minSdk 26, targetSdk 36, and CMake 3.22.1. Keep these in sync with the checked-out source rather than assuming they will never change.

Suggested first phone build:

```powershell
.\gradlew.bat :app:assembleProdDebug -Pbitchord.bundleWear=false
```

## GPL reminder

Keep upstream copyright and license notices. If you distribute this derivative, comply with GPL-3.0, including providing the Corresponding Source under the same license and required notices. Review `LICENSE` in the project root.