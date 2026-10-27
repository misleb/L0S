# 0016: The Pi 5's boot config, read and changed from L0S

Track: Pi 5 · Status: done · Needs: – · Spec: pi5.md, programs.md

## Why

The Pi 5's bootloader keeps its configuration (`BOOT_ORDER`,
`TFTP_PREFIX` and the rest) in its EEPROM, and the only way to see or
change it is `rpi-eeprom-config` on Raspberry Pi OS
([pi5.md](../spec/pi5.md), "Over the network": the board's EEPROM must
say `BOOT_ORDER=0xf21`). A board running L0S can't say how it will boot
next, or be switched between the card and the network, without another
OS's card.

## Done when

- On the Pi 5, a command prints the bootloader's configuration as the
  firmware has it.
- The same command changes it: the next boot's bootloader flashes the
  new configuration, and the boot after that prints it.
- Host tests cover finding and replacing the configuration in an
  EEPROM image and the update's digest; the flash itself is checked on
  a board, its log saying what was seen.

## Steps

- [x] Read the configuration through the firmware, as `vcgencmd
  bootloader_config` does: the mailbox's gencmd tag (0x00030080, to be
  confirmed on the board), over `mailbox.l0` as `rtc` asks for the time.
  A program `eeprom` prints it. This step needs no disk.
- [x] A SHA-256 library in `user/lib`, tested against FIPS 180-4's
  vectors: the bootloader checks an update by `pieeprom.sig`, the
  image's SHA-256 in hex and a `ts:` line.
- [x] Find and replace `bootconf.txt` in an EEPROM image, as
  `rpi-eeprom-config` does: walk the image's sections by their magic
  and big-endian lengths, read the file section named `bootconf.txt`,
  and write a new one in its place, refusing a config larger than the
  section has room for. Pure, on `bytes`, with host tests on a small
  image made in the test.
- [x] `eeprom update IMAGE CONFIG DIR`: take a release image copied onto
  a volume (`pieeprom.bin`, from rpi-eeprom's `firmware-2712`), replace
  its config with the file CONFIG, and write `pieeprom.upd` and
  `pieeprom.sig` to DIR, the boot volume; `reboot` then has the
  bootloader flash it.
- [x] On a board: `eeprom` prints what `vcgencmd bootloader_config`
  does, `eeprom update` of `BOOT_ORDER` is flashed on the next boot from
  the card, and the boot after prints it. (On the host, `eeprom
  update`'s files already match rpi-eeprom's for a release image: log,
  2026-10-27.)

## Spec changes

All moved into pi5.md.

## Log

- 2026-10-27: written. The bootloader's own self-update (the files on
  the boot partition) is chosen over driving the SPI flash directly:
  it needs no new region from L0, keeps the bootloader's own checks,
  and a bad image is refused rather than bricking the board.
- 2026-10-27: steps 1 to 4 landed: `/sbin/eeprom` (`eeprom.l0`, its
  gencmd messages; `image.l0`, the image's sections and the update),
  `user/lib/format/sha256.l0`, `dev /sbin/eeprom` in `pi5/etc/inittab`,
  and the e2e cases `eeprom_nombox` and `eeprom_show`. Moved into the
  spec: pi5.md's "The bootloader's configuration", its Limit and a
  first-boot check, and programs.md's and testing.md's rows. The
  image's layout, the gencmd tag and the `.sig` format were from memory
  of rpi-eeprom and vcgencmd.
- 2026-10-27: checked against rpi-eeprom's master on the host, with the
  release image `firmware-2712/default/pieeprom-2026-09-25.bin` (2 MiB,
  sha256 02c4daa2…0edd). Its sections: the bootcode at 0, padding,
  `readonlyver` and `updatetime`, padding to 64 KiB; then the first
  partition, `bootsys` at 65536, its pieces (magic 0x55aaf44f),
  `versioninfo`, `updatetime`, `pubkey.bin`, `cacert.der`,
  `bootconf.sig`, and `bootconf.txt` at 700416, followed by two padding
  sections to 2088960. That showed three things memory had wrong, all
  fixed in `image.l0`: the configuration's room runs to the next section
  that is not padding (it had stopped at the padding after it, 64 bytes,
  and would have refused nearly any configuration), within the first
  partition, 64 KiB to 1052 KiB, where an update looks for it; the
  largest configuration is 4076 bytes, not 2024; and the tool already
  writes a padding section of length 0 for a gap of 8. Then, for five
  configurations of 0 to 3406 bytes, `ee_update` (built for the host
  with a harness in a scratch directory) wrote `pieeprom.upd` and
  `pieeprom.sig` identical to `rpi-eeprom-config --config` and
  `rpi-eeprom-digest` with the same time; the image's own configuration
  written back gave the image unchanged; and both refuse 4400 bytes.
  The gencmd tag is still unchecked: that needs the board.
- 2026-10-27: on the Pi 5 (2 GB, network booting, `BOOT_ORDER=0xf2`).
  `run /sbin/eeprom` printed the running configuration (`BOOT_UART=1`,
  `UART_SELECT=2`, `BOOT_ORDER=0xf2`, `NET_INSTALL_AT_POWER_ON=1`) and
  `eeprom version` the bootloader's (2026/05/26 release 086b83e3,
  `update-time 1792897039`): the gencmd tag, 0x00030080, is right. The
  board has no battery on its RTC, whose clock read 1970, so an update
  stamped with the clock would have been older than the last and
  ignored; `eeprom update` now takes the later of the clock and
  bootloader_version's update-time and a second. With
  `pieeprom-2026-05-26.bin`, the running bootloader's own release, and
  that configuration with a comment line added, both in a one-off
  initramfs's `/etc` (`tftp` of the image hung the shell, now 0018),
  `eeprom update` wrote `/Volumes/tmp/pieeprom.upd` and `.sig` with
  `ts: 1792897040` and SHA-256 7d7bfe5b…0677d, the same as
  `rpi-eeprom-config` and `rpi-eeprom-digest` give on the host for the
  same image, configuration and time. Nothing was flashed. This board
  boots only from the network, so a flash would go through the TFTP
  root, not the card.
- 2026-10-27: flashed, with the user's go-ahead. Those two files (the
  host's copies, the same bytes by their SHA-256) put in
  `build/pi5-tftp` as `pieeprom.upd` and `pieeprom.sig`, and the board
  rebooted (`tools/pi5-boot --no-build --reboot`): the bootloader
  fetched both over TFTP and said `SELF-UPDATE timestamp current
  1792897039 new 1792897040`, `Writing EEPROM` (5.5 s), `Verify BOOT
  EEPROM`, `BOOT-EEPROM: UPDATED`, and rebooted; on that boot it found
  the same files again and said `timestamp current 1792897040 new
  1792897040 skip`, so an update left in place is not flashed twice.
  Then `eeprom` printed the configuration with `# set from L0S by
  eeprom update`, and `eeprom version` `update-time 1792897040`. The
  bootloader self-updates from a network boot's TFTP root as from a
  card. The files were taken out of the TFTP root after. Done. Reading needs only the mailbox, so the first step
  could go ahead before 0004.
