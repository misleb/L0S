#!/usr/bin/env bash
# usb.sh -- boots tests/usb/etc's initramfs, the desktop on a qemu-xhci's
# usb-kbd and usb-mouse (QEMU_INPUT=usb), with no window, and checks:
#
#   1. run keys, typed at the serial shell, echoes keys pressed on the
#      USB keyboard through QEMU's monitor (sendkey), through xhci and
#      usb-hid keyboard: "hi! A", shift included
#   2. the USB mouse, moved through QMP's input-send-event with relative
#      axes, as a mouse moves, from where the pointer starts, 0, 0, to
#      the top bar's Applications, 60, 16, and clicked, opens the
#      launcher: its pill shows behind the label, as launcher.sh pins it
#
# Run from the top of the project, after make usb-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/usb.sock"
qmp="$BUILD/usb.qmp"
fifo="$BUILD/usb.in"
out="$BUILD/usb.out"
dump="$BUILD/usb.ppm"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"

QEMU_INPUT=usb QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/usb.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - usb: $1"; sed 's/^/  # /' "$out"; exit 1; }

monitor() { printf '%s\n' "$1" | nc -U -w 1 "$sock" > /dev/null 2>&1; }

# The mouse, through QMP: each argument an input event.
events() {
  local list
  list=$(IFS=,; echo "$*")
  printf '{"execute":"qmp_capabilities"}\n{"execute":"input-send-event","arguments":{"events":[%s]}}\n' "$list" \
    | nc -U -w 1 "$qmp" > /dev/null 2>&1
}
by() {
  echo "{\"type\":\"rel\",\"data\":{\"axis\":\"x\",\"value\":$1}},{\"type\":\"rel\",\"data\":{\"axis\":\"y\",\"value\":$2}}"
}
button() { echo "{\"type\":\"btn\",\"data\":{\"down\":$1,\"button\":\"left\"}}"; }

waits_for() {
  local try
  for try in $(seq 1 30); do
    grep -qF "$1" "$out" 2> /dev/null && return 0
    sleep 1
  done
  fail "no '$1' on the serial line; it showed:"
}

# Pixel x, y of the screendump, a 1280 by 800 PPM whose header is 16 bytes.
pixel() { od -An -tu1 -j $((16 + ($2 * 1280 + $1) * 3)) -N3 "$dump" | tr -s ' ' | sed 's/^ //; s/ $//'; }

# Waits up to 30 s for each "X Y R G B" given to be on the screen.
shows() {
  local name=$1; shift
  local try p ok got px py r g b
  for try in $(seq 1 30); do
    rm -f "$dump"
    monitor "screendump $dump"
    if [ -s "$dump" ]; then
      ok=1; got=""
      for p in "$@"; do
        read -r px py r g b <<< "$p"
        got="$got ($px,$py)=$(pixel $px $py)"
        [ "$(pixel $px $py)" = "$r $g $b" ] || ok=0
      done
      [ "$ok" = 1 ] && { echo "ok - usb: $name"; return 0; }
    fi
    sleep 1
  done
  echo "not ok - usb: $name: got$got, wanted $*"
  exit 1
}

waits_for "device 1 0627:0001 high keyboard"
waits_for "l0s> "

printf 'run keys\n' >&3
waits_for "keys: type in QEMU's window; Esc ends"
# wm says it serves once the display has drawn the wallpaper, which may
# come after the prompt: wait, so its line is not among the keys.
waits_for "serving compositor"
for k in h i shift-1 spc shift-a ret; do monitor "sendkey $k"; done
waits_for "hi! A"
echo "ok - usb: the USB keyboard typed 'hi! A'"
monitor "sendkey esc"

# As launcher.sh pins them: the top bar's 8, 16 black, the launcher's
# pill behind Applications 404040 once it is open.
pill="64 64 64"
shows "the launcher closed" "40 16 0 0 0"
events "$(by 60 16)"; sleep 1
events "$(button true)"; sleep 1
events "$(button false)"; sleep 1
shows "the mouse moved to Applications and clicked it open" "40 16 $pill"
