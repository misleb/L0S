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

USB is how a keyboard, a mouse and a microphone reach a Raspberry Pi 5,
whose ports are on RP1, the southbridge behind PCIe: two Synopsys DWC3
controllers, each an xHCI in host mode. QEMU has no Pi 5, but its virt
board takes a `qemu-xhci` on PCIe, with a `usb-kbd` and a `usb-mouse` on
it (`QEMU_INPUT=usb` in `tools/qemu-boot.sh`), and its `usb-tablet`, as
the demo has, its `usb-audio`, a speaker, or a device of the host passed
through (`QEMU_USB`, which gives the controller 8 USB 2 ports, not
QEMU's 4, past which QEMU puts devices behind a hub of its own). So one
driver serves both, and only how it finds its controllers differs:

```
 usb-hid: keyboard and pointer, each on a port of its own --- wm, vt, keys,
                    |  usb (proto/usb.l0)                 as from virtio-input
 usb-audio: mic ----+-------------------------------------- rec
                    v
                  xhci (dev): every controller, rings, ports, enumeration,
                    |         control transfers, IN endpoints polled,
                    |         isochronous endpoints streamed
                    |  pci (proto/pci.l0), QEMU only
                  pcie (dev): the ECAM read, BARs put in the MMIO window
```

**It runs on QEMU** (`tests/e2e/usb`, `tests/usb.sh`): the keyboard
types in the shell, and the mouse and the tablet move the pointer and
click. L0's
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
| `open DEV EP` | `ok`, and IN endpoint EP of an interface the asker claimed polled: each report a notice `uin` (DEV, EP, the bytes) to the reply port. An isochronous endpoint, IN or OUT, of the setting the asker chose (`SET_INTERFACE`, a `control`) streams instead: a packet each interval, and a `uin` for each 10 packets, or as many of the endpoint's largest as fit a message, an IN one's bytes joined, an OUT one's empty, its packets having gone as silence ([Isochronous endpoints](#isochronous-endpoints)) |
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

One `usb-hid` serves both names, started with no argument: it claims
every boot keyboard and every boot mouse the usb server tells it of,
and QEMU's tablet,
and waits on three ports at once, a set (`port_set`): its own, where
the usb server's answers and notices come, every endpoint's reports
among them, each naming its device and endpoint, and the kernel's
alarms, which time a held key's repeats; and one each for `keyboard`
and `pointer`, where their clients ask to `listen`, told apart by the
port they came on.

`usb-hid` uses HID's boot protocol: a keyboard's 8-byte reports,
compared with the last to find what was pressed and let go (Linux's key
codes, then `keymap.l0`'s characters), and a mouse's buttons, movement
and wheel. A held key repeats in the driver, as USB keyboards leave to
the host. Beside them it takes QEMU's `usb-tablet`, a HID interface of
no boot subclass on a device of QEMU's vendor, 0627: its reports, laid
out as QEMU's report descriptor says, the buttons, x and y from 0 to
32767, and the wheel, are sent on `pointer` as a `PointerEvent`, after
a `WheelEvent` if the wheel turned, as `virtio-input`'s tablet sends
them. So the demo's window passes the host's pointer on with no grab,
the tablet taking the host's moves and the mouse left for QMP's
relative ones. A report descriptor is never read, so any other tablet,
a wheel past the boot report's, or a key outside the boot keyboard's
104 usages is not seen; nor is anything behind a hub.

### Isochronous endpoints

An isochronous endpoint, a microphone's or a speaker's, moves a packet
every interval, a frame (1 ms) at full speed, never retried. `xhci`
opens one as `open` asks (`core.l0`'s `iso_queued`): Configure Endpoint
gives it its context, its CErr 0 as xHCI requires; it takes three
pages, its ring's and two for its buffer, cut into slots of the
endpoint's largest packet (1024 bytes at most), 42 of a speaker's 192
and 26 of the Yeti Nano's 294; and every slot is a TD of one Isoch TRB,
Start Isoch ASAP, interrupting when done or, IN, short. Each packet's
event takes the oldest slot (`iso_event`): an IN packet's bytes are read
from it (`iso_want`), a packet missed (Missed Service) or failed is done
with none, and the slot is queued again at once; a ring found empty
(Ring Underrun or Overrun) takes no slot. Every 10 packets, or as many
of its largest as fit a message, its opener is told them, a `uin`. On
QEMU's `usb-audio` (`tests/e2e/usbaudio`) half a second of silence is
500 packets.

`usb-audio` (`user/sbin/usb-audio`) is the class driver of USB Audio
Class 1.0 devices, one process for every one: it reads each device's
configuration as its audio function (`format/uac.l0`): its terminals and
units, linked one to the next, and each streaming interface's setting
that moves sound, its isochronous endpoint, channels, bytes and bits a
sample, and rates; and names each stream by the terminal at its far end
(`microphone`, `speaker`, `headset`...), the input terminal a stream in
comes from, the output terminal a stream out reaches. It serves `mic`
([sound.md](sound.md#microphones)), and claims an interface only to use
it: a stream is set going by SET_INTERFACE to its setting, SET_CUR of
its endpoint's sampling frequency (a device that takes one rate may
refuse it, which is let be), and `open`; and stopped by `close` and
SET_INTERFACE to setting 0. It waits on two ports, a set: its own, for
the usb server's answers and notices and the kernel's alarms, and
`mic`'s.

**On the Pi 5** (`xhci rp1`, which `pi5/etc/inittab` starts; see
[The Raspberry Pi 5](pi5.md#the-raspberry-pi-5)): the
firmware must leave RP1 set up (`pciex4_reset=0` in `config.txt`); the
DWC3s are put in host mode, their PHYs kept from suspending, as RP1's
device tree's quirks say; and a device reaches memory at the CPU's own
address (the firmware's PCIe controller maps PCI 0 to 64 GB onto RAM; the
0x10_0000_0000 of Linux's `dma-ranges` did not work for `gem` on a
board). Both controllers take their interrupts as RP1 MSI-X vectors 31
and 36 (interrupts 191 and 196). A boot keyboard and a boot mouse on
its root ports work there: each controller's line comes on the serial
line, then a `device` line for each, then `usb-hid`'s, and the keys
reach the shell and the windows and the mouse moves the pointer.

## Limits

- **USB has run on QEMU and the Pi 5** (see [USB](#usb)): boot keyboards
  and mice, and on QEMU its `usb-tablet` and `usb-audio` speaker, only, on root ports
  only, no hubs. Isochronous endpoints have run on QEMU only: OUT to
  its `usb-audio`, and IN from a real microphone, the Yeti Nano passed
  through to it, but not on a Pi 5. An isochronous OUT endpoint sends only silence,
  and its packets are its largest, not each interval's share of the
  rate. A high-speed endpoint's extra packets a microframe are not
  used. USB Audio Class 2.0 is not read. A control
  transfer moves 2 KB at most, an endpoint's report 2 KB; and each
  controller has 64 pages for its devices, about 3 a device and 1 an
  endpoint opened.
