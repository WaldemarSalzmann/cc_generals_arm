#!/bin/bash
# Install C&C Generals Zero Hour (prebuilt for the ODROID-N2+, bgfx on OpenGL) on a DietPi kiosk.
# Run as root on the device next to generalszh-arm64.tar.gz, generals-zh, generals-zh-session and Bgfx.ini.
# The retail game data must already be in /opt/cnc-gamedata/{generals,zerohour} (tools/install-remote.sh copies it
# from your own Steam installs). Safe to run again. The kiosk stays the autostart; start the game with generals-zh.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
DIST=$HERE/generalszh-arm64.tar.gz
DATA=/opt/cnc-gamedata
GAME=/opt/generalszh
# Runtime libraries the game links or SDL3 / OpenAL load at run time (present on a Chromium kiosk already)
RUNTIME="libx11-6 libxext6 libxcursor1 libxi6 libxfixes3 libxrandr2 libxss1 libxkbcommon0 libegl1 libgl1
  libwayland-egl1 libdecor-0-0 libasound2t64 libpulse0 libfreetype6 libfontconfig1 x11-xserver-utils xinit"

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
for g in generals zerohour; do
  [ -f "$DATA/$g/.complete" ] || { echo "game data missing: $DATA/$g" >&2; exit 1; }
done

echo "== runtime libraries"
missing=""
for p in $RUNTIME; do dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"; done
if [ -n "$missing" ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends $missing >/dev/null
  echo "installed:$missing"
else
  echo "all present"
fi

echo "== game"
systemctl stop generals-zh 2>/dev/null || true
rm -rf "$GAME.new"; mkdir -p "$GAME.new"
tar -xzf "$DIST" -C "$GAME.new" --strip-components=1
find "$GAME.new" -maxdepth 1 -name '\\*' -delete   # log files a Windows-path bug writes next to the binary
rm -rf "$GAME"; mv "$GAME.new" "$GAME"
install -m 644 "$HERE/Bgfx.ini" "$GAME/Data/INI/Bgfx.ini"
# Loose retail files next to the binary (the .big archives stay in $DATA); Zero Hour's take precedence
cp -rn "$DATA/zerohour/Data/." "$GAME/Data/"
cp -rn "$DATA/generals/Data/." "$GAME/Data/"
if (cd "$GAME" && LD_LIBRARY_PATH=libs ldd generalszh | grep 'not found'); then
  echo "unresolved libraries" >&2; exit 1
fi

echo "== launcher"
install -m 755 "$HERE/generals-zh" /usr/local/bin/generals-zh
install -D -m 755 "$HERE/generals-zh-session" /usr/local/lib/generals-zh-session

echo "installed: $GAME ($(du -sh "$GAME" | cut -f1)), start with: generals-zh"
