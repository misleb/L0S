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
# The board has a virtio-gpu, a virtio keyboard, a virtio tablet, and a
# virtio-rng, on modern transports as l0 boot gives them, for the
# virtio-gpu, virtio-input and virtio-rng drivers; the virtio-rng draws
# on the host's /dev/urandom. QEMU_DISPLAY says where the screen is shown, and
# so where keys are typed and the pointer moved: none, the default, shows
# it nowhere; cocoa is a window on macOS.
# The PL031 real-time clock counts local time, not UTC, so that the
# desktop's top bar, which shows it as it is, agrees with this machine's.
# QEMU_DISK, unset unless given, is a raw disk image the board has as a
# virtio-blk, for the virtio-blk driver; the demo's is build/disk.img.
# QEMU_SD, unset unless given, is a raw image, of a power of 2 bytes, the
# board has as an SD card in a sdhci-pci on PCIe, for pcie and sdhci; the
# demo's is build/sd.img.
# QEMU_GPU, unset unless given, is options for the virtio-gpu, such as
# xres=3840,yres=2160 for a 4K screen, which the desktop draws at scale 2.
# GPU, gl or 2d, 2d if not set, says whether the board's virtio-gpu is the
# GL device, for which the display has GL on (none becomes egl-headless),
# or the plain one. The demo sets it from tools/qemu-gl. The screen tests
# stay on 2d: QEMU's screendump has no surface to read when the scanout is
# a GL texture, as it is on the GL device even for 2D resources.
# QEMU_NET, unset unless given, is the network a virtio-net is on, for
# the virtio-net driver, as -netdev names one without its id: user,
# QEMU's own, at 10.0.2.0/24, or user,tftp=DIR with its TFTP server
# serving DIR at 10.0.2.2. The card's address is 52:54:00:12:34:56.
# QEMU_MONITOR, none unless set, is where QEMU's monitor listens, such as
# unix:PATH,server=on,wait=off for tests/gpu-screen.sh's screendump; and
# QEMU_QMP, unset unless given, where its QMP does, for the tests that
# move the pointer with input-send-event. QEMU_APPEND, unset unless
# given, is the kernel's boot arguments, as -append gives them, such as
# root=UUID to boot from that system volume. QEMU_INPUT=usb gives the
# board a qemu-xhci on PCIe with a USB keyboard and mouse on it, for
# pcie, xhci and usb-hid, in place of the virtio keyboard and tablet.
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
sd=()
if [ -n "${QEMU_SD:-}" ]; then
  sd=(-device sdhci-pci -drive "file=$QEMU_SD,if=none,format=raw,id=sd0" -device sd-card,drive=sd0)
fi
net=()
if [ -n "${QEMU_NET:-}" ]; then
  net=(-netdev "$QEMU_NET,id=net0" -device virtio-net-device,netdev=net0,mac=52:54:00:12:34:56)
fi
append=()
if [ -n "${QEMU_APPEND:-}" ]; then append=(-append "$QEMU_APPEND"); fi
# The keyboard and pointer: virtio's, or with QEMU_INPUT=usb a USB
# keyboard and mouse on a qemu-xhci, for pcie, xhci and usb-hid.
input=(-device virtio-keyboard-device -device virtio-tablet-device)
if [ "${QEMU_INPUT:-virtio}" = usb ]; then
  input=(-device qemu-xhci -device usb-kbd -device usb-mouse)
fi
mode=${GPU:-2d}
if [ "$mode" = gl ]; then
  # virgl: the GL device, and a display that has GL, which none and a
  # window both are given.
  gpudev=virtio-gpu-gl-device
  case $display in
    none) display=egl-headless ;;
    *gl=*) ;;
    *) display="$display,gl=on" ;;
  esac
else
  gpudev=virtio-gpu-device
fi
gpu=$gpudev${QEMU_GPU:+,$QEMU_GPU}
len=$(wc -c < "$initramfs" | tr -d ' ')
exec "$qemu" -M virt -cpu cortex-a72 -m 2G -display "$display" -monitor "$monitor" ${qmp[@]+"${qmp[@]}"} \
  -rtc base=localtime \
  -global virtio-mmio.force-legacy=false \
  -device "$gpu" "${input[@]}" -device virtio-rng-device \
  ${disk[@]+"${disk[@]}"} \
  ${sd[@]+"${sd[@]}"} \
  ${net[@]+"${net[@]}"} \
  -chardev stdio,id=console,mux=on,signal=off -serial chardev:console -semihosting \
  -device loader,addr=0x4FFFFFF8,data="$len",data-len=8 \
  -device loader,file="$initramfs",addr=0x50000000,force-raw=on \
  ${append[@]+"${append[@]}"} \
  -kernel "$kernel"
