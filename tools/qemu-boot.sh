#!/usr/bin/env bash
# qemu-boot.sh INITRAMFS [KERNEL] -- boots the kernel on QEMU's virt board
# with INITRAMFS as its standard input, as l0 boot does, but with the board's
# serial line on this terminal in both directions, so that what is typed
# reaches the PL011, and the console driver. l0 boot instead gives QEMU
# no input at all. Exits with the kernel's status.
#
# Ctrl-C is a key like any other, sent to the board, where the console
# driver tells the shell; QEMU's own signal handling of it is off. To
# quit QEMU itself, type Ctrl-A then x.
#
# The board has a virtio-gpu, a virtio keyboard, and a virtio tablet, on
# modern transports as l0 boot gives them, for the virtio-gpu and
# virtio-input drivers. QEMU_DISPLAY says where the screen is shown, and
# so where keys are typed and the pointer moved: none, the default, shows
# it nowhere; cocoa is a window on macOS.
# The PL031 real-time clock counts local time, not UTC, so that the
# desktop's top bar, which shows it as it is, agrees with this machine's.
# QEMU_DISK, unset unless given, is a raw disk image the board has as a
# virtio-blk, for the virtio-blk driver; the demo's is build/disk.img.
# QEMU_GPU, unset unless given, is options for the virtio-gpu, such as
# xres=3840,yres=2160 for a 4K screen, which the desktop draws at scale 2.
# QEMU_NET, unset unless given, is the network a virtio-net is on, for
# the virtio-net driver, as -netdev names one without its id: user,
# QEMU's own, at 10.0.2.0/24, or user,tftp=DIR with its TFTP server
# serving DIR at 10.0.2.2. The card's address is 52:54:00:12:34:56.
# QEMU_MONITOR, none unless set, is where QEMU's monitor listens, such as
# unix:PATH,server=on,wait=off for tests/gpu-screen.sh's screendump; and
# QEMU_QMP, unset unless given, where its QMP does, for the tests that
# move the pointer with input-send-event. QEMU_APPEND, unset unless
# given, is the kernel's boot arguments, as -append gives them, such as
# root=UUID to boot from that system volume.
#
# This copies how l0's virt_boot loads a program's standard input: its
# bytes at 0x50000000 and their count in the word below, which is what the
# board's runtime reads. If l0 changes that, change this with it.
set -eu
initramfs=$1
kernel=${2:-build/kernel.img}
qemu=${L0_QEMU:-qemu-system-aarch64}
display=${QEMU_DISPLAY:-none}
monitor=${QEMU_MONITOR:-none}
qmp=()
if [ -n "${QEMU_QMP:-}" ]; then qmp=(-qmp "$QEMU_QMP"); fi
disk=()
if [ -n "${QEMU_DISK:-}" ]; then
  disk=(-drive "file=$QEMU_DISK,if=none,format=raw,id=disk0" -device virtio-blk-device,drive=disk0)
fi
net=()
if [ -n "${QEMU_NET:-}" ]; then
  net=(-netdev "$QEMU_NET,id=net0" -device virtio-net-device,netdev=net0,mac=52:54:00:12:34:56)
fi
append=()
if [ -n "${QEMU_APPEND:-}" ]; then append=(-append "$QEMU_APPEND"); fi
gpu=virtio-gpu-device${QEMU_GPU:+,$QEMU_GPU}
len=$(wc -c < "$initramfs" | tr -d ' ')
exec "$qemu" -M virt -cpu cortex-a72 -m 2G -display "$display" -monitor "$monitor" ${qmp[@]+"${qmp[@]}"} \
  -rtc base=localtime \
  -global virtio-mmio.force-legacy=false \
  -device "$gpu" -device virtio-keyboard-device -device virtio-tablet-device \
  ${disk[@]+"${disk[@]}"} \
  ${net[@]+"${net[@]}"} \
  -chardev stdio,id=console,mux=on,signal=off -serial chardev:console -semihosting \
  -device loader,addr=0x4FFFFFF8,data="$len",data-len=8 \
  -device loader,file="$initramfs",addr=0x50000000,force-raw=on \
  ${append[@]+"${append[@]}"} \
  -kernel "$kernel"
