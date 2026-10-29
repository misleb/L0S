#!/usr/bin/env bash
# widgets.sh -- boots tests/screen/etc's initramfs with no window: the
# compositor, wm, and no vt. Types run widgets & at the serial shell, which
# opens the toolkit's gallery (user/apps/widgets) in a window, learns where it
# is from run windows, and checks, by QEMU's screendump:
#
#   1. its title bar, an Adwaita header bar in front, dark, 303030
#   2. the toolbar on the window's ground, 242424; the grid's header's
#      line under it; End Process faded, with no row selected; and the
#      toolbar's line in Source Sans 3, its i narrower than its m, each
#      where the sums of the advances put it
#   3. a click of the tablet, through QMP, on the second row: the
#      pointer's press and release forwarded to the window, the row
#      selected, in the accent's tint, and End Process its own red; then
#      the focus ring, on Refresh after Tab, on End Process after Tab
#      again, and back on Refresh after Shift-Tab, the key's modifier
#      come through wm and the toolkit; and, as run windows lists them,
#      each Tab's change shown from the window's other buffer, its id
#      flipping between 4 and 6, and a frame told for each (roadmap
#      0006)
#   4. the tab bar along its foot, AdwTabBar's: three tabs, the first
#      raised; a click on the third raises it instead, and a click on
#      the second's close button closes it, the two left sharing the bar
#   5. the title bar's close button: wm asks the gallery to close, the
#      toolkit closes it for the gallery, and run windows lists none
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# screen-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/widgets.sock"
qmp="$BUILD/widgets.qmp"
fifo="$BUILD/widgets.in"
out="$BUILD/widgets.out"
dump="$BUILD/widgets.ppm"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"

QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/screen.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - widgets: $1"; sed 's/^/  # /' "$out"; exit 1; }

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

waits_for() {
  local try
  for try in $(seq 1 30); do
    grep -qE "$1" "$out" 2> /dev/null && return 0
    sleep 1
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# Where the gallery's window is, as run windows lists it: w_x, w_y.
window() {
  local try from line
  for try in $(seq 1 30); do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    sleep 1
    line=$(tail -c +$from "$out" | grep -aE '^[0-9]+ Widgets ' | head -1)
    if [ -n "$line" ]; then
      read -r _ _ w_x w_y _ _ _ <<< "$line"
      return 0
    fi
  done
  fail "run windows never listed the gallery's window; it showed:"
}

# The buffer the gallery's window shows and the frames its client has
# been told, as run windows lists them: w_buf, w_frames.
paced() {
  local try from line
  for try in $(seq 1 30); do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    sleep 1
    line=$(tail -c +$from "$out" | grep -aE '^[0-9]+ Widgets .* buffer [0-9]+ frames [0-9]+' | head -1)
    if [ -n "$line" ]; then
      read -r _ _ _ _ _ _ _ _ _ w_buf _ w_frames _ <<< "$line"
      return 0
    fi
  done
  fail "run windows never listed the gallery's buffer and frames; it showed:"
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
      [ "$ok" = 1 ] && { echo "ok - widgets: $name"; return 0; }
    fi
    sleep 1
  done
  echo "not ok - widgets: $name: got$got, wanted $*"
  exit 1
}

# The window's content starts under its 46-row header bar, 2 in from its
# left, inside the frame's border. In it: the
# toolbar, 46 rows, its End Process button at its right end, 6 in, its
# label 68 wide in Source Sans 3 and 10 either side, 88, so from 546 and
# its label from 556; a line; then the grid, its header 32 rows, the last its line, and
# its rows, 30 each, sorted by pid. A row's Name column runs from 70 to
# 300, its text at its start.
bar=46
headerbar="48 48 48"; ground="36 36 36"; line="64 64 64"
selected="36 56 80"; red="224 27 36"; faded="130 32 36"

waits_for "^l0s> "
printf 'run widgets &\n' >&3
window
cx=$((w_x + 2)); cy=$((w_y + bar))

shows "its header bar" "$((w_x + 6)) $((w_y + 6)) $headerbar"
shows "the toolbar, the grid's header, End Process faded" \
  "$((cx + 100)) $((cy + 3)) $ground" "$((cx + 5)) $((cy + 78)) $line" "$((cx + 550)) $((cy + 22)) $faded"

# The toolbar's line, "Select a process from the list", dimmed, in
# Source Sans 3, 11888 units, 159 wide, in the middle of its 494 from
# 46, so from 213, its line's top 15 down: the pens of from's m
# and the space after it are 107 and 118, of list's i and s 145 and
# 149, the advances and kerning summed (ui_text_pen); row 8 of the line
# crosses both, where the strike's m inks 108 to 117 and its i 146 to
# 147. So the i is narrower than the m: proportional, not cells of 8.
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
ly=$((cy + 15 + 8)); lx=$((cx + 213))
rm -f "$dump"; monitor "screendump $dump"
m_ink=$(ink $((lx + 107)) $((lx + 118)) $ly); i_ink=$(ink $((lx + 145)) $((lx + 149)) $ly)
[ "$m_ink" = "$((lx + 108)) $((lx + 117))" ] && [ "$i_ink" = "$((lx + 146)) $((lx + 147))" ] \
  || { echo "not ok - widgets: the toolbar's line is not proportional: m inks $m_ink, i $i_ink, wanted $((lx + 108)) $((lx + 117)) and $((lx + 146)) $((lx + 147))"; exit 1; }
echo "ok - widgets: the toolbar's line is proportional: its i 2 wide, its m 10"

# The second row, pid 2, its Name column past its text.
rx=$((cx + 240)); ry=$((cy + 79 + 30 + 15))
events "$(at $rx $ry)"; sleep 1
events "$(button true)"; sleep 1
events "$(button false)"; sleep 1
shows "a click selected the second row, and End Process woke" \
  "$rx $((cy + 79 + 30 + 1)) $selected" "$((cx + 550)) $((cy + 22)) $red"

# The focus, by the keyboard: the targets in order are Refresh, End
# Process, then the tabs and their close buttons. The ring is a button's
# outer 2 pixels, the accent mixed half with the toolbar's ground:
# 3584e4 and 242424 make 2d5484. Refresh is 34 square from 6, so its
# ring's left side is at 6; End Process's at 546. Tab from nothing goes
# to Refresh, Tab again to End Process, and Shift-Tab back to Refresh,
# End Process its own red again; Esc takes the focus away.
ring="45 84 132"
paced; buf0=$w_buf; frames0=$w_frames
monitor "sendkey tab"
shows "Tab put the focus on Refresh" "$((cx + 6)) $((cy + 22)) $ring" "$((cx + 546)) $((cy + 22)) $red"
paced; buf1=$w_buf; frames1=$w_frames
monitor "sendkey tab"
shows "Tab moved it on to End Process" "$((cx + 6)) $((cy + 22)) $ground" "$((cx + 546)) $((cy + 22)) $ring"
paced; buf2=$w_buf; frames2=$w_frames

# Each change is painted in the buffer the screen did not show, which
# then shows: the window's content flips between its two ids, 4 and 6
# for window 0, at each, and wm tells its client a frame for each.
case "$buf0 $buf1 $buf2" in
  "4 6 4"|"6 4 6") echo "ok - widgets: each change shown from the other buffer, $buf0, $buf1, $buf2" ;;
  *) fail "the buffers shown were $buf0, $buf1, $buf2, not each the other" ;;
