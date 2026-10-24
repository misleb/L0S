#!/usr/bin/env bash
# files.sh -- boots tests/disks/etc's initramfs, the compositor with no
# window and the disk's driver and file server, on a fresh disk from
# tools/mkdisk. Writes a file on data, types run files & at the serial
# shell, which opens Files (user/apps/files), a window that draws its own
# header bars, learns where it is from run windows (its content at its
# x, y: wm draws no title bar for it), and checks, by QEMU's screendump,
# the tablet through QMP, and the keyboard through the monitor:
#
#   1. its own header bars' ground, ebebeb, the sidebar's, Computer's
#      row selected, and /'s folders' tiles, in the accent
#   2. a click on data's row: it selected, and Computer's not; a double
#      click on its file shows the file's text, and Esc goes back
#   3. a drag of the place's header bar's ground: wm moves the window,
#      as the client's move request asks, and run windows says where
#   4. the toggle to the list: its header's line
#   5. a right click on the file, Rename..., a new name typed, Enter:
#      ls /Volumes/data at the serial shell lists it so
#   6. the menu button's New Folder..., a name, Enter: the folder made
#   7. Delete, and the dialog's Delete: the new folder, selected as it
#      was made, gone
#   8. Volumes, scratch selected, F2, notes, Enter: ls /Volumes lists
#      notes, the volume relabelled
#   9. the header bar's own close button: run windows lists no Files
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# disks-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/files.sock"
qmp="$BUILD/files.qmp"
fifo="$BUILD/files.in"
out="$BUILD/files.out"
dump="$BUILD/files.ppm"
disk="$BUILD/files-test.img"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"
tools/mkdisk "$disk"

QEMU_DISK="$disk" QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/disks.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - files: $1"; sed 's/^/  # /' "$out"; exit 1; }

monitor() { printf '%s\n' "$1" | nc -U -w 1 "$sock" > /dev/null 2>&1; }

# Each key named typed, as the monitor's sendkey names them.
keys() { local k; for k in "$@"; do monitor "sendkey $k"; sleep 0.3; done; }

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
button() { echo "{\"type\":\"btn\",\"data\":{\"down\":$1,\"button\":\"${2:-left}\"}}"; }
click() {
  events "$(at "$1" "$2")"; sleep 1
  events "$(button true "${3:-left}")"; sleep 1
  events "$(button false "${3:-left}")"; sleep 1
}

# A double click at x, y: two clicks well within 400 ms.
dbl() {
  events "$(at "$1" "$2")"; sleep 1
  events "$(button true)"; events "$(button false)"; events "$(button true)"; events "$(button false)"; sleep 1
}

