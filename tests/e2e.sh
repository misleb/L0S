#!/usr/bin/env bash
# e2e.sh -- boots each case, a directory tests/e2e/NAME, under the kernel,
# from an initramfs of every program and the case's own etc, whose
# inittab says what runs. Then it compares:
#
#   expected   what standard output must be
#   status     the exit status, 0 if there is no such file
#   stderr     a line standard error must hold, if there is such a file
#
# If NAME/typed exists, it is typed at the board's serial line, through
# tools/qemu-boot.sh, a line at a time as tools/slowtype types, for the
# console driver to read. If NAME/font exists, the console font is added
# to the case's etc as /etc/font.txt, for vt. If NAME/disk exists, the
# board has a virtio-blk too, a fresh disk tools/mkdisk makes for the
# case: of its own layout, if NAME/layout holds one, SECTORS then each
# volume as mkfs takes them, in which @ is the case's own initramfs, to
# fill a volume from. If NAME/bootargs exists, its words are the
# kernel's boot arguments, such as root=UUID. Every boot is killed after
# a minute. Run from
# the top of the project, after make root, which stages every program in
# build/root as /bin, /sbin and /Applications; this script's raw programs
# go in /bin beside them. The board has a virtio-gpu,
# shown nowhere, and a virtio keyboard, either way.
set -u
cd "$(dirname "$0")/.."
L0=${L0:-l0}
export L0_QEMU_ARGS="-device virtio-gpu-device -device virtio-keyboard-device -device virtio-tablet-device"
BUILD=build
mkdir -p "$BUILD/raw" "$BUILD/e2e"

# Raw programs, a few aarch64 instructions each, for what an L0 program
# cannot do: fault, pass a bad buffer, or wait on nothing.
word() { printf "\\x${1:6:2}\\x${1:4:2}\\x${1:2:2}\\x${1:0:2}"; }
image() { local out=$1; shift; : > "$out"; for w in "$@"; do word "$w" >> "$out"; done; }
SVC=D4000001
image "$BUILD/raw/crash.img"    D2800201 F9400020                  # movz x1,#16; ldr x0,[x1]
image "$BUILD/raw/badbuf.img"   D2800020 D2800201 D28000A2 D2800048 $SVC D2800068 $SVC
                                # write(1, 16, 5); exit(x0)
image "$BUILD/raw/deadlock.img" D2802048 $SVC D2802088 D2800102 $SVC 14000000
                                # port_new; receive(x0, 0, 8); b .

raws=("$BUILD"/raw/*.img)

pass=0; fail=0
for dir in tests/e2e/*/; do
  dir=${dir%/}
  name=$(basename "$dir")
  want_status=0
  [ -f "$dir/status" ] && want_status=$(cat "$dir/status")
  out="$BUILD/e2e/$name.out"; err="$BUILD/e2e/$name.err"; cpio="$BUILD/e2e/$name.cpio"
  etc="$dir/etc"
  if [ -f "$dir/font" ]; then
    etc="$BUILD/e2e/$name.etc"
    rm -rf "$etc" && cp -R "$dir/etc" "$etc" && cp fonts/l0s-8x16.txt "$etc/font.txt"
  fi
  if ! tools/mkinitramfs "$cpio" "$etc" "$BUILD/root" "${raws[@]}"; then
    echo "not ok - $name: mkinitramfs failed"; fail=$((fail+1)); continue
  fi
  disk=""; qemu_args=$L0_QEMU_ARGS
  if [ -f "$dir/disk" ]; then
    disk="$BUILD/e2e/$name.disk"
    layout=()
    if [ -f "$dir/layout" ]; then
      read -ra layout < <(sed "s|@|$cpio|g" "$dir/layout")
    fi
    if ! tools/mkdisk "$disk" ${layout[@]+"${layout[@]}"} > /dev/null; then
      echo "not ok - $name: mkdisk failed"; fail=$((fail+1)); continue
    fi
    qemu_args="$qemu_args -drive file=$disk,if=none,format=raw,id=disk0 -device virtio-blk-device,drive=disk0"
  fi
  bootargs=()
  [ -f "$dir/bootargs" ] && read -ra bootargs < "$dir/bootargs"
  if [ -f "$dir/typed" ]; then
    tools/slowtype "$dir/typed" |
      QEMU_DISK=$disk QEMU_APPEND="${bootargs[*]+${bootargs[*]}}" tools/deadline 60 tools/qemu-boot.sh "$cpio" > "$out" 2> "$err"
  else
    L0_QEMU_ARGS=$qemu_args tools/deadline 60 "$L0" boot "$BUILD/kernel.img" ${bootargs[@]+"${bootargs[@]}"} < "$cpio" > "$out" 2> "$err"
  fi
  status=$?
  why=""
  if ! diff -u "$dir/expected" "$out" > "$BUILD/e2e/$name.diff"; then
    why="standard output differs:"$'\n'"$(cat "$BUILD/e2e/$name.diff")"
  elif [ "$status" != "$want_status" ]; then
    why="exit status $status, wanted $want_status"
  elif [ -f "$dir/stderr" ] && ! grep -qF "$(cat "$dir/stderr")" "$err"; then
    why="standard error lacks: $(cat "$dir/stderr")"
  fi
  if [ -z "$why" ]; then
    echo "ok - $name"; pass=$((pass+1))
  else
    echo "not ok - $name: $why"; sed 's/^/  # stderr: /' "$err"; fail=$((fail+1))
  fi
done

# What is not an initramfs is refused.
printf 'not an initramfs' | "$L0" boot "$BUILD/kernel.img" > /dev/null 2> "$BUILD/e2e/garbage.err"
status=$?
if [ "$status" = 1 ] && grep -qF 'l0s: initramfs: no 070701 magic' "$BUILD/e2e/garbage.err"; then
  echo "ok - garbage"; pass=$((pass+1))
else
  echo "not ok - garbage: status $status"; fail=$((fail+1))
fi

# An initramfs without an inittab is refused, naming what is missing.
mkdir -p "$BUILD/e2e/noinit/bin"
cp "$BUILD/bin/hello.img" "$BUILD/e2e/noinit/bin/hello"
(cd "$BUILD/e2e/noinit" && find . | LC_ALL=C sort | bsdtar -n --format newc -cf ../noinit.cpio -T -)
"$L0" boot "$BUILD/kernel.img" < "$BUILD/e2e/noinit.cpio" > /dev/null 2> "$BUILD/e2e/noinit.err"
status=$?
if [ "$status" = 1 ] && grep -qF 'l0s: initramfs: no /etc/inittab' "$BUILD/e2e/noinit.err"; then
  echo "ok - noinit"; pass=$((pass+1))
else
  echo "not ok - noinit: status $status"; fail=$((fail+1))
fi

echo "# $pass passed, $fail failed"
[ "$fail" = 0 ]
