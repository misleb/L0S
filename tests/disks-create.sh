#!/usr/bin/env bash
# disks-create.sh -- a partition and a volume made with Disks
# (user/apps/disks). Boots tests/disks/etc's initramfs, the compositor with no
# window and the disk's driver and file server, on a disk build/mkfs
# makes with sectors 1040 to 1535 free between data and scratch, as
# tests/partitions.sh does. Types run disks & at the serial shell, learns
# where its window is from run windows, and checks, by QEMU's screendump:
#
#   1. data selected in the accent, and the free space after it on the
#      window's ground
#   2. a click of the tablet, through QMP, on that free space: selected
#   3. a click on Create Partition...: the dialog, its entry focused, in
#      the accent's ring, and Create in the accent, for all the free space
#   4. the size typed, through the monitor's sendkey, as 999 kB, more
#      than there is: Create faded; then as 254: Create again
#   5. Enter: the dialog gone, and the new partition selected where the
#      free space was
#   6. a click on Format...: the dialog, its entry focused, and Format
#      faded, for no name; made typed: Format in the accent
#   7. Enter: the dialog gone, and at the serial shell /Volumes listing
#      made, a file written to it and read back
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# disks-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/disks-create.sock"
qmp="$BUILD/disks-create.qmp"
fifo="$BUILD/disks-create.in"
out="$BUILD/disks-create.out"
dump="$BUILD/disks-create.ppm"
disk="$BUILD/disks-create.img"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"
make -s build/mkfs
"$BUILD/mkfs" "$disk" 2048 "$(date +%s)000" data:40:1000 scratch:1536:479 || { echo "not ok - disks-create: mkfs failed"; exit 1; }

QEMU_DISK="$disk" QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/disks.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - disks-create: $1"; sed 's/^/  # /' "$out"; exit 1; }

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
click() {
  events "$(at "$1" "$2")"; sleep 1
  events "$(button true)"; sleep 1
  events "$(button false)"; sleep 1
}

# Keys on the virtio keyboard, through the monitor: each argument one
# key, as sendkey names it.
keys() {
  local k
  for k in "$@"; do monitor "sendkey $k"; sleep 0.3; done
}

waits_for() {
  local try
  for try in $(seq 1 30); do
    grep -qE "$1" "$out" 2> /dev/null && return 0
    sleep 1
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# Where Disks's window is, as run windows lists it: w_x, w_y.
window() {
  local try from line
  for try in $(seq 1 30); do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    sleep 1
    line=$(tail -c +$from "$out" | grep -aE '^[0-9]+ Disks ' | head -1)
    if [ -n "$line" ]; then
      read -r _ _ w_x w_y _ _ _ <<< "$line"
      return 0
    fi
  done
  fail "run windows never listed Disks's window; it showed:"
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
      [ "$ok" = 1 ] && { echo "ok - disks-create: $name"; return 0; }
    fi
    sleep 1
  done
  echo "not ok - disks-create: $name: got$got, wanted $*"
  exit 1
}

# What the serial shell prints for a command.
said() {
  local from
  from=$(($(wc -c < "$out") + 1))
  printf '%s\n' "$1" >&3
  sleep 2
  tail -c +$from "$out"
}

# The window's content starts under its 46-row header bar, 2 in from its
# left. In it the pane is from 221, 18 in, and the bar of volumes from
# 239, 164, 623 by 64, its parts 4 in, from 243, 168, 56 high: 615 across,
# 609 of it the parts' and 6 the three gaps. Each part is 48 and a share
# by sectors of the other 417, of 1981: the gap before data 49, data 258,
# the free space 152 and scratch the rest, 150. So the free space is from
# 554 to 706; the button under the bar from 239, 240, 34 high.
#
# Create Partition's card is 362 by 224, in the middle of the window's
# 880 by 520, from 259, 148, and its content 24 in, from 283, 172: its
# heading, a line, and from 228 its Size, the names' column 160 wide,
# "Free Space Following", so the entry 120 wide from 455, 34 high; under
# it the space left, and from 314 its buttons, each in a half of the 314
# across, 12 apart: Create, 68 wide, from 487.
#
# Format's card is 340 by 224, from 270, 148, its content from 294, 172:
# its Volume Name, the names' column 88 wide, so the entry from 394; its
# buttons from 314, each in a half of 292: Format, 68 wide, from 482.
#
# On a card's white the entry's ring, the accent at half, is 154 194 242,
# as is a suggested button faded.
bar=46
ground="250 250 250"; sidebar="235 235 237"; accent="53 132 228"; faded="154 194 242"

waits_for "^l0s> "
printf 'run disks &\n' >&3
waits_for "\[pid [0-9]+ running\]"
window
cx=$((w_x + 2)); cy=$((w_y + bar))
segy=$((cy + 172))
data_x=$((cx + 420)); free_x=$((cx + 630))
button_x=$((cx + 280)); button_y=$((cy + 257))
# Each dialog's button, 4 in, before its label, which is 10 in.
create_x=$((cx + 491)); format_x=$((cx + 486)); ok_y=$((cy + 331))

shows "data selected, the free space after it" "$data_x $segy $accent" "$free_x $segy $ground"

click $free_x $((cy + 200))
shows "a click selected the free space" "$free_x $segy $accent"

click $button_x $button_y
shows "Create Partition... asks, its entry focused, all of it to fit" \
  "$((cx + 515)) $((cy + 228)) $faded" "$create_x $ok_y $accent"

keys backspace backspace backspace backspace backspace 9 9 9
shows "999 kB does not fit" "$create_x $ok_y $faded"
keys backspace backspace backspace 2 5 4
shows "254 kB fits" "$create_x $ok_y $accent"

keys ret
shows "Enter made the partition, and selected it" "$((cx + 100)) $((cy + 300)) $sidebar" "$free_x $segy $accent"

click $button_x $button_y
shows "Format... asks, its entry focused, for a name" \
  "$((cx + 460)) $((cy + 228)) $faded" "$format_x $ok_y $faded"
keys m a d e
shows "made is a name" "$format_x $ok_y $accent"

keys ret
shows "Enter made the volume" "$((cx + 100)) $((cy + 300)) $sidebar" "$free_x $segy $accent"
said 'ls /Volumes' | grep -aq "made/" || fail "/Volumes has no made; it showed:"
said 'write /Volumes/made/hello hi there' > /dev/null
said 'cat /Volumes/made/hello' | grep -aq "hi there" || fail "the file on made was not read back; it showed:"
echo "ok - disks-create: made is mounted at /Volumes/made, and holds a file"
