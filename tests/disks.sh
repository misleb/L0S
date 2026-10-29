#!/usr/bin/env bash
# disks.sh -- boots tests/disks/etc's initramfs, the compositor with no
# window and the disk's driver and file server, on a fresh disk from
# tools/mkdisk. Writes a file on data, types run disks & at the serial
# shell, which opens Disks (user/apps/disks) in a window, learns where it is
# from run windows, and checks, by QEMU's screendump:
#
#   1. the sidebar's ground, 2e2e32, and its drive's row selected, 434347
#   2. the bar of volumes: data, the first volume, selected in the accent;
#      the free space before it on the window's ground; scratch on the
#      view's
#   3. a click of the tablet, through QMP, on scratch: it is selected,
#      and data on the view's ground
#   4. a click on Format Volume...: the dialog, its Format button red,
#      over the window dimmed, the sidebar's ground mixed with black
#   5. Esc, through the monitor's sendkey: the dialog gone
#   6. data selected again, Format Volume..., and the dialog's Format:
#      the dialog gone, and ls /Volumes/data at the serial shell listing
#      no file
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# disks-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/disks.sock"
qmp="$BUILD/disks.qmp"
fifo="$BUILD/disks.in"
out="$BUILD/disks.out"
dump="$BUILD/disks.ppm"
disk="$BUILD/disks-test.img"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"
tools/mkdisk "$disk"

QEMU_DISK="$disk" QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/disks.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - disks: $1"; sed 's/^/  # /' "$out"; exit 1; }

monitor() { printf '%s\n' "$1" | tools/qsock "$sock" > /dev/null 2>&1; }

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
# A click at x, y: there, pressed, let go. What it does is waited for
# by what checks it, not here.
click() {
  events "$(at "$1" "$2")"; sleep 0.1
  events "$(button true)"; sleep 0.1
  events "$(button false)"
}

# Waits up to 30 s for a line like the regex on the serial line.
waits_for() {
  local end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    grep -qE "$1" "$out" 2> /dev/null && return 0
    sleep 0.2
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# Waits up to 5 s for the shell's prompt on the serial line after byte
# offset from.
prompt_after() {
  local end=$((SECONDS + 5))
  until [ $SECONDS -ge $end ] || tail -c +$1 "$out" | grep -aq 'l0s> '; do sleep 0.1; done
}

# Where Disks's window is, as run windows lists it: w_x, w_y. Asks for
# up to 30 s.
window() {
  local from line end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    prompt_after $from
    line=$(tail -c +$from "$out" | grep -aE '^[0-9]+ Disks ' | head -1)
    if [ -n "$line" ]; then
      read -r _ _ w_x w_y _ _ _ <<< "$line"
      return 0
    fi
    sleep 0.2
  done
  fail "run windows never listed Disks's window; it showed:"
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
      [ "$ok" = 1 ] && { echo "ok - disks: $name"; return 0; }
    fi
    sleep 0.2
  done
  echo "not ok - disks: $name: got$got, wanted $*"
  exit 1
}

# What the serial shell prints for a command, up to its next prompt.
said() {
  local from
  from=$(($(wc -c < "$out") + 1))
  printf '%s\n' "$1" >&3
  prompt_after $from
  tail -c +$from "$out"
}

# The window's content starts under its 46-row header bar, 2 in from its
# left. In it: the sidebar, 220 wide, its row from 6, 6 to 214, 54; a
# line; the pane from 221, 18 in. Down the pane: the heading's row, 34;
# the drive's three properties, 60; "Volumes", 16; the bar, 64, from 164,
# its parts 4 in, from 168 to 224, 611 between them: 48 each and the
# rest, 467, by size, so free space 49 from 243, data 396 from 294 and
# scratch 166 from 692, 2 apart; then Format Volume... from 240, at 239.
# The dialog's card is 320 by 156 in the middle of the window's 880 by
# 520, from 280, 182; its buttons' row from 280, 34 high, each in a half
# of the 272 inside it, 12 apart, its Format button, 68 wide, from 477.
bar=46
sidebar="46 46 50"; side_sel="67 67 71"; ground="36 36 36"; view="30 30 30"
accent="53 132 228"; red="224 27 36"; side_dim="32 32 35"

waits_for "^l0s> "
# The prompt can come before the disk's volumes are mounted.
waits_for "/Volumes/data mounted"
said 'write /Volumes/data/hello hi' > /dev/null
said 'ls /Volumes/data' | grep -q "hello" || fail "the file was not written; it showed:"
printf 'run disks &\n' >&3
waits_for "\[pid [0-9]+ running\]"
window
cx=$((w_x + 2)); cy=$((w_y + bar))
segy=$((cy + 172))
free_x=$((cx + 260)); data_x=$((cx + 300)); scratch_x=$((cx + 800))
format_x=$((cx + 300)); format_y=$((cy + 257))

shows "the sidebar, its drive selected" "$((cx + 100)) $((cy + 300)) $sidebar" "$((cx + 200)) $((cy + 50)) $side_sel"
shows "data selected, free space before it, scratch after" \
  "$data_x $segy $accent" "$free_x $segy $ground" "$scratch_x $segy $view"

click $scratch_x $((cy + 200))
shows "a click selected scratch" "$scratch_x $segy $accent" "$data_x $segy $view"

click $data_x $((cy + 200))
click $format_x $format_y
shows "Format Volume... asks, over the window dimmed" "$((cx + 500)) $((cy + 284)) $red" "$((cx + 100)) $((cy + 300)) $side_dim"

monitor "sendkey esc"
shows "Esc closed the dialog" "$((cx + 100)) $((cy + 300)) $sidebar" "$data_x $segy $accent"

click $format_x $format_y
shows "the dialog again" "$((cx + 500)) $((cy + 284)) $red"
click $((cx + 510)) $((cy + 297))
shows "Format closed it" "$((cx + 100)) $((cy + 300)) $sidebar"
if said 'ls /Volumes/data' | grep -q "hello"; then fail "data still has its file; it showed:"; fi
echo "ok - disks: formatting emptied data"
