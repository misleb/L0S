#!/usr/bin/env bash
# keyboard.sh -- boots tests/screen/etc's initramfs with no window, types
# run keys at the serial shell, then presses keys on the board's virtio
# keyboard through QEMU's monitor (sendkey), as typing in QEMU's window
# would, and checks that keys echoed them to its terminal, the serial
# line, and that Esc ended it. The serial line is typed through a FIFO,
# and the board keeps running until this kills it. Run from the top of
# the project, after make screen-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/keyboard.sock"
fifo="$BUILD/keyboard.in"
out="$BUILD/keyboard.out"
rm -f "$sock" "$fifo"
mkfifo "$fifo"

QEMU_MONITOR="unix:$sock,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/screen.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

# Waits up to 30 s for the console to show text; fails with what it did
# show if it never does.
waits_for() {
  local try
  for try in $(seq 1 30); do
    grep -qF "$1" "$out" 2> /dev/null && return 0
    sleep 1
  done
  echo "not ok - keyboard: no '$1' on the console; it showed:"
  sed 's/^/  # /' "$out"
  exit 1
}

monitor() { printf '%s\n' "$1" | nc -U -w 1 "$sock" > /dev/null 2>&1; }

waits_for "l0s> "
printf 'run keys\n' >&3
waits_for "keys: type in QEMU's window; Esc ends"

for k in h i shift-1 spc shift-a ret; do monitor "sendkey $k"; done
waits_for "hi! A"

# Once Esc has ended keys, the next line typed is the shell's again.
monitor "sendkey esc"
sleep 1
printf 'echo done\n' >&3
waits_for "l0s> echo done"
for try in $(seq 1 30); do grep -qx "done" "$out" && break; sleep 1; done
grep -qx "done" "$out" || { echo "not ok - keyboard: the shell did not run echo done"; exit 1; }

echo "ok - keyboard: keys echoed 'hi! A', and Esc ended it"
