#!/usr/bin/env bash
# launcher-install.sh -- boots tests/launcher-install/etc's initramfs, copied
# onto the System volume of a disk and booted from it with root=, so that
# / is writable: the compositor, wm, with no window. At the serial shell it
# installs an app, a bundle Extra.app in /Applications, made of a copy of
# Terminal's program and icon and a manifest of its own, and checks, by
# QEMU's screendump, that the launcher shows it once it is opened again:
#
#   1. the launcher opened: seven apps, Terminal's icon in the sixth cell
#      and none where Extra's will be
#   2. Esc closes it; Extra.app is installed from the shell
#   3. Applications opens it again: an eighth app, Extra, in the third cell,
#      with Terminal's icon, and Terminal in the seventh
#   4. a click on Extra starts it: run windows lists vt1's window in front,
#      and the top bar names the front window's app, Extra
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# launcher-install-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/launcher-install.sock"
qmp="$BUILD/launcher-install.qmp"
fifo="$BUILD/launcher-install.in"
out="$BUILD/launcher-install.out"
dump="$BUILD/launcher-install.ppm"
disk="$BUILD/launcher-install.img"
uuid=018f4c30-0000-7000-8000-000000000001
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"
tools/mkdisk "$disk" 131072 "System:40:110000:$BUILD/launcher-install.cpio:$uuid" data:110040:20998 > /dev/null

QEMU_DISK="$disk" QEMU_APPEND="root=$uuid" \
  QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/launcher-install.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - launcher-install: $1"; sed 's/^/  # /' "$out"; exit 1; }

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
  for try in $(seq 1 60); do
    grep -qE "$1" "$out" 2> /dev/null && return 0
    sleep 1
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# Types a line at the serial shell, and waits for it to answer with its
# prompt again, up to 60 s.
typed() {
  local before try
  before=$(grep -ac '^l0s> ' "$out")
  printf '%s\n' "$1" >&3
  for try in $(seq 1 60); do
    [ "$(grep -ac '^l0s> ' "$out")" -gt "$before" ] && return 0
    sleep 1
  done
  fail "the shell did not answer '$1' with a prompt; it showed:"
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
      read -r _ _ w_x w_y _ _ w_front _ <<< "$line"
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
      [ "$ok" = 1 ] && { echo "ok - launcher-install: $name"; return 0; }
    fi
    sleep 1
  done
  echo "not ok - launcher-install: $name: got$got, wanted $*"
  exit 1
}

# The geometry is launcher.sh's. Seven apps, About, Disks, Files, Fonts,
# System Monitor, Terminal and Widgets, are cells 136 wide from (1280 -
# 7 * 136) / 2 = 164, so the second cell starts at 300, its icon, 48
# square, 44 in, at 344, and its pixel 336, 138 is the page's; Terminal,
# the sixth, at 844, has its icon at 888, so 920, 138, 32 in and 30
# down, is on its screen, 241f31. An eighth app, the volume's listing
# being sorted by name, About, Disks, Extra, Files, Fonts, System
# Monitor, Terminal, Widgets, moves the grid to start at (1280 - 8 *
# 136) / 2 = 96: Extra's cell is 368 across, its icon, Terminal's, at
# 412, so 444, 138 is on it, and Terminal's, the seventh, at 912 across,
# has its at 956, so 988, 138 is on that, and 900, 138, past System
# Monitor's icon, is the page's.
page="36 36 36"; screen="36 31 49"; headerbar="48 48 48"; ink="255 255 255"
desk="15 26 39"

waits_for "^l0s> "
shows "closed, at the start" "40 16 0 0 0" "0 32 $desk"

click 60 16
shows "seven apps: Terminal's icon, and none at the second cell's edge" \
  "0 32 $page" "920 138 $screen" "336 138 $page"

monitor "sendkey esc"
shows "Esc closed it" "40 16 0 0 0" "0 32 $desk"

typed "mkdir /Applications/Extra.app"
typed "cp /Applications/Terminal.app/vt /Applications/Extra.app/vt"
typed "cp /Applications/Terminal.app/icon.ppm /Applications/Extra.app/icon.ppm"
typed "write /Applications/Extra.app/manifest name Extra"
typed "append /Applications/Extra.app/manifest exec vt"
typed "append /Applications/Extra.app/manifest icon icon.ppm"
echo "ok - launcher-install: Extra.app installed from the shell"

click 60 16
shows "opened again: Extra's icon in the third cell, Terminal's in the seventh" \
  "0 32 $page" "444 138 $screen" "988 138 $screen" "900 138 $page"

click 436 150
window
[ "$w_front" = "front" ] || fail "vt1's window opened, but not in front"
echo "ok - launcher-install: a click on Extra started vt1, in front"
# The bar names the window's app, Extra, from 126: Source Sans 3's E at
# 16 has its box a pixel past the pen, 2 down; its top arm is lit along
# row 10, 4 of 15 at 128, as T's crossbar is, and its stem down the left
# of its box, 12 of 15 at 127, 16, where T has none; each pixel is the
# smooth glyph's partial cover on black, 27% and 80%, not white.
shows "its window shown, the launcher closed, the bar naming Extra" \
  "$((w_x + 6)) $((w_y + 6)) $headerbar" "0 32 $desk" "128 10 69 69 69" "127 16 204 204 204"
