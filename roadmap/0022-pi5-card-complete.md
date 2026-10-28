# 0022: `install --boot` writes all a Pi 5's card needs

Track: Pi 5 · Status: active · Needs: – · Spec: pi5.md, programs.md, testing.md

## Why

`install --boot VOLUME` makes a FAT32 volume a Pi 5's boot partition
from the running system, but writes only `l0.img`, `config.txt`,
`cmdline.txt` and `input.bin` ([pi5.md](../spec/pi5.md), "Making a card
from a running L0S"). The firmware is in the EEPROM, but it loads the
board's device tree from the card, and the Pi 5's initramfs has none,
so on a card L0S partitioned and formatted itself `install` can only
say `no bcm2712-rpi-5-b.dtb` and send the user to Raspberry Pi OS's
boot partition for it. A board running L0S cannot make a card that
boots without another OS's files from another computer. The build
already fetches the two device trees for the network boot
(`tools/pi5-boot`, into `build/pi5-dtb`), but only there, unpinned
(raspberrypi/firmware's `stable` branch) and unchecked.

## Done when

- `make pi5-card` and the Pi 5's initramfs hold `bcm2712-rpi-5-b.dtb`
  and `bcm2712d0-rpi-5-b.dtb`, fetched once from raspberrypi/firmware at
  a pinned commit and refused unless their SHA-256 matches, or taken
  from `PI5_BOOT` as before.
- `install --boot VOLUME` copies them with the other boot files, so on
  a volume that had nothing it says no `no bcm2712-rpi-5-b.dtb`; the
  note stays for a FROM without them. The e2e case `install_boot` shows
  the first, `install_test` the note.
- On a board: a blank card, given a partition and a FAT32 volume by
  `partition` and `mkfs` (or Disks) and filled by `run install --boot`,
  boots the Pi 5 to the shell with `BOOT_ORDER` trying the card first,
  the log saying what the bootloader read from it.

## Steps

- [x] One fetch of the device trees for every Pi 5 target: a Makefile
  rule for `build/pi5-dtb` from raspberrypi/firmware's `boot/` at a
  pinned commit, each file's SHA-256 checked before it is kept, that
  `pi5-netboot` and `tools/pi5-boot` use in place of their own; `PI5_BOOT`
  still overrides it. Their license, GPL-2.0 as Linux's sources they are
  built from, said beside the pin.
- [x] `pi5-initramfs` puts them in `/boot` beside `l0.img`, and
  `pi5-card` in `build/pi5-card`, so `install --boot` copies them as any
  boot file. `install`'s `boot_line` counts them with the rest; the
  `install_boot` e2e case's `/etc/boot` gains a stand-in `.dtb`, and
  the note for a FROM without one stays `install_test`'s.
- [x] Disks' Format... and `fs`'s `mkfs` on an MBR's partition, so a
  card Raspberry Pi OS made can be kept: its ext4 rootfs made L0FS (for
  `install`, and `root=`) or FAT32, by the UUID `fs` knows it by, the
  partition's type byte alone changed in sector 0 (`0C`, or `7F` for
  L0FS, which `fs` then mounts from an MBR).
- [x] `install --boot VOLUME [FROM] --root ROOT`: the card's
  `cmdline.txt` made to say `root=` and ROOT's UUID, its other words
  kept, so a card boots a system volume `install ROOT` filled; ROOT
  checked before anything is written. Host tests of the words and the
  file's text; `install_boot` with `--root data`.
- [x] `fs`'s `erase DISK`, the shell's `erase` and Disks' Format
  Disk...: a drive given a new, empty GPT in place of its table, an
  MBR's too, its volumes unmounted first, so a card Raspberry Pi OS
  made can be started over as one of L0S's own.
- [ ] On a board: a card with no partitions, partitioned and formatted
  from L0S, `install --boot` onto it, and `eeprom update` to
  `BOOT_ORDER=0xf21` if the board tries only the network; it boots to
  the shell. This checks what nothing on QEMU can: that the bootloader
  takes L0S's GPT and the partition type `partition` gives a FAT32
  volume, and needs nothing more, no `overlays/`, beside these files.
  Whatever it does need goes into the first two steps' files.

## Spec changes

- pi5.md: its first section drops "A card holding only them has not
  yet been booted from". Limits: the board boots from a card L0S
  wrote, not only one `l0 card` wrote.

## Log

- 2026-10-27: written. The device trees are fetched at build time
  rather than kept in the tree, as `tools/pi5-boot` already does, but
  pinned and checked so a build is the same build every time.
- 2026-10-27: step 1 landed. `PI5_DTB_COMMIT` pins raspberrypi/firmware
  at 12eeaa1, its `stable` on 2026-06-01 (kernel 6.18.33), whose two
  device trees are byte for byte the ones `tools/pi5-boot` had fetched
  on 2026-10-25 and the board has booted with since; their SHA-256s are
  in `pi5/dtb.sha256`. The Makefile's `build/pi5-dtb/%.dtb` fetches one
  and keeps it only if its hash matches, leaving any copy already there
  as it was; `pi5-netboot` needs both, from there or `PI5_BOOT`, and
  `tools/pi5-boot` no longer fetches its own. Moved into pi5.md: the
  network boot's paragraphs, `PI5_BOOT` now optional.
- 2026-10-27: step 2 landed. `pi5-initramfs` copies both device trees
  into `/boot` before `l0 card` writes there, and `pi5-card` into
  `build/pi5-card`, so `l0 card` no longer says the card lacks one;
  `pi5-netboot` takes them from `build/pi5-card` with the rest, and the
  fetch's variables moved above `pi5-initramfs`, whose prerequisites
  name them. `install` needed no change: it copies whatever `/boot`
  holds, and its note looks at the volume. A second `install --boot` in
  `install_boot`, from a FROM without a device tree, would have taken
  the boot past e2e's two minutes (each writes the whole initramfs,
  about 55 s), so the case has only the FROM with one and the note
  stays `install_test`'s. Moved into the spec: pi5.md's first section
  and "Making a card", programs.md's `install` row, testing.md's
  `install_boot`; pi5.md says a card holding only these files has not
  yet been booted from, which step 3 settles.
