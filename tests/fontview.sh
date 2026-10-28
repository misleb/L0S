#!/usr/bin/env bash
# fontview.sh -- boots tests/screen/etc's initramfs with no window, opens
# Fonts from the launcher with the tablet, through QMP, and checks, by
# QEMU's screendump:
#
#   1. Fonts' window: four cards, one for each face font names, each
#      "Aa" in its face, and no fifth
#   2. a click on Source Sans 3's card opens it: its pangram at 64, in
#      which the i of big is narrower than the m of my
#   3. Back, then Source Code Pro's card: the same pangram, its m and i
#      each in a cell of 32, at 14 and 18 cells along, the same width
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# screen-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/fontview.sock"
qmp="$BUILD/fontview.qmp"
fifo="$BUILD/fontview.in"
out="$BUILD/fontview.out"
dump="$BUILD/fontview.ppm"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"

QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/screen.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - fontview: $1"; sed 's/^/  # /' "$out"; exit 1; }

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

# Where Fonts' window is, as run windows lists it: w_x, w_y.
window() {
  local try from line
  for try in $(seq 1 30); do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    sleep 1
    line=$(tail -c +$from "$out" | grep -aE '^[0-9]+ Fonts ' | head -1)
    if [ -n "$line" ]; then
      read -r _ _ w_x w_y _ <<< "$line"
      return 0
    fi
  done
  fail "run windows never listed Fonts' window; it showed:"
}

# Pixel x, y of the screendump, a 1280 by 800 PPM whose header is 16 bytes.
pixel() { od -An -tu1 -j $((16 + ($2 * 1280 + $1) * 3)) -N3 "$dump" | tr -s ' ' | sed 's/^ //; s/ $//'; }

# A screendump taken, in $dump.
dumped() { rm -f "$dump"; monitor "screendump $dump"; [ -s "$dump" ]; }

# The first and last columns from x0 up to x1 of row y that are not the
# view's ground, as "FIRST LAST", or "none".
ink() {
  local x first="" last=""
  for x in $(seq $1 $(($2 - 1))); do
    if [ "$(pixel $x $3)" != "$ground" ]; then
      [ -z "$first" ] && first=$x
      last=$x
    fi
  done
  if [ -z "$first" ]; then echo none; else echo "$first $last"; fi
}

# Waits up to 30 s for ink to say $4 of columns $1 up to $2 of row $3,
# relative to cx; "some" is any ink.
ink_is() {
  local try got
  for try in $(seq 1 30); do
    if dumped; then
      got=$(ink $((cx + $1)) $((cx + $2)) $3)
      if [ "$4" = some ]; then [ "$got" != none ] && { echo "$got"; return 0; }
      else [ "$got" = "$4" ] && { echo "$got"; return 0; }; fi
    fi
    sleep 1
  done
  echo "not ok - fontview: $5: ink $got, wanted $4"
  exit 1
}

# Fonts is the fourth of the seven apps, About, Disks, Files, Fonts,
# System Monitor, Terminal and Widgets, in cells 136 wide from 164, so
# its cell is from 572, its icon, 48 square, from 616, 108.
#
# Its window draws its own header bar, so its content is the window:
# under the 46 rows of the header bar, the grid of cards on the view's
# ground, 1e1e1e, tiles 112 by 96 from 38, 58, each its face's "Aa" 48
# square, 32 in and 12 down, so from 70 + 112 i, 70, and a row 30 into
# them, 100, crosses the a's bowl and the A.
#
# A face's page: the pangram at 64 from 18, 449 (fontview_test.l0's
# test_page), "Jackdaws love my big sphinx of quartz", and row 38 of its
# line is in the x-height. In Source Sans 3 the pens of my's m and y are
# 334 and 378, of big's i and g 443 and 457, its advances and kerning
# summed at a line of 64 (ui_text_pen); the strike's m inks 338 to 374
# of that row, its i 447 to 451. In Source Code Pro each pen is 32 on: m
# at 448, i at 576; its m inks 451 to 477, its i 592 to 597, each inside
# its cell. Only its first 22 characters show there, and "...".
ground="30 30 30"

waits_for "^l0s> "
# wm says it serves once the display has drawn the wallpaper, which may
# come after the prompt: wait, so the launcher's click reaches it.
waits_for "serving compositor"
click 60 16
click 640 130
window
cx=$w_x; cy=$w_y
echo "ok - fontview: the launcher opened Fonts, at $cx, $cy"

for i in 0 1 2 3; do
  got=$(ink_is $((70 + 112 * i)) $((118 + 112 * i)) $((cy + 100)) some "card $i's Aa") || { echo "$got"; exit 1; }
done
echo "ok - fontview: four cards, each its Aa"
ink_is 518 566 $((cy + 100)) none "no fifth card" > /dev/null || exit 1
echo "ok - fontview: no fifth card"

y=$((cy + 449 + 38))
click $((cx + 318)) $((cy + 106))
got=$(ink_is $((18 + 443)) $((18 + 457)) $y "$((cx + 18 + 447)) $((cx + 18 + 451))" "Source Sans 3's i") || { echo "$got"; exit 1; }
got=$(ink_is $((18 + 334)) $((18 + 378)) $y "$((cx + 18 + 338)) $((cx + 18 + 374))" "Source Sans 3's m") || { echo "$got"; exit 1; }
echo "ok - fontview: Source Sans 3 at 64, its i 5 wide, narrower than its m, 37"

click $((cx + 23)) $((cy + 22))
got=$(ink_is $((18 + 443)) $((18 + 457)) $y none "back at the grid, no pangram") || { echo "$got"; exit 1; }
click $((cx + 94)) $((cy + 106))
got=$(ink_is $((18 + 576)) $((18 + 608)) $y "$((cx + 18 + 592)) $((cx + 18 + 597))" "Source Code Pro's i") || { echo "$got"; exit 1; }
got=$(ink_is $((18 + 448)) $((18 + 480)) $y "$((cx + 18 + 451)) $((cx + 18 + 477))" "Source Code Pro's m") || { echo "$got"; exit 1; }
echo "ok - fontview: Source Code Pro at 64, its i and m each in a cell of 32, the same width"
