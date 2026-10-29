#!/usr/bin/env bash
# vt.sh -- boots the demo's initramfs with no window, on its USB keyboard
# and mouse (QEMU_INPUT=usb), but with tests/vt/etc/system's two
# Terminals: the compositor, wm, with two vt windows, each drawing its
# own header bar and with a tab, its shell. It learns where the windows
# are from run windows, typed at the serial shell, since which vt opens
# first, and so where each is, varies. Then it checks:
#
#   1. both header bars, by QEMU's screendump: the front window's
#      active, the other's in the backdrop; the front one's corner cut
#      by its shape, and the terminal's ground under its header bar
#   2. echo hi, typed on the USB keyboard through QEMU's monitor
#      (sendkey), as typing in QEMU's window would: the front window
#      shows the h of hi on row 8, under the motd, the banner, and the
#      prompt
#   3. run nap 30000 &, typed the same way: ps at the serial shell shows
#      nap, started by the front window's shell, which its vt started,
#      one of the two vts /etc/system started
#   4. a click of the USB mouse, through QMP, on the other window's header
#      bar: it comes to the front, its header bar active, as run windows
#      and the screendump show
#   5. a drag of its header bar: run windows shows it moved as far as the
#      pointer did
#   6. run cat /etc/inittab, typed three times into it, more than its 24
#      rows: it scrolls, and its prompt's cursor is on its last row; a
#      step of the wheel up shows three rows back, with the overlay
#      scrollbar, and Backspace typed brings it back to the bottom
#   7. a line typed, not yet entered, longer than 40 columns, then the
#      window's right edge dragged in to 40 columns: the line wrapped
#      again, its cursor still on the last row, 10 into its second row;
#      dragged out again, the line whole and the cursor 50 in
#   8. a click on the new-tab button: a second tab, vt3, its name the
#      window's title, and the tab bar under the header bar, the new tab
#      selected; echo hi typed in it answered in it; ps shows both tabs'
#      shells started by the window's vt
#   9. a click on the first tab: it is shown again, the title its name,
#      and echo hi typed is answered in it
#  10. a click on the second tab's close button: its shell ends, the tab
#      bar goes, and the title is the first tab's; then Ctrl-Shift-T
#      opens a tab as the button did, which its close button closes
#  11. exit, typed into it: its shell ends, and so its tab and, the last,
#      the window, and its vt, leaving the other window in front
#  12. a click on that one's close button: its vt ends its tab's shell
#      and closes the window
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

monitor() { printf '%s\n' "$1" | tools/qsock "$sock" > /dev/null 2>&1; }

# Each key of a line, as sendkey names them, and no Enter.
keys() {
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
}
# Each key of a line, then Enter.
typekeys() { keys "$1"; monitor "sendkey ret"; }

# The USB mouse, through QMP: each argument an input event.
events() {
  local list
  list=$(IFS=,; echo "$*")
  printf '{"execute":"qmp_capabilities"}\n{"execute":"input-send-event","arguments":{"events":[%s]}}\n' "$list" \
    | tools/qsock "$qmp" > /dev/null 2>&1
}
# A move of dx, dy, a pixel a count, as a mouse moves.
by() {
  echo "{\"type\":\"rel\",\"data\":{\"axis\":\"x\",\"value\":$1}},{\"type\":\"rel\",\"data\":{\"axis\":\"y\",\"value\":$2}}"
}
# What the serial shell prints for a command typed there, in $said:
# waits up to 5 s for its next prompt, so that each command's answer is
# whole, and no answer comes late into the next's.
say() {
  local from end=$((SECONDS + 5))
  from=$(($(wc -c < "$out") + 1))
  printf '%s\n' "$1" >&3
  until [ $SECONDS -ge $end ] || tail -c +$from "$out" | grep -aq 'l0s> '; do sleep 0.1; done
  said=$(tail -c +$from "$out")
}

# Where run windows says the pointer is: p_x, p_y.
pointer() {
  local line
  say 'run windows'
  line=$(printf '%s\n' "$said" | sed 's/^l0s> //' | grep -aE '^pointer -?[0-9]+ -?[0-9]+' | tail -1)
  read -r _ p_x p_y _ <<< "$line"
}

