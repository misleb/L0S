#!/usr/bin/env bash
# launch.sh -- boots tests/disks/etc's initramfs, the compositor with no
# window and the disk's driver and file server, on a fresh disk from
# tools/mkdisk, and launches apps from the launcher, by the tablet
# through QMP, and with open at the serial shell, checking what run
# windows lists and, by QEMU's screendump, what shows:
#
#   1. Files clicked in the launcher twice: two Files windows, of one
#      client, the second in front, as the running Files was asked to
#      open and opened a window more (roadmap 0032)
#   2. Disks clicked twice: one Disks window, in front
#   3. Terminal clicked: its window over Disks; Disks clicked again:
#      Disks in front once more, still one window, and no other process
#   4. run open files /Volumes: a third Files window, of the same
#      client, in front, at /Volumes, its sidebar's Volumes row selected
#      and Computer's not
#   5. Terminal clicked again: a second window of the same vt, in
#      front, titled with its own tab's name, and wm never said an app
#      did not answer its open
#
# Pids are read from run windows, never fixed. The serial line is typed
# through a FIFO, and the board keeps running until this kills it. Run
# from the top of the project, after make disks-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/launch.sock"
qmp="$BUILD/launch.qmp"
fifo="$BUILD/launch.in"
out="$BUILD/launch.out"
dump="$BUILD/launch.ppm"
disk="$BUILD/launch-test.img"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"
tools/mkdisk "$disk"

QEMU_DISK="$disk" QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/disks.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - launch: $1"; sed 's/^/  # /' "$out"; exit 1; }

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

# The windows, as run windows lists them, front first: each line ID
# TITLE X Y W H front-or-- PID, the pointer's line left out; in $wins.
listed() {
  local from
  from=$(($(wc -c < "$out") + 1))
  printf 'run windows\n' >&3
  sleep 2
  wins=$(tail -c +$from "$out" | tr -d '\r' | grep -aE '^[0-9]+ [^ ]+ -?[0-9]+ -?[0-9]+ [0-9]+ [0-9]+ (front|-) [0-9]+$')
}

# How many windows titled $1 there are, and how many clients they have.
count() { printf '%s\n' "$wins" | grep -cE "^[0-9]+ $1 " ; }
clients() { printf '%s\n' "$wins" | grep -E "^[0-9]+ $1 " | awk '{print $8}' | sort -u | grep -c . ; }

# The front window's title.
front() { printf '%s\n' "$wins" | grep -E ' front [0-9]+$' | awk '{print $2}'; }

# Waits up to 40 s for run windows to list n windows titled t, of one
# client, the front one titled f.
expects() {
  local name=$1 t=$2 n=$3 f=$4 try
  for try in $(seq 1 20); do
    listed
    if [ "$(count "$t")" = "$n" ] && [ "$(clients "$t")" = 1 ] && [ "$(front)" = "$f" ]; then
      echo "ok - launch: $name"
      return 0
    fi
  done
  echo "not ok - launch: $name: run windows listed:"
  printf '%s\n' "$wins" | sed 's/^/  # /'
  exit 1
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
      [ "$ok" = 1 ] && { echo "ok - launch: $name"; return 0; }
    fi
    sleep 1
  done
  echo "not ok - launch: $name: got$got, wanted $*"
  exit 1
}

# Applications is at 60, 16 on the top bar. The launcher's seven apps,
# About, Disks, Files, Fonts, System Monitor, Terminal and Widgets, are
# one row of cells 136 wide from (1280 - 7 * 136) / 2 = 164, their icons
# 48 square 44 in and 12 down from 96 (launcher.sh): Disks's icon is at
# 344 to 392, Files's at 480 to 528, Terminal's at 888 to 936, each
# clicked at its middle, 150 down.
apps_x=60; disks_x=368; files_x=504; terminal_x=912; icon_y=150

