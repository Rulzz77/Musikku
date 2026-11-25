# MusikKu fork information

- Upstream repository: https://github.com/kushagrasinghx/BitChord
- Upstream branch cloned: `main` (shallow clone at the time this script runs)
- Upstream license: GPL-3.0; original `LICENSE` is retained.
- App label: MusikKu
- Production application ID: `id.musikku.player`
- Development application ID: `id.musikku.dev`
- Internal Android namespace: `com.music.bitchord` (retained intentionally for the first low-risk fork)
- Fork version: `0.1.59`, versionCode `60`

## Important upstream dependencies

The upstream app README advertises YouTube Music search/playback, configurable module sources, local files, background media session, offline downloads, lyrics providers, and additional services. This fork retains those code paths as far as the upstream source allows; this branding script does not independently test or guarantee the availability of any source or hosted service.

Addon authentication uses Android hardware-key attestation. MusikKu intentionally leaves `ADDON_AUTH_SERVER` blank by default: the upstream BitChord service checks the official BitChord package/signing identity, so pointing this fork at it does not grant addon access and would still send the device's attestation certificate chain (plus an optional tester code) to that upstream service. When no server is configured, ordinary addons continue to work; only addons that explicitly require BitChord authentication are unavailable, and no attestation request is sent. Configure `ADDON_AUTH_SERVER` in `local.properties`, the build environment, or the GitHub Actions secret only when a trusted service explicitly supports this app/signing identity and its key is trusted by the addon operators.

The Listen Together default remains an upstream-hosted URL (`https://bitchord-listen-together.onrender.com`) unless `LISTEN_TOGETHER_SERVER` is configured. This is a separate runtime dependency for party coordination; use a trusted self-hosted endpoint before enabling it when independence from upstream is required.

The update checker points to `Rulzz77/Musikku` GitHub Releases, and the release workflow publishes to the current repository.

## Build

The upstream source currently specifies Gradle wrapper 8.11.1, Kotlin plugins 2.3.20, Android Gradle Plugin 8.10.1, compileSdk 37, minSdk 26, targetSdk 36, and CMake 3.22.1. Keep these in sync with the checked-out source rather than assuming they will never change.

Suggested first phone build:

```powershell
.\gradlew.bat :app:assembleProdDebug -Pmusikku.bundleWear=false
```

## GPL reminder

Keep upstream copyright and license notices. If you distribute this derivative, comply with GPL-3.0, including providing the Corresponding Source under the same license and required notices. Review `LICENSE` in the project root.