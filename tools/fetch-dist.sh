#!/bin/bash
# Copy the built game from a kiosk to dist/generalszh-arm64.tar.gz (the archive tools/install-remote.sh installs).
# Leaves out the retail files that device/install.sh adds again from /opt/cnc-gamedata.
#
#   KIOSK_PASSWORD=... KIOSK_HOSTKEY=SHA256:... tools/fetch-dist.sh
set -euo pipefail

HOST=${KIOSK_HOST:-192.168.2.162}
PLINK=${PLINK:-"/c/Program Files/PuTTY/plink.exe"}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${KIOSK_PASSWORD:?set KIOSK_PASSWORD}"
: "${KIOSK_HOSTKEY:?set KIOSK_HOSTKEY (SHA256 fingerprint of the device host key)}"

mkdir -p "$ROOT/dist"
"$PLINK" -batch -ssh "root@$HOST" -pw "$KIOSK_PASSWORD" -hostkey "$KIOSK_HOSTKEY" \
  'cd /opt && tar -c --exclude="generalszh/\\\\*" --exclude=generalszh/Data/Movies --exclude=generalszh/Data/Scripts \
     --exclude=generalszh/Data/Cursors --exclude="generalszh/Data/[Gg]erman*" generalszh | gzip -1' \
  > "$ROOT/dist/generalszh-arm64.tar.gz.part"
gzip -t "$ROOT/dist/generalszh-arm64.tar.gz.part"
mv "$ROOT/dist/generalszh-arm64.tar.gz.part" "$ROOT/dist/generalszh-arm64.tar.gz"
ls -l "$ROOT/dist/generalszh-arm64.tar.gz"
