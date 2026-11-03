# 0064: RP1's DMA window set up by L0S, whatever the bootloader

Track: Pi 5 · Status: done · Needs: – · Spec: pi5.md, programs.md

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

Run 3 (Log) showed the interrupts were not what broke: 2026-10-30's
narrows the controller's inbound window for RP1's DMA, and the goal
was renamed for it.

## Done when

- With 2026-10-30's bootloader, or the newest, a Pi 5 boots L0S with
  its USB keyboard and mouse and a DHCP lease, as with 2026-05-26's.
- `rp1_up` (or the kernel) sets what the bootloaders leave differently,
  rather than relying on the firmware's: as run 3 found, the inbound
  window RP1's DMA uses, not the MSI target, which L0's host sets.
- The release's pin may then move to a newer bootloader, and pi5.md
  says which ones L0S has run on.

## Steps

1. [x] The probe: under `debug`, the kernel says, before it changes
   anything, what the firmware left in the PCIe controller's MISC block
   (0x4000 to 0x413F: `MSI_BAR`, the inbound windows `RC_BAR1` on and
   their UBUS remaps), its own MSI interrupt's words (0x4500) and the
   MIP, mip0 at 0x1000130000 in the board's device tree, which takes
   PCI 0xFF_FFFFF000 through the controller's third inbound window and
   raises SPI 128 + n (`rp1_probe`, `common/rp1.l0`).
2. [x] Board runs with `PI5_ARGS=debug`: under 2026-05-26's bootloader
   a network and a card boot, under 2026-10-30's a card boot; the
   probes diffed. What differs is the inbound window RP1's DMA uses,
   RC_BAR2 and its remap, not the MSIs' (run 3 in the Log).
3. [x] `rp1_up` sets that window as 2026-05-26's leaves it, every time,
   whether or not RP1's window already answers (`rp1_inbound_writes`,
   `rp1_inbound_set`); the words pure and tested on the host.
4. [x] On the board: 2026-10-30's and the newest bootloader each boot
   with USB HID and a DHCP lease, and 2026-05-26's still does; the
   release's pin moved to the newest that ran; pi5.md and programs.md.

## Spec changes

- pi5.md: RP1's interrupts, set up by L0S; the bootloaders run on.
- programs.md: what `rp1_up` sets.

## Log

- 2026-11-02: written as 0027 closed, after 2026-10-30's bootloader
  left the board with no USB device and no network.
- 2026-11-02: steps written, with 0063, whose board runs these share;
  step 1, the probe, in, the MIP's address and window read from the
  pinned `bcm2712-rpi-5-b.dtb` (mip0's `reg`, pcie2's third
  `dma-ranges`, PCI 0xFF_FFFFF000 to 0x1000130000). Not yet run on the
  board.
- 2026-11-02: run 1, a network boot under 2026-05-26's bootloader
  (`build/pi5-net-0526.log`). The controller as the kernel found it:
  RC_BAR3 (0x403C, 0x4040) `fffff01c 000000ff` and its UBUS remap
  (0x40BC, 0x40C0) `00130001 00000010`, PCI 0xFF_FFFFF000 to the MIP,
  which L0's own Pi 5 host sets as it starts (`l0 spec pi5`, the PCIe
  MSIs), not the firmware; MSI_BAR (0x4044, 0x4048) `fffffffd 0000000f`
  and MSI_DATA (0x404C) `ffe06540`, the controller's own target at
  0xF_FFFFFFFC, Linux's data word; UBUS BAR1 and BAR2 remaps 1 and 0,
  identity. The MIP is no region (`no device there`): L0's host keeps it,
  as it does the GIC, making its vectors edge-triggered and the CPU's
  alone. So what 2026-10-30's firmware breaks is either in the
  controller, which L0S can set, or in the MIP or GIC, which only L0's
  host can: run 3 decides, and in the second case step 3 is a request
  to L0 (`probes/`), not code here.
- 2026-11-02: run 2, a card boot under 2026-05-26's
  (`build/pi5-card-0526.log`, 0063's): the controller's words the same
  as run 1's but 0x4050 (`3ba36080`, `3ba360c0` on the network), and
  every RP1 interrupt came. Run 3 is a card boot under 2026-10-30's,
  the release made with `PIEEPROM=build/fetch/pieeprom.bin` and
  installed, so that the Installer flashes it; with no network after,
  2026-05-26's goes back as in 0027, by `make pi5-eeprom` and a network
  boot with the card out.
- 2026-11-02: run 3, the card boot under 2026-10-30's
  (`build/pi5-card-1030.log`, `BOOTLOADER release … 2026/10/30`). As in
  0027, `xhci`'s ports connected but no device was reset, and `inet`
  said `no DHCP server answered`, though `gem` linked. The interrupts
  were not what changed: RC_BAR3 and its remap to the MIP were as
  before, and `gem` and `xhci` bound theirs. What changed was the
  controller's second inbound window, by which RP1's DMA reaches
  memory: RC_BAR2 (0x4034) `3b000008` and its remap (0x40B4)
  `3b000001`, 8 MB at 0x3B000000, where 2026-05-26's leaves `00000015`
  and `00000001`, PCI 0 for 64 GB; and 0x4050, whose meaning is not
  known, `3b01c080`. So RP1 reads and writes only the firmware's own
  buffers, and every ring and buffer of `xhci` and `gem` is out of its
  reach. `rp1_up` now writes 2026-05-26's four words every time
  (`rp1_inbound_writes`), whatever the window's state; the goal's name
  and Why blame the interrupts, which run 3 cleared.
- 2026-11-02: done. Run 4, a network boot of that build under
  2026-10-30's (`build/pi5-net-1030-fix.log`; the probe read
  `3b000008` and `3b000001` before `rp1_up` set them): `xhci` reset and
  enumerated the keyboard and mouse, `usb-hid` served both, and `inet`
  took a lease. 2026-10-30's is rpi-eeprom's newest default image, and
  the release pins it now (the Makefile's `PIEEPROM_*`, its SHA-256 the
  same as `build/fetch/pieeprom.bin`'s, which the Installer flashed).
  2026-05-26's was not booted with the fix: under it, runs 1 and 2 read
  the very words `rp1_up` now writes, so the writes change nothing
  there. pi5.md and programs.md updated. The goal was renamed from
  "RP1's interrupts set up by L0S".
