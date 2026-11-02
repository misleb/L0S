# 0027: Installing and updating L0S from the proxy, with a GUI

Track: Storage · Status: active · Needs: – · Spec: boot.md, pi5.md, programs.md, storage.md, network.md, agent.md, speech.md, demo.md, testing.md

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

- `make release [WHISTLE=PATH] [PIEEPROM=PATH]` stages
  `build/release/BOARD/` for `pi5` and `virt`: `system/` (the programs
  and that board's `/etc`), `boot/` on the Pi 5 (`l0.img`,
  `config.txt`, `cmdline.txt`, the dtbs, `input.bin`, and
  `pieeprom.bin` if given), `speech/whistle.cact` if given, `agent/`
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
- [ ] On a Pi 5: a fresh install from the network with the boot order
  set, booted from the card; an update; how long each took.

## Spec changes

- pi5.md: the Pi 5's fresh install and update timed, and what the boot
  order's update did there.

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
