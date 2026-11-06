#!/usr/bin/env bash
# screenshot.sh -- boots tests/screenshot/etc's initramfs: the compositor
# with no window, the audio server with QEMU's usb-audio speaker, and a
# disk whose data volume is FAT32, so the host can read what is saved
# there. Through QMP's usb-tablet and the serial shell, it checks:
#
#   1. the status button shows the speaker once the audio server says
#      its default output's volume
#   2. the card's slider, pressed and dragged, sets that volume: sound
#      volume 1 says it
#   3. the screenshot button freezes the screen: a drag outlines the area
#      in the accent color, and the release saves it with /bin/snip,
#      which says so, as a PNG under /Volumes/data/user
#   4. snip X Y W H FILE from the shell saves that rectangle
#   5. both PNGs, copied off the disk with mtools, hold the screen's
#      pixels there, as QEMU's screendump has them
#
# The serial line is typed through a FIFO. Run from the top of the
# project, after make screenshot-initramfs.
set -u
cd "$(dirname "$0")/.."
BUILD=build
sock="$BUILD/screenshot.sock"
qmp="$BUILD/screenshot.qmp"
fifo="$BUILD/screenshot.in"
out="$BUILD/screenshot.out"
dump="$BUILD/screenshot.ppm"
disk="$BUILD/screenshot.img"
rm -f "$sock" "$qmp" "$fifo" "$dump" "$disk" "$BUILD"/screenshot-*.png
if ! command -v mcopy > /dev/null; then
  echo "ok - screenshot # SKIP no mtools to read the saved PNGs"
  exit 0
fi
mkfifo "$fifo"
tools/mkdisk "$disk" 72000 "data:2048:69000:fat32" > /dev/null || { echo "not ok - screenshot: mkdisk failed"; exit 1; }

QEMU_INPUT=usb QEMU_USB="tablet audio" QEMU_DISK="$disk" \
  QEMU_MONITOR="unix:$sock,server=on,wait=off" QEMU_QMP="unix:$qmp,server=on,wait=off" \
  tools/qemu-boot.sh "$BUILD/screenshot.cpio" < "$fifo" > "$out" 2>&1 &
qemu=$!
trap 'kill $qemu 2> /dev/null; rm -f "$fifo"' EXIT
exec 3> "$fifo"

fail() { echo "not ok - screenshot: $1"; sed 's/^/  # /' "$out"; exit 1; }

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

# A click at x, y: there, pressed, let go. What it does is waited for
# by what checks it, not here.
click() {
  events "$(at $1 $2)"; sleep 0.1
  events "$(button true)"; sleep 0.1
  events "$(button false)"
}

# A press at x1, y1, moved in steps to x2, y2, held there.
press_to() {
  events "$(at $1 $2)"; sleep 0.1
  events "$(button true)"; sleep 0.1
  local i
  for i in 1 2 3 4; do
    events "$(at $(( $1 + ($3 - $1) * i / 4 )) $(( $2 + ($4 - $2) * i / 4 )))"; sleep 0.1
  done
}

waits_for() {
  local end=$((SECONDS + 30))
  until [ $SECONDS -ge $end ]; do
    grep -qaE "$1" "$out" 2> /dev/null && return 0
    sleep 0.2
  done
  fail "no line like '$1' on the serial line; it showed:"
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
      [ "$ok" = 1 ] && { echo "ok - screenshot: $name"; return 0; }
    fi
    sleep 0.2
  done
  echo "not ok - screenshot: $name: got$got, wanted $*"
  exit 1
}

# What a line typed at the serial shell answered: the text after it up
# to the shell's next prompt, waited for up to 30 s.
said() {
  local from end=$((SECONDS + 30))
  from=$(($(wc -c < "$out") + 1))
  printf '%s\n' "$1" >&3
  until [ $SECONDS -ge $end ]; do
    tail -c +$from "$out" | grep -aq 'l0s> ' && { tail -c +$from "$out"; return 0; }
    sleep 0.2
  done
  fail "'$1' never ended; it showed:"
}

