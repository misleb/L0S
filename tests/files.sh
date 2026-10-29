#!/usr/bin/env bash
# files.sh -- boots tests/disks/etc's initramfs, the compositor with no
# window and the disk's driver and file server, on a fresh disk from
# tools/mkdisk. Writes a file on data, types run files & at the serial
# shell, which opens Files (user/apps/files), a window that draws its own
# header bars, learns where it is from run windows (its content at its
# x, y: wm draws no title bar for it), and checks, by QEMU's screendump,
# the tablet through QMP, and the keyboard through the monitor:
#
#   1. its own header bars' ground, 303030, the sidebar's, Computer's
#      row selected, and /'s folders' tiles, in the accent
#   2. a click on data's row: it selected, and Computer's not; a double
#      click on its file shows the file's text, and Esc goes back
#   3. a drag of the place's header bar's ground: wm moves the window,
#      as the client's move request asks, and run windows says where;
#      a double click there maximizes it, and another restores it; and
#      drags from inside its right edge, its bottom left corner and its
#      bottom resize it, as the client's edges request asks
#   4. the toggle to the list: its header's line
#   5. a right click on the file, Rename..., a new name typed, Enter:
#      ls /Volumes/data at the serial shell lists it so
#   6. the menu button's New Folder..., a name, Enter: the folder made
#   7. Delete, and the dialog's Delete: the new folder, selected as it
#      was made, gone
#   8. Volumes, scratch selected, F2, notes, Enter: ls /Volumes lists
#      notes, the volume relabelled
#   9. the window taken to 0, 32, and the menu button's New Window: run
#      windows lists two Files windows of one client; the new one taken
#      to 400, 240; a click on each, the new one's Computer and the
#      first's data, changes that one alone
#  10. the first's own close button: the new one stays
#  11. the new one's close button: run windows lists no Files
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

monitor() { printf '%s\n' "$1" | tools/qsock "$sock" > /dev/null 2>&1; }

# Each key named typed, as the monitor's sendkey names them.
keys() { local k; for k in "$@"; do monitor "sendkey $k"; sleep 0.1; done; }

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
button() { echo "{\"type\":\"btn\",\"data\":{\"down\":$1,\"button\":\"${2:-left}\"}}"; }
# A click at x, y, of the left button or the one named. What it does is
# waited for by what checks it, not here.
click() {
  events "$(at "$1" "$2")"; sleep 0.1
  events "$(button true "${3:-left}")"; sleep 0.1
  events "$(button false "${3:-left}")"
}

# A double click at x, y: two clicks well within 400 ms, each press and
# release its own input-send-event, so its own report, all four on one
# connection.
dbl() {
  local b
  events "$(at "$1" "$2")"; sleep 0.1
  {
    printf '{"execute":"qmp_capabilities"}\n'
    for b in true false true false; do
      printf '{"execute":"input-send-event","arguments":{"events":[%s]}}\n' "$(button $b)"
    done
  } | tools/qsock "$qmp" > /dev/null 2>&1
}

