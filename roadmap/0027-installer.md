# 0027: Installing and updating L0S from the proxy, with a GUI

Track: Storage · Status: done · Needs: – · Spec: boot.md, pi5.md, programs.md, storage.md, network.md, agent.md, speech.md, demo.md, testing.md

## Why

L0S can install itself from scratch now (goal
[0022](0022-pi5-card-complete.md)), but only through steps a user must
already know, in order, across two programs and the shell
([pi5.md](../spec/pi5.md), "A card that boots a system volume"):

1. Network boot, and erase the card (Disks' Format Disk..., or `erase`).
2. Create a FAT32 partition for the boot files, sized by guess.
3. Create an L0FS partition for the system, and format both.
4. `run install System`.
5. `run install --boot bootfs --root System`.
6. Change the EEPROM's `BOOT_ORDER` to try the card (`eeprom`).
7. Reboot.

Nothing says what a good layout is, and nothing checks the result. A
step done wrong (the wrong volume as `--root`, a boot partition too
small for `input.bin`, the boot order left at the network) shows only
when the board fails to boot. On QEMU the same install is
`install VOLUME` and `root=`, with no boot partition at all.

`install` copies whatever `/` is, the initramfs the board booted, so
the system can be no newer than that, and nothing brings over what is
not in it: Whistle's 16.9 MB model (goal
[0060](0060-speech-to-text.md)) reached the Pi 5 by hand, over `tftp`.
The board already talks to a proxy on the host for the model's API,
backups and `build_app` ([network.md](../spec/network.md)); the same
proxy can serve the host's latest build, a **release**.

## Done when

- `make release` stages `build/release/BOARD/` for `pi5` and `virt`:
  `system/` (the programs and that board's `/etc`), `boot/` on the Pi
  5 (`l0.img`, `config.txt`, `cmdline.txt`, the dtbs, `input.bin`),
  `eeprom/pieeprom.bin` on the Pi 5 and `speech/whistle.cact`, both
  fetched once at a pinned commit and SHA-256, `agent/`
  (the home's `CLAUDE.md` and `CONSTITUTION.md`), and a `manifest`
  naming each file's part, path, size, SHA-256 and mode. The proxy
  serves it, with the board's token, as `GET /release/BOARD/manifest`
  and `GET /release/BOARD/PATH`, a file streamed, nothing outside the
  release; `test_proxy.py` tests both and the refusals.
- `install --net fresh [--boot BOOT] [--boot-order sd,net] SYSTEM`
  checks everything first (the volumes, `/Volumes/data`, the
  manifest), says what it will format, formats BOOT and SYSTEM, writes
  the release's system and boot files, `cmdline.txt` with
  `root=SYSTEM's UUID`, and on the data volume `agent`, `speech` and
  `user`, the model in `speech`, the agent's seed files in `agent` (an
  existing one kept), each file checked against its SHA-256 as it
  comes.
- `install --net update [SYSTEM]` (the running system volume if none)
  writes the system and boot files again, keeping `cmdline.txt`'s
  `root=` and `/etc/agent`'s `config` and `token`, fetches the model
  only if the data volume's differs, and never overwrites an agent
  file: it names each it kept.
- On a Pi 5, `--boot-order sd,net` puts `pieeprom.upd` and
  `pieeprom.sig` on the boot volume, the configuration the running one
  (or the image's own) with `BOOT_ORDER=0xf21`, which the bootloader
  flashes as it next boots.
- An app, Installer, in the launcher, does the same through the same
  library: fresh install or update, the volumes chosen from those
  mounted, a warning if `/Volumes/data` is missing, what it will format
  said before it does, and each step's progress (the file, bytes of
  the total).
- An e2e case installs fresh from a release served by the proxy, then
  updates over it with an agent file changed, kept; a screen test
  drives the Installer; a Pi 5 installs from the network and boots
  from the card it wrote.

## Steps

- [x] The goal: Done when and Steps, and 0060's open question (where
  the model lives) answered here: on the data volume, in `speech`.
