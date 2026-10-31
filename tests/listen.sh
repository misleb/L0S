#!/usr/bin/env bash
# listen.sh -- Whistle heard on the board (roadmap 0060): boots the kernel
# with listen as its one program, the model and recordings in its
# initramfs, and checks each recording's text is the reference's.
#
#   WHISTLE=PATH/whistle.cact tests/listen.sh [CLIPDIR...]
#
# Each CLIPDIR is one of probes/whistle/oracle.py's, with rebuild.py's
# greedy.txt in it: its clip16.wav is heard, and its text must be
# greedy.txt's second line. With none, every one in build/whistle-oracle.
# The model is not in the project (probes/whistle says how it is
# fetched), so make e2e does not run this; with no WHISTLE it says so
# and exits 0. Run after make root and build/kernel.img; listen's lines
# of how long it took are in build/listen.err.
set -u
L0=${L0:-l0}
BUILD=build
if [ -z "${WHISTLE:-}" ] || [ ! -f "$WHISTLE" ]; then
  echo "ok - listen # skip: no model (WHISTLE=PATH/whistle.cact)"
  exit 0
fi
dirs=("$@")
[ ${#dirs[@]} -eq 0 ] && dirs=("$BUILD"/whistle-oracle/*/)
etc="$BUILD/listen.etc"
rm -rf "$etc" && mkdir -p "$etc/clips"
cp "$WHISTLE" "$etc/whistle.cact"
files=(); : > "$BUILD/listen.expected"
for d in "${dirs[@]}"; do
  d=${d%/}; name=$(basename "$d")
  cp "$d/clip16.wav" "$etc/clips/$name.wav"
  files+=("/etc/clips/$name.wav")
  sed -n 2p "$d/greedy.txt" >> "$BUILD/listen.expected"
done
echo "start /bin/listen -t ${files[*]}" > "$etc/inittab"
tools/mkinitramfs "$BUILD/listen.cpio" "$etc" "$BUILD/root" || { echo "not ok - listen: mkinitramfs failed"; exit 1; }
L0_QEMU_ARGS="-smp ${QEMU_CPUS:-1}" tools/deadline 1800 "$L0" boot "$BUILD/kernel.img" < "$BUILD/listen.cpio" > "$BUILD/listen.out" 2> "$BUILD/listen.err"
status=$?
grep '^listen:' "$BUILD/listen.err"
if [ $status -eq 0 ] && diff "$BUILD/listen.expected" "$BUILD/listen.out" > "$BUILD/listen.diff"; then
  echo "ok - listen: ${#files[@]} recordings, the reference's text"
else
  echo "not ok - listen: status $status"; cat "$BUILD/listen.diff" 2> /dev/null; tail -5 "$BUILD/listen.err"
  exit 1
fi
