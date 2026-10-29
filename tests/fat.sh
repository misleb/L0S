#!/usr/bin/env bash
# fat.sh -- FAT32 as other systems have it, both ways: what L0S writes is
# what their own tools take, and what they make L0S reads and writes.
#
#   1. a disk build/mkfs makes, FAT32 filled from build/initramfs.cpio:
#      the host's fsck finds nothing wrong
#   2. a disk the host makes, an MBR and a FAT32 volume of type 0B or 0C
#      on it, as a Raspberry Pi's card has, with config.txt: booted with
#      tests/disks/etc's initramfs, at the serial shell its file is read,
#      a file of a long name written, a directory made, a file moved into
#      it and another removed; then the host's fsck finds nothing wrong,
#      and on macOS the host mounts it and finds L0S's files there
#
# On macOS the host's tools are hdiutil and fsck_msdos; on Linux,
# sfdisk, mkfs.fat and fsck.fat. Without them it says so and passes. Run
# from the top of the project, after make disks-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
fifo="$BUILD/fat.in"
out="$BUILD/fat.out"
own="$BUILD/fat-own.img"
disk="$BUILD/fat-host.img"
part="$BUILD/fat-part.img"
mnt="$BUILD/fat-mnt"
qemu=""

fail() { echo "not ok - fat: $1"; [ -f "$out" ] && sed 's/^/  # /' "$out"; exit 1; }
ok() { echo "ok - fat: $1"; }

if command -v fsck_msdos > /dev/null && command -v hdiutil > /dev/null; then
  host=mac; fsck() { fsck_msdos -n "$1"; }
elif command -v fsck.fat > /dev/null && command -v mkfs.fat > /dev/null && command -v sfdisk > /dev/null; then
  host=linux; fsck() { fsck.fat -n "$1"; }
else
  echo "ok - fat: # SKIP no FAT tools on this host (fsck_msdos and hdiutil, or fsck.fat, mkfs.fat and sfdisk)"
  exit 0
fi

# The volume of disk image $1 from sector $2, its $3 sectors, checked.
checked() {
  dd if="$1" of="$part" bs=512 skip="$2" count="$3" 2> /dev/null
  fsck "$part" > "$BUILD/fat.fsck" 2>&1 || { cat "$BUILD/fat.fsck" > "$out"; fail "$4: fsck found it bad:"; }
}

# ------------------------------------------------------------ L0S's own

make -s build/mkfs
"$BUILD/mkfs" "$own" 71680 "$(date +%s)000" "BOOT:2048:67584:fat32=$BUILD/initramfs.cpio" > /dev/null || fail "mkfs failed"
checked "$own" 2048 67584 "mkfs's volume"
ok "a volume tools/mkfs made, filled from the initramfs, is what the host's fsck takes"

# ------------------------------------------------------------ the host's

rm -f "$disk"
if [ "$host" = mac ]; then
  rm -f "$BUILD/fat-host.dmg"
  hdiutil create -size 64m -fs "MS-DOS FAT32" -layout MBRSPUD -volname MACFAT "$BUILD/fat-host.dmg" > /dev/null || fail "hdiutil could not make a disk"
  mkdir -p "$mnt"
  hdiutil attach -mountpoint "$mnt" "$BUILD/fat-host.dmg" > /dev/null || fail "hdiutil could not mount it"
  printf 'arm_64bit=1\nkernel=l0.img\n' > "$mnt/config.txt"
  hdiutil detach "$mnt" > /dev/null
  hdiutil convert "$BUILD/fat-host.dmg" -format UDTO -o "$BUILD/fat-host" > /dev/null || fail "hdiutil could not convert it"
  mv "$BUILD/fat-host.cdr" "$disk"
  start=1
else
  dd if=/dev/zero of="$disk" bs=1M count=64 2> /dev/null
  echo 'start=2048, type=c' | sfdisk -q "$disk" || fail "sfdisk could not partition it"
  mkfs.fat -F 32 -n MACFAT --offset 2048 "$disk" $(( (131072 - 2048) / 2 )) > /dev/null || fail "mkfs.fat failed"
  start=2048
fi
count=$(( $(wc -c < "$disk") / 512 - start ))

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
  local end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    grep -qE "$1" "$out" 2> /dev/null && return 0
    sleep 0.2
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# What the serial shell prints for a command, up to its next prompt,
# waited for up to 5 s.
said() {
  local from end=$((SECONDS + 5))
  from=$(($(wc -c < "$out") + 1))
  printf '%s\n' "$1" >&3
  until [ $SECONDS -ge $end ] || tail -c +$from "$out" | grep -aq 'l0s> '; do sleep 0.1; done
  tail -c +$from "$out"
}

boot
# The volume may be mounted after the prompt, while the display draws
# its wallpaper.
waits_for "/Volumes/MACFAT mounted"
said 'ls /Volumes' | grep -aq "MACFAT/" || fail "the host's volume is not mounted; it showed:"
if [ "$host" = mac ]; then
  said 'cat /Volumes/MACFAT/config.txt' | grep -aq "kernel=l0.img" || fail "its config.txt was not read; it showed:"
fi
said 'write /Volumes/MACFAT/CmdlineForTheKernel.txt console=serial0' > /dev/null
said 'mkdir /Volumes/MACFAT/l0s' > /dev/null
said 'mv /Volumes/MACFAT/CmdlineForTheKernel.txt /Volumes/MACFAT/l0s/cmdline.txt' > /dev/null
said 'write /Volumes/MACFAT/gone.txt x' > /dev/null
said 'rm /Volumes/MACFAT/gone.txt' > /dev/null
said 'cat /Volumes/MACFAT/l0s/CMDLINE.TXT' | grep -aq "console=serial0" || fail "the file moved was not read back; it showed:"
ok "L0S read and wrote the host's volume, on an MBR, at the serial shell"
stop

checked "$disk" "$start" "$count" "the host's volume, once L0S wrote it"
ok "the host's fsck takes the host's volume as L0S left it"

if [ "$host" = mac ]; then
  mkdir -p "$mnt"
  hdiutil attach -readonly -imagekey diskimage-class=CRawDiskImage -mountpoint "$mnt" "$disk" > /dev/null || fail "hdiutil could not mount it again"
  got=$(cat "$mnt/l0s/cmdline.txt" 2> /dev/null)
  gone=$(ls "$mnt" | grep -c gone.txt)
  hdiutil detach "$mnt" > /dev/null
  [ "$got" = "console=serial0" ] || fail "macOS does not find l0s/cmdline.txt as L0S wrote it, but '$got'"
  [ "$gone" = 0 ] || fail "macOS still finds gone.txt"
  ok "macOS finds L0S's files on it, and not the one removed"
fi
