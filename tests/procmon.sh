#!/usr/bin/env bash
# procmon.sh -- boots tests/screen/etc's initramfs with no window: the
# compositor, wm, and no vt. Types run procmon & at the serial shell, which
# opens the process monitor (user/apps/procmon) in a window, learns where it is
# from run windows, and checks, by QEMU's screendump:
#
#   1. its title bar, an Adwaita header bar in front, dark, 303030
#   2. the toolbar on the window's ground, 242424; the grid's header's
#      line under it; End Process faded, with no row selected
#   3. a row of its own, pid 8, the eighth by pid, its state's dot drawn;
#      and no ninth row; and under the grid the memory's line, its level
#      bar filled in the accent
#   4. after run nap 600000 & at the shell, a ninth row, nap's (run
#      windows's processes have exited, so are not listed), with nothing
#      pressed: the table is read again by itself
#   5. a click of the tablet, through QMP, on that row: it is selected, in
#      the accent's tint, and End Process its own red
#   6. a click on End Process: the row gone, End Process faded again, and
#      ps at the shell listing no nap
#   7. after five more naps, thirteen rows, more than the ten that fit: the
#      overlay scrollbar's slider, at the top
#   8. a step of the wheel, through QMP, over the rows: three rows
#      scrolled, as far as they go, the slider at the end
#   9. the pointer on the scrollbar's strip: the slider wider and darker
#  10. the slider dragged back up: at the top again
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# screen-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/procmon.sock"
qmp="$BUILD/procmon.qmp"
fifo="$BUILD/procmon.in"
out="$BUILD/procmon.out"
dump="$BUILD/procmon.ppm"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"

QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/screen.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - procmon: $1"; sed 's/^/  # /' "$out"; exit 1; }

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
# A step of the wheel, wheel-down or wheel-up: QEMU's tablet reports the
# press as REL_WHEEL.
wheel() { echo "{\"type\":\"btn\",\"data\":{\"down\":true,\"button\":\"$1\"}},{\"type\":\"btn\",\"data\":{\"down\":false,\"button\":\"$1\"}}"; }
click() {
  events "$(at "$1" "$2")"; sleep 1
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

# Where the monitor's window is, as run windows lists it: w_x, w_y.
window() {
  local try from line
  for try in $(seq 1 30); do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    sleep 1
    line=$(tail -c +$from "$out" | grep -aE '^[0-9]+ Processes ' | head -1)
    if [ -n "$line" ]; then
      read -r _ _ w_x w_y _ _ _ <<< "$line"
      return 0
    fi
  done
  fail "run windows never listed the monitor's window; it showed:"
}

# Pixel x, y of the screendump, a 1280 by 800 PPM whose header is 16 bytes.
pixel() { od -An -tu1 -j $((16 + ($2 * 1280 + $1) * 3)) -N3 "$dump" | tr -s ' ' | sed 's/^ //; s/ $//'; }

# Waits up to 30 s for each "X Y R G B" given to be on the screen, or,
# for "X Y !R G B", for that pixel to be any other color.
shows() {
  local name=$1; shift
  local try p ok got px py r g b want
  for try in $(seq 1 30); do
    rm -f "$dump"
    monitor "screendump $dump"
    if [ -s "$dump" ]; then
      ok=1; got=""
      for p in "$@"; do
        read -r px py r g b <<< "$p"
        got="$got ($px,$py)=$(pixel $px $py)"
        want="${r#!} $g $b"
        if [ "$r" = "${r#!}" ]; then
          [ "$(pixel $px $py)" = "$want" ] || ok=0
        else
          [ "$(pixel $px $py)" != "$want" ] || ok=0
        fi
      done
      [ "$ok" = 1 ] && { echo "ok - procmon: $name"; return 0; }
    fi
    sleep 1
  done
  echo "not ok - procmon: $name: got$got, wanted $*"
  exit 1
}

# The window's content starts under its 46-row header bar, 2 in from its
# left, inside the frame's border. In it: the
# toolbar, 46 rows, its End Process button 88 wide at its right end, 6
# in, from 746, its label, 68 wide in Source Sans 3, from 756; a line; then the grid, its header 32 rows, the last its line, and
# its rows, 30 each, sorted by pid, from 79. The State column runs from
# 190, its dot 8 across from 199, 11 down a row; Memory and Shared from
# 380 and 480; the Detail column from 580, empty for a sleeping process,
# and at most 24 characters, to 781, for a receiving one, so from 800 it
# is the row's ground. The window is 840 wide, and under the grid's 400
# rows is the memory's line.
bar=46
headerbar="48 48 48"; ground="36 36 36"; line="64 64 64"; view="30 30 30"
selected="36 56 80"; red="224 27 36"; faded="130 32 36"

waits_for "^l0s> "
printf 'run procmon &\n' >&3
waits_for "\[pid 8 running\]"
window
cx=$((w_x + 2)); cy=$((w_y + bar))
row() { echo $((cy + 79 + 30 * ($1 - 1))); }
dot() { echo "$((cx + 203)) $(($(row $1) + 15))"; }
endx=$((cx + 750)); endy=$((cy + 22))

shows "its header bar" "$((w_x + 6)) $((w_y + 6)) $headerbar"
shows "the toolbar, the grid's header, End Process faded" \
  "$((cx + 100)) $((cy + 3)) $ground" "$((cx + 5)) $((cy + 78)) $line" "$endx $endy $faded"
shows "its own row, the eighth, and no ninth" "$(dot 8) !$view" "$(dot 9) $view"

# The memory's line under the grid's 400 rows and their line: 6 down,
# Memory in bold, 49 wide, from 12, then 12 on its level bar, 8 high
# in the middle of the line's 16, from 411; the share used is filled in
# the accent, at least 8 of it.
accent="53 132 228"
shows "the memory's line, its level bar filled in the accent" "$((cx + 76)) $((cy + 415)) $accent"

from=$(($(wc -c < "$out") + 1))
printf 'run nap 600000 &\n' >&3
for try in $(seq 1 30); do
  tail -c +$from "$out" | grep -qE "\[pid [0-9]+ running\]" && break
  [ "$try" = 30 ] && fail "nap never started; it showed:"
  sleep 1
done
shows "nap's row, the ninth, read by itself" "$(dot 9) !$view"

click $((cx + 800)) $(($(row 9) + 15))
shows "a click selected nap's row, and End Process woke" \
  "$((cx + 800)) $(($(row 9) + 1)) $selected" "$endx $endy $red"

click $((endx + 20)) $endy
shows "End Process ended nap: its row gone, End Process faded" \
  "$((cx + 800)) $(($(row 9) + 1)) $view" "$(dot 9) $view" "$endx $endy $faded"

from=$(($(wc -c < "$out") + 1))
printf 'ps\n' >&3
sleep 2
listing=$(tail -c +$from "$out")
echo "$listing" | grep -q "PID  PARENT" || fail "ps listed nothing; it showed:"
if echo "$listing" | grep -q " nap "; then fail "ps still lists nap; it showed:"; fi
echo "ok - procmon: ps lists no nap"

# Thirteen rows, ten shown from y 79 to 379: the slider is ten thirteenths
# of the 300, 230 long, so it travels 70. At the top it is from 81 to 307,
# 2 in from each end of its 230, and at the end, three rows on, from 151
# to 377. At rest it is 6 wide, 3 in from the grid's right edge at 840,
# from x 831, the text, white, at 40% on the view's 1e1e1e, 787878;
# with the pointer on its strip, 8 wide, from 829, at 60%, a5a5a5.
for n in 1 2 3 4 5; do printf 'run nap 600000 &\n' >&3; sleep 1; done
gx=$((cx + 833)); wide=$((cx + 830))
slider="120 120 120"; slider_hot="165 165 165"
shows "thirteen rows, the slider at the top" "$gx $((cy + 100)) $slider" "$gx $((cy + 360)) $view"

# The pointer in the middle of the fifth row, on its empty detail: the
# row under it is tinted, 4% of the text on the view's ground, 39,
# before the wheel turns and after, though another row is under it then.
hovered="39 39 39"
events "$(at $((cx + 800)) $(($(row 5) + 15)))"; sleep 1
events "$(wheel wheel-down)"; sleep 1
shows "a step of the wheel scrolled to the end, the row now under the pointer tinted" \
  "$gx $((cy + 100)) $view" "$gx $((cy + 360)) $slider" "$((cx + 800)) $(($(row 5) + 15)) $hovered" "$((cx + 800)) $(($(row 2) + 15)) $view"

events "$(at $gx $((cy + 360)))"; sleep 1
shows "the pointer on the strip: the slider wide and dark" "$wide $((cy + 360)) $slider_hot"

events "$(button true)"; sleep 1
events "$(at $gx $((cy + 230)))"; sleep 1
events "$(at $gx $((cy + 100)))"; sleep 1
events "$(button false)"; sleep 1
shows "the slider dragged back to the top" "$gx $((cy + 100)) $slider_hot" "$gx $((cy + 360)) $view"