- 2026-10-27: step 3 added and landed, asked for before the board
  test: Disks could not format the ext4 rootfs of the user's card,
  since L0S wrote nothing to an MBR. Now `mkfs` finds an MBR's
  partition by its `mbr_part_uuid`, makes the volume, and rewrites
  sector 0 with that partition's type changed, every other byte kept
  (`mbr_with_type`); a disk load mounts L0FS volumes on partitions of
  type 7F, beside FAT32's. 7F was chosen as the type set aside for an
  OS of one's own, so Linux leaves the partition alone. Disks offers
  Format... on an MBR's partitions with no volume served; still no
  Create Partition. Tests: `mbr_test`'s `test_part_of`, `test_with_type`,
  `test_typed`; `fs_test`'s `test_mkfs_mbr`, `_found`, `_refused`;
  Disks' `test_mbr_acts`. Moved into the spec: fat32.md's "Where",
  storage.md's L0FS type and Limits, programs.md's `fs`, `disks` and
  `mbr.l0` rows.
- 2026-10-27: step 4 added and landed, also asked for before the board
  test: `install --boot` sets the root. Chosen with the user: a flag,
  `--root ROOT`, rather than the running `/`'s UUID, so a card can boot
  a volume just filled by `install ROOT` while the board runs from the
  initramfs. `cmdline_rooted` keeps the file's words, drops any
  `root=`, appends `root=UUID`, and puts `--l0-args` first if it was
  missing. In the e2e case `data` now has a fixed UUID in `layout`.
  Moved into the spec: pi5.md's "A card that boots a system volume",
  programs.md's `install` row, testing.md's `install_boot`. pi5.md says
  such a card has not yet been booted from, which the board step
  settles.
- 2026-10-27: with 0023's windows `install_boot` takes about 3 s, not
  55, so it has the run step 2 left out: first from `/etc/nodtb`, with
  no device tree, and the note; then `/etc/boot`'s, with none.
- 2026-10-27: on the board, network booted, with 0023's windows: `run
  install System` onto the card's rootfs, made L0FS by Disks, in just
  under a minute, and `run install --boot bootfs --root System` in
  about 15 s. Not yet booted from: the board's `BOOT_ORDER` is 0xf2,
  the network only, so the last step needs `eeprom update` to 0xf21
  first.
- 2026-10-27: booted from the card, by the user, its EEPROM changed to
  try the card. The bootloader's log: `autoboot.txt` and `pieeprom.upd`
  not found; `config.txt` read (179 bytes); `input.bin` loaded at
  0x10000000 (19,751,068 bytes); `dtb_file 'bcm2712-rpi-5-b.dtb'`
  (78,679 bytes), then `/overlays/overlay_map.dtb` and
  `/overlays/bcm2712d0.dtbo`, Raspberry Pi OS's, still on `bootfs`;
  `cmdline.txt`'s `--l0-args root=f5d35b74-0000-0000-0000-000000000002`;
  `l0.img`; Starting OS at 19.3 s. Then L0S `booted with root=…`,
  mounted `System` at sector 1064960 and said `/ is the volume System,
  and the initramfs is given up`, and the shell's prompt came. So an
  L0S-installed card boots, root and all. Not shown: a card with only
  L0S's files (the firmware read `overlays/` to fit the C1 tree to this
  D0 board, and with none may want `bcm2712d0-rpi-5-b.dtb`, which
  `/boot` has too), nor one on L0S's GPT. Step 5 stays open for those:
  renaming `bootfs`'s `overlays` and booting again answers the first.
- 2026-10-27: for step 5 on a card with nothing of Raspberry Pi OS's,
  as the user asked: `fs`'s `erase DISK`, the shell's `erase` and
  Disks' Format Disk... give a drive a new, empty GPT in place of its
  table, an MBR's too, its volumes unmounted first. Then Create
  Partition and Format... make `bootfs` FAT32 and `System` L0FS on it,
  so the user can network boot, erase the card, and install from
  scratch. Tests: `fs_test`'s `test_erase`, `_mbr`, `_refused`; Disks'
  `test_erase_dialog`, `_button`; `sh`'s `test_erase`; and `fat_mbr`,
  which now ends erasing its MBR card.
- 2026-10-27: on the board, with the card's rootfs made L0FS `System`
  by Disks: `install System` wrote, but slowly, and `install --boot
  bootfs --root System` was stopped after minutes, still writing. Not
  a hang: `fs` makes about 4 disk requests and a flush for each 4 KB of
  a file, which a card makes slow. That is 0023; the board step can go
  ahead before it, given the time.
