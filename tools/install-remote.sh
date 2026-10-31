#!/bin/bash
# Install C&C Generals Zero Hour on a running kiosk over SSH: copies the retail data from your own Steam installs
# (read only) and the prebuilt game (dist/generalszh-arm64.tar.gz, see tools/fetch-dist.sh), then runs
# device/install.sh. The kiosk runs Dropbear without SFTP/scp, so everything is streamed through plink as tar.
#
#   KIOSK_PASSWORD=... KIOSK_HOSTKEY=SHA256:... tools/install-remote.sh
#
# Optional: KIOSK_HOST (default 192.168.2.162), PLINK (default PuTTY's plink.exe), GENERALS_DIR, ZEROHOUR_DIR,
# GENERALS_DIST. The game data (~2.6 GB, ~8 min) is copied once; a marker file skips it on later runs.
set -euo pipefail

HOST=${KIOSK_HOST:-192.168.2.162}
PLINK=${PLINK:-"/c/Program Files/PuTTY/plink.exe"}
STEAM="/c/Program Files (x86)/Steam/steamapps/common"
GENERALS_DIR=${GENERALS_DIR:-"$STEAM/Command and Conquer Generals"}
ZEROHOUR_DIR=${ZEROHOUR_DIR:-"$STEAM/Command & Conquer Generals - Zero Hour"}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST=${GENERALS_DIST:-"$ROOT/dist/generalszh-arm64.tar.gz"}
: "${KIOSK_PASSWORD:?set KIOSK_PASSWORD}"
: "${KIOSK_HOSTKEY:?set KIOSK_HOSTKEY (SHA256 fingerprint of the device host key)}"
[ -f "$DIST" ] || { echo "missing $DIST (tools/fetch-dist.sh)" >&2; exit 1; }

kiosk() { "$PLINK" -batch -ssh "root@$HOST" -pw "$KIOSK_PASSWORD" -hostkey "$KIOSK_HOSTKEY" "$@"; }
echo "device: $(kiosk hostname)"

# The .big archives plus the loose files the engine reads from disk: Scripts, Cursors, Movies, <language>/Movies
copy_data() {
  local name=$1 dir=$2
  if kiosk "test -f /opt/cnc-gamedata/$name/.complete"; then echo "$name: data already on the device"; return; fi
  echo "$name: copying data from $dir"
  (cd "$dir" && tar -c ./*.big Data/Scripts Data/Cursors Data/Movies Data/*/Movies) |
    kiosk "set -e; D=/opt/cnc-gamedata/$name; rm -rf \$D; mkdir -p \$D; tar -x -C \$D; touch \$D/.complete
      echo \"$name: \$(ls \$D/*.big | wc -l) archives, \$(du -sh \$D | cut -f1)\""
}
copy_data generals "$GENERALS_DIR"
copy_data zerohour "$ZEROHOUR_DIR"

DEVICE="$ROOT/device"
tar -c -C "$DEVICE" install.sh generals-zh generals-zh-session Bgfx.ini -C "$(dirname "$DIST")" "$(basename "$DIST")" |
  kiosk 'set -e; d=$(mktemp -d -p /root); tar -x -C "$d"; bash "$d/install.sh"; rm -rf "$d"'
