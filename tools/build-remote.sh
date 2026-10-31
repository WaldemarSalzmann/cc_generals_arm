#!/bin/bash
# Build the game on a running kiosk (see build/build-generals.sh) as a background systemd unit, so closing SSH
# does not stop it. Follow the log with: tail -f /root/gen/build.log (ends with BUILD-DONE).
# Afterwards tools/fetch-dist.sh copies the result to dist/.
#
#   KIOSK_PASSWORD=... KIOSK_HOSTKEY=SHA256:... tools/build-remote.sh
set -euo pipefail

HOST=${KIOSK_HOST:-192.168.2.162}
PLINK=${PLINK:-"/c/Program Files/PuTTY/plink.exe"}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${KIOSK_PASSWORD:?set KIOSK_PASSWORD}"
: "${KIOSK_HOSTKEY:?set KIOSK_HOSTKEY (SHA256 fingerprint of the device host key)}"

tar -c -C "$ROOT" build patches device |
  "$PLINK" -batch -ssh "root@$HOST" -pw "$KIOSK_PASSWORD" -hostkey "$KIOSK_HOSTKEY" '
    set -e; mkdir -p /root/gen/repo; tar -x -C /root/gen/repo; echo "device: $(hostname)"
    systemctl reset-failed generals-build 2>/dev/null || true
    systemd-run --unit=generals-build --property=Nice=10 \
      --property=StandardOutput=append:/root/gen/build.log --property=StandardError=append:/root/gen/build.log \
      /bin/bash /root/gen/repo/build/build-generals.sh'
