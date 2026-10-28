# 0027: Installing L0S, a process of its own, with a GUI

Track: Storage · Status: idea · Needs: – · Spec: boot.md, pi5.md, programs.md, storage.md, testing.md

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

## Done when

- To be written. What it will at least hold:
  - One installer, an app in the launcher, that takes a disk and leaves
    it bootable: it lays the disk out (on a Pi 5 a FAT32 boot partition
    and an L0FS system volume), formats, copies the system, writes the
    boot files and `root=`, and, if asked, sets the boot order. It shows
    each step's progress and says plainly what it will erase before it
    does.
  - The same process with no GUI, a command `sh` runs, which the GUI
    drives or shares a library with, so an e2e case can test it whole.
  - A defined layout: the boot partition's size from what `input.bin`
    needs, with room to grow; volume labels; what happens to a disk that
    already holds L0S (reinstall over it, keeping or replacing
    `System`).

## To decide

- Whether the installer is its own program or a mode of Disks.
- Whether `input.bin` should stop carrying `/boot` once the installer
  writes the boot files from somewhere else, and where that is: the
  initramfs, a release image fetched with `tftp`, or the running card's
  `bootfs`.
- Whether a system volume keeps a record of its install (version, date,
  boot partition's UUID), and whether an update is a reinstall.
- QEMU: whether the installer handles `virt` too (a system volume and
  no boot partition), and how a QEMU boot gets `root=`.
- Whether it checks the result before it says it's done, by reading
  back `cmdline.txt` and the system volume's `/etc/system`.

## Steps

None yet: an `idea` until Done when is written.

## Spec changes

To be written with the steps.

## Log

- 2026-10-28: written, after the first install from scratch on the
  Pi 5 (0022's last step) took seven manual steps across Disks, the
  shell and `eeprom`.
