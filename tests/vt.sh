#!/usr/bin/env bash
# vt.sh -- boots the demo's initramfs with no window, on its USB keyboard
# and mouse (QEMU_INPUT=usb), but with tests/vt/etc/system's two
# terminals: the compositor, wm, with two vt
# windows, each with a shell. It learns where the windows are
# from run windows, typed at the serial shell, since which vt opens first,
# and so where each is, varies. Then it checks:
#
#   1. both title bars, by QEMU's screendump: the front window's active,
#      the other's in the backdrop
#   2. echo hi, typed on the USB keyboard through QEMU's monitor
#      (sendkey), as typing in QEMU's window would: the front window
#      shows the h of hi on row 8, under the motd, the banner, and the
#      prompt
#   3. run nap 30000 &, typed the same way: ps at the serial shell shows
#      nap, started by the front window's shell, which its vt started
#   4. a click of the USB mouse, through QMP, on the other window's title
#      bar: it comes to the front, its title bar active, as run windows
#      and the screendump show
#   5. a drag of its title bar: run windows shows it moved as far as the
#      pointer did
#   6. run cat /etc/inittab, typed three times into it, more than its 24
#      rows: it scrolls, and its prompt's cursor is on its last row; a
#      step of the wheel up shows three rows back, with the overlay
#      scrollbar, and Backspace typed brings it back to the bottom
#   7. exit, typed into it: its shell ends, and so its vt, which closes
#      the window, leaving the other in front
#   8. a click on that one's close button: its vt is killed, the window
#      closes, and its shell, its terminal gone, exits too
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# vt-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/vt.sock"
qmp="$BUILD/vt.qmp"
fifo="$BUILD/vt.in"
out="$BUILD/vt.out"
dump="$BUILD/vt.ppm"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"

QEMU_INPUT=usb QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/vt.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - vt: $1"; sed 's/^/  # /' "$out"; exit 1; }

monitor() { printf '%s\n' "$1" | nc -U -w 1 "$sock" > /dev/null 2>&1; }

# Each key of a line, as sendkey names them, then Enter.
typekeys() {
  local s=$1 i c
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      " ") monitor "sendkey spc" ;;
      "&") monitor "sendkey shift-7" ;;
      "/") monitor "sendkey slash" ;;
      ".") monitor "sendkey dot" ;;
      *) monitor "sendkey $c" ;;
    esac
  done
  monitor "sendkey ret"
}

# The USB mouse, through QMP: each argument an input event.
events() {
  local list
  list=$(IFS=,; echo "$*")
  printf '{"execute":"qmp_capabilities"}\n{"execute":"input-send-event","arguments":{"events":[%s]}}\n' "$list" \
    | nc -U -w 1 "$qmp" > /dev/null 2>&1
}
# A move of dx, dy, a pixel a count, as a mouse moves.
by() {
  echo "{\"type\":\"rel\",\"data\":{\"axis\":\"x\",\"value\":$1}},{\"type\":\"rel\",\"data\":{\"axis\":\"y\",\"value\":$2}}"
}
# The pointer to screen pixel x, y: into the top left corner first, where
# wm keeps it however far past it the mouse goes, then from there. QEMU
# adds up one batch's moves, so the two are sent apart.
point() { events "$(by -4000 -4000)"; sleep 1; events "$(by "$1" "$2")"; }
button() { echo "{\"type\":\"btn\",\"data\":{\"down\":$1,\"button\":\"left\"}}"; }
# A step of the wheel, wheel-down or wheel-up, as the mouse reports it.
wheel() { echo "{\"type\":\"btn\",\"data\":{\"down\":true,\"button\":\"$1\"}},{\"type\":\"btn\",\"data\":{\"down\":false,\"button\":\"$1\"}}"; }

