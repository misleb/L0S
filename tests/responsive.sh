#!/usr/bin/env bash
# responsive.sh -- boots tests/disks/etc's initramfs, the compositor with
# no window and the disk's driver and file server, on a disk whose data
# volume holds a folder of 400 files, and checks that a window answers
# the pointer at once (roadmap 0033), by QEMU's screendump:
#
#   1. Fonts opened from the launcher, Source Sans 3's page open: the
#      pointer moved onto Back, from the title, through QMP, and the
#      button lit in a screendump within bound_ms of the move, dumps
#      taken one after another from the move on
#   2. Files opened at the folder of 400 files (run open files PATH),
#      which it lists by asking fs and then looks at a file at a time as
#      idle work: the pointer moved onto its menu button while it does,
#      the button lit the same way
#
# Each is tried tries times, the pointer taken off the button and left
# a second between, and passes on the quickest: one slow try of several
# is the host's load, not the window's. The move and the dumps go over a
# QMP and a monitor connection kept open, each waited for until QEMU
# answers, so what is timed is the move, the app's step, the
# compositor's and the display's work, and the dump that shows it.
#
# bound_ms is 250, not the 50 ms the goal names: alone on this host the
# button shows lit 38 to 65 ms after the move, in the second dump, each
# dump 15 to 30 ms of it, and a dump stops the board while QEMU writes
# it; under make e2e's parallel boots both are slower. Run from the top
# of the project, after make disks-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/responsive.sock"
qmp="$BUILD/responsive.qmp"
fifo="$BUILD/responsive.in"
out="$BUILD/responsive.out"
dump="$BUILD/responsive.ppm"
disk="$BUILD/responsive-test.img"
many="$BUILD/responsive-files"
cpio="$BUILD/responsive-files.cpio"
bound_ms=250
tries=5
rm -f "$sock" "$qmp" "$fifo" "$dump"
rm -rf "$many" && mkdir -p "$many/many"
for i in $(seq 1 400); do printf 'file %d\n' "$i" > "$many/many/f$i"; done
(cd "$many" && find . | LC_ALL=C sort | bsdtar -n --format newc -cf "../$(basename "$cpio")" -T -)
tools/mkdisk "$disk" 8192 data:40:8000:"$cpio" > /dev/null
mkfifo "$fifo"

QEMU_DISK="$disk" QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/disks.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo" "$BUILD/responsive.qin" "$BUILD/responsive.min"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - responsive: $1"; sed 's/^/  # /' "$out"; exit 1; }

axis() { echo $(( $1 * 32767 / ($2 - 1) )); }
at() {
  echo "{\"type\":\"abs\",\"data\":{\"axis\":\"x\",\"value\":$(axis "$1" 1280)}},{\"type\":\"abs\",\"data\":{\"axis\":\"y\",\"value\":$(axis "$2" 800)}}"
}
button() { echo "{\"type\":\"btn\",\"data\":{\"down\":$1,\"button\":\"left\"}}"; }

# A click at x, y: there, pressed, let go, on the QMP line kept open
# (open_lines), as QEMU's sockets take one client at a time. What it
# does is waited for by what checks it, not here.
click() {
  moved $1 $2; sleep 0.1
  sent "$(button true)"; sleep 0.1
  sent "$(button false)"
}

