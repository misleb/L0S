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
# to the case's etc as /etc/font.txt, for vt, and the face for scale 2 as
# /etc/face2x. If NAME/disk exists, the
# board has a virtio-blk too, a fresh disk tools/mkdisk makes for the
# case: of its own layout, if NAME/layout holds one, SECTORS then each
# volume as mkfs takes them, in which @ is the case's own initramfs, to
# fill a volume from. If NAME/bootargs exists, its words are the
# kernel's boot arguments, such as root=UUID. If NAME/gpu exists, its
# line is the virtio-gpu's options, such as xres=3840,yres=2160 for a 4K
# screen. If NAME/net exists, the board has a virtio-net on the network
# its line names, as -netdev takes one without its id, such as user, or
# user,tftp=tests/e2e/NAME/tftp for QEMU's TFTP server at 10.0.2.2
# serving that directory. Every boot is killed after
# a minute. Run from
# the top of the project, after make root, which stages every program in
# build/root as /bin, /sbin and /Applications; this script's hand-made
# programs go in /bin beside them. The board has a virtio-gpu,
# shown nowhere, and a virtio keyboard, either way.
set -u
cd "$(dirname "$0")/.."
L0=${L0:-l0}
export L0_QEMU_ARGS="-device virtio-gpu-device -device virtio-keyboard-device -device virtio-tablet-device"
BUILD=build
mkdir -p "$BUILD/asm" "$BUILD/e2e"

# Hand-made programs, a few aarch64 instructions each, for what an L0
# program cannot do: fault, pass a bad buffer, or wait on nothing. Each
# is an ELF as spec section 10.3 lays one out: the ELF header and one
# program header in the first page, then the code, one PT_LOAD readable
# and executable at 0xC0000000, its entry.
word() { printf "\\x${1:6:2}\\x${1:4:2}\\x${1:2:2}\\x${1:0:2}"; }
le64() { local i; for i in 0 1 2 3 4 5 6 7; do printf "\\x$(printf %02x $(( ($1 >> (8 * i)) & 255 )))"; done; }
image() {
  local out=$1; shift
  local n=$(( $# * 4 )) at=$((0xC0000000))
  {
    printf '\x7fELF\x02\x01\x01\x00'; le64 0                 # 64-bit, little-endian, version 1
    printf '\x02\x00\xb7\x00\x01\x00\x00\x00'                # ET_EXEC, EM_AARCH64
    le64 $at; le64 64; le64 0                                # entry, program headers, no sections
    printf '\x00\x00\x00\x00\x40\x00\x38\x00\x01\x00\x00\x00\x00\x00\x00\x00'
    printf '\x01\x00\x00\x00\x05\x00\x00\x00'                # PT_LOAD, PF_R | PF_X
    le64 4096; le64 $at; le64 $at; le64 $n; le64 $n; le64 4096
    head -c $((4096 - 120)) /dev/zero
    for w in "$@"; do word "$w"; done
  } > "$out"
}
SVC=D4000001
image "$BUILD/asm/crash.img"    D2800201 F9400020                  # movz x1,#16; ldr x0,[x1]
image "$BUILD/asm/badbuf.img"   D2800020 D2800201 D28000A2 D2800048 $SVC D2800068 $SVC
                                # write(1, 16, 5); exit(x0)
image "$BUILD/asm/deadlock.img" D2802048 $SVC D2802088 D2800102 $SVC 14000000
                                # port_new; receive(x0, 0, 8); b .

asms=("$BUILD"/asm/*.img)

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
    [ -f "$BUILD/face2x" ] && cp "$BUILD/face2x" "$etc/face2x"
  fi
  if ! tools/mkinitramfs "$cpio" "$etc" "$BUILD/root" "${asms[@]}"; then
    echo "not ok - $name: mkinitramfs failed"; fail=$((fail+1)); continue
  fi
  disk=""; qemu_args=$L0_QEMU_ARGS; gpu=""
  if [ -f "$dir/gpu" ]; then
    gpu=$(cat "$dir/gpu")
    qemu_args=${qemu_args/virtio-gpu-device/virtio-gpu-device,$gpu}
  fi
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
  net=""
  if [ -f "$dir/net" ]; then
    net=$(cat "$dir/net")
    qemu_args="$qemu_args -netdev $net,id=net0 -device virtio-net-device,netdev=net0,mac=52:54:00:12:34:56"
  fi
  bootargs=()
  [ -f "$dir/bootargs" ] && read -ra bootargs < "$dir/bootargs"
  if [ -f "$dir/typed" ]; then
    tools/slowtype "$dir/typed" |
      QEMU_DISK=$disk QEMU_GPU=$gpu QEMU_NET=$net QEMU_APPEND="${bootargs[*]+${bootargs[*]}}" tools/deadline 60 tools/qemu-boot.sh "$cpio" > "$out" 2> "$err"
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