esac
if [ "$frames1" -gt "$frames0" ] && [ "$frames2" -gt "$frames1" ] && [ "$frames0" -gt 0 ]; then
  echo "ok - widgets: frames told, $frames0, $frames1, $frames2"
else
  fail "frames told were $frames0, $frames1, $frames2, not more at each change"
fi
monitor "sendkey shift-tab"
shows "Shift-Tab moved it back to Refresh" "$((cx + 6)) $((cy + 22)) $ring" "$((cx + 546)) $((cy + 22)) $red"
monitor "sendkey esc"
shows "Esc took the focus away" "$((cx + 6)) $((cy + 22)) $ground"

# The tab bar, the content's last 40 rows, from 400: the header bar's
# ground, 303030, and three tabs 34 high from 403, sharing its 640, 6 in
# from each side and 3 apart, 207 each, from 6, 216 and 426. The
# selected one is raised, white at 10% over the bar, 454545; under the
# pointer, 13%, 4b4b4b.
tab_on="69 69 69"; tab_hover="75 75 75"
ty=$((cy + 420))
shows "the tab bar, its first tab raised" "$((cx + 14)) $ty $tab_on" "$((cx + 224)) $ty $headerbar" "$((cx + 434)) $ty $headerbar"
events "$(at $((cx + 500)) $ty)"; sleep 1
events "$(button true)"; sleep 1
events "$(button false)"; sleep 1
shows "a click raised the third tab" "$((cx + 14)) $ty $headerbar" "$((cx + 434)) $ty $tab_hover"
# The second's close button, 24 square, 5 in from its end: 216 + 207 -
# 29 = 394 to 418. The two left share the bar, 312 each, from 6 and 321,
# the third still raised; the pointer then taken off the bar.
events "$(at $((cx + 406)) $ty)"; sleep 1
events "$(button true)"; sleep 1
events "$(button false)"; sleep 1
events "$(at $((cx + 300)) $((cy + 200)))"; sleep 1
shows "the second tab closed, the third raised" "$((cx + 329)) $ty $tab_on" "$((cx + 14)) $ty $headerbar" "$((cx + 316)) $ty $headerbar"

# The title bar's close button, 24 square, 6 in from the window's right,
# 644 wide, and 10 down: 614 to 637 across, its middle 626, 22. wm asks
# the gallery to close with the close notice; the gallery does nothing
# with win.close, so the toolkit closes its window and has wm end it:
# run windows lists no gallery.
events "$(at $((w_x + 626)) $((w_y + 22)))"; sleep 0.3
events "$(button true)"; sleep 0.3
events "$(button false)"
for try in $(seq 1 30); do
  from=$(($(wc -c < "$out") + 1))
  printf 'run windows\n' >&3
  sleep 1
  got=$(tail -c +$from "$out")
  if printf '%s\n' "$got" | grep -aq '^pointer ' && ! printf '%s\n' "$got" | grep -aqE '^[0-9]+ Widgets '; then
    echo "ok - widgets: the close button closed the gallery"
    exit 0
  fi
done
fail "the close button left the gallery open; it showed:"
