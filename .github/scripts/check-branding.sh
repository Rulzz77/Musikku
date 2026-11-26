#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "::error::$1"
  exit 1
}

# Catch old product names in visible Android strings and active web metadata.
if grep -RInE '>([^<]*)(BitChord|flutter_application_5)' \
  app/src/main/res/values* \
  wearos/src/main/res/values* \
  tv/src/main/res/values* 2>/dev/null; then
  fail "Legacy product branding remains in Android/Wear OS/TV string values."
fi

# The image-based lyric share card has its own Canvas wordmark, outside the
# Android string catalogs above. Keep it tied to the current product name too.
if ! grep -q 'LYRICS_SHARE_BRAND = "MusikKu"' \
  app/src/main/java/com/music/bitchord/ui/player/LyricsShareCard.kt; then
  fail "The lyric share card does not use the MusikKu wordmark."
fi

# Compose owns a separate, localized string catalog used by the shared player UI.
if grep -RInE '>([^<]*)(BitChord|flutter_application_5)' \
  sharedUi/src/commonMain/composeResources/values* 2>/dev/null; then
  fail "Legacy product branding remains in shared Compose string values."
fi

if grep -nE '<title>BitChord|flutter_application_5|A new Flutter project' \
  web/app/index.html web/index.html web/manifest.json 2>/dev/null; then
  fail "Legacy product branding remains in web/PWA metadata."
fi

# The eight selectable launcher aliases must use the new vector layers, not old PNG mipmaps.
if grep -RInE '@mipmap/ic_[A-Za-z0-9_]+_(foreground|background)' \
  app/src/main/res/mipmap-anydpi 2>/dev/null; then
  fail "An adaptive launcher icon still points at a legacy mipmap image."
fi

if grep -RIn 'R\.mipmap\.ic_.*_foreground' app/src/main/java/com/music/bitchord/AppIcon.kt; then
  fail "An app-icon preview still points at an old raster foreground."
fi

# Old density-specific icons and TV banners must not return to source control.
for dir in \
  app/src/main/res/mipmap-hdpi app/src/main/res/mipmap-mdpi \
  app/src/main/res/mipmap-xhdpi app/src/main/res/mipmap-xxhdpi \
  app/src/main/res/mipmap-xxxhdpi wearos/src/main/res/mipmap-hdpi \
  wearos/src/main/res/mipmap-mdpi wearos/src/main/res/mipmap-xhdpi \
  wearos/src/main/res/mipmap-xxhdpi wearos/src/main/res/mipmap-xxxhdpi
do
  if [[ -d "$dir" ]] && find "$dir" -type f -print -quit | grep -q .; then
    fail "Legacy density-specific launcher assets remain in $dir."
  fi
done

if find tv/src/main/res -type f -name 'tv_banner.png' -print -quit | grep -q .; then
  fail "A legacy raster Android TV banner remains."
fi

# Confirm the new vector identity and the one-source PNG generator are present.
test -f app/src/main/res/drawable/ic_musikku_launcher.xml || fail "Missing MusikKu launcher vector."
test -f app/src/main/res/drawable/ic_musikku_monochrome.xml || fail "Missing MusikKu monochrome icon."
test -f wearos/src/main/res/drawable/ic_logo.xml || fail "Missing Wear OS logo vector."
test -f tv/src/main/res/drawable/tv_banner.xml || fail "Missing Android TV vector banner."
test -f web/app/public/favicon.svg || fail "Missing web brand source SVG."

grep -q "favicon.svg" web/extension/scripts/gen-icons.mjs || fail "Browser/store icon generator is not using the MusikKu source SVG."
grep -q "playStorePath" web/extension/scripts/gen-icons.mjs || fail "Play Store artwork generation is missing."
grep -q "pnpm run icons && wxt build" web/extension/package.json || fail "Extension builds do not regenerate branded icons."


# All visible MusikKu brand surfaces use the same five-bar equalizer, not the
# retired M/music-note monogram. Keep Android, Wear OS, TV, SVG and web assets aligned.
legacy_logo_files=(
  app/src/main/res/drawable/ic_logo.xml
  app/src/main/res/drawable/ic_notification_logo.xml
  sharedUi/src/commonMain/composeResources/drawable/ic_logo.xml
  wearos/src/main/res/drawable/ic_logo.xml
  wearos/src/main/res/drawable/ic_launcher_foreground.xml
  wearos/src/main/res/drawable/ic_musikku_monochrome.xml
  tv/src/main/res/drawable/tv_banner.xml
  app/src/main/assets/Logo.svg
  app/src/main/assets/LogoTransparent.svg
  Logo.svg
  web/app/public/favicon.svg
  web/app/src/assets/logo-mark.svg
)
if grep -nE 'M25,78 V35|M25 78V35|M120 369V166|M45,63 V80|M45 63V80|M256,73v92' "${legacy_logo_files[@]}"; then
  fail "A product surface still contains the retired M/music-note logo."
fi

for file in \
  app/src/main/res/drawable/ic_logo.xml \
  app/src/main/res/drawable/ic_notification_logo.xml \
  sharedUi/src/commonMain/composeResources/drawable/ic_logo.xml \
  wearos/src/main/res/drawable/ic_logo.xml
do
  grep -q 'M30,39 V74' "$file" || fail "The equalizer brand mark is missing from $file."
done

for file in \
  app/src/main/assets/LogoTransparent.svg \
  web/app/src/assets/logo-mark.svg
do
  grep -q 'M30 39V74' "$file" || fail "The equalizer SVG mark is missing from $file."
done

echo "MusikKu branding and icon audit passed."