# A drag of the left button from x, y by dx, dy, in four steps.
drag() {
  local i
  events "$(at "$1" "$2")"; sleep 1
  events "$(button true)"; sleep 1
  for i in 1 2 3 4; do
    events "$(at $(($1 + $3 * i / 4)) $(($2 + $4 * i / 4)))"; sleep 0.5
  done
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

# Where Files's window is, as run windows lists it: w_x, w_y; or none,
# w_x empty, if it is not there.
window() {
  local try from line
  w_x=""
  for try in $(seq 1 ${1:-30}); do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    sleep 1
    line=$(tail -c +$from "$out" | grep -aE '^[0-9]+ Files ' | head -1)
    if [ -n "$line" ]; then
      read -r _ _ w_x w_y _ _ _ <<< "$line"
      return 0
    fi
  done
  return 1
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
      [ "$ok" = 1 ] && { echo "ok - files: $name"; return 0; }
    fi
    sleep 1
  done
  echo "not ok - files: $name: got$got, wanted $*"
  exit 1
}

# What the serial shell prints for a command.
said() {
  local from
  from=$(($(wc -c < "$out") + 1))
  printf '%s\n' "$1" >&3
  sleep 2
  tail -c +$from "$out"
}

# Waits up to 20 s for a command's output to hold a line like $2.
said_holds() {
  local try
  for try in $(seq 1 10); do
    said "$1" | grep -qE "$2" && return 0
  done
  return 1
}

# The window is 880 by 560, all of it its content. The sidebar's pane,
# 220 wide: its header bar, 46, then its rows from 52, 48 each,
# Computer, Volumes, data, scratch. A line at 220; the place's pane from
# 221, 659 wide: its header bar, Back at 227, Forward at 267, the path
# bar in the middle, and from 736 the toggle, grid and list 34 each, the
# menu button at 810 and the close button at 850, 24 square from 10
# down. Under it the place, from 46, to the line of what was done: its
# tiles 5 across, 112 by 96, from 270, 58, each's icon 48 square 32 in
# and 12 down; or its list, a header of 32, then rows of 30.
header="235 235 235"; sidebar="235 235 237"; side_sel="217 217 218"; white="255 255 255"
accent="53 132 228"; line="224 224 224"

waits_for "^l0s> "
said 'write /Volumes/data/hello hi' > /dev/null
said 'ls /Volumes/data' | grep -q "hello" || fail "the file was not written; it showed:"
printf 'run files &\n' >&3
waits_for "\[pid [0-9]+ running\]"
window || fail "run windows never listed Files's window; it showed:"
cx=$w_x; cy=$w_y

# Applications, the first of /'s folders: its folder's case, a full row
# 5 of its art, 3 high at scale 3, from 85.
shows "its own header bars, the sidebar, Computer selected, /'s folders" \
  "$((cx + 100)) $((cy + 3)) $header" "$((cx + 300)) $((cy + 3)) $header" \
  "$((cx + 100)) $((cy + 400)) $sidebar" "$((cx + 200)) $((cy + 76)) $side_sel" \
  "$((cx + 320)) $((cy + 86)) $accent"

click $((cx + 100)) $((cy + 172))
shows "data selected, Computer not" "$((cx + 200)) $((cy + 172)) $side_sel" "$((cx + 200)) $((cy + 76)) $sidebar"

# hello, data's one file, its first tile: a double click shows its text,
# rows of a list under a header of its name, whose line is 31 down from
# the header bar; Esc goes back to the tiles.
dbl $((cx + 326)) $((cy + 100))
shows "a double click showed the file" "$((cx + 600)) $((cy + 77)) $line"
keys esc
shows "Esc went back to the tiles" "$((cx + 600)) $((cy + 77)) $white"

drag $((cx + 350)) $((cy + 20)) 100 80
window || fail "run windows lost Files's window; it showed:"
[ "$w_x" = $((cx + 100)) ] && [ "$w_y" = $((cy + 80)) ] || fail "the drag left the window at $w_x, $w_y, not $((cx + 100)), $((cy + 80)); it showed:"
echo "ok - files: its header bar dragged the window"
cx=$w_x; cy=$w_y

click $((cx + 787)) $((cy + 22))
shows "the list, its header's line" "$((cx + 400)) $((cy + 77)) $line" "$((cx + 400)) $((cy + 120)) $white"

# hello, the list's first row, 78 to 108: its menu from where it was
# clicked, 6 in: Open, a line, Rename..., Delete.
click $((cx + 300)) $((cy + 93)) right
click $((cx + 350)) $((cy + 157))
keys backspace backspace backspace backspace backspace g r e e t i n g ret
said_holds 'ls /Volumes/data' "greeting" || fail "Rename... did not rename hello; it showed:"
echo "ok - files: Rename... renamed the file"

# The menu button's menu, 160 wide, kept 6 in from the window's right,
# from 714, under the button, from 43: New Folder... its first row.
click $((cx + 827)) $((cy + 22))
click $((cx + 750)) $((cy + 64))
keys d o c s ret
said_holds 'ls /Volumes/data' "docs" || fail "New Folder... made no folder; it showed:"
echo "ok - files: New Folder... made a folder"

# docs, made, is selected: Delete asks, Tab twice is on the dialog's
# Delete, and Enter presses it; the folder, empty, is gone, and
# greeting stays.
keys delete
sleep 1
keys tab tab ret
said_holds 'ls /Volumes/data' "^  greeting" || fail "greeting went too; it showed:"
if said 'ls /Volumes/data' | grep -q "docs"; then fail "Delete left the folder; it showed:"; fi
echo "ok - files: Delete deleted the folder"

# In /Volumes: data's tile, then scratch's, from 382.
click $((cx + 100)) $((cy + 124))
click $((cx + 438)) $((cy + 100))
keys f2 backspace backspace backspace backspace backspace backspace backspace n o t e s ret
said_holds 'ls /Volumes' "notes" || fail "F2 did not relabel scratch; it showed:"
echo "ok - files: F2 relabelled a volume"

click $((cx + 862)) $((cy + 22))
if window 5; then fail "the close button left the window; it showed:"; fi
echo "ok - files: its own close button closed it"
