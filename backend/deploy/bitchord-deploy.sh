#!/usr/bin/env bash
# Pulls MusikKu main and rebuilds the Listen Together service.
# The GitHub deploy key is pinned to this script (forced command), so a leaked
# key can do nothing but redeploy the MusikKu backend.
set -euo pipefail

REPO=https://github.com/Rulzz77/Musikku.git
SRC=/opt/bitchord-src

if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$(dirname "$SRC")"
  git clone --depth 1 --branch main "$REPO" "$SRC"
else
  # Migrate any existing checkout from the upstream BitChord repository.
  git -C "$SRC" remote set-url origin "$REPO"
  git -C "$SRC" fetch --depth 1 origin main
  git -C "$SRC" reset --hard FETCH_HEAD
fi

echo "deploying MusikKu $(git -C "$SRC" log -1 --format='%h %s')"
DOMAIN="$(cat /etc/bitchord-domain)"
DOMAIN="$DOMAIN" bash "$SRC/backend/deploy/setup.sh"

# Verify the reverse proxy and local Go service without checking an upstream
# BitChord domain. Caddy serves /healthz locally and accepts the configured host.
for attempt in $(seq 1 12); do
  if curl -fsSk --max-time 5 --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/healthz" | grep -q '"ok":true'; then
    echo "MusikKu backend is healthy at https://$DOMAIN/healthz"
    exit 0
  fi
  sleep 5
done

echo "MusikKu backend health check failed for https://$DOMAIN/healthz" >&2
exit 1
