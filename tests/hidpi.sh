#!/usr/bin/env bash
# hidpi.sh -- boots tests/screen/etc's initramfs on a 4K virtio-gpu,
# 3840 by 2160, which the desktop draws at scale 2: laid out as 1920 by
# 1080 of its own pixels, each 2 by 2 of the screen's, with text, icons
# and corners drawn at the screen's resolution. Checks, by QEMU's
# screendump of the whole screen:
#
#   1. the screen is the mode's own size, 3840 by 2160, not half of it
#   2. the top bar, black, 64 rows, twice its 32; the wallpaper's ground
#      below it
#   3. run draw size says 1920x1080, the desktop's pixels
#   4. after run draw line 0 32 1919 1079 red, its ends, each a dot of 2
#      by 2: 0, 64 to 1, 65, and 3838, 2158 to 3839, 2159
#   5. after run widgets &, the gallery's title, Widgets in bold, smooth:
#      along a row through it, more colors than the header bar's ground
#      and the text's, its edges mixed between them
#   6. after run Terminal &, vt1's window: its text, drawn by vt into its
#      own buffer, smooth the same way on its dark ground
#
# Then boots again with the boot argument scale=1, and checks that the
# same screen is drawn at 1: its top bar 32 rows. Commands are typed
# through a FIFO; the board keeps running until this kills it. Run from
# the top of the project, after make screen-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/hidpi.sock"
dump="$BUILD/hidpi.ppm"
fifo="$BUILD/hidpi.in"
out="$BUILD/hidpi.out"
W=3840
H=2160

boot() {
  rm -f "$sock" "$dump" "$fifo"
  mkfifo "$fifo"
  QEMU_GPU="xres=$W,yres=$H" QEMU_APPEND="$1" QEMU_MONITOR="unix:$sock,server=on,wait=off" \
    tools/qemu-boot.sh "$BUILD/screen.cpio" < "$fifo" > "$out" 2>&1 &
  qemu=$!
  exec 3> "$fifo"
}
stop() { exec 3>&-; kill $qemu 2> /dev/null; wait $qemu 2> /dev/null; rm -f "$fifo"; }
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT

fail() { echo "not ok - hidpi: $1"; sed 's/^/  # /' "$out"; exit 1; }

# The screendump's header, "P6\n3840 2160\n255\n", is 17 bytes.
header() { printf 'P6\n%s %s\n255\n' $W $H; }
pixel() { od -An -tu1 -j $((17 + ($2 * W + $1) * 3)) -N3 "$dump" | tr -s ' ' | sed 's/^ //; s/ $//'; }

dumped() {
  rm -f "$dump"
  printf 'screendump %s\n' "$dump" | nc -U -w 1 "$sock" > /dev/null 2>&1
  [ -s "$dump" ]
}

# Waits up to 30 s for each "X Y R G B" to be on the screen.
shows() {
  local name=$1; shift
  local try p ok got px py r g b
  for try in $(seq 1 30); do
    sleep 1
    [ -S "$sock" ] || continue
    dumped || continue
    [ "$(head -c 17 "$dump")" = "$(header)" ] || continue
    ok=1; got=""
    for p in "$@"; do
      read -r px py r g b <<< "$p"
      got="$got ($px,$py)=$(pixel $px $py)"
      [ "$(pixel $px $py)" = "$r $g $b" ] || ok=0
    done
    if [ "$ok" = 1 ]; then echo "ok - hidpi: $name after ${try}s"; return 0; fi
  done
  echo "not ok - hidpi: $name: got$got, wanted $*"
  [ -s "$dump" ] && echo "  # the screendump's header: $(head -c 17 "$dump" | tr '\n' ' ')"
  exit 1
}

waits_for() {
  local try
  for try in $(seq 1 30); do
    grep -qaE "$1" "$out" 2> /dev/null && return 0
    sleep 1
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# How many colors pixels x0 up to x1 of row y hold.
colors() {
  od -An -tu1 -v -j $((17 + ($3 * W + $1) * 3)) -N $((($2 - $1) * 3)) "$dump" | tr -s ' ' '\n' | grep -v '^$' \
    | paste - - - | sort -u | wc -l | tr -d ' '
}

boot ""

# 1, 2. The wallpaper's ground, 12 28 38 at 70%, and the bar over it.
shows "a 4K screen, its bar 64 rows" "0 0 0 0 0" "3839 63 0 0 0" "0 64 8 19 26" "3839 2159 8 19 26"

# 3.
printf 'run draw size\n' >&3
waits_for '^1920x1080'
echo "ok - hidpi: draw size is the desktop's, 1920x1080"

# 4.
printf 'run draw line 0 32 1919 1079 red\n' >&3
shows "a line's ends, 2 by 2" "0 64 255 0 0" "1 65 255 0 0" "3838 2158 255 0 0" "3839 2159 255 0 0"

# 5. The gallery's window, where run windows lists it, in the desktop's
# pixels; its title, 7 bold characters of 8, 57 wide, in the middle of
# its title bar, 644 wide and 46 high; the row through its middle.
printf 'run widgets &\n' >&3
w_x=""
for try in $(seq 1 30); do
  from=$(($(wc -c < "$out") + 1))
  printf 'run windows\n' >&3
  sleep 1
  line=$(tail -c +$from "$out" | grep -aE '^[0-9]+ Widgets ' | head -1)
  if [ -n "$line" ]; then read -r _ _ w_x w_y _ _ _ <<< "$line"; break; fi
done
[ -n "$w_x" ] || fail "run windows never listed the gallery's window; it showed:"
mid=$((w_x + 322)); x0=$(((mid - 28) * 2)); x1=$(((mid + 28) * 2)); row=$(((w_y + 23) * 2))
shows "the gallery's header bar" "$(((w_x + 20) * 2)) $row 48 48 48"
n=$(colors $x0 $x1 $row)
if [ "$n" -gt 4 ]; then
  echo "ok - hidpi: the title is smooth, $n colors along it"
else
  fail "the title's row holds $n colors, so its text is not smoothed; the serial line showed:"
fi
# 6. A terminal, run Terminal &: its window, and the first row of its
# text, the motd's, 8 rows into its content under its 46-row title bar,
# smooth on its ground, 1e1e1e, as the gallery's title is.
printf 'run Terminal &\n' >&3
v_x=""
for try in $(seq 1 30); do
  from=$(($(wc -c < "$out") + 1))
  printf 'run windows\n' >&3
  sleep 1
  line=$(tail -c +$from "$out" | grep -aE '^[0-9]+ vt1 ' | head -1)
  if [ -n "$line" ]; then read -r _ _ v_x v_y _ _ _ <<< "$line"; break; fi
done
[ -n "$v_x" ] || fail "run windows never listed vt1's window; it showed:"
trow=$(((v_y + 46 + 8) * 2))
shows "the terminal's ground" "$(((v_x + 2 + 636) * 2)) $trow 30 30 30"
n=$(colors $(((v_x + 2) * 2)) $(((v_x + 2 + 320) * 2)) $trow)
if [ "$n" -gt 4 ]; then
  echo "ok - hidpi: the terminal's text is smooth, $n colors along a row"
else
  fail "the terminal's row holds $n colors, so its text is not smoothed; the serial line showed:"
fi
# The screen at scale 2 kept, to look at: build/hidpi-2x.ppm.
cp "$dump" "$BUILD/hidpi-2x.ppm"
stop

# The same screen at scale=1: its bar 32 rows, the wallpaper's ground
# just below.
boot "scale=1"
shows "scale=1 at 4K, its bar 32 rows" "3839 31 0 0 0" "3839 32 8 19 26"
