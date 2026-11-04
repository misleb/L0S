#!/usr/bin/env bash
# installer.sh -- boots tests/installer/etc's initramfs, the compositor
# with no window, the disk's driver and file server, and the network, on
# a disk of two volumes, System and data; on the host, the proxy
# tools/api-proxy/e2e_serve.py runs serving tests/e2e/install_net's
# release, which agent/config names at 10.0.2.2. Types run installer &
# at the serial shell, which opens the Installer (user/apps/installer),
# learns where its window is from run windows, and checks, by QEMU's
# screendump and the serial shell:
#
#   1. a fresh install onto System, as / is the initramfs: its Install
#      button red, the status of /Volumes/data's dot green
#   2. a click of the tablet, through QMP, on Install: install --net runs,
#      and its end, Done, has a green dot where the button was
#   3. at the serial shell, the system on System and data's agent,
#      speech and user directories, the model in speech
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# installer-initramfs and make proxy.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/installer.sock"
qmp="$BUILD/installer.qmp"
fifo="$BUILD/installer.in"
out="$BUILD/installer.out"
dump="$BUILD/installer.ppm"
disk="$BUILD/installer-test.img"
etc="$BUILD/installer-run-etc"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"
tools/mkdisk "$disk" 65536 System:40:40000 data:40040:25000 > /dev/null

# The proxy on a free port of the loopback, which the board reaches as
# 10.0.2.2, named in a copy of the staged etc.
port=$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
build/proxy/venv/bin/python -I tools/api-proxy/e2e_serve.py "$port" tests/e2e/install_net > "$BUILD/installer.serve" 2>&1 &
serve=$!
rm -rf "$etc" && cp -R "$BUILD/installer-etc" "$etc"
sed -i.bak "s/@PORT@/$port/" "$etc/agent/config" && rm -f "$etc/agent/config.bak"
tools/mkinitramfs "$BUILD/installer.cpio" "$etc" "$BUILD/root" || { echo "not ok - installer: mkinitramfs failed"; exit 1; }
end=$((SECONDS + 30))
until grep -q 'the proxy on' "$BUILD/installer.serve" 2> /dev/null || [ $SECONDS -ge $end ]; do sleep 0.2; done

QEMU_NET=user QEMU_DISK="$disk" QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/installer.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu $serve 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - installer: $1"; sed 's/^/  # /' "$out"; exit 1; }

monitor() { printf '%s\n' "$1" | tools/qsock "$sock" > /dev/null 2>&1; }

# The tablet, through QMP: each argument an input event.
events() {
  local list
  list=$(IFS=,; echo "$*")
  printf '{"execute":"qmp_capabilities"}\n{"execute":"input-send-event","arguments":{"events":[%s]}}\n' "$list" \
    | tools/qsock "$qmp" > /dev/null 2>&1
}
axis() { echo $(( $1 * 32767 / ($2 - 1) )); }
at() {
  echo "{\"type\":\"abs\",\"data\":{\"axis\":\"x\",\"value\":$(axis "$1" 1280)}},{\"type\":\"abs\",\"data\":{\"axis\":\"y\",\"value\":$(axis "$2" 800)}}"
}
button() { echo "{\"type\":\"btn\",\"data\":{\"down\":$1,\"button\":\"left\"}}"; }
# A click at x, y: there, pressed, let go.
click() {
  events "$(at "$1" "$2")"; sleep 0.1
  events "$(button true)"; sleep 0.1
  events "$(button false)"
}

# Waits up to 30 s for a line like the regex on the serial line.
waits_for() {
  local end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    grep -qE "$1" "$out" 2> /dev/null && return 0
    sleep 0.2
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# Waits up to 5 s for the shell's prompt on the serial line after byte
# offset from.
prompt_after() {
  local end=$((SECONDS + 5))
  until [ $SECONDS -ge $end ] || tail -c +$1 "$out" | grep -aq 'l0s> '; do sleep 0.1; done
}

# Where the Installer's window is, as run windows lists it: w_x, w_y.
# Asks for up to 30 s.
window() {
  local from line end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    from=$(($(wc -c < "$out") + 1))
    printf 'run windows\n' >&3
    prompt_after $from
    line=$(tail -c +$from "$out" | grep -aE '^[0-9]+ Installer ' | head -1)
    if [ -n "$line" ]; then
      read -r _ _ w_x w_y _ _ _ <<< "$line"
      return 0
    fi
    sleep 0.2
  done
  fail "run windows never listed the Installer's window; it showed:"
}

# Pixel x, y of the screendump, a 1280 by 800 PPM whose header is 16 bytes.
pixel() { od -An -tu1 -j $((16 + ($2 * 1280 + $1) * 3)) -N3 "$dump" | tr -s ' ' | sed 's/^ //; s/ $//'; }

# Waits up to the seconds given for each "X Y R G B" to be on the screen.
shows_within() {
  local secs=$1 name=$2; shift 2
  local p ok got px py r g b end=$((SECONDS + secs))
  until [ $SECONDS -ge $end ]; do
    rm -f "$dump"
    monitor "screendump $dump"
    if [ -s "$dump" ]; then
      ok=1; got=""
      for p in "$@"; do
        read -r px py r g b <<< "$p"
        got="$got ($px,$py)=$(pixel $px $py)"
        [ "$(pixel $px $py)" = "$r $g $b" ] || ok=0
      done
      [ "$ok" = 1 ] && { echo "ok - installer: $name"; return 0; }
    fi
    sleep 0.2
  done
  echo "not ok - installer: $name: got$got, wanted $*"
  sed 's/^/  # /' "$out"
  exit 1
}
shows() { shows_within 30 "$@"; }

# What the serial shell prints for a command, up to its next prompt.
said() {
  local from
  from=$(($(wc -c < "$out") + 1))
  printf '%s\n' "$1" >&3
  prompt_after $from
  tail -c +$from "$out"
}

# The window's content starts under its 46-row header bar, 2 in from its
# left, its page 18 in: the heading's row, 34 high, a button's (the
# title is 32), Install at its end, 18 in from the 640's right, its red
# taken 10 in from there, in its padding; the line under it, 16, 12
# apart; the properties, two rows of 34, 6 apart; data's status, then
# the status of what it will do, 28 apart, their dots 8 across at their
# start.
bar=46
red="224 27 36"; green="46 194 126"; yellow="229 165 10"

waits_for "^l0s> "
waits_for "/Volumes/data mounted"
printf 'run installer &\n' >&3
waits_for "\[pid [0-9]+ running\]"
window
cx=$((w_x + 2)); cy=$((w_y + bar))
dot_x=$((cx + 22)); data_y=$((cy + 18 + 34 + 12 + 16 + 12 + 34 + 6 + 34 + 12 + 10))
what_y=$((data_y + 25)); btn_y=$((cy + 18 + 17)); btn_x=$((cx + 640 - 18 - 10))

shows "a fresh install onto System, data there, what it erases said" \
  "$btn_x $btn_y $red" "$dot_x $data_y $green" "$dot_x $what_y $yellow"
click $btn_x $btn_y
shows_within 120 "install --net ran to its end, Done" "$dot_x $what_y $green"
said 'ls /Volumes/data /Volumes/data/speech' | grep -q 'whistle.cact' || fail "data has no model; it showed:"
said 'cat /Volumes/System/etc/motd' | grep -q 'installed from a release' || fail "System has no motd; it showed:"
echo "ok - installer: the release on System and data"
