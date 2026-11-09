#!/usr/bin/env bash
# Build the iOS IPA using the version maintained in ios/version.properties.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION_FILE="ios/version.properties"
if [[ ! -s "$VERSION_FILE" ]]; then
  echo "Missing $VERSION_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$VERSION_FILE"

if [[ ! "${IOS_VERSION:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "IOS_VERSION in $VERSION_FILE must look like 1.0.0" >&2
  exit 1
fi
if [[ ! "${IOS_BUILD_NUMBER:-}" =~ ^[0-9]+$ ]]; then
  echo "IOS_BUILD_NUMBER in $VERSION_FILE must be numeric" >&2
  exit 1
fi

flutter pub get
flutter build ipa --release \
  --build-name="$IOS_VERSION" \
  --build-number="$IOS_BUILD_NUMBER" \
  "$@"
