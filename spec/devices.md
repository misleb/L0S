# Devices

## Randomness

`virtio-rng` ([user/sbin/virtio-rng](../user/sbin/virtio-rng/virtio-rng.l0))
drives QEMU's virtio-rng, which every boot gives the board
(`tools/qemu-boot.sh`, the Makefile's `DEVICES`, `tests/e2e.sh`), and
which reads the host's `/dev/urandom`. It serves **the random protocol**
([user/lib/proto/random.l0](../user/lib/proto/random.l0)) as `random`:

| Request | Does |
|---|---|
| `bytes N` | `random HEX`: N bytes, 1 to 1024, that the device gave, as 2N lowercase hex digits |

`random_bytes` asks for some, at once with no waiting, and says why
there are none when no driver has registered `random`, so its clients do
without on a board with no device: `fs`, which makes the noise of a new
partition's UUID of it (see [Volumes](storage.md#volumes)), falling back to the
clock's mixer, and `inet`, which keys TCP's first sequence numbers with
a word of it (see [The network](network.md#the-network)), falling back to the
clock alone. `run random [N]` writes N bytes.

## USB

USB is how a keyboard and a mouse reach a Raspberry Pi 5, whose ports
are on RP1, the southbridge behind PCIe: two Synopsys DWC3 controllers,
each an xHCI in host mode. QEMU has no Pi 5, but its virt board takes a
`qemu-xhci` on PCIe, with a `usb-kbd` and a `usb-mouse` on it
(`QEMU_INPUT=usb` in `tools/qemu-boot.sh`). So one driver serves both,
and only how it finds its controllers differs:

```
 usb-hid keyboard --+                          +-- wm, vt, keys: keyboard and pointer,
 usb-hid mouse -----+  usb (proto/usb.l0)      |   as from virtio-input
                    v                          |
                  xhci (dev): every controller, rings, ports, enumeration,
                    |         control transfers, IN endpoints polled
                    |  pci (proto/pci.l0), QEMU only
                  pcie (dev): the ECAM read, BARs put in the MMIO window
```

**It runs on QEMU** (`tests/e2e/usb`, `tests/usb.sh`): the keyboard
types in the shell and the mouse moves the pointer and clicks. L0's
runtime gives the regions it needs, QEMU's PCIe ECAM and MMIO window and
the Pi 5's RP1, and `frame_sync`, which `dma_sync` (call 293) offers
drivers, for the Pi's DMA, which does not see the CPU's caches; L0S
asked for them in [probes/usb](../probes/usb/REQUEST-pcie-rp1-cache.md).
Everything the stack decides is pure and tested on the host: `xhci`'s
`core.l0` is a state machine of one controller, driven in its tests
through usb-kbd's whole enumeration, a stall, an unplug and a full-speed
device, and its shell only carries out the writes, doorbells and
messages it says, cleaning each page of the controller's memory as it
writes it and cleaning and invalidating it before it reads it.

**The usb protocol** ([user/lib/proto/usb.l0](../user/lib/proto/usb.l0)),
which `xhci` serves as `usb`; a device is DEV, a number never given
twice, and numbers are decimal:

| Request | Answer |
|---|---|
| `listen` | `ok`; then to the reply port a notice `uat` of each device there and each plugged in later (DEV, vendor, product, speed), and `udt` of each unplugged |
| `devices` | a line `DEV VID PID SPEED` for each device |
| `descriptor DEV`, `config DEV` | its device descriptor's bytes, or its first configuration's, all of them, in hex |
| `claim DEV IFACE` | `ok`, the interface the asker's reply port's until it is gone; or `error: taken` |
| `control DEV TYPE REQ VALUE INDEX LEN [BYTE...]` | a control transfer: for IN, the bytes the device gave, in hex; for OUT, `ok` once the BYTEs, LEN of them, are sent; `error: stall` if the device refused it |
| `open DEV EP` | `ok`, and IN endpoint EP of an interface the asker claimed polled: each report a notice `uin` (DEV, EP, the bytes) to the reply port |
| `close DEV EP` | `ok` |

**The pci protocol** ([user/lib/proto/pci.l0](../user/lib/proto/pci.l0)),
which `pcie` serves as `pci`:

| Request | Answer |
|---|---|
| `devices` | a line for each function: `BDF VENDOR DEVICE CLASS IRQ` and each of its six BARs' base and size; IRQ is its INTx line's interrupt, 35 to 38, shared by every fourth slot, or its MSI once it has one |
| `find CLASS` | the lines of those of the 24-bit class CLASS, an xHCI's 787248 (0x0C0330) |
| `msi BDF` | the function given an MSI, the next of the GICv2m frame's 80 to 143, through its MSI capability or else the first entry of its MSI-X table, which `pcie` reaches through the function's BAR, and its INTx turned off: the interrupt, the same one if asked again, or `error: it can signal no MSI` (QEMU's `sdhci-pci`) or `error: no MSI left`. Only a function whose driver asks is given one, so `pcie` changes nothing of a device no driver drives |

`xhci` and `sdhci` ask for an MSI first, through `pci_interrupt`, and
bind their INTx line if refused. QEMU's `qemu-xhci` has MSI-X only, so it
is given entry 0 of its table, which serves interrupter 0. A board given
no network of its own, as `l0 boot` gives the e2e cases and
`tools/qemu-boot.sh` without `QEMU_NET`, gets QEMU's default network
card, a virtio-net-pci, at 00:01.0, which moves the other functions down
a slot, and so their INTx lines; the demo, on QEMU's user network, has
none.

`xhci` brings each device up alone: a USB 2 port is reset, 100 ms after
the device is seen (USB 2's debounce), until it is enabled; after 50 ms
of the reset's recovery, Enable Slot gives it a slot, Address Device its
address, and 10 ms more SET_ADDRESS's recovery; then
GET_DESCRIPTOR reads 8 bytes, whose packet size Evaluate Context gives the
default endpoint if it differs, then all 18, then 9 of the configuration
and all wTotalLength (2 KB at most), and SET_CONFIGURATION chooses the
first. Commands go one at a time, and a stalled default endpoint is
reset and sent past the transfer. Each ring is a DMA page, 127 TRBs a
pass and its buffer in the second half, and a TD never straddles the
Link TRB. A device costs 3 pages, an endpoint opened 1, from each
controller's 64. After each interrupt `xhci` writes ERDP with Event
Handler Busy cleared, even when it read no event, as Linux's `xhci_irq`
does: an event read before interrupt moderation set its IP leaves EHB
set with nothing new to read, and while EHB is set the controller
raises no interrupt. On the Pi 5, RP1's vectors for the two controllers
are routed level-triggered, as a DWC3's line is, and acknowledged in
RP1 after each interrupt and once as each is bound: one RP1 sent before
then, for what the firmware left pending, reached no one, and RP1 sent
none again until acknowledged. Either left both devices hung after
their ports' resets.

`usb-hid` uses HID's boot protocol only: a keyboard's 8-byte reports,
compared with the last to find what was pressed and let go (Linux's key
codes, then `keymap.l0`'s characters), and a mouse's buttons, movement
and wheel. A held key repeats in the driver, as USB keyboards leave to
the host. A report descriptor is never read, so a tablet, a wheel past
the boot report's, or a key outside the boot keyboard's 104 usages is
not seen; nor is anything behind a hub.

**On the Pi 5** (`xhci rp1`, which `pi5/etc/inittab` starts; see
[The Raspberry Pi 5](pi5.md#the-raspberry-pi-5)): the
firmware must leave RP1 set up (`pciex4_reset=0` in `config.txt`); the
DWC3s are put in host mode, their PHYs kept from suspending, as RP1's
device tree's quirks say; and a device reaches memory at the CPU's own
address (the firmware's PCIe controller maps PCI 0 to 64 GB onto RAM; the
0x10_0000_0000 of Linux's `dma-ranges` did not work for `gem` on a
board, and this is untried for USB). Both controllers take their
interrupts as RP1 MSI-X vectors 31 and 36 (interrupts 191 and 196). The first run
should check, on the serial line: that each controller's line comes
(HCIVERSION, ports, slots, scratchpads, contexts' size), that a key
plugged in gives a `device` line, and that those agree with Linux's view
of the same board, its `dma-ranges` and its RP1 node's quirks, and read
DWC3's GSNPSID (0xC120) to confirm the window reaches the controllers.

## Limits

- **USB has run on QEMU only** (see [USB](#usb)), not on a Pi 5, where
  L0S does not boot yet. Boot keyboards and mice only, on root ports
  only, no hubs; `xhci` takes interrupts on the virt board, which L0's
  runtime gives for PCIe since its roadmap 0106 (asked for in
  [probes/usb](../probes/usb/REQUEST-pcie-interrupts.md)), but polls RP1's
  controllers, whose interrupts it does not give yet; a control
  transfer moves 2 KB at most, an endpoint's report 2 KB; and each
  controller has 64 pages for its devices, about 3 a device and 1 an
  endpoint opened.
