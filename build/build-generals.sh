#!/bin/bash
# Build C&C Generals Zero Hour natively on an ODROID-N2+ kiosk (DietPi, Debian 13, arm64): GeneralsGameCode fork
# with the bgfx renderer, patched for OpenGL 3.1 (Mali-G52 / Panfrost) and for ARM64 + GCC 14.
# Run as root on the device with the patches in ../patches (tools/build-remote.sh does that). Logs to stdout.
# Result: /opt/generalszh and /root/gen/generalszh-arm64.tar.gz (the archive device/install.sh expects).
# Takes about 1-1.5 hours on the N2+ (3 parallel jobs, 4 GB swap file). Running it again only rebuilds what changed.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PATCHES=${PATCHES:-$HERE/../patches}
W=/root/gen; mkdir -p "$W"; cd "$W"
REPO=https://github.com/bobtista/GeneralsGameCode.git
COMMIT=8c03683467d4be389fe633214f4894332a562a57
PRESET=linux-generalsmd-sdl3-bgfx
phase(){ echo; echo "== $(date +%H:%M:%S) $*"; }

phase "swap"
if ! swapon --show=NAME --noheadings | grep -q "$W/swapfile"; then
  [ -f swapfile ] || { fallocate -l 4G swapfile; chmod 600 swapfile; mkswap swapfile >/dev/null; }
  swapon swapfile
fi

phase "build dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential cmake ninja-build pkg-config git curl xz-utils \
  libx11-dev libxext-dev libxrandr-dev libxi-dev libxcursor-dev libxinerama-dev libxfixes-dev libxrender-dev \
  libxss-dev libxtst-dev libxkbcommon-dev libwayland-dev wayland-protocols libdecor-0-dev \
  libgl1-mesa-dev libegl1-mesa-dev libvulkan-dev libfreetype-dev libfontconfig-dev \
  libasound2-dev libpulse-dev zlib1g-dev >/dev/null

phase "source"
if [ ! -d src/.git ]; then
  git init -q src
  git -C src remote add origin "$REPO"
  git -C src fetch -q --depth 1 origin "$COMMIT"
  git -C src checkout -q "$COMMIT"
fi
# Applied patches are recorded in .applied (a reverse check fails once later patches touch the same lines)
mkdir -p "$W/.applied"
for p in "$PATCHES"/*.patch; do
  n=${p##*/}
  if [ -e "$W/.applied/$n" ]; then echo "already applied: $n"
  else git -C src apply "$p"; touch "$W/.applied/$n"; echo "applied: $n"; fi
done

phase "minimal ffmpeg"
[ -f ffmpeg-min/lib/pkgconfig/libavcodec.pc ] ||
  bash src/scripts/build/linux/build-ffmpeg-minimal.sh "$W/ffmpeg-min" 2>&1 | tail -3

phase "configure + build"
cd src
export PKG_CONFIG_PATH="$W/ffmpeg-min/lib/pkgconfig"
[ -f "build/$PRESET/build.ninja" ] ||
  cmake --preset "$PRESET" -DGGC_BGFX_RENDERER=gl \
    -DRTS_DEBUG_LOGGING=ON -DRTS_DEBUG_CRASHING=OFF -DRTS_DEBUG_STACKTRACE=OFF -DRTS_DEBUG_PROFILE=OFF
start=$(date +%s)
cmake --build "build/$PRESET" --config Release --target z_generals -j3
echo "build took $(( ($(date +%s)-start)/60 )) min"

phase "stage"
GGC_LINUX_RUNTIME_DIR=/opt/generalszh bash scripts/build/linux/deploy-linux-generalsmd.sh "$PRESET" Release | tail -3
install -m 644 "$HERE/../device/Bgfx.ini" /opt/generalszh/Data/INI/Bgfx.ini
tar -C /opt -czf "$W/generalszh-arm64.tar.gz" generalszh
ls -l "$W/generalszh-arm64.tar.gz"
# The loose retail files (Data/Scripts, Cursors, Movies) are added by device/install.sh
[ -x /usr/local/bin/generals-zh ] && [ -d /opt/cnc-gamedata ] && {
  cp -rn /opt/cnc-gamedata/zerohour/Data/. /opt/generalszh/Data/
  cp -rn /opt/cnc-gamedata/generals/Data/. /opt/generalszh/Data/
}
echo BUILD-DONE
