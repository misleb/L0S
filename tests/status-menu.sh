#!/usr/bin/env bash
# status-menu.sh -- boots tests/screen/etc's initramfs with no window:
# the compositor, wm, and no vt, and no audio server. Clicks the top
# bar's status button, at its right end, with the tablet, through QMP,
# and checks, by QEMU's screendump and the serial line:
#
#   1. the card open: the button on its pill, the card's ground under the
#      bar, at the right
#   2. Esc, on the virtio keyboard, closes it
#   3. the settings button does nothing yet: the card stays open
#   4. power opens Restart and Shut Down in the card, which grows
#   5. Restart resets the board: the kernel says so, and boots again
#   6. Shut Down kills pid 1: QEMU exits by itself
#
# The serial line is typed through a FIFO. Run from the top of the
# project, after make screen-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/status-menu.sock"
qmp="$BUILD/status-menu.qmp"
fifo="$BUILD/status-menu.in"
out="$BUILD/status-menu.out"
dump="$BUILD/status-menu.ppm"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"

QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/screen.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - status-menu: $1"; sed 's/^/  # /' "$out"; exit 1; }

monitor() { printf '%s\n' "$1" | tools/qsock "$sock" > /dev/null 2>&1; }

# The tablet, through QMP: each argument an input event.
events() {
  local list
  list=$(IFS=,; echo "$*")
  printf '{"execute":"qmp_capabilities"}\n{"execute":"input-send-event","arguments":{"events":[%s]}}\n' "$list" \
    | tools/qsock "$qmp" > /dev/null 2>&1
}
axis() { echo $(( $1 * 32767 / ($2 - 1) )); }
at() {
  echo "{\"type\":\"abs\",\"data\":{\"axis\":\"x\",\"value\":$(axis "$1" 1280)}},{\"type\":\"abs\",\"data\":{\"axis\":\"y\",\"value\":$(axis "$2" 800)}}"
}
button() { echo "{\"type\":\"btn\",\"data\":{\"down\":$1,\"button\":\"left\"}}"; }

# A click at x, y: there, pressed, let go. What it does is waited for
# by what checks it, not here.
click() {
  events "$(at $1 $2)"; sleep 0.1
  events "$(button true)"; sleep 0.1
  events "$(button false)"
}

waits_for() {
  local end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    grep -qE "$1" "$out" 2> /dev/null && return 0
    sleep 0.2
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# Pixel x, y of the screendump, a 1280 by 800 PPM whose header is 16 bytes.
pixel() { od -An -tu1 -j $((16 + ($2 * 1280 + $1) * 3)) -N3 "$dump" | tr -s ' ' | sed 's/^ //; s/ $//'; }

# Waits up to 30 s for each "X Y R G B" given to be on the screen.
shows() {
  local name=$1; shift
  local p ok got px py r g b end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    rm -f "$dump"
    monitor "screendump $dump"
    if [ -s "$dump" ]; then
      ok=1; got=""
      for p in "$@"; do
        read -r px py r g b <<< "$p"
        got="$got ($px,$py)=$(pixel $px $py)"
        [ "$(pixel $px $py)" = "$r $g $b" ] || ok=0
      done
      [ "$ok" = 1 ] && { echo "ok - status-menu: $name"; return 0; }
    fi
    sleep 0.2
  done
  echo "not ok - status-menu: $name: got$got, wanted $*"
  exit 1
}

# With no audio the button is the power icon alone, 36 wide at 1244 on
# 1280, its pill, 404040, from 1248: 1250, 16 is on it while the card is
# open. The card is 360 wide, 4 in from the right and 4 under the bar,
# at 916, 36, 104 high, 216 with power open; its ground, 242424, is at
# 950, 65, left of its buttons, and 920, 230 is on it only with power
# open. Its buttons, 34 round, are 222, 268 and 314 in, 12 down: settings
# at 1201, 65, power at 1247, 65; power open, Restart's row is 94 to 144
# on the screen, Shut Down's 144 to 194.
pill="64 64 64"; card="36 36 36"

waits_for "^l0s> "
# wm says it serves once the display has drawn the wallpaper, which may
# come after the prompt: wait, so the button's click reaches it.
waits_for "serving compositor"
shows "closed, at the start" "1250 16 0 0 0"

click 1262 16
shows "the button opened the card: its pill and the card" "1250 16 $pill" "950 65 $card"

monitor "sendkey esc"
shows "Esc closed it" "1250 16 0 0 0"

click 1262 16
shows "opened again" "1250 16 $pill"
click 1201 65
sleep 1
shows "settings did nothing: the card is open" "1250 16 $pill" "950 65 $card"
click 1247 65
shows "power opened Restart and Shut Down: the card grew" "920 230 $card"
click 100 400
shows "a click on the page closed it" "1250 16 0 0 0"

# Restart: the board resets and QEMU boots it again, its banner a
# second time.
click 1262 16
shows "opened a third time" "1250 16 $pill"
click 1247 65
shows "power open again" "920 230 $card"
click 1096 119
waits_for "l0s: restarting the board, as wm \(pid [0-9]+\) asked"
end=$((SECONDS + 30))
until [ $SECONDS -ge $end ]; do
  [ "$(grep -c '^l0s: aarch64' "$out")" -ge 2 ] && break
  sleep 0.2
done
[ "$(grep -c '^l0s: aarch64' "$out")" -ge 2 ] || fail "Restart did not boot the board again; it showed:"
echo "ok - status-menu: Restart reset the board, and it booted again"
# The second boot's prompt, and its wm serving, up to 30 s, before the
# next click.
end=$((SECONDS + 30))
until [ $SECONDS -ge $end ]; do
  [ "$(grep -c '^l0s> ' "$out")" -ge 2 ] && [ "$(grep -c 'serving compositor' "$out")" -ge 2 ] && break
  sleep 0.2
done
shows "the desktop again, the card closed" "1250 16 0 0 0"

click 1262 16
shows "opened after the restart" "1250 16 $pill"
click 1247 65
shows "power open after the restart" "920 230 $card"
click 1096 169
end=$((SECONDS + 30))
until [ $SECONDS -ge $end ]; do
  kill -0 $qemu 2> /dev/null || { echo "ok - status-menu: Shut Down stopped the board"; exit 0; }
  sleep 0.2
done
fail "Shut Down left the board running"
