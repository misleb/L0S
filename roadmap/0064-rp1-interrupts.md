# 0064: RP1's interrupts set up by L0S, whatever the bootloader

Track: Pi 5 · Status: idea · Needs: – · Spec: pi5.md, programs.md

## Why

RP1's interrupts reach the CPU as MSIs, which L0S takes as interrupts
160 to 223 because the host, the firmware, has set the PCIe
controller up to take them (AGENTS.md, spec 10.3); `rp1_up` sets up
only RP1's side, its MSI-X table and BARs. Goal
[0027](0027-installer.md) flashed rpi-eeprom's 2026-10-30 bootloader,
and from then on no RP1 interrupt came, on a card or a network boot:
`xhci` found its ports but no device, `gem` its link but no frame, and
DHCP failed. Going back to 2026-05-26's mended it, and the release now
pins that one (pi5.md). So L0S runs only on the bootloaders whose
firmware leaves the controller's MSI target as L0S expects, and any
update to one, by Raspberry Pi OS or by hand, can take USB and the
network away.

## Done when

- With 2026-10-30's bootloader, or the newest, a Pi 5 boots L0S with
  its USB keyboard and mouse and a DHCP lease, as with 2026-05-26's.
- `rp1_up` (or the kernel) sets the PCIe controller's MSI target and
  enables it, as Linux's `pcie-brcmstb` does, rather than relying on
  the firmware's.
- The release's pin may then move to a newer bootloader, and pi5.md
  says which ones L0S has run on.

## Steps

To be written. First, the controller's MSI registers read on a board
under each bootloader, to see what 2026-10-30's leaves differently.

## Spec changes

- pi5.md: RP1's interrupts, set up by L0S; the bootloaders run on.
- programs.md: what `rp1_up` sets.

## Log

- 2026-11-02: written as 0027 closed, after 2026-10-30's bootloader
  left the board with no USB device and no network.
