#!/usr/bin/env bash
# resize.sh -- boots tests/screen/etc's initramfs with no window: the
# compositor, wm, and no vt. Types run widgets & at the serial shell, which
# opens the toolkit's gallery (user/apps/widgets) in a window, and drags
# its edges with the tablet, through QMP, checking what run windows lists
# and, by QEMU's screendump, what is shown:
#
#   1. the lower right corner dragged 100 right and 60 down: the window
#      listed 100 wider and 60 higher, and its toolbar's End Process,
#      which sits at the content's right end, 100 further right
#   2. the left edge dragged 30 left: the window listed 30 wider, its left
#      at 30 less, and so its right where it was
#   3. the pointer, as run windows names it: ew-resize over the frame's
#      right side, nwse-resize over the lower right corner, the arrow
#      (no name) over the content
#   4. the top left corner grabbed just outside the window, where its
#      rounded corner is cut away, and dragged 30 right and 20 down: the
#      window that much smaller, its top left that much further in
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# screen-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/resize.sock"
qmp="$BUILD/resize.qmp"
fifo="$BUILD/resize.in"
out="$BUILD/resize.out"
dump="$BUILD/resize.ppm"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"

QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/screen.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - resize: $1"; sed 's/^/  # /' "$out"; exit 1; }

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

# Where the gallery's window is, as run windows lists it, and how big its
# content: w_x, w_y, w_w, w_h. With arguments, waits up to 30 s for it to
# be that size, W H.
window() {
  local try from line
  for try in $(seq 1 30); do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    sleep 1
    line=$(tail -c +$from "$out" | grep -aE '^[0-9]+ Widgets ' | head -1)
    if [ -n "$line" ]; then
      read -r _ _ w_x w_y w_w w_h _ <<< "$line"
      [ $# -eq 0 ] && return 0
      [ "$w_w" = "$1" ] && [ "$w_h" = "$2" ] && return 0
    fi
  done
  fail "run windows never listed the gallery's window as ${1:-any} by ${2:-any}; it last said: ${line:-nothing}"
}

# The tablet taken from x0, y0 to x1, y1 with the left button held, in
# steps, as a hand would.
drag() {
  local i
  events "$(at $1 $2)"; sleep 1
  events "$(button true)"; sleep 1
  for i in 1 2 3 4; do
    events "$(at $(( $1 + ($3 - $1) * i / 4 )) $(( $2 + ($4 - $2) * i / 4 )))"; sleep 1
  done
  events "$(button false)"; sleep 1
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
      [ "$ok" = 1 ] && { echo "ok - resize: $name"; return 0; }
    fi
    sleep 1
  done
  echo "not ok - resize: $name: got$got, wanted $*"
  exit 1
}

# The window's content starts under its 46-row header bar, 2 in from its
# left, and its toolbar's End Process is 108 wide at the content's right
# end, 6 in, in the middle of the toolbar's 46 rows: faded, with no row
# selected. The window is 4 wider than its content, and 48 higher.
bar=46
ground="250 250 250"; faded="237 139 143"

waits_for "^l0s> "
printf 'run widgets &\n' >&3
window
x0=$w_x; y0=$w_y; w0=$w_w; h0=$w_h
cx=$((x0 + 2)); cy=$((y0 + bar))
shows "the toolbar, End Process at the content's right end" \
  "$((cx + w0 - 60)) $((cy + 22)) $faded"

# The lower right corner, just inside the frame, 100 right and 60 down.
drag $((x0 + w0 + 3)) $((y0 + bar + h0 + 1)) $((x0 + w0 + 103)) $((y0 + bar + h0 + 61))
window $((w0 + 100)) $((h0 + 60))
[ "$w_x $w_y" = "$x0 $y0" ] || fail "a corner dragged moved the window to $w_x $w_y, not $x0 $y0"
echo "ok - resize: the corner dragged: ${w_w} by ${w_h}"
shows "End Process 100 further right, the toolbar's ground where it was" \
  "$((cx + w0 + 100 - 60)) $((cy + 22)) $faded" "$((cx + w0 - 60)) $((cy + 22)) $ground"

# The left edge, in the frame's side 100 rows down, 30 left.
w1=$w_w; h_before=$w_h
drag $x0 $((y0 + bar + 100)) $((x0 - 30)) $((y0 + bar + 100))
window $((w1 + 30)) $h_before
[ "$w_x" = "$((x0 - 30))" ] || fail "the left edge dragged left put the window at $w_x, not $((x0 - 30))"
echo "ok - resize: the left edge dragged: ${w_w} by ${w_h} at ${w_x}"

# The pointer at x, y: waits up to 30 s for run windows to name it as
# shown, nothing for the arrow.
pointer_is() {
  local try from line want
  want="^pointer [0-9]+ [0-9]+${3:+ $3}\$"
  events "$(at $1 $2)"; sleep 1
  for try in $(seq 1 30); do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    sleep 1
    line=$(tail -c +$from "$out" | grep -aE '^pointer ' | head -1 | tr -d '\r')
    if echo "$line" | grep -qE "$want"; then
      echo "ok - resize: the pointer at $1, $2: ${3:-the arrow}"
      return 0
    fi
  done
  fail "the pointer at $1, $2 was not ${3:-the arrow}; run windows last said: ${line:-nothing}"
}

x1=$w_x; y1=$w_y; w2=$w_w; h2=$w_h
pointer_is $((x1 + w2 + 3)) $((y1 + bar + 100)) ew-resize
pointer_is $((x1 + w2 + 3)) $((y1 + bar + h2 + 1)) nwse-resize
pointer_is $((x1 + 100)) $((y1 + bar + 100))

# The top left corner, 2 left of the window and 2 above it, outside it,
# 30 right and 20 down.
drag $((x1 - 2)) $((y1 - 2)) $((x1 + 28)) $((y1 + 18))
window $((w2 - 30)) $((h2 - 20))
[ "$w_x $w_y" = "$((x1 + 30)) $((y1 + 20))" ] || fail "the top left corner dragged put the window at $w_x $w_y, not $((x1 + 30)) $((y1 + 20))"
echo "ok - resize: the top left corner dragged: ${w_w} by ${w_h} at ${w_x}, ${w_y}"
