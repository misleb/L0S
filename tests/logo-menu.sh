#!/usr/bin/env bash
# logo-menu.sh -- boots tests/screen/etc's initramfs with no window: the
# compositor, wm, and no vt. Clicks the top bar's logo with the tablet,
# through QMP, and checks, by QEMU's screendump and the serial shell:
#
#   1. the menu open: the logo on its pill, the card's ground under the bar
#   2. Esc, on the virtio keyboard, closes it
#   3. About L0S starts the About window: run windows lists it
#   4. Restart resets the board: the kernel says so, and boots again
#   5. Shut Down kills pid 1: QEMU exits by itself
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
      [ "$ok" = 1 ] && { echo "ok - logo-menu: $name"; return 0; }
    fi
    sleep 0.2
  done
  echo "not ok - logo-menu: $name: got$got, wanted $*"
  exit 1
}

# Waits up to 30 s for run windows to list a window titled About L0S,
# and up to 5 s each time for the shell's prompt after the list.
about_window() {
  local from prompt end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    prompt=$((SECONDS + 5))
    until [ $SECONDS -ge $prompt ] || tail -c +$from "$out" | grep -aq 'l0s> '; do sleep 0.1; done
    tail -c +$from "$out" | grep -aq 'About L0S' && return 0
    sleep 0.2
  done
  fail "run windows never listed the About window; it showed:"
}

# The logo's pill, 404040, is 3, 16 while the card is open; the card's
# ground, 242424, is 190, 40, inside About's row, past its label.
pill="64 64 64"; card="36 36 36"

waits_for "^l0s> "
# wm says it serves once the display has drawn the wallpaper, which may
# come after the prompt: wait, so the logo's click reaches it.
waits_for "serving compositor"
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

# Restart, the card's third row, 110 to 140 on the screen: the board
# resets and QEMU boots it again, its banner a second time.
click 16 16
shows "opened a third time" "3 16 $pill"
click 100 124
waits_for "l0s: restarting the board, as wm \(pid [0-9]+\) asked"
end=$((SECONDS + 30))
until [ $SECONDS -ge $end ]; do
  [ "$(grep -c '^l0s: aarch64' "$out")" -ge 2 ] && break
  sleep 0.2
done
[ "$(grep -c '^l0s: aarch64' "$out")" -ge 2 ] || fail "Restart did not boot the board again; it showed:"
echo "ok - logo-menu: Restart reset the board, and it booted again"
# The second boot's prompt, and its wm serving, up to 30 s, before the
# next click.
end=$((SECONDS + 30))
until [ $SECONDS -ge $end ]; do
  [ "$(grep -c '^l0s> ' "$out")" -ge 2 ] && [ "$(grep -c 'serving compositor' "$out")" -ge 2 ] && break
  sleep 0.2
done
shows "the desktop again, the menu closed" "3 16 0 0 0"

click 16 16
shows "opened after the restart" "3 16 $pill"
click 100 92
end=$((SECONDS + 30))
until [ $SECONDS -ge $end ]; do
  kill -0 $qemu 2> /dev/null || { echo "ok - logo-menu: Shut Down stopped the board"; exit 0; }
  sleep 0.2
done
fail "Shut Down left the board running"
