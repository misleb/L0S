#!/usr/bin/env bash
# speak.sh -- a Piper voice speaking on the board (roadmap 0062): boots
# the kernel with a disk whose FAT32 volume SPEECH holds the voice and
# CMUdict (the voice, 63.5 MB, is past what an initramfs may hold), types
# run speak -0 -o at the serial shell for each of oracle.py's sentences, and
# checks each WAV it wrote, read back from the volume with mtools, is the
# oracle's: the same rate and length, and a correlation of 0.999 or more.
#
#   PIPER_VOICE=PATH.onnx CMUDICT=PATH tests/speak.sh [ORACLEDIR...]
#
# Each ORACLEDIR is one of probes/piper/oracle.py's, its text.txt said
# and its audio.wav the reference; with none, Hello and Board, the two
# whose phonemes L0S gives as Piper does (probes/piper/textcheck.l0): on
# the others L0S's phonemes differ in a vowel, so its samples cannot be
# the oracle's, which are made from Piper's. The voice and the dictionary are not in the
# project, so make e2e does not run this; with no PIPER_VOICE it takes
# build/fetch's, which make piper-fetch fetches, and with neither, or no
# mtools, it says so and exits 0. Run after make root and
# build/kernel.img; what the board said is in build/speak.out.
set -u
cd "$(dirname "$0")/.."
BUILD=build
VOICE=${PIPER_VOICE:-$BUILD/fetch/en_US-ljspeech-medium.onnx}
DICT=${CMUDICT:-$BUILD/fetch/cmudict.dict}
fifo="$BUILD/speak.in"
out="$BUILD/speak.out"
disk="$BUILD/speak.img"
qemu=""

fail() { echo "not ok - speak: $1"; [ -f "$out" ] && tail -20 "$out" | sed 's/^/  # /'; exit 1; }

if [ ! -f "$VOICE" ] || [ ! -f "$VOICE.json" ] || [ ! -f "$DICT" ]; then
  echo "ok - speak # skip: no voice (PIPER_VOICE=PATH.onnx, with its .json, and CMUDICT=PATH; or make piper-fetch)"
  exit 0
fi
if ! command -v mcopy > /dev/null || ! command -v bsdtar > /dev/null; then
  echo "ok - speak # skip: no mtools or bsdtar on this host"
  exit 0
fi
dirs=("$@")
[ ${#dirs[@]} -eq 0 ] && dirs=("$BUILD/piper-oracle/Hello" "$BUILD/piper-oracle/Board")

# The volume: the voice, its config and the dictionary, as a cpio.
vol="$BUILD/speak.vol"
rm -rf "$vol" && mkdir -p "$vol"
cp "$VOICE" "$vol/voice.onnx" && cp "$VOICE.json" "$vol/voice.onnx.json" && cp "$DICT" "$vol/cmudict.dict"
(cd "$vol" && bsdtar --format newc -cf ../speak-vol.cpio voice.onnx voice.onnx.json cmudict.dict) || fail "bsdtar failed"
tools/mkdisk "$disk" 300000 "SPEECH:40:299000:fat32=$BUILD/speak-vol.cpio" > /dev/null || fail "mkdisk failed"

# The board: the serial shell, the disk's driver and fs.
etc="$BUILD/speak.etc"
rm -rf "$etc" && mkdir -p "$etc"
printf '%s\n' "start /bin/sh" "start /sbin/uart noecho" "start /sbin/virtio-blk" "start /sbin/fs" \
  "dev /sbin/uart" "dev /sbin/virtio-blk" > "$etc/inittab"
tools/mkinitramfs "$BUILD/speak.cpio" "$etc" "$BUILD/root" || fail "mkinitramfs failed"

waits_for() {
  local end=$((SECONDS + $2))
  until [ $SECONDS -ge $end ]; do
    grep -qaE "$1" "$out" 2> /dev/null && return 0
    sleep 0.5
  done
  fail "no line like '$1' on the serial line within $2 s; it showed:"
}

# A command typed, and its output up to the next prompt, waited for up
# to $2 s.
said() {
  local from end=$((SECONDS + $2))
  from=$(($(wc -c < "$out") + 1))
  printf '%s\n' "$1" >&3
  until [ $SECONDS -ge $end ] || tail -c +$from "$out" | grep -aq 'l0s> '; do sleep 0.5; done
  tail -c +$from "$out"
}

rm -f "$fifo"; mkfifo "$fifo"
QEMU_DISK="$disk" QEMU_CPUS="${QEMU_CPUS:-1}" tools/qemu-boot.sh "$BUILD/speak.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
exec 3> "$fifo"
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
waits_for "^l0s> " 60
waits_for "/Volumes/SPEECH mounted" 60

# Paths from the volume, to keep the lines short.
said "cd /Volumes/SPEECH" 10 > /dev/null
names=()
k=0
for d in "${dirs[@]}"; do
  d=${d%/}; k=$((k + 1))
  text=$(head -1 "$d/text.txt")
  said "run speak -t -0 -v voice.onnx -d cmudict.dict -o said$k.wav $text" 1800 > /dev/null
  names+=("$d")
done
grep -a 'speak:' "$out" | sed 's/^l0s> //; s/^/  # /'
# The volume unmounted, so that fs has written all of the last file
# before the board stops.
said "cd /" 10 > /dev/null
said "unmount SPEECH" 60 | grep -a 'unmount' | sed 's/^/  # /'
said "exit" 10 > /dev/null
kill $qemu 2> /dev/null; wait $qemu 2> /dev/null; exec 3>&-

k=0; bad=0
for d in "${names[@]}"; do
  k=$((k + 1))
  rm -f "$BUILD/speak$k.wav"
  mcopy -n -i "$disk@@$((40 * 512))" "::said$k.wav" "$BUILD/speak$k.wav" 2> /dev/null || { echo "  # $(basename "$d"): no said$k.wav on the volume"; bad=1; continue; }
  line=$(python3 -I probes/piper/wavcorr.py "$BUILD/speak$k.wav" "$d/audio.wav" 0.999) || bad=1
  echo "  # $(basename "$d"): $line"
done
[ $bad -eq 0 ] || fail "a WAV is not the oracle's"
echo "ok - speak: ${#names[@]} sentences, each the oracle's"
