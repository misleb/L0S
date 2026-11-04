#!/usr/bin/env bash
# agent.sh -- boots tests/agent-screen/etc's initramfs: the compositor
# with no window, the disk's driver and file server, the network and
# agentd, on a fresh disk whose data volume holds agentd's home; on the
# host, tools/api-proxy/e2e_serve.py runs serving tests/agent-screen,
# its stand-in model asking for build_app, its builder painting the
# case's preview.png, 32 by 16 and all 3584e4, as the scene main. Types
# run chat & at the serial shell, which opens Agent (user/apps/chat,
# roadmap 0066), learns where its window is from run windows, and checks,
# by QEMU's screendump, its places pinned by chat_test.l0's test_placed:
#
#   1. a click on the Images toggle: the pane says it has none, its
#      ground at the middle of the picture's room
#   2. run agent at the serial shell, a line said and /exit: what was
#      said an outgoing bubble at the conversation's end, the accent's
#      blue, and the build's preview, told as agent image, read from the
#      home, decoded and shown, the accent's blue at the middle of the
#      picture's room
#
# The serial line is typed through a FIFO, and the board keeps running
# until this kills it. Run from the top of the project, after make
# agent-screen-initramfs and make proxy.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/agent.sock"
qmp="$BUILD/agent.qmp"
fifo="$BUILD/agent.in"
out="$BUILD/agent.out"
dump="$BUILD/agent.ppm"
disk="$BUILD/agent-test.img"
etc="$BUILD/agent-run-etc"
rm -f "$sock" "$qmp" "$fifo" "$dump"
mkfifo "$fifo"
tools/mkdisk "$disk" > /dev/null

# The proxy on a free port of the loopback, which the board reaches as
# 10.0.2.2, named in a copy of the staged etc.
port=$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
build/proxy/venv/bin/python -I tools/api-proxy/e2e_serve.py "$port" tests/agent-screen > "$BUILD/agent.serve" 2>&1 &
serve=$!
rm -rf "$etc" && cp -R "$BUILD/agent-screen-etc" "$etc"
sed -i.bak "s/@PORT@/$port/" "$etc/agent/config" && rm -f "$etc/agent/config.bak"
tools/mkinitramfs "$BUILD/agent.cpio" "$etc" "$BUILD/root" || { echo "not ok - agent: mkinitramfs failed"; exit 1; }
end=$((SECONDS + 30))
until grep -q 'the proxy on' "$BUILD/agent.serve" 2> /dev/null || [ $SECONDS -ge $end ]; do sleep 0.2; done

QEMU_NET=user QEMU_DISK="$disk" QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/agent.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu $serve 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - agent: $1"; sed 's/^/  # /' "$out"; exit 1; }

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

waits_for() {
  local end=$((SECONDS + 60))
  until [ $SECONDS -ge $end ]; do
    grep -qE "$1" "$out" 2> /dev/null && return 0
    sleep 0.2
  done
  fail "no line like '$1' on the serial line; it showed:"
}

# A click at x, y, and the pointer then taken off the window, to the
# screen's corner, so nothing is tinted under it.
click() {
  events "$(at $1 $2)"; sleep 0.1
  events "$(button true)"; sleep 0.1
  events "$(button false)"; sleep 0.1
  events "$(at 1270 790)"
}

# What run windows lists, from the serial line, in $got: typed, and
# read up to the shell's next prompt, waited for up to 5 s.
listed() {
  local from end=$((SECONDS + 5))
  from=$(($(wc -c < "$out") + 1))
  printf 'run windows\n' >&3
  until [ $SECONDS -ge $end ] || tail -c +$from "$out" | grep -aq 'l0s> '; do sleep 0.1; done
  got=$(tail -c +$from "$out")
}

# Where Agent's window is, as run windows lists it: w_x, w_y. Waits up
# to 30 s for it to be listed.
window() {
  local line end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    listed
    line=$(printf '%s\n' "$got" | grep -aE '^[0-9]+ Agent ' | head -1)
    if [ -n "$line" ]; then
      read -r _ _ w_x w_y _ <<< "$line"
      return 0
    fi
    sleep 0.2
  done
  fail "run windows never listed Agent's window; it showed:"
}

# Pixel x, y of the screendump, a 1280 by 800 PPM whose header is 16 bytes.
pixel() { od -An -tu1 -j $((16 + ($2 * 1280 + $1) * 3)) -N3 "$dump" | tr -s ' ' | sed 's/^ //; s/ $//'; }

# Waits up to 30 s for each "X Y R G B" given to be on the screen.
shows() {
  local name=$1; shift
  local p ok got px py r g b end=$((SECONDS + 30))
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
      [ "$ok" = 1 ] && { echo "ok - agent: $name"; return 0; }
    fi
    sleep 0.2
  done
  echo "not ok - agent: $name: got$got, wanted $*"
  sed 's/^/  # /' "$out"
  exit 1
}

# The window's content starts under its 46-row title bar, 2 in from its
# left, inside the frame's border. In it: the first bubble's ground,
# from 20 to 52 and ending at 467, 12 in from the conversation's half,
# looked at 4 in from its end, past its text; the Images toggle from
# 536, 6, 61 by 34; the picture's room, the pane's view, 1e1e1e, its
# middle 720, 250, where the preview is drawn whole, from 704, 242.
bar=46
view="30 30 30"; accent="53 132 228"

waits_for "^l0s> "
waits_for "agentd: serving agent"
printf 'run chat &\n' >&3
window
cx=$((w_x + 2)); cy=$((w_y + bar))
events "$(at 1270 790)"

click $((cx + 566)) $((cy + 23))
shows "the Images toggle: none yet, the pane's ground" "$((cx + 720)) $((cy + 140)) $view"
printf 'run agent\nbuild me an app that says hello\n/exit\n' >&3
waits_for "Built: apps/hello"
shows "what was said a bubble, a build's preview shown, read from the home and decoded" \
  "$((cx + 463)) $((cy + 36)) $accent" "$((cx + 720)) $((cy + 250)) $accent" "$((cx + 705)) $((cy + 243)) $accent"