# The pointer to screen pixel x, y: moved from where wm says it is, as
# far as it is from there, and waited for there, up to 10 s, so that no
# button or move after it is added to it. QEMU adds up the moves the
# board has not yet read.
point() {
  local end=$((SECONDS + 10))
  pointer
  [ -n "$p_x" ] || fail "run windows said nothing of the pointer; it showed:"
  events "$(by $(($1 - p_x)) $(($2 - p_y)))"
  until [ $SECONDS -ge $end ]; do
    pointer
    [ "$p_x $p_y" = "$1 $2" ] && return 0
    sleep 0.1
  done
  fail "the pointer went to $p_x, $p_y, not $1, $2; it showed:"
}
button() { echo "{\"type\":\"btn\",\"data\":{\"down\":$1,\"button\":\"left\"}}"; }
# A step of the wheel, wheel-down or wheel-up, as the mouse reports it.
wheel() { echo "{\"type\":\"btn\",\"data\":{\"down\":true,\"button\":\"$1\"}},{\"type\":\"btn\",\"data\":{\"down\":false,\"button\":\"$1\"}}"; }
# A click at x, y. What it does is waited for by what checks it, not
# here.
click() { point "$1" "$2"; events "$(button true)"; sleep 0.1; events "$(button false)"; }
# A drag from x, y by dx, dy, in two moves, each its own report.
drag() {
  point "$1" "$2"
  events "$(button true)"; sleep 0.2
  events "$(by $(($3 / 2)) $(($4 / 2)))"; sleep 0.2
  events "$(by $(($3 - $3 / 2)) $(($4 - $4 / 2)))"; sleep 0.2
  events "$(button false)"
}

