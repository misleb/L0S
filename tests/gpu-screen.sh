#!/usr/bin/env bash
# gpu-screen.sh -- boots tests/screen/etc's initramfs, the demo's without
# its vt windows, and checks what the virtio-gpu's screen shows, by
# QEMU's screendump: the compositor's desktop, which the driver composes
# from the compositor's own buffer.
#
#   0. the driver's first frame, booted with no wm: the wallpaper,
#      branding/wallpaper-dark.svg as build/wallpaper.qoi holds it,
#      centered, where the top bar will be too
#   1. the wallpaper: branding/wallpaper-dark.svg as
#      build/wallpaper.qoi holds it, centered; and the compositor's top
#      bar over it, black, its first 32 rows, with no clock running and
#      so no time on it
#   2. after run draw line 0 32 1279 799 red, typed at the shell, which
#      draw sends the compositor for the desktop, both of the line's
#      ends, the first just below the bar
#   3. after run draw circle 640 400 300 cyan, the circle's right edge
#
# Commands are typed through a FIFO, one once the screen shows what the
# one before it drew. The board keeps running until this kills it. Run
# from the top of the project, after make screen-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/gpu-screen.sock"
dump="$BUILD/gpu-screen.ppm"
fifo="$BUILD/gpu-screen.in"
first="$BUILD/gpu-screen-first"

# Boots the initramfs $1, typing what goes into the FIFO; stop ends it.
boot() {
  rm -f "$sock" "$dump" "$fifo"
  mkfifo "$fifo"
  QEMU_MONITOR="unix:$sock,server=on,wait=off" \
    tools/qemu-boot.sh "$1" < "$fifo" > "$BUILD/gpu-screen.out" 2>&1 &
  qemu=$!
  exec 3> "$fifo"
}
stop() { exec 3>&-; kill $qemu 2> /dev/null; wait $qemu 2> /dev/null; rm -f "$fifo"; }
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT

# The 3 bytes of pixel x, y of the screendump, a 1280 by 800 PPM whose
# header, "P6\n1280 800\n255\n", is 16 bytes, in decimal.
pixel() { od -An -tu1 -j $((16 + ($2 * 1280 + $1) * 3)) -N3 "$dump" | tr -s ' ' | sed 's/^ //; s/ $//'; }

# Waits up to 30 s for each "X Y R G B" given to be on the screen; says
# what NAME showed, and stops at the first that does not.
shows() {
  local name=$1; shift
  local p ok got="" px py r g b start=$SECONDS end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    sleep 0.2
    [ -S "$sock" ] || continue
    rm -f "$dump"
    printf 'screendump %s\n' "$dump" | tools/qsock "$sock" > /dev/null 2>&1
    # Until the driver sets its mode, QEMU's screen is a smaller one.
    [ -s "$dump" ] && [ "$(wc -c < "$dump")" = $((16 + 1280 * 800 * 3)) ] || continue
    ok=1; got=""
    for p in "$@"; do
      read -r px py r g b <<< "$p"
      got="$got ($px,$py)=$(pixel $px $py)"
      [ "$(pixel $px $py)" = "$r $g $b" ] || ok=0
    done
    if [ "$ok" = 1 ]; then echo "ok - gpu-screen: $name after $((SECONDS - start))s"; return 0; fi
  done
  echo "not ok - gpu-screen: $name: got$got, wanted $*"
  exit 1
}

# The wallpaper is 1920 by 1080, centered and cut to 1280 by 800: the
# screen's 0, 0 is its 320, 140. Its 320, 172 is the sky, 15 26 39, and
# its 576, 440, the screen's 256, 300, is on the L's stem, 184 141 67,
# as build/wallpaper.qoi holds them, at full brightness.
#
# 0. The driver's first frame, before wm: the same initramfs with no
# wm, so the screen stays as virtio-gpu first showed it. The wallpaper
# where the bar will be, 0, 0 and 640, 16, and the stem.
rm -rf "$first.etc" && cp -R "$BUILD/screen-etc" "$first.etc"
grep -v '^start /sbin/wm$' "$BUILD/screen-etc/inittab" > "$first.etc/inittab"
tools/mkinitramfs "$first.cpio" "$first.etc" "$BUILD/root" > /dev/null
boot "$first.cpio"
shows "the driver's first frame, the wallpaper" "0 0 15 27 39" "640 16 22 35 54" "256 300 184 141 67"
stop
rm -rf "$first.etc" "$first.cpio"

# 1. The desktop, wm's, over the same wallpaper.
boot "$BUILD/screen.cpio"
shows "wallpaper" "0 32 15 26 39" "256 300 184 141 67"
shows "top bar" "0 0 0 0 0" "640 16 0 0 0" "1279 31 0 0 0"

printf 'run draw line 0 32 1279 799 red\n' >&3
shows "line" "0 32 255 0 0" "1279 799 255 0 0"

printf 'run draw circle 640 400 300 cyan\n' >&3
shows "circle" "940 400 0 255 255" "340 400 0 255 255"
