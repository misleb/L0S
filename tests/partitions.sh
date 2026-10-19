#!/usr/bin/env bash
# partitions.sh -- a partition made, and a volume on it by the UUID it
# was given, on the board. Boots tests/disks/etc's initramfs, the disk's
# driver and file server, on a disk build/mkfs makes with sectors 1040
# to 1535 free between data and scratch, and at the serial shell:
#
#   1. partition 400: a UUID of version 7, said, beginning with the
#      clock's time
#   2. mkfs UUID made: /Volumes/made listed, a file written to it and
#      read back, df counting it
#   3. mkfs of the same UUID again: refused, its volume served
#   4. the board booted again on the same disk: made is mounted at once,
#      and the UUID still names its partition, so mkfs is refused again
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# disks-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
fifo="$BUILD/partitions.in"
out="$BUILD/partitions.out"
disk="$BUILD/partitions.img"
qemu=""

fail() { echo "not ok - partitions: $1"; sed 's/^/  # /' "$out"; exit 1; }

make -s build/mkfs
"$BUILD/mkfs" "$disk" 2048 "$(date +%s)000" data:40:1000 scratch:1536:479 > /dev/null || fail "mkfs failed"

boot() {
  rm -f "$fifo"; mkfifo "$fifo"
  QEMU_DISK="$disk" tools/qemu-boot.sh "$BUILD/disks.cpio" < "$fifo" > "$out" 2>&1 &
  qemu=$!
  exec 3> "$fifo"
  waits_for "^l0s> "
}
stop() { kill $qemu 2> /dev/null; wait $qemu 2> /dev/null; exec 3>&-; }
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT

waits_for() {
  local try
  for try in $(seq 1 30); do
    grep -qE "$1" "$out" 2> /dev/null && return 0
    sleep 1
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# What the serial shell prints for a command.
said() {
  local from
  from=$(($(wc -c < "$out") + 1))
  printf '%s\n' "$1" >&3
  sleep 2
  tail -c +$from "$out"
}

ok() { echo "ok - partitions: $1"; }

boot
uuid=$(said 'partition 400' | grep -aoE '[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}' | head -1)
[ -n "$uuid" ] || fail "partition said no UUID of version 7; it showed:"
# Its first 48 bits are the clock's time in milliseconds: after 2020.
ms=$((16#$(echo "$uuid" | tr -d - | cut -c1-12)))
[ "$ms" -gt 1577836800000 ] || fail "the UUID's time, $ms ms, is not the clock's; it showed:"
ok "partition 400 made $uuid, of the clock's time"

said "mkfs $uuid made" | grep -aq "sh: mkfs" && fail "mkfs refused; it showed:"
said 'ls /Volumes' | grep -aq "made/" || fail "/Volumes has no made; it showed:"
said 'write /Volumes/made/hello hi there' > /dev/null
said 'cat /Volumes/made/hello' | grep -aq "hi there" || fail "the file on made was not read back; it showed:"
# 196K of clusters: its root directory's 4K and its file's 4K used.
said 'df' | grep -aqE "/Volumes/made +196K +8K +188K +1" || fail "df does not count made; it showed:"
ok "mkfs made a volume on it, by its UUID, served at /Volumes/made"

said "mkfs $uuid again" | grep -aq "its volume is served" || fail "a second mkfs was not refused; it showed:"
ok "a second mkfs of it is refused"

stop
boot
said 'ls /Volumes' | grep -aq "made/" || fail "made was not mounted at boot; it showed:"
said 'cat /Volumes/made/hello' | grep -aq "hi there" || fail "made's file is gone; it showed:"
said "mkfs $uuid again" | grep -aq "its volume is served" || fail "the UUID no longer names the partition; it showed:"
ok "booted again, made is served, and $uuid still names its partition"
