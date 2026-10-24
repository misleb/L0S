#!/usr/bin/env bash
# logo-menu.sh -- boots tests/screen/etc's initramfs with no window: the
# compositor, wm, and no vt. Clicks the top bar's logo with the tablet,
# through QMP, and checks, by QEMU's screendump and the serial shell:
#
#   1. the menu open: the logo on its pill, the card's ground under the bar
#   2. Esc, on the virtio keyboard, closes it
#   3. About L0S starts the About window: run windows lists it
#   4. Shut Down kills pid 1: QEMU exits by itself
#
# The serial line is typed through a FIFO. Run from the top of the
# project, after make screen-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/logo-menu.sock"
qmp="$BUILD/logo-menu.qmp"
fifo="$BUILD/logo-menu.in"
out="$BUILD/logo-menu.out"
dump="$BUILD/logo-menu.ppm"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"

QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/screen.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - logo-menu: $1"; sed 's/^/  # /' "$out"; exit 1; }

monitor() { printf '%s\n' "$1" | nc -U -w 1 "$sock" > /dev/null 2>&1; }

# The tablet, through QMP: each argument an input event.
events() {
  local list
  list=$(IFS=,; echo "$*")
  printf '{"execute":"qmp_capabilities"}\n{"execute":"input-send-event","arguments":{"events":[%s]}}\n' "$list" \
    | nc -U -w 1 "$qmp" > /dev/null 2>&1
}
axis() { echo $(( $1 * 32767 / ($2 - 1) )); }
at() {
  echo "{\"type\":\"abs\",\"data\":{\"axis\":\"x\",\"value\":$(axis "$1" 1280)}},{\"type\":\"abs\",\"data\":{\"axis\":\"y\",\"value\":$(axis "$2" 800)}}"
}
button() { echo "{\"type\":\"btn\",\"data\":{\"down\":$1,\"button\":\"left\"}}"; }

# A click at x, y: there, pressed, let go.
click() {
  events "$(at $1 $2)"; sleep 1
  events "$(button true)"; sleep 1
  events "$(button false)"; sleep 1
}

waits_for() {
  local try
  for try in $(seq 1 30); do
    grep -qE "$1" "$out" 2> /dev/null && return 0
    sleep 1
  done
  fail "no line like '$1' on the serial line; it showed:"
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
      [ "$ok" = 1 ] && { echo "ok - logo-menu: $name"; return 0; }
    fi
    sleep 1
  done
  echo "not ok - logo-menu: $name: got$got, wanted $*"
  exit 1
}

# Waits up to 30 s for run windows to list a window titled About L0S.
about_window() {
  local try from
  for try in $(seq 1 30); do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    sleep 1
    tail -c +$from "$out" | grep -aq 'About L0S' && return 0
  done
  fail "run windows never listed the About window; it showed:"
}

# The logo's pill, 404040, is 3, 16 while the card is open; the card's
# ground, 242424, is 190, 40, inside About's row, past its label.
pill="64 64 64"; card="36 36 36"

waits_for "^l0s> "
shows "closed, at the start" "3 16 0 0 0"

click 16 16
shows "the logo opened the menu: its pill and the card" "3 16 $pill" "190 40 $card"

monitor "sendkey esc"
shows "Esc closed it" "3 16 0 0 0"

click 16 16
shows "opened again" "3 16 $pill"
click 100 50
about_window
echo "ok - logo-menu: About L0S opened its window"
shows "the menu closed" "3 16 0 0 0"

click 16 16
shows "opened a third time" "3 16 $pill"
click 100 92
for try in $(seq 1 30); do
  kill -0 $qemu 2> /dev/null || { echo "ok - logo-menu: Shut Down stopped the board"; exit 0; }
  sleep 1
done
fail "Shut Down left the board running"