- [x] The release and the proxy's routes: `tools/mkrelease`, `make
  release`, `proxy.py --release` (`release.py`, the manifest made from
  the files), `test_proxy.py`.
- [x] The libraries: SHA-256 a piece at a time; `sys/release.l0` (the
  manifest, the plan for each mode, where each file goes, a download
  to a file checked as it comes, and what `install` and the Installer
  share), with host tests.
- [x] `install --net fresh|update`, `/etc/board`, `listen`'s model at
  `/Volumes/data/speech/whistle.cact`, and the e2e case `install_net`.
- [x] The boot order: `eeprom`'s image and mailbox code as libraries
  (`format/pieeprom.l0`, `sys/bootloader.l0`), `boot_order_set`,
  `--boot-order sd,net`, the release's `pieeprom.bin`.
- [x] The Installer app, its host tests and its screen test.
- [x] On a Pi 5: a fresh install from the network with the boot order
  set, booted from the card; an update; how long each took (not
  measured: see the log).

## Spec changes

All moved into spec/. pi5.md says what the boot order's update did on
the board: the release's bootloader, 2026-10-30's, broke RP1's
interrupts, so the release pins 2026-05-26's, and `make pi5-eeprom`
flashes it back. The install's and update's times were not taken.

## Log

- 2026-10-28: written, after the first install from scratch on the
  Pi 5 (0022's last step) took seven manual steps across Disks, the
  shell and `eeprom`.
- 2026-11-01: steps written. The installer fetches from the proxy, not
  the initramfs: two modes, fresh and update; the volumes are made in
  Disks and chosen, not laid out by the installer; the data volume is
  `/Volumes/data`, with `agent`, `speech` and `user`; agent files are
  never overwritten; the boot order is set through `pieeprom.upd`.
- 2026-11-01: steps 2 to 6 done. `make release` staged 131 files for
  the Pi 5 (17.2 MB of `input.bin`, 16.9 MB of the model) and 124 for
  virt. On QEMU, `install_net` installs fresh from the proxy and
  updates over it, keeping the agent's rules, the token and the model;
  the Installer does a fresh install from its window
  (`tests/installer.sh`). `install` and the Installer cannot use the
  mailbox, not being flagged `dev`, so the boot order starts from the
  release image's configuration, which they say. The Installer runs
  `install --net --progress` as its child on a terminal of its own, so
  the window never waits on the network or the file server.
- 2026-11-02: `make release` fetches Whistle's model (Hugging Face,
  commit 7411186) and the Pi 5's bootloader image (rpi-eeprom's
  `default`, pieeprom-2026-10-30.bin) into `build/fetch` itself, each
  checked against a pinned SHA-256, so no path is given;
  `WHISTLE_MODEL` replaces `WHISTLE`, which named the Makefile's speech
  libraries too and broke their build when set on make's line.
- 2026-11-02: the first fresh install on a Pi 5 stopped after the plan
  was said: "the proxy said nothing for 30 s". The manifest's
  connection had sat idle while the SD card's volumes were formatted,
  and its next request went unanswered; QEMU, with the proxy closing
  idle connections after 0.3 s, did not show it. `install` now fetches
  the files on a new connection made after the format, and the message
  names the file and how much of it came.
- 2026-11-02: the next try stopped the same way after 108 KB of
  `input.bin`, the fifth file. `inet` gave each segment to its client as
  it came, acknowledged it, and offered a window of 8192 bytes always;
  `install`, writing each piece to the card before reading the next,
  let its port's 32 messages fill, and `inet` reset the connection with
  a notice that could not reach the full port either. `inet` now holds
  a full port's notices in order, offers a window less what it holds,
  and gives them every 2 ms (network.md).
- 2026-11-02: the next try ended `aborted` near the same place: data
  joined from segments that came out of order was told in one notice
  of up to 8192 bytes, over a message's 4096, which the kernel refused
  as too big, and `inet` gave the connection up; split, it fits. Then,
  as the user asked, the real fix, here since the installer is its test:
  each connection's data now comes through a ring of 16 shared pages
  that `inet` fills and the owner reads, told `tcp ID data N` and
  answering `took ID N`, one notice unanswered at a time, the window the
  ring's room, up to 65535 (network.md). A connection without one, as
  under `l0 test`, keeps the notices. On QEMU, `install_net` with a
  reader slowed to 20 ms a piece took 1 MB through the ring, 16 times
  round, whole; `net_echo` now sends 300000 bytes.
- 2026-11-02: on the Pi 5, a fresh install from the Installer went
  through, boot order and all, and the card booted. But the bootloader
  it flashed, the release's, rpi-eeprom's 2026-10-30, broke L0S on the
  board: from then on RP1's interrupts never came, so `xhci` found no
  device and `gem` no frame, and DHCP failed, booted from the card or
  the network. The release now pins 2026-05-26's, the one L0S had run
  on, and `make pi5-eeprom` (`tools/mkeeprom`) puts its update in the
  netboot's root to flash it back. Why 2026-10-30's firmware leaves
  RP1's MSIs unset, and drivers that set them up themselves, are not
  this goal's.
- 2026-11-02: with 2026-05-26's bootloader back, the user netbooted and
  installed fresh from the Installer, and the card booted: but with no
  network, `gem` finding no PHY, so `install --net update` could not
  run from it. A card's bootloader leaves the PHY held in reset by
  RP1's GPIO 32, which a network boot's lets go; `gem` now lets it go
  itself when no PHY answers (network.md), not yet tried on the board.
- 2026-11-02: done. The user installed fresh and then updated on the
  Pi 5 from the Installer, with the release's 2026-05-26 bootloader,
  and the board then booted from the card; both worked. The serial log
  of those runs was not kept, so neither their times nor gem's line on
  the card boot were seen. A card boot still differs from a network
  boot: no firmware splash, `hvs` at the firmware's 1920x1080 rather
  than 4K, and perhaps no HDMI audio, which is
  [0063](0063-card-boot-display.md)'s; and L0S needing the bootloader to
  have set RP1's interrupts up is [0064](0064-rp1-interrupts.md)'s.