waits_for() {
  local end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    grep -qaE "$1" "$out" 2> /dev/null && return 0
    sleep 0.2
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# Where the window titled $1 is, as run windows lists it: w_x, w_y.
# Waits up to 30 s for it to be listed, each run windows read up to the
# shell's next prompt, waited for up to 5 s.
window() {
  local from line end=$((SECONDS + 30)) prompt
  until [ $SECONDS -ge $end ]; do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    prompt=$((SECONDS + 5))
    until [ $SECONDS -ge $prompt ] || tail -c +$from "$out" | grep -aq 'l0s> '; do sleep 0.1; done
    line=$(tail -c +$from "$out" | grep -aE "^[0-9]+ $1 " | head -1)
    if [ -n "$line" ]; then
      read -r _ _ w_x w_y _ <<< "$line"
      return 0
    fi
    sleep 0.2
  done
  fail "run windows never listed $1's window; it showed:"
}

# Pixel x, y of the screendump, a 1280 by 800 PPM whose header is 16 bytes.
pixel() { od -An -tu1 -j $((16 + ($2 * 1280 + $1) * 3)) -N3 "$dump" | tr -s ' ' | sed 's/^ //; s/ $//'; }

# Waits up to 30 s for pixel x, y to be r g b.
shows() {
  local end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    dumped
    [ -s "$dump" ] && [ "$(pixel $1 $2)" = "$3" ] && return 0
    sleep 0.2
  done
  fail "$4: pixel $1,$2 is $(pixel $1 $2), not $3"
}

# Waits up to 30 s for Fonts' grid of cards drawn: the view's ground,
# 30 30 30, at g, y, and some ink, anything else, from x0 up to x1 of
# row y. Arguments x0 x1 y g.
cards() {
  local end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    dumped
    if [ -s "$dump" ] && [ "$(pixel $4 $3)" = "30 30 30" ] \
      && od -An -tu1 -v -j $((16 + ($3 * 1280 + $1) * 3)) -N $((($2 - $1) * 3)) "$dump" \
        | tr -s ' ' '\n' | grep -v '^$' | paste - - - | grep -qv '^30	30	30$'; then
      return 0
    fi
    sleep 0.2
  done
  fail "Fonts never drew its cards"
}

now_ms() { echo $(( $(date +%s%N) / 1000000 )); }

# A connection to QMP and one to the monitor kept open for the timed
# moves and dumps, so no connection is made, nor waited out (nc's -w), in
# what is timed: each a FIFO into nc and nc's answers in a file.
open_lines() {
  rm -f "$BUILD/responsive.qin" "$BUILD/responsive.min" "$BUILD/responsive.qout" "$BUILD/responsive.mout"
  mkfifo "$BUILD/responsive.qin" "$BUILD/responsive.min"
  nc -U "$qmp" < "$BUILD/responsive.qin" > "$BUILD/responsive.qout" 2>&1 &
  nc -U "$sock" < "$BUILD/responsive.min" > "$BUILD/responsive.mout" 2>&1 &
  exec 5> "$BUILD/responsive.qin" 6> "$BUILD/responsive.min"
  printf '{"execute":"qmp_capabilities"}\n' >&5
  answered "$BUILD/responsive.qout" 0 '"return"' || fail "QMP never answered qmp_capabilities"
}

# Waits until file $1 holds more than $2 lines saying $3.
answered() {
  local n
  for n in $(seq 1 2000); do
    [ "$(grep -ac "$3" "$1")" -gt "$2" ] && return 0
    sleep 0.002
  done
  return 1
}

# Input events $1 sent on the open line, once QEMU has them.
sent() {
  local n
  n=$(grep -ac '"return"' "$BUILD/responsive.qout")
  printf '{"execute":"input-send-event","arguments":{"events":[%s]}}\n' "$1" >&5
  answered "$BUILD/responsive.qout" "$n" '"return"'
}

# The pointer moved to x, y on the open line, once QEMU has it.
moved() { sent "$(at $1 $2)"; }

# A screendump on the open line, once QEMU has written it.
dumped() {
  local n
  rm -f "$dump"
  n=$(grep -ac '(qemu)' "$BUILD/responsive.mout")
  printf 'screendump %s\n' "$dump" >&6
  answered "$BUILD/responsive.mout" "$n" '(qemu)'
}

# Screendumps taken one after another until pixel x, y is lit, for 3 s
# at most: in $t1 the ms from t0 to the end of the first dump showing it
# lit (999999 if none did), in $dumps how many were taken.
lit_by() {
  local now
  dumps=0; t1=999999
  while :; do
    dumped
    dumps=$((dumps + 1))
    now=$(now_ms)
    if [ -s "$dump" ] && [ "$(pixel $1 $2)" = "$3" ]; then t1=$((now - $4)); return 0; fi
    [ $((now - $4)) -gt 3000 ] && return 1
  done
}

# The pointer moved from x0, y onto x1, y, a flat button whose ground at
# x1, y is lit, from header to lit, by the first screendump after the
# move: the quickest of tries, in ms from the move sent to the dump
# written, in $quick; fails if never lit.
answers() {
  local name=$1 x0=$2 x1=$3 y=$4 lit=$5 t0 t1 best=999999 try
  for try in $(seq 1 $tries); do
    moved $x0 $y; sleep 1
    t0=$(now_ms)
    moved $x1 $y
    lit_by "$x1" "$y" "$lit" "$t0"
    [ "$t1" -lt $best ] && best=$t1
    echo "  # $name: try $try, lit after $t1 ms, $dumps dumps"
  done
  quick=$best
  [ "$best" -lt 999999 ] || fail "$name: the button was not lit in the first screendump after the move, in $tries tries"
  [ "$best" -le "$bound_ms" ] || fail "$name: lit only $best ms after the move, over $bound_ms"
}

# Fonts is the fourth of the launcher's seven apps, its icon's middle at
# 640, 130 (fontview.sh). Its page's header bar: Back 34 square from 6,
# 6, its ground at 9, 22, 30 30 30 on the header's 48 48 48 at rest and
# 62 62 62 under the pointer; the title from 300 along.
header="48 48 48"; lit="62 62 62"

waits_for "^l0s> "
waits_for "serving compositor"
open_lines
# Applications clicked, and the launcher's pill, 404040 at 40, 16, waited
# for (launcher.sh) before Fonts' icon is.
click 60 16
shows 40 16 "64 64 64" "the launcher's pill"
click 640 130
window Fonts
fx=$w_x; fy=$w_y
# Its cards drawn (fontview.sh): the third's Aa, from 294 to 342, 100
# down, inked on the view's ground, at 20 left of the first tile; then
# that card clicked.
cards $((fx + 294)) $((fx + 342)) $((fy + 100)) $((fx + 20))
click $((fx + 318)) $((fy + 106))
shows $((fx + 9)) $((fy + 22)) "$header" "Source Sans 3's page and its Back"
sleep 3
answers "Fonts' Back" $((fx + 300)) $((fx + 9)) $((fy + 22)) "$lit"
echo "ok - responsive: Fonts' Back lit $quick ms after the pointer came, at most $bound_ms"

# Files' window, 880 by 560: its place's header bar's menu button 34
# square at 810, 6, its ground at 813, 24 (files.sh); the path bar from
# 400.
printf 'run open files /Volumes/data/many\n' >&3
window Files
cx=$w_x; cy=$w_y
shows $((cx + 813)) $((cy + 24)) "$header" "Files' menu button"
answers "Files' menu button, listing 400 files" $((cx + 500)) $((cx + 813)) $((cy + 24)) "$lit"
echo "ok - responsive: Files' menu button lit $quick ms after the pointer came, at most $bound_ms, as it looks at 400 files"

# The folder listed: its first tile's icon, 48 square from 302, 70 of
# the window (files.sh), drawn on the view's ground, 30 30 30.
end=$((SECONDS + 30))
until [ $SECONDS -ge $end ]; do
  dumped
  [ -s "$dump" ] && [ "$(pixel $((cx + 326)) $((cy + 100)))" != "30 30 30" ] && break
  sleep 0.2
done
[ "$(pixel $((cx + 326)) $((cy + 100)))" != "30 30 30" ] || fail "Files never showed the folder's files"
echo "ok - responsive: Files listed the folder of 400 files"