# Files's windows are 880 by 560, its content at the x, y run windows
# gives: its sidebar's rows from 52, 48 each, Computer's middle 76 down
# and Volumes's 124, the row selected 434347, the others 2e2e32
# (files.sh).
sidebar="46 46 50"; side_sel="67 67 71"

waits_for "^l0s> "
waits_for "serving compositor"
sleep 2

# 1. Files, twice: one client, two windows.
click $apps_x 16; click $files_x $icon_y
expects "Files launched: its window, in front" Files 1 Files
click $apps_x 16; click $files_x $icon_y
expects "Files again: two windows of one client, the new one in front" Files 2 Files

# 2. Disks, twice: one window.
click $apps_x 16; click $disks_x $icon_y
expects "Disks launched: its window, in front" Disks 1 Disks
click $apps_x 16; click $disks_x $icon_y
sleep 2
expects "Disks again: still one window, in front" Disks 1 Disks

# 3. Terminal over Disks, then Disks again: Disks in front, with the
# keyboard's focus, which goes to the front window.
click $apps_x 16; click $terminal_x $icon_y
for try in $(seq 1 20); do
  listed
  f=$(front)
  [ -n "$f" ] && [ "$f" != Disks ] && [ "$f" != Files ] && break
done
[ -n "$f" ] && [ "$f" != Disks ] && [ "$f" != Files ] || fail "Terminal's window never came in front"
echo "ok - launch: Terminal launched, its window over Disks"
disks_pid=$(printf '%s\n' "$wins" | grep -E '^[0-9]+ Disks ' | awk '{print $8}')
click $apps_x 16; click $disks_x $icon_y
expects "Disks again, from behind Terminal: in front, one window" Disks 1 Disks
now_pid=$(printf '%s\n' "$wins" | grep -E '^[0-9]+ Disks ' | awk '{print $8}')
[ "$now_pid" = "$disks_pid" ] || fail "Disks is pid $now_pid now, not $disks_pid: it was started again"
echo "ok - launch: the same Disks, pid $disks_pid"

# 4. open files /Volumes: a third window of the one Files, there.
printf 'run open files /Volumes\n' >&3
expects "open files /Volumes: a third Files window, in front" Files 3 Files
line=$(printf '%s\n' "$wins" | grep -E ' front [0-9]+$')
read -r _ _ fx fy _ <<< "$line"
shows "at /Volumes: its Volumes row selected, Computer's not" \
  "$((fx + 200)) $((fy + 124)) $side_sel" "$((fx + 200)) $((fy + 76)) $sidebar"

# 5. Terminal again: a second window of the one vt, in front, with a
# tab of its own (so a title of its own, its tab's name), and no wait on
# wm's 2 seconds for an open vt never answered (roadmap 0032's last
# step).
term_pid=$(printf '%s\n' "$wins" | grep -vE '^[0-9]+ (Files|Disks) ' | awk '{print $8}' | sort -u | head -1)
[ -n "$term_pid" ] || fail "no Terminal window listed"
click $apps_x 16; click $terminal_x $icon_y
for try in $(seq 1 20); do
  listed
  n=$(printf '%s\n' "$wins" | awk -v p="$term_pid" '$8 == p' | grep -c .)
  fp=$(printf '%s\n' "$wins" | grep -E ' front [0-9]+$' | awk '{print $8}')
  [ "$n" = 2 ] && [ "$fp" = "$term_pid" ] && break
done
if [ "$n" != 2 ] || [ "$fp" != "$term_pid" ]; then
  echo "not ok - launch: Terminal again: run windows listed:"
  printf '%s\n' "$wins" | sed 's/^/  # /'
  exit 1
fi
titles=$(printf '%s\n' "$wins" | awk -v p="$term_pid" '$8 == p {print $2}' | sort -u | grep -c .)
[ "$titles" = 2 ] || fail "Terminal's two windows share one title, so one tab name"
echo "ok - launch: Terminal again: two windows of one vt, pid $term_pid, the new one in front"
grep -q "did not answer its open" "$out" && fail "wm waited on an open no app answered"
echo "ok - launch: every open answered"
