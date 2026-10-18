#!/usr/bin/env bash
# launcher.sh -- boots tests/screen/etc's initramfs with no window: the
# compositor, wm, and no vt. Clicks the top bar's Applications with the
# tablet, through QMP, and checks, by QEMU's screendump:
#
#   1. the launcher open: Applications on its pill, the page's ground,
#      and Terminal's icon, its dark square, in the grid's third cell
#   2. Esc, on the virtio keyboard, closes it: the desktop shows again
#   3. a click on the page, away from the apps, closes it too
#   4. a click on Terminal starts it: run windows, typed at the serial
#      shell, lists vt1's window, in front, and the top bar names the
#      front window's app, Terminal, not its title
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# screen-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/launcher.sock"
qmp="$BUILD/launcher.qmp"
fifo="$BUILD/launcher.in"
out="$BUILD/launcher.out"
dump="$BUILD/launcher.ppm"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"

QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/screen.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - launcher: $1"; sed 's/^/  # /' "$out"; exit 1; }

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

# Where vt1's window is, as run windows lists it, and whether it is in
# front: w_x, w_y, w_front.
window() {
  local try from line
  for try in $(seq 1 30); do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    sleep 1
    line=$(tail -c +$from "$out" | grep -aE '^[0-9]+ vt1 ' | head -1)
    if [ -n "$line" ]; then
      read -r _ _ w_x w_y _ _ w_front <<< "$line"
      return 0
    fi
  done
  fail "run windows never listed vt1's window; it showed:"
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
      [ "$ok" = 1 ] && { echo "ok - launcher: $name"; return 0; }
    fi
    sleep 1
  done
  echo "not ok - launcher: $name: got$got, wanted $*"
  exit 1
}

# The top bar is 32 rows; Applications is its first 120 columns, and
# while the launcher is open a pill, 404040, from 4 to 116 across and 4
# to 28 down, is behind its label, which starts at 12. The page is under
# the bar, 242424. Its four apps, Disks, System Monitor, Terminal and
# Widgets, in the archive's order, are one row of cells 136 wide from
# (1280 - 4 * 136) / 2 = 368, 64 below the bar: Terminal's cell is 640 to
# 776 across and 96 to 200 down on the screen, its icon 48 square at 684,
# 108, a rounded square of dark_3, 3d3846, its prompt's glyph from 8 in.
# The desktop's wallpaper at 0, 32 is 8 19 26, as gpu-screen.sh pins it.
# The front window's app's name starts at 120, 8 down: T's crossbar is
# lit along row 2 of its glyph, from column 0, so 121, 10 is white.
pill="64 64 64"; page="36 36 36"; square="61 56 70"; desk="8 19 26"
headerbar="235 235 235"; ink="255 255 255"

waits_for "^l0s> "
shows "closed, at the start" "8 16 0 0 0" "0 32 $desk"

click 60 16
shows "Applications opened it: the pill, the page, Terminal's icon" \
  "8 16 $pill" "100 700 $page" "0 32 $page" "708 112 $square"

monitor "sendkey esc"
shows "Esc closed it" "8 16 0 0 0" "0 32 $desk"

click 60 16
shows "opened again" "8 16 $pill" "0 32 $page"
click 100 700
shows "a click on the page closed it" "8 16 0 0 0" "0 32 $desk"

click 60 16
shows "opened a third time" "708 112 $square"
click 708 150
window
[ "$w_front" = "front" ] || fail "vt1's window opened, but not in front"
echo "ok - launcher: a click on Terminal started vt1, in front"
shows "its window shown, the launcher closed, the bar naming Terminal" \
  "$((w_x + 6)) $((w_y + 6)) $headerbar" "0 32 $desk" "8 16 0 0 0" "121 10 $ink"