# A drag of the left button from x, y by dx, dy, in four steps.
drag() {
  local i
  events "$(at "$1" "$2")"; sleep 0.2
  events "$(button true)"; sleep 0.2
  for i in 1 2 3 4; do
    events "$(at $(($1 + $3 * i / 4)) $(($2 + $4 * i / 4)))"; sleep 0.2
  done
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

# What the serial shell prints for a command, up to its next prompt,
# waited for up to 5 s, so that no answer comes late into the next's.
said() {
  local from end=$((SECONDS + 5))
  from=$(($(wc -c < "$out") + 1))
  printf '%s\n' "$1" >&3
  until [ $SECONDS -ge $end ] || tail -c +$from "$out" | grep -aq 'l0s> '; do sleep 0.1; done
  tail -c +$from "$out"
}

# Where Files's window is, as run windows lists it: w_x, w_y, and its
# size, w_w, w_h; or none, w_x empty, if it is not there. Asks for up
# to 30 s until it is.
window() {
  local line end=$((SECONDS + 30))
  w_x=""
  until [ $SECONDS -ge $end ]; do
    line=$(said 'run windows' | sed 's/^l0s> //' | grep -aE '^[0-9]+ Files ' | head -1)
    if [ -n "$line" ]; then
      read -r _ _ w_x w_y w_w w_h _ <<< "$line"
      return 0
    fi
    sleep 0.2
  done
  return 1
}

# Waits up to 30 s for Files's window to be at "X Y", or at and as big
# as "X Y W H".
window_at() {
  local end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    window && { [ "$w_x $w_y $w_w $w_h" = "$1" ] || [ "$w_x $w_y" = "$1" ]; } && return 0
    sleep 0.2
  done
  return 1
}

# Waits up to 10 s for run windows to list no Files window.
no_window() {
  local end=$((SECONDS + 10))
  until [ $SECONDS -ge $end ]; do
    said 'run windows' | grep -aqE '^(l0s> )?[0-9]+ Files ' || return 0
    sleep 0.2
  done
  return 1
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
      [ "$ok" = 1 ] && { echo "ok - files: $name"; return 0; }
    fi
    sleep 0.2
  done
  echo "not ok - files: $name: got$got, wanted $*"
  exit 1
}

# Pixel x, y of the screen as it is now, in $seen.
look() { rm -f "$dump"; monitor "screendump $dump"; seen=$(pixel "$1" "$2"); }

# Waits up to 30 s for pixel x, y to be other than R G B: something,
# such as a menu or a dialog, drawn over it.
leaves() {
  local name=$1 px py r g b end=$((SECONDS + 30))
  read -r px py r g b <<< "$2"
  until [ $SECONDS -ge $end ]; do
    look $px $py
    [ -n "$seen" ] && [ "$seen" != "$r $g $b" ] && return 0
    sleep 0.2
  done
  fail "$name: ($px,$py) stayed $r $g $b; it showed:"
}

# A click at x, y that opens a menu, then, once the menu shows at ix,
# iy, a click on its item there.
menu() {
  look "$3" "$4"
  local was=$seen
  click "$1" "$2" "${5:-left}"
  leaves "a menu at $1, $2" "$3 $4 $was"
  click "$3" "$4"
}

# Waits up to 30 s for a dialog over the window at cx, cy: its header
# bar dimmed beneath it.
dialog() { leaves "a dialog" "$((cx + 100)) $((cy + 3)) $header"; }

# Waits up to 20 s for a command's output to hold a line like $2.
said_holds() {
  local end=$((SECONDS + 20))
  until [ $SECONDS -ge $end ]; do
    said "$1" | grep -qE "$2" && return 0
    sleep 0.2
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
header="48 48 48"; sidebar="46 46 50"; side_sel="67 67 71"; view="30 30 30"
accent="53 132 228"; line="64 64 64"

waits_for "^l0s> "
said 'write /Volumes/data/hello hi' > /dev/null
said 'ls /Volumes/data' | grep -q "hello" || fail "the file was not written; it showed:"
printf 'run files &\n' >&3
waits_for "\[pid [0-9]+ running\]"
window || fail "run windows never listed Files's window; it showed:"
cx=$w_x; cy=$w_y

# Applications, the first of /'s folders: its icon, Adwaita's full-color
# folder at 48, from 302, 70, its front light blue at 326, 100; and the
# Computer row's, Adwaita's computer at 32, from 14, 58, its screen blue
# at 30, 73.
folder="164 202 238"; computer="69 140 226"
shows "its own header bars, the sidebar, Computer selected, /'s folders" \
  "$((cx + 100)) $((cy + 3)) $header" "$((cx + 300)) $((cy + 3)) $header" \
  "$((cx + 100)) $((cy + 400)) $sidebar" "$((cx + 200)) $((cy + 76)) $side_sel" \
  "$((cx + 326)) $((cy + 100)) $folder" "$((cx + 30)) $((cy + 73)) $computer"

click $((cx + 100)) $((cy + 172))
shows "data selected, Computer not" "$((cx + 200)) $((cy + 172)) $side_sel" "$((cx + 200)) $((cy + 76)) $sidebar"

# hello, data's one file, its first tile: a double click shows its text,
# rows of a list under a header of its name, whose line is 31 down from
# the header bar; Esc goes back to the tiles.
dbl $((cx + 326)) $((cy + 100))
shows "a double click showed the file" "$((cx + 600)) $((cy + 77)) $line"
keys esc
shows "Esc went back to the tiles" "$((cx + 600)) $((cy + 77)) $view"

drag $((cx + 350)) $((cy + 20)) 100 80
window_at "$((cx + 100)) $((cy + 80))" || fail "the drag left the window at $w_x, $w_y, not $((cx + 100)), $((cy + 80)); it showed:"
echo "ok - files: its header bar dragged the window"
cx=$w_x; cy=$w_y; cw=$w_w; ch=$w_h

# A double click on the header bar's ground maximizes the window: all of
# the screen under the top bar, 1280 by 768 from 0, 32. Another, where
# the ground is then, restores its place and size.
dbl $((cx + 350)) $((cy + 20))
window_at "0 32 1280 768" || fail "a double click on the header bar left the window at $w_x, $w_y, $w_w by $w_h, not maximized; it showed:"
echo "ok - files: a double click on its header bar maximized it"
dbl 350 52
window_at "$cx $cy $cw $ch" || fail "a second double click left the window at $w_x, $w_y, $w_w by $w_h, not $cx, $cy, $cw by $ch; it showed:"
echo "ok - files: another restored it"

# A press inside the window's edge, 3 deep, which the client asks wm to
# resize it by: its right side, 2 in, dragged 60 right, makes it 60
# wider; its bottom left, 2 in from the left and 15 up from the bottom,
# clear of the corner wm cuts, dragged 60 right and 40 down, moves its
# left side and makes it 40 taller; and its bottom, 2 up, 40 up, puts its
# height back. None of these is in the border outside, which is wm's.
drag $((cx + cw - 2)) $((cy + 300)) 60 0
window_at "$cx $cy $((cw + 60)) $ch" || fail "a drag inside the right edge left the window at $w_x, $w_y, $w_w by $w_h, not $cx, $cy, $((cw + 60)) by $ch; it showed:"
echo "ok - files: a drag inside its right edge widened it"
drag $((cx + 2)) $((cy + ch - 15)) 60 40
window_at "$((cx + 60)) $cy $cw $((ch + 40))" || fail "a drag inside the bottom left corner left the window at $w_x, $w_y, $w_w by $w_h, not $((cx + 60)), $cy, $cw by $((ch + 40)); it showed:"
echo "ok - files: a drag inside its bottom left corner resized it"
drag $((cx + 360)) $((cy + ch + 38)) 0 -40
window_at "$((cx + 60)) $cy $cw $ch" || fail "a drag inside the bottom edge left the window at $w_x, $w_y, $w_w by $w_h, not $((cx + 60)), $cy, $cw by $ch; it showed:"
echo "ok - files: a drag inside its bottom edge put its height back"
cx=$((cx + 60))

click $((cx + 787)) $((cy + 22))
shows "the list, its header's line" "$((cx + 400)) $((cy + 77)) $line" "$((cx + 400)) $((cy + 120)) $view"

# hello, the list's first row, 78 to 108: its menu from where it was
# clicked, 6 in: Open, a line, Rename..., Delete.
menu $((cx + 300)) $((cy + 93)) $((cx + 350)) $((cy + 157)) right
dialog
keys backspace backspace backspace backspace backspace g r e e t i n g ret
said_holds 'ls /Volumes/data' "greeting" || fail "Rename... did not rename hello; it showed:"
echo "ok - files: Rename... renamed the file"

# The menu button's menu, 160 wide, kept 6 in from the window's right,
# from 714, under the button, from 43: New Folder... its first row.
menu $((cx + 827)) $((cy + 22)) $((cx + 750)) $((cy + 64))
dialog
keys d o c s ret
said_holds 'ls /Volumes/data' "docs" || fail "New Folder... made no folder; it showed:"
echo "ok - files: New Folder... made a folder"

# docs, made, is selected: Delete asks, Tab twice is on the dialog's
# Delete, and Enter presses it; the folder, empty, is gone, and
# greeting stays.
keys delete
dialog
keys tab tab ret
said_holds 'ls /Volumes/data' "^  greeting" || fail "greeting went too; it showed:"
if said 'ls /Volumes/data' | grep -q "docs"; then fail "Delete left the folder; it showed:"; fi
echo "ok - files: Delete deleted the folder"

# In /Volumes, still a list: Volumes's row in the sidebar, then
# scratch's, the list's second, 108 to 138, selected, in the selection's
# tint once the pointer is off it, before F2.
row_sel="36 56 80"
click $((cx + 100)) $((cy + 124))
shows "Volumes selected" "$((cx + 200)) $((cy + 124)) $side_sel"
click $((cx + 438)) $((cy + 123))
events "$(at $((cx + 100)) $((cy + 400)))"
shows "scratch's row selected" "$((cx + 600)) $((cy + 123)) $row_sel" "$((cx + 600)) $((cy + 93)) $view"
keys f2
dialog
keys backspace backspace backspace backspace backspace backspace backspace n o t e s ret
said_holds 'ls /Volumes' "notes" || fail "F2 did not relabel scratch; it showed:"
echo "ok - files: F2 relabelled a volume"

# Every Files window listed, front first: n_lines of them, f_* the
# front one's id, place, size and client's pid, b_* the one behind's;
# and if "X Y" is given, the front one there. Asks for up to 30 s.
files_windows() {
  local lines end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    lines=$(said 'run windows' | sed 's/^l0s> //' | grep -aE '^[0-9]+ Files ')
    if [ "$(printf '%s\n' "$lines" | grep -c .)" = "$1" ]; then
      read -r f_id _ f_x f_y _ _ _ f_pid _ <<< "$(printf '%s\n' "$lines" | sed -n 1p)"
      read -r b_id _ b_x b_y _ _ _ b_pid _ <<< "$(printf '%s\n' "$lines" | sed -n 2p)"
      [ -z "${2:-}" ] || [ "$f_x $f_y" = "$2" ] && return 0
    fi
    sleep 0.2
  done
  return 1
}

# The window taken to the top left, 0, 32, so that a second can be put
# where both show: New Window, the menu button's second row, 30 under
# New Folder..., opens one more in front, of the same client, at the
# same place.
drag $((cx + 350)) $((cy + 20)) $((0 - cx)) $((32 - cy))
window_at "0 32" || fail "the drag left the window at $w_x, $w_y, not 0, 32; it showed:"
cx=0; cy=32
menu $((cx + 827)) $((cy + 22)) $((cx + 750)) $((cy + 94))
files_windows 2 || fail "New Window did not make two Files windows; it showed:"
[ "$f_pid" = "$b_pid" ] || fail "the two windows are of pids $f_pid and $b_pid, not one client; it showed:"
[ "$b_x $b_y" = "0 32" ] || fail "the first window is not behind the new one; it showed:"
echo "ok - files: New Window opened a second window, of the same client, pid $f_pid"
first=$b_id

# The new one taken to 400, 240, over the first's right and foot: the
# first's sidebar shows left of it, its close button above it.
drag $((f_x + 350)) $((f_y + 20)) $((400 - f_x)) $((240 - f_y))
files_windows 2 "400 240" || fail "the drag left the new window at $f_x, $f_y, not 400, 240; it showed:"
nx=400; ny=240
shows "both at /Volumes, its row selected in each" \
  "$((nx + 200)) $((ny + 124)) $side_sel" "$((cx + 200)) $((cy + 124)) $side_sel"

# A click on the new one's Computer: it goes to /, and the first stays.
click $((nx + 100)) $((ny + 76))
shows "the new window went to /, the first did not" \
  "$((nx + 200)) $((ny + 76)) $side_sel" "$((nx + 200)) $((ny + 124)) $sidebar" \
  "$((cx + 200)) $((cy + 124)) $side_sel" "$((cx + 200)) $((cy + 76)) $sidebar"

# A click on the first's data: it comes to the front and goes there, and
# the new one stays at /, seen once a press on its sidebar's empty foot,
# under the first, brings it back.
click $((cx + 100)) $((cy + 172))
shows "the first went to data, in front" "$((cx + 200)) $((cy + 172)) $side_sel" "$((cx + 200)) $((cy + 124)) $sidebar"
click $((nx + 100)) $((ny + 500))
shows "the new window still at /, the first still at data" \
  "$((nx + 200)) $((ny + 76)) $side_sel" "$((nx + 200)) $((ny + 172)) $sidebar" "$((cx + 200)) $((cy + 172)) $side_sel"

# The first's own close button, 862, 22 in it, above the new one: it
# closes, and the new one stays.
click $((cx + 862)) $((cy + 22))
files_windows 1 || fail "the first's close button did not leave one Files window; it showed:"
[ "$f_id $f_x $f_y" != "$first 0 32" ] || fail "the close button closed the new window, not the first; it showed:"
echo "ok - files: the first's close button closed it, and the new one stayed"
cx=$nx; cy=$ny

click $((cx + 862)) $((cy + 22))
no_window || fail "the close button left the window; it showed:"
echo "ok - files: its own close button closed its last window"