# Waits up to 30 s for the serial line to show a line matching a pattern.
waits_for() {
  local end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    grep -qE "$1" "$out" 2> /dev/null && return 0
    sleep 0.2
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# The windows, as run windows lists them, in front, f_* and in back,
# b_*: title, x, y, width, height. Asks for up to 30 s until there are
# N, 2 unless given, every one titled vtN, the first listed in front,
# and, if T is given, titled T. A vt's window is titled Terminal until
# its tab has a name.
windows() {
  local n=${1:-2} want=${2:-} lines end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    say 'run windows'
    # A prompt may come before a line, when the board is slow to answer.
    lines=$(printf '%s\n' "$said" | sed 's/^l0s> //' | grep -aE '^[0-9]+ [^ ]+ -?[0-9]+ -?[0-9]+ [0-9]+ [0-9]+ (front|-) ')
    if [ "$(printf '%s\n' "$lines" | grep -c .)" = "$n" ] &&
       [ "$(printf '%s\n' "$lines" | grep -acE '^[0-9]+ vt[0-9] ')" = "$n" ]; then
      [ "$n" = 0 ] && return 0
      read -r _ f_title f_x f_y f_w f_h f_front _ <<< "$(printf '%s\n' "$lines" | sed -n 1p)"
      read -r _ b_title b_x b_y b_w b_h b_front _ <<< "$(printf '%s\n' "$lines" | sed -n 2p)"
      [ "$f_front" = front ] && { [ -z "$want" ] || [ "$f_title" = "$want" ]; } && return 0
    fi
    sleep 0.2
  done
  fail "run windows never listed $n vt windows, the first in front${want:+, $want}; last it listed: $(printf '%s' "$lines" | tr '\n' ';'); it showed:"
}

# The lines of ps, typed at the serial shell, after it is typed.
ps_lines() { say ps; printf '%s\n' "$said"; }

# Waits up to 10 s for ps to show neither vt pid P nor a process it
# started, as a vt ends a moment after its window closes.
gone() {
  local end=$((SECONDS + 10))
  until [ $SECONDS -ge $end ]; do
    ps_lines | grep -aqE "^ +$1 +1  vt |^ +[0-9]+ +$1  " || return 0
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
      [ "$ok" = 1 ] && { echo "ok - vt: $name"; return 0; }
    fi
    sleep 0.2
  done
  echo "not ok - vt: $name: got$got, wanted $*"
  exit 1
}

# A point on the back window's header bar that the front window does not
# cover: 60 in from its left, past its new-tab button, or else from its
# right, before its close button.
back_title() {
  local x=$((b_x + 60)) y=$((b_y + 6))
  if [ $x -ge $f_x ] && [ $x -lt $((f_x + f_w)) ] && [ $y -ge $f_y ] && [ $y -lt $((f_y + f_h)) ]; then
    x=$((b_x + b_w - 60))
  fi
  echo "$x $y"
}

# The header bars are Adwaita's dark ones, 46 rows: 303030 in front,
# 242424 in the backdrop. The window draws them itself, so it has no
# frame: run windows gives all of it, and the terminal starts at its
# left, under the header bar, and under the tab bar, 40 more, with two
# tabs. The terminal is GNOME Console's, white on 1e1e1e, its cursor
# white too. The new-tab button is the header bar's first, 34 square 6
# in; the close button its last, 24 round 6 in from its right.
bar=46; tabbar=40
active="48 48 48"; backdrop="36 36 36"; ink="255 255 255"; cursor="255 255 255"; stem="194 194 194"
ground="30 30 30"
# The overlay scrollbar's slider: white at 40% over the terminal's
# 1e1e1e, (255 * 40 + 30 * 60 + 50) / 100. A selected tab: white at 10%
# over the header bar's 303030, (255 * 10 + 48 * 90 + 50) / 100.
thumb="120 120 120"; tab_on="69 69 69"

waits_for "^l0s> "
windows
read -r bx by <<< "$(back_title)"
shows "both windows, $f_title in front" "$((f_x + 60)) $((f_y + 6)) $active" "$bx $by $backdrop"

# The front window's corners are rounded by its shape: its top left pixel
# shows what is under it, as the pixel left of it does.
rm -f "$dump"; monitor "screendump $dump"
[ -s "$dump" ] && [ "$(pixel $f_x $f_y)" = "$(pixel $((f_x - 1)) $f_y)" ] && [ "$(pixel $f_x $f_y)" != "$active" ] ||
  fail "the top left corner of $f_title shows $(pixel $f_x $f_y), not what is under it, $(pixel $((f_x - 1)) $f_y)"
echo "ok - vt: $f_title's corners are rounded"

shows "$f_title's terminal under its header bar" "$((f_x + 100)) $((f_y + bar - 2)) $active" \
  "$((f_x + 600)) $((f_y + bar + 300)) $ground"

# The prompt's cursor on row 7's last pixel row, after "l0s> ".
shows "$f_title's shell is waiting" "$((f_x + 40)) $((f_y + bar + 7 * 16 + 15)) $cursor"
typekeys "echo hi"
# h's stem, column 1, its middle, on row 8: 11 of 15 covered, white mixed
# over the terminal's ground, as the smooth 8 by 16 glyph has it.
shows "echo hi typed and answered in $f_title" "$((f_x + 1)) $((f_y + bar + 8 * 16 + 8)) $stem"

# The two windows' vts are pids 17 and 18: boot, pid 1, starts
# /etc/system's programs after the inittab's thirteen, sh 14, font 15,
# wm 16, then the two vts, vt_base + 1 and vt_base + 2. Each registers
# its tab's name itself and starts the tab's shell, with no relay, so
# ps shows no vt but those two; nap's parent is the front window's
# shell, whose parent is its vt.
vt_base=16
typekeys "run nap 30000 &"
# Up to 10 s for ps to show nap.
end=$((SECONDS + 10))
until [ $SECONDS -ge $end ]; do
  lines=$(ps_lines)
  printf '%s\n' "$lines" | grep -aqE "^ +[0-9]+ +[0-9]+  nap " && break
  sleep 0.2
done
shell=$(printf '%s\n' "$lines" | grep -aE "^ +[0-9]+ +[0-9]+  nap " | tail -1 | awk '{print $2}')
[ -n "$shell" ] || fail "ps showed no nap; it showed:"
vt=$(printf '%s\n' "$lines" | grep -aE "^ +$shell +[0-9]+  sh " | tail -1 | awk '{print $2}')
[ "$vt" = $((vt_base + 1)) ] || [ "$vt" = $((vt_base + 2)) ] || fail "nap's shell, pid $shell, has parent ${vt:-none}, not a window's vt"
echo "ok - vt: $f_title's shell, pid $shell, started by its window's vt, pid $vt, ran nap"
vts=$(printf '%s\n' "$lines" | grep -aE "^ +[0-9]+ +[0-9]+  vt " | awk '{print $1}' | sort -n | tr '\n' ' ')
[ "$vts" = "$((vt_base + 1)) $((vt_base + 2)) " ] || fail "ps shows vts ${vts:-none}, not the windows' two, $((vt_base + 1)) and $((vt_base + 2)), and no relay"
echo "ok - vt: the windows' two vts and no relay"
# The other window's vt is the other of the two.
other_vt=$((vt_base + 1)); [ "$vt" = "$other_vt" ] && other_vt=$((vt_base + 2))

# A click on the back window's header bar brings it to the front.
front=$b_title; front_vt=$other_vt; other=$f_title; other_vt=$vt
click $bx $by
windows
[ "$f_title" = "$front" ] || fail "a click on $front's header bar left $f_title in front"
shows "a click brought $front to the front" "$((f_x + 60)) $((f_y + 6)) $active" "$(back_title | tr -d '\n') $backdrop"

# A drag of its header bar moves it as far as the pointer moved.
want_x=$((f_x + 150)); want_y=$((f_y + 120))
drag $((f_x + 60)) $((f_y + 10)) 150 120
windows
[ "$f_title" = "$front" ] && [ "$f_x" = "$want_x" ] && [ "$f_y" = "$want_y" ] ||
  fail "after the drag, $f_title is in front at $f_x, $f_y; wanted $front at $want_x, $want_y"
echo "ok - vt: a drag moved $front to $f_x, $f_y"

# The inittab three times over is more than the window's 24 rows: it
# scrolls, and the prompt's cursor is on the last row, row 23.
# Its output is not on the serial line: each is given a second to run
# before the next is typed.
for n in 1 2 3; do typekeys "run cat /etc/inittab"; sleep 1; done
shows "$front scrolled, the prompt on its last row" "$((f_x + 40)) $((f_y + bar + 383)) $cursor"

# A step of the wheel up over it shows the rows scrolled off, three of
# them, drawn from its cells: the toolkit's overlay scrollbar shows along
# its right, its slider 6 wide, 3 in, near its foot, as the view is only
# three rows back. A key typed, Backspace on the empty line, brings the
# view back to the bottom: the slider gone, the cursor back.
point $((f_x + 300)) $((f_y + bar + 200))
events "$(wheel wheel-up)"
slider="$((f_x + f_w - 6)) $((f_y + bar + 330))"
shows "the wheel scrolled $front back, its scrollbar shown" "$slider $thumb"
monitor "sendkey backspace"
shows "a key brought $front back to the bottom" "$slider $ground" "$((f_x + 40)) $((f_y + bar + 383)) $cursor"

# A line typed and not entered, l0s> and echo and 40 more, 50 columns:
# the cursor 50 in on the last row. The right edge, grabbed in the
# border outside it, dragged 320 in: 320 wide, 40 columns, the line wraps
# again, its first 40 on the row above, and the cursor is 10 into the
# last row. Dragged out again, it is whole, the cursor 50 in.
a10=aaaaaaaaaa
keys "echo $a10$a10$a10$a10"
shows "a line of 50 typed in $front" "$((f_x + 50 * 8 + 4)) $((f_y + bar + 383)) $cursor"
drag $((f_x + f_w + 2)) $((f_y + bar + 100)) -320 0
windows 2 "$front"
[ "$f_w" = 320 ] || fail "the right edge dragged 320 in left $front $f_w wide, not 320"
shows "the line wrapped again at 40, the cursor 10 into the last row" "$((f_x + 10 * 8 + 4)) $((f_y + bar + 383)) $cursor"
drag $((f_x + f_w + 2)) $((f_y + bar + 100)) 320 0
windows 2 "$front"
[ "$f_w" = 640 ] || fail "the right edge dragged out again left $front $f_w wide, not 640"
shows "the line whole again at 80, the cursor 50 in, not 10" "$((f_x + 50 * 8 + 4)) $((f_y + bar + 383)) $cursor" \
  "$((f_x + 10 * 8 + 4)) $((f_y + bar + 383)) $ground"
monitor "sendkey ret"
echo "ok - vt: $front resized by its edge, its lines wrapped again"

# The new-tab button opens a tab, vt3, the first name free, selected: it
# is the window's title, and the tab bar shows under the header bar, its
# second tab raised, its first not. Two tabs share the bar's 640, 6 in
# from each side and 3 apart: 312 each, the first from 6, the second
# from 321, 34 high from 3 down.
first=$front
click $((f_x + 6 + 17)) $((f_y + 23))
windows 2 vt3
shows "the new tab, vt3, selected on the tab bar" "$((f_x + 329)) $((f_y + bar + 20)) $tab_on" \
  "$((f_x + 14)) $((f_y + bar + 20)) $active"
top=$((bar + tabbar))
shows "vt3's shell is waiting" "$((f_x + 40)) $((f_y + top + 7 * 16 + 15)) $cursor"
typekeys "echo hi"
shows "echo hi typed and answered in vt3" "$((f_x + 1)) $((f_y + top + 8 * 16 + 8)) $stem"
lines=$(ps_lines)
n=$(printf '%s\n' "$lines" | grep -acE "^ +[0-9]+ +$front_vt  sh ")
[ "$n" = 2 ] || fail "ps shows $n shells started by $front's vt, pid $front_vt, not 2; it showed:"
tab_shell=$(printf '%s\n' "$lines" | grep -aE "^ +[0-9]+ +$front_vt  sh " | awk '{print $1}' | sort -n | tail -1)
echo "ok - vt: a tab opened by the button, vt3, its own shell, pid $tab_shell"

# A click on the first tab shows it: the title its name, the second tab
# no longer raised, and its prompt on its last row, row 20 now, the 344
# rows under the tab bar holding 21; and echo hi typed answered on row 19
# as the prompt comes back.
click $((f_x + 100)) $((f_y + bar + 20))
windows 2 "$first"
shows "the first tab, $first, shown again" "$((f_x + 329)) $((f_y + bar + 20)) $active" \
  "$((f_x + 44)) $((f_y + top + 20 * 16 + 15)) $cursor"
typekeys "echo hi"
shows "echo hi typed and answered in $first" "$((f_x + 1)) $((f_y + top + 19 * 16 + 8)) $stem"

# The second tab's close button, 24 square, 5 in from its end, 604 to
# 628: its shell is killed, so the tab closes, and with one tab left the
# tab bar goes, the terminal under the header bar again, past where the
# second tab ended.
click $((f_x + 616)) $((f_y + bar + 20))
windows 2 "$first"
shows "vt3 closed, the tab bar gone" "$((f_x + 639)) $((f_y + bar + 20)) $ground"
ps_lines | grep -aqE "^ +$tab_shell +$front_vt  sh " && fail "after its tab closed, vt3's shell, pid $tab_shell, is still there"
echo "ok - vt: vt3's close button ended its shell and closed it"

# Ctrl-Shift-T, on the USB keyboard through wm, opens a tab as the
# button does: the tab bar again, the new second tab raised; its close
# button closes it, as before.
monitor "sendkey ctrl-shift-t"
shows "Ctrl-Shift-T opened a tab" "$((f_x + 329)) $((f_y + bar + 20)) $tab_on" \
  "$((f_x + 14)) $((f_y + bar + 20)) $active"
click $((f_x + 616)) $((f_y + bar + 20))
shows "its close button closed it, the tab bar gone" "$((f_x + 639)) $((f_y + bar + 20)) $ground"
windows 2 "$first"

# exit at its shell ends the shell, and so its tab, the window's last,
# so the window closes and its vt ends: the other is left, in front, and
# ps shows neither the vt nor a shell of it.
typekeys "exit"
windows 1
[ "$f_title" = "$other" ] || fail "after exit in $first, $f_title is left, not $other"
gone $front_vt ||
  fail "after exit in $first, ps still shows its vt, pid $front_vt, or a process it started"
echo "ok - vt: exit closed $first, its vt gone, $other left in front"

# A click on the close button, at the right end of the header bar: the
# window's vt ends its tab's shell, and closes the window.
click $((f_x + f_w - 18)) $((f_y + 23))
windows 0
gone $other_vt ||
  fail "after the close button, ps still shows $other's vt, pid $other_vt, or a process it started"
echo "ok - vt: the close button ended $other's vt and its shell"
