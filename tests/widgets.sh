#!/usr/bin/env bash
# widgets.sh -- boots tests/screen/etc's initramfs with no window: the
# compositor, wm, and no vt. Types run widgets & at the serial shell, which
# opens the toolkit's gallery (user/apps/widgets) in a window, learns where it
# is from run windows, and checks, by QEMU's screendump:
#
#   1. its title bar, an Adwaita header bar in front, dark, 303030
#   2. the toolbar on the window's ground, 242424; the grid's header's
#      line under it; End Process faded, with no row selected
#   3. a click of the tablet, through QMP, on the second row: the
#      pointer's press and release forwarded to the window, the row
#      selected, in the accent's tint, and End Process its own red
#   4. the tab bar along its foot, AdwTabBar's: three tabs, the first
#      raised; a click on the third raises it instead, and a click on
#      the second's close button closes it, the two left sharing the bar
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
# toolbar, 46 rows, its End Process button 108 wide at its right end, 6
# in; a line; then the grid, its header 32 rows, the last its line, and
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
  "$((cx + 100)) $((cy + 3)) $ground" "$((cx + 5)) $((cy + 78)) $line" "$((cx + 530)) $((cy + 22)) $faded"

# The second row, pid 2, its Name column past its text.
rx=$((cx + 240)); ry=$((cy + 79 + 30 + 15))
events "$(at $rx $ry)"; sleep 1
events "$(button true)"; sleep 1
events "$(button false)"; sleep 1
shows "a click selected the second row, and End Process woke" \
  "$rx $((cy + 79 + 30 + 1)) $selected" "$((cx + 530)) $((cy + 22)) $red"

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
