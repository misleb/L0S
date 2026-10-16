#!/usr/bin/env bash
# gpu-screen.sh -- boots tests/screen/etc's initramfs, the demo's without
# its vt windows, and checks what the virtio-gpu's screen shows, by
# QEMU's screendump: the compositor's desktop, which the driver composes
# from the compositor's own buffer.
#
#   1. the wallpaper: the splash, centered, on its own ground color,
#      both at 70%; and the compositor's top bar over it, black, its
#      first 32 rows, with no clock running and so no time on it
#   2. after run draw line 0 32 1279 799 red, typed at the shell, which
#      draw sends the compositor for the desktop, both of the line's
#      ends, the first just below the bar
#   3. after run draw circle 640 400 300 cyan, the circle's right edge
#
# Commands are typed through a FIFO, one once the screen shows what the
# one before it drew. The board keeps running until this kills it. Run
# from the top of the project, after make screen-initramfs, with
# build/splash.ppm the splash it holds.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/gpu-screen.sock"
dump="$BUILD/gpu-screen.ppm"
fifo="$BUILD/gpu-screen.in"
rm -f "$sock" "$dump" "$fifo"
mkfifo "$fifo"

QEMU_MONITOR="unix:$sock,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/screen.cpio" < "$fifo" > "$BUILD/gpu-screen.out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

# The 3 bytes of pixel x, y of the screendump, a 1280 by 800 PPM whose
# header, "P6\n1280 800\n255\n", is 16 bytes, in decimal.
pixel() { od -An -tu1 -j $((16 + ($2 * 1280 + $1) * 3)) -N3 "$dump" | tr -s ' ' | sed 's/^ //; s/ $//'; }

# Waits up to 30 s for each "X Y R G B" given to be on the screen; says
# what NAME showed, and stops at the first that does not.
shows() {
  local name=$1; shift
  local try p ok got px py r g b
  for try in $(seq 1 30); do
    sleep 1
    [ -S "$sock" ] || continue
    rm -f "$dump"
    printf 'screendump %s\n' "$dump" | nc -U -w 1 "$sock" > /dev/null 2>&1
    [ -s "$dump" ] || continue
    ok=1; got=""
    for p in "$@"; do
      read -r px py r g b <<< "$p"
      got="$got ($px,$py)=$(pixel $px $py)"
      [ "$(pixel $px $py)" = "$r $g $b" ] || ok=0
    done
    if [ "$ok" = 1 ]; then echo "ok - gpu-screen: $name after ${try}s"; return 0; fi
  done
  echo "not ok - gpu-screen: $name: got$got, wanted $*"
  exit 1
}

# The splash is 640 by 360, centered at 320, 220: its 0, 0 is ground,
# 12 28 38 at full brightness, and its 190, 100 is on the L's stem,
# 231 196 78, 9 of 64 parts dimmed; the compositor shows both at 70%.
shows "wallpaper" "0 32 8 19 26" "510 320 161 137 54"
shows "top bar" "0 0 0 0 0" "640 16 0 0 0" "1279 31 0 0 0"

printf 'run draw line 0 32 1279 799 red\n' >&3
shows "line" "0 32 255 0 0" "1279 799 255 0 0"

printf 'run draw circle 640 400 300 cyan\n' >&3
shows "circle" "940 400 0 255 255" "340 400 0 255 255"
