# MusikKu Remote Config

The installed Android app can refresh a small public JSON file without an APK
release. It is intended for rollout switches and safe fallbacks for features
whose code is already installed.

## Edit the live configuration

Edit `remote-config.json` on the repository's `main` branch:

```json
{
  "schemaVersion": 1,
  "revision": 2,
  "features": {
    "globalSearch": true,
    "playlistSearch": false
  }
}
```

- `schemaVersion` must remain `1` unless a future app version adds support for
  a new schema.
- Increase `revision` for each published configuration change.
- `globalSearch` controls the global Search entry and top-bar search field.
- `playlistSearch` controls the Search filter on album, playlist and local
  folder detail pages.
- Omitted or invalid feature values fall back to enabled. A missing, malformed
  or unsupported document is rejected and does not replace the last good cache.

The Android app fetches this document from the repository's raw `main` URL.
It refreshes when the app enters the foreground, at most once every 15 minutes.
The last known-good response is cached on-device; if the network or GitHub is
unavailable, cached values remain active. A fresh install with no cache uses
the built-in defaults (both flags enabled).

## What this can and cannot change

Remote Config can switch or tune behavior that already exists in the installed
APK. It cannot download new Kotlin/Compose code, repair a native crash in old
code, change Android permissions, or add a new screen/feature. Those changes
still need an APK update. Never put API keys, credentials, personal data or
other secrets in this public JSON file.