# Waits up to 30 s for the serial line to show a line matching a pattern.
waits_for() {
  local try
  for try in $(seq 1 30); do
    grep -qE "$1" "$out" 2> /dev/null && return 0
    sleep 1
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# The windows, as run windows lists them, in front, f_* and in back,
# b_*: title, x, y, width, height. Asks until there are N, 2 unless given.
windows() {
  local n=${1:-2} try lines from
  for try in $(seq 1 30); do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    sleep 1
    lines=$(tail -c +$from "$out" | grep -aE '^[0-9]+ vt[0-9] ')
    if [ "$(printf '%s\n' "$lines" | grep -c .)" = "$n" ]; then
      [ "$n" = 0 ] && return 0
      read -r _ f_title f_x f_y f_w f_h f_front <<< "$(printf '%s\n' "$lines" | sed -n 1p)"
      read -r _ b_title b_x b_y b_w b_h b_front <<< "$(printf '%s\n' "$lines" | sed -n 2p)"
      [ "$f_front" = front ] || fail "the first window listed is not in front"
      return 0
    fi
  done
  fail "run windows never listed $n windows; it showed:"
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
      [ "$ok" = 1 ] && { echo "ok - vt: $name"; return 0; }
    fi
    sleep 1
  done
  echo "not ok - vt: $name: got$got, wanted $*"
  exit 1
}

# A point on the back window's title bar that the front window does not
# cover: its left end, or else its right.
back_title() {
  local x=$((b_x + 6)) y=$((b_y + 6))
  if [ $x -ge $f_x ] && [ $x -lt $((f_x + f_w + 2 * edge)) ] && [ $y -ge $f_y ] && [ $y -lt $((f_y + bar + f_h + edge)) ]; then
    x=$((b_x + b_w + 2 * edge - 7))
  fi
  echo "$x $y"
}

# The title bars are Adwaita's dark header bars, 46 rows: 303030 in
# front, 242424 in the backdrop. Each window's frame is a border of their
# color, 2 pixels down its content's sides and along its foot, so its
# content is 2 in from its left. The terminal is GNOME Console's, white
# on 1e1e1e, its cursor white too.
bar=46; edge=2
active="48 48 48"; backdrop="36 36 36"; ink="255 255 255"; cursor="255 255 255"; stem="194 194 194"
# The overlay scrollbar's slider: white at 40% over the terminal's
# 1e1e1e, (255 * 40 + 30 * 60 + 50) / 100.
thumb="120 120 120"

waits_for "^l0s> "
windows
read -r bx by <<< "$(back_title)"
shows "both windows, $f_title in front" "$((f_x + 6)) $((f_y + 6)) $active" "$bx $by $backdrop"

# The front window's corners are rounded by its shape: its top left pixel
# shows what is under the window, as the pixel left of it does.
rm -f "$dump"; monitor "screendump $dump"; sleep 1
[ -s "$dump" ] && [ "$(pixel $f_x $f_y)" = "$(pixel $((f_x - 1)) $f_y)" ] && [ "$(pixel $f_x $f_y)" != "$active" ] ||
  fail "the top left corner of $f_title shows $(pixel $f_x $f_y), not what is under it, $(pixel $((f_x - 1)) $f_y)"
echo "ok - vt: $f_title's corners are rounded"

# Its frame: the border down both sides of the terminal, and along its
# foot, in the active title bar's color; the terminal's ground inside.
shows "$f_title's border, its title bar's color" \
  "$f_x $((f_y + bar + 100)) $active" "$((f_x + edge - 1)) $((f_y + bar + 100)) $active" \
  "$((f_x + edge + f_w)) $((f_y + bar + 100)) $active" "$((f_x + 100)) $((f_y + bar + f_h + edge - 1)) $active" \
  "$((f_x + edge)) $((f_y + bar + 300)) 30 30 30"

# The prompt's cursor on row 7's last pixel row, after "l0s> ".
shows "$f_title's shell is waiting" "$((f_x + edge + 40)) $((f_y + bar + 7 * 16 + 15)) $cursor"
typekeys "echo hi"
# h's stem, column 1, its middle, on row 8: 11 of 15 covered, white mixed
# over the terminal's ground, as the smooth 8 by 16 glyph has it.
shows "echo hi typed and answered in $f_title" "$((f_x + edge + 1)) $((f_y + bar + 8 * 16 + 8)) $stem"

# vt1 and vt2 are pids 17 and 18: boot, pid 1, starts /etc/system's
# programs after the inittab's fourteen, sh 15, wm 16, then the two vts
# in that order, and each names itself first thing. Each starts its own
# shell, which ps shows as its child.
vt=$((16 + ${f_title#vt}))
typekeys "run nap 30000 &"
sleep 2
printf 'ps\n' >&3
waits_for "^ +[0-9]+ +$vt  sh "
shell=$(grep -aE "^ +[0-9]+ +$vt  sh " "$out" | tail -1 | awk '{print $1}')
waits_for "^ +[0-9]+ +$shell  nap +sleeping"
echo "ok - vt: $f_title's shell, pid $shell, started by $f_title, ran nap"

# A click on the back window's title bar brings it to the front.
front=$b_title
point "$bx" "$by"; sleep 1
events "$(button true)"; sleep 1
events "$(button false)"; sleep 1
windows
[ "$f_title" = "$front" ] || fail "a click on $front's title bar left $f_title in front"
shows "a click brought $front to the front" "$((f_x + 6)) $((f_y + 6)) $active" "$(back_title | tr -d '\n') $backdrop"

# A drag of its title bar moves it as far as the pointer moved.
x0=$((f_x + 30)); y0=$((f_y + 10)); x1=$((x0 + 150)); y1=$((y0 + 120))
want_x=$((f_x + x1 - x0)); want_y=$((f_y + y1 - y0))
point $x0 $y0; sleep 1
events "$(button true)"; sleep 1
events "$(by 70 60)"; sleep 1
events "$(by $((x1 - x0 - 70)) $((y1 - y0 - 60)))"; sleep 1
events "$(button false)"; sleep 1
windows
[ "$f_title" = "$front" ] && [ "$f_x" = "$want_x" ] && [ "$f_y" = "$want_y" ] ||
  fail "after the drag, $f_title is in front at $f_x, $f_y; wanted $front at $want_x, $want_y"
echo "ok - vt: a drag moved $front to $f_x, $f_y"

# The inittab three times over is more than the window's 24 rows: it
# scrolls, and the prompt's cursor is on the last row, row 23.
for n in 1 2 3; do typekeys "run cat /etc/inittab"; sleep 2; done
shows "$front scrolled, the prompt on its last row" "$((f_x + edge + 40)) $((f_y + bar + 383)) $cursor"

# A step of the wheel up over it shows the rows scrolled off, three of
# them, drawn from its cells: the toolkit's overlay scrollbar shows along
# its right, its slider 6 wide, 3 in, white at 40% over the ground, near
# its foot, as the view is only three rows back; the cursor's row is now
# out of view. A key typed, Backspace on the empty line, brings the view
# back to the bottom: the slider gone, the cursor back.
point $((f_x + edge + 300)) $((f_y + bar + 200)); sleep 1
events "$(wheel wheel-up)"; sleep 1
slider="$((f_x + edge + f_w - 6)) $((f_y + bar + 330))"
shows "the wheel scrolled $front back, its scrollbar shown" "$slider $thumb"
monitor "sendkey backspace"
shows "a key brought $front back to the bottom" "$slider 30 30 30" "$((f_x + edge + 40)) $((f_y + bar + 383)) $cursor"

# exit at its shell ends the shell, and so its vt, which closes its
# window: the other is left, in front, and ps shows neither process.
other=$b_title
vt=$((16 + ${front#vt}))
typekeys "exit"
windows 1
[ "$f_title" = "$other" ] || fail "after exit in $front, $f_title is left, not $other"
from=$(($(wc -c < "$out") + 1))
printf 'ps\n' >&3
sleep 2
tail -c +$from "$out" | grep -aqE "^ +$vt +1  vt |^ +[0-9]+ +$vt  sh " &&
  fail "after exit in $front, ps still shows its vt, pid $vt, or its shell"
echo "ok - vt: exit closed $front, its vt gone, $other left in front"

# A click on the close button, at the right end of the title bar, kills
# the window's vt, which closes the window; its shell, its terminal gone,
# exits too.
vt=$((16 + ${other#vt}))
from=$(($(wc -c < "$out") + 1))
printf 'ps\n' >&3
# Its shell's line in this ps's output, not an earlier one's: without it
# the check below would match every line.
shell=""
for try in $(seq 1 30); do
  shell=$(tail -c +$from "$out" | grep -aE "^ +[0-9]+ +$vt  sh " | tail -1 | awk '{print $1}')
  [ -n "$shell" ] && break
  sleep 1
done
[ -n "$shell" ] || fail "ps never showed $other's shell, a child of its vt, pid $vt; it showed:"
cx=$((f_x + f_w + 2 * edge - 18)); cy=$((f_y + 22))
point $cx $cy; sleep 1
events "$(button true)"; sleep 1
events "$(button false)"; sleep 1
windows 0
sleep 1
from=$(($(wc -c < "$out") + 1))
printf 'ps\n' >&3
sleep 2
tail -c +$from "$out" | grep -aqE "^ +($vt|$shell) " &&
  fail "after the close button, ps still shows $other's vt, pid $vt, or its shell, pid $shell"
echo "ok - vt: the close button killed $other's vt, and its shell went with it"