# Whether the PNG at $1 holds the pixels of the screendump at $2 from x,
# y on, as wide and high as the PNG, or from a place up to 2 pixels from
# it each way, since the tablet's axes round where a press lands: its
# rows inflated and unfiltered as the PNG spec says.
same_pixels() {
  python3 -I - "$1" "$2" "$3" "$4" <<'PY'
import sys, struct, zlib
png, ppm, x0, y0 = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
b = open(png, 'rb').read()
assert b[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG'
i, idat = 8, b''
while i < len(b):
    n, kind = struct.unpack('>I4s', b[i:i + 8])
    data = b[i + 8:i + 8 + n]
    if kind == b'IHDR':
        w, h, depth, color = struct.unpack('>IIBB', data[:10])
        assert (depth, color) == (8, 2), 'not 8-bit RGB'
    elif kind == b'IDAT':
        idat += data
    i += 12 + n
raw = zlib.decompress(idat)
stride = 3 * w
rows, prev = [], bytearray(stride)
for y in range(h):
    f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
    for k in range(stride):
        a = line[k - 3] if k >= 3 else 0
        u = prev[k]
        c = prev[k - 3] if k >= 3 else 0
        if f == 1: line[k] = (line[k] + a) & 255
        elif f == 2: line[k] = (line[k] + u) & 255
        elif f == 3: line[k] = (line[k] + (a + u) // 2) & 255
        elif f == 4:
            p = a + u - c
            pa, pb, pc = abs(p - a), abs(p - u), abs(p - c)
            line[k] = (line[k] + (a if pa <= pb and pa <= pc else u if pb <= pc else c)) & 255
    rows.append(line)
    prev = line
d = open(ppm, 'rb').read()
head = d.split(b'\n', 3)
sw = int(head[1].split()[0])
body = d[len(b'\n'.join(head[:3])) + 1:]
def differ(x0, y0):
    bad = 0
    for y in range(h):
        want = body[((y0 + y) * sw + x0) * 3:((y0 + y) * sw + x0 + w) * 3]
        bad += sum(1 for k in range(stride) if rows[y][k] != want[k])
    return bad
best = min((differ(x0 + dx, y0 + dy), x0 + dx, y0 + dy) for dx in range(-2, 3) for dy in range(-2, 3))
print(f'{w}x{h} at {best[1]}, {best[2]}, {best[0]} bytes differ')
sys.exit(1 if best[0] else 0)
PY
}

# The status button, with a speaker, is 60 wide at 1220 on 1280: its
# speaker at 1230 to 1246, its pill from 1224. The card is at 916, 36;
# the screenshot button's middle at 1155, 65; the slider's node from 966
# to 1266, 96 to 126 on the screen, 1150 about 62 and 1050 about 26.
waits_for "^l0s> "
waits_for "serving compositor"
waits_for "usb-audio: .*speaker"
# wm looks for the audio server as it starts and each minute: the
# speaker's line shows once wm has the volume. Ink is white on black.
end=$((SECONDS + 75))
found=0
until [ $SECONDS -ge $end ]; do
  rm -f "$dump"; monitor "screendump $dump"
  if [ -s "$dump" ]; then
    for x in 1233 1235 1237 1239; do
      [ "$(pixel $x 16)" != "0 0 0" ] && found=1
    done
  fi
  [ "$found" = 1 ] && break
  sleep 0.5
done
[ "$found" = 1 ] || fail "the status button never showed the speaker"
echo "ok - screenshot: the button shows the speaker"

click 1262 16
shows "the card open" "1228 16 64 64 64"
press_to 1150 111 1050 111
events "$(button false)"
v=$(said "run sound volume 1")
echo "$v" | grep -aqE '^volume (2[2-9]|30)' || fail "the slider did not set the volume: sound said $v"
echo "ok - screenshot: the slider set the volume: $(echo "$v" | grep -aoE '^volume [0-9]+' | tail -1)"

click 1155 65
sleep 1
events "$(at 640 400)"
# The frozen screen is the screen: the bar's ground at 700, 16 black.
shows "the card closed, the screen frozen" "1228 16 0 0 0"
press_to 200 200 300 260
shows "the area outlined in the accent color" "250 200 53 132 228" "200 230 53 132 228"
events "$(button false)"
waits_for "snip: saved /Volumes/data/user/Screenshot-[0-9-]+\.png, [0-9]+ x [0-9]+, [0-9]+ bytes"
line=$(grep -aoE "saved /Volumes/data/user/Screenshot-[0-9-]+\.png, [0-9]+ x [0-9]+" "$out" | head -1)
echo "ok - screenshot: the area saved: $line"

v=$(said "run snip 8 40 64 48 /Volumes/data/user/corner.png")
echo "$v" | grep -aqE 'saved /Volumes/data/user/corner.png, 64 x 48, [0-9]+ bytes' || fail "snip from the shell said $v"
echo "ok - screenshot: snip from the shell saved 64 x 48"

rm -f "$dump"; monitor "screendump $dump"
# The volume unmounted, so that fs has written both files before the
# board stops.
said "unmount data" > /dev/null
name=$(echo "$line" | grep -aoE 'Screenshot-[0-9-]+\.png')
kill $qemu 2> /dev/null; wait $qemu 2> /dev/null
off=$((2048 * 512))
mcopy -n -i "$disk@@$off" "::user/corner.png" "$BUILD/screenshot-corner.png" 2> /dev/null || fail "no user/corner.png on the volume"
mcopy -n -i "$disk@@$off" "::user/$name" "$BUILD/screenshot-area.png" 2> /dev/null || fail "no user/$name on the volume"
r=$(same_pixels "$BUILD/screenshot-corner.png" "$dump" 8 40) || fail "corner.png is not the screen there: $r"
echo "ok - screenshot: corner.png is the screen's pixels: $r"
r=$(same_pixels "$BUILD/screenshot-area.png" "$dump" 200 200) || fail "$name is not the screen there: $r"
echo "ok - screenshot: the area's PNG is the screen's pixels: $r"
