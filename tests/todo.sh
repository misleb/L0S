#!/usr/bin/env bash
# todo.sh -- boots tests/screen/etc's initramfs with no window: the
# compositor, wm, and no vt. Types run todo & at the serial shell, which
# opens To Do (user/apps/todo, roadmap 0065), learns where its window is
# from run windows, and checks, by QEMU's screendump, what a person
# does with it, its places pinned by todo_test.l0's test_placed:
#
#   1. as it opens, no tasks: the window's ground where the list will be
#   2. milk typed, through the monitor's sendkey, and Enter: typed into
#      the entry, which had the focus as the window opened, and added as
#      a task, the list's card under the toolbar
#   3. a click on its check box: done, the box in the accent
#   4. Clear Completed, then the dialog's Clear: the dialog over the
#      window, everything beneath it darkened, then the done task gone,
#      the window's ground there again
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# screen-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/todo.sock"
qmp="$BUILD/todo.qmp"
fifo="$BUILD/todo.in"
out="$BUILD/todo.out"
dump="$BUILD/todo.ppm"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"

QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/screen.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - todo: $1"; sed 's/^/  # /' "$out"; exit 1; }

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
button() { echo "{\"type\":\"btn\",\"data\":{\"down\":$1,\"button\":\"left\"}}"; }

waits_for() {
  local end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    grep -qE "$1" "$out" 2> /dev/null && return 0
    sleep 0.2
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# A click at x, y, and the pointer then taken off the window, to the
# screen's corner, so nothing is tinted under it.
click() {
  events "$(at $1 $2)"; sleep 0.1
  events "$(button true)"; sleep 0.1
  events "$(button false)"; sleep 0.1
  events "$(at 1270 790)"
}

# What run windows lists, from the serial line, in $got: typed, and
# read up to the shell's next prompt, waited for up to 5 s.
listed() {
  local from end=$((SECONDS + 5))
  from=$(($(wc -c < "$out") + 1))
  printf 'run windows\n' >&3
  until [ $SECONDS -ge $end ] || tail -c +$from "$out" | grep -aq 'l0s> '; do sleep 0.1; done
  got=$(tail -c +$from "$out")
}

# Where To Do's window is, as run windows lists it, its title two words:
# w_x, w_y. Waits up to 30 s for it to be listed.
window() {
  local line end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    listed
    line=$(printf '%s\n' "$got" | grep -aE '^[0-9]+ To Do ' | head -1)
    if [ -n "$line" ]; then
      read -r _ _ _ w_x w_y _ <<< "$line"
      return 0
    fi
    sleep 0.2
  done
  fail "run windows never listed To Do's window; it showed:"
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
      [ "$ok" = 1 ] && { echo "ok - todo: $name"; return 0; }
    fi
    sleep 0.2
  done
  echo "not ok - todo: $name: got$got, wanted $*"
  exit 1
}

# The window's content starts under its 46-row title bar, 2 in from its
# left, inside the frame's border. In it: the toolbar, 46 rows, the
# entry from 6, 6; under it, 12 in, the list from 59, its first row 50
# high, its card 363636 on the window's 242424; the row's check box from
# 24, 76, 16 square, the trough's color on the card off, white at 15%,
# and the accent, 3584e4, on; Clear Completed from 361, 6, 113 by 34;
# the dialog's Clear from 288, 280, 49 by 34. Beneath the dialog the
# window is mixed 30% with black: the card's 54 is 38.
bar=46
ground="36 36 36"; card="54 54 54"; dark_card="38 38 38"; accent="53 132 228"

waits_for "^l0s> "
printf 'run todo &\n' >&3
window
cx=$((w_x + 2)); cy=$((w_y + bar))
events "$(at 1270 790)"

shows "as it opens, no list: the window's ground" "$((cx + 240)) $((cy + 66)) $ground"
keys m i l k ret
shows "milk typed into the focused entry and Enter: the list's card" "$((cx + 240)) $((cy + 66)) $card"
click $((cx + 32)) $((cy + 84))
shows "its check box clicked: done, in the accent" "$((cx + 32)) $((cy + 78)) $accent"
click $((cx + 417)) $((cy + 23))
shows "Clear Completed: the dialog, the window beneath it darkened" "$((cx + 240)) $((cy + 66)) $dark_card"
click $((cx + 312)) $((cy + 297))
shows "Clear: the done task gone, the window's ground again" "$((cx + 240)) $((cy + 66)) $ground"
