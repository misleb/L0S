# The Raspberry Pi 5

```
make pi5-card     # build/pi5-card: l0.img, input.bin, config.txt, cmdline.txt
```

L0S builds for the Pi 5 and has booted on one over the network, to the
shell on the debug UART, the compositor, and the Ethernet link at 1000
Mb/s with an address from DHCP. Seventeen reboots in a row
(`tools/pi5-boot --reboot`) each reached all of them, though boots from
power have not been tried as often, and some earlier ones corrupted
memory (the display's IOMMU was the suspect). `make pi5-card`
does three things:
- builds the kernel with `--target pi5`, as `build/kernel-pi5.img`
- builds the initramfs from `pi5/etc` and the same programs as QEMU's,
  as `build/pi5.cpio`, with the boot files in `/boot` too (below)
- has `l0 card` write the boot partition's files into `build/pi5-card`

Copy them onto the boot partition of an SD card that holds Raspberry Pi's
firmware, from Raspberry Pi OS. `l0 card`'s `config.txt` loads the image
at 0x80000 and the initramfs at 0x10000000, leaves RP1 set up
(`pciex4_reset=0`) and forces HDMI's hotplug.

**Making a card from a running L0S.** The Pi 5's initramfs holds its own
boot files in `/boot`, `l0.img`, `config.txt` and `cmdline.txt` as `l0
card` writes them, so a running system, from its initramfs or a system
volume, can make a card boot it, with no other computer, on any disk it
can write ([FAT32 volumes](fat32.md#fat32-volumes)):

```
l0s> partition disk1 1048576 2048
0199c82c-c07b-7123-8456-0123456789ab
l0s> mkfs 0199c82c-c07b-7123-8456-0123456789ab BOOT fat32
l0s> run install --boot BOOT
install: 3 boot files and input.bin, an initramfs of 70 files, written to /Volumes/BOOT
install: /Volumes/BOOT: no bcm2712-rpi-5-b.dtb; copy the Pi 5's device trees there from Raspberry Pi OS's boot partition
```

or Disks' Create Partition... and Format... with FAT32 chosen. `install
--boot VOLUME [FROM]` copies FROM's files, `/boot` unless given, onto the
volume, and writes `input.bin` beside them, an initramfs of every
directory and file of `/` but `/Volumes`, a file at a time, so the card
boots the system running now, `/boot` and all. The firmware is in the
Pi 5's EEPROM, but it loads the board's device tree from the card, so
`bcm2712-rpi-5-b.dtb` (C1) and `bcm2712d0-rpi-5-b.dtb` (D0), Raspberry
Pi's, must be copied there too, as `install` says when they are not.
Onto a card Raspberry Pi OS made, whose `bootfs` on its MBR holds them
already, `run install --boot bootfs` is all; and its `config.txt` or
`cmdline.txt` can be changed in place with `write`, as on any volume.

**Over the network.** The Pi 5 keeps its firmware in its EEPROM and can
fetch the rest by TFTP:

```
make pi5-netboot PI5_BOOT=DIR [PI5_TFTP_PREFIX=SERIAL]   # build/pi5-tftp
```

This copies the card's files and the board's device trees into
`build/pi5-tftp`, the root a TFTP server serves. The device trees are
`bcm2712-rpi-5-b.dtb` for the C1 stepping and `bcm2712d0-rpi-5-b.dtb`
for D0. They are Raspberry Pi's, so `PI5_BOOT` names a directory that
holds them: Raspberry Pi OS's boot partition, or `boot/` of
raspberrypi/firmware. The Pi's bootloader asks in a directory named for
its serial number, 8 hex digits, which `PI5_TFTP_PREFIX` makes, unless
its EEPROM says `TFTP_PREFIX=1` with no `TFTP_PREFIX_STR`.

The board's EEPROM must try the network: `BOOT_ORDER=0xf21`, from
`rpi-eeprom-config --edit` on Raspberry Pi OS, tries the SD card, then
the network. The network's DHCP server must name the TFTP server, as a
proxy can for an existing network; with dnsmasq that is
`dhcp-range=192.168.1.0,proxy`, `pxe-service=0,"Raspberry Pi Boot"`,
`enable-tftp` and `tftp-root=build/pi5-tftp`.

`tools/pi5-boot` is the cycle for a board that network boots, with a
DHCP server already naming this machine (option 66): it fetches the
device trees once into `build/pi5-dtb`, runs `make pi5-netboot` with
them, checks that a dnsmasq serves `build/pi5-tftp` (printing the `sudo
dnsmasq` command to run once if not, as port 69 needs root), and reads
the debug UART, `/dev/ttyUSB0` or `PI5_SERIAL`, into
`build/pi5-serial.log` while the board is power-cycled. `--until REGEX`
stops at a line, as `--until 'l0s>'` at the shell's prompt, `--wait`
after so many seconds, `--no-build` serves what was built, and
`--console` opens the line in picocom to type to the shell. `PI5_ARGS`
gives the kernel's boot arguments, as `PI5_ARGS=debug`, to both.
`--reboot` types `reboot` at the shell of the L0S already running on
the board, so the board restarts (L0's `board_reset`, PSCI
`SYSTEM_RESET`) and its bootloader fetches the new build, with nobody at
the board, as long as that boot's console still answers; it says when
the kernel's `l0s: restarting the board` line did not come, and the
board must be power-cycled as before. `exit` at the shell halts the
board instead (PSCI `SYSTEM_OFF`, which the bootloader shows as
`Halt:`), and a board that hangs needs its power cycled
([probes/driver](../probes/driver/REQUEST-pi5-reboot.md) asked for the
reset, landed in L0). Once booted, L0S has its
own driver for the same port, `gem` (see [The network on the Raspberry
Pi 5](network.md#the-network-on-the-raspberry-pi-5)).

The kernel is the same source as QEMU's. Only the board under it is L0's
other host: the GIC-400, the generic timer at 54 MHz, and the debug UART
as the kernel's standard output and error. The kernel keeps about 285
bytes of record for each page it gives, and every page past its heap
and stack is for processes, so its heap is sized to the board's RAM,
`PI5_RAM_GB` (2 by default, the least a Pi 5 has): 64 MB and 72 for
each GB, at most 1,008 MB, which `PI5_KERNEL_HEAP_MB` overrides. A 2 GB
board's kernel has 208 MB, leaving about 1.8 GB to processes, as QEMU
leaves at `-m 2G`; a 16 GB board's has 1,008 MB, enough for about 13 GB
of pages given at once (see [Limits](kernel.md#limits)). Build with
`PI5_RAM_GB=N` for a board of more than 2 GB.

`pi5/etc/inittab` starts what the board has a driver for:

| Program | What it does there |
|---|---|
| `boot` | pid 1, then `/etc/system`: `sh` on the console, `wm`, a Terminal |
| `uart` | the debug UART, the 3-pin header between the HDMI ports, found as QEMU's is found, at whatever rate the firmware set, which `uart` never changes, as `console`; interrupt 153 |
| `xhci rp1`, `usb-hid keyboard`, `usb-hid mouse` | RP1's two USB controllers, a keyboard and a mouse (see [USB](devices.md#usb)) |
| `hvs` | HDMI0 (see [The display on the Raspberry Pi 5](display.md#the-display-on-the-raspberry-pi-5)), brought up a stage at a time by its argument (`probe`, `list`, `iommu`, or none to serve `display`; `mode` and `hdmi` beside them), at the monitor's preferred mode, which it sets itself (`hdmi=boot` keeps the firmware's 1920×1080, `hdmi=30` asks for 30 Hz). With no monitor on HDMI0 at boot it says so and exits, and `wm` waits for a display. `make pi5-shell` leaves it out |
| `hdmi-audio` | sound on HDMI0, served as `audio`, once `hvs` serves `display` (see [Sound on the Raspberry Pi 5](sound.md#sound-on-the-raspberry-pi-5)); `play /etc/chime.wav` tries it. `make pi5-shell` leaves it out too |
| `fs ram` | a volume in memory, `/Volumes/tmp`, since L0 gives no region over the Pi's SD controller |
| `rtc clock` | the time, from the RTC in the Pi's power controller. Only the firmware reaches it, so `rtc` asks with the firmware's property interface (`GET_RTC_REG`, as Linux's rtc-rpi does) through the VideoCore mailbox, a region, from a DMA page below 4 GB (`firmware.l0` over `mailbox.l0`). It keeps time over a power cut only with a battery on the RTC connector |
| `gem`, `inet dhcp` | the Ethernet port, RP1's GEM, serving `nic`, and the IPv4 stack over it at the address DHCP gives (see [The network on the Raspberry Pi 5](network.md#the-network-on-the-raspberry-pi-5)) |

Nothing else of the demo's has a device here: no virtio, so no `random`
for `inet`'s TCP, no PCIe for `pcie virt`, and no `sdhci pci`. The first
boot should check these, on the debug UART (`dmesg` repeats them):
- the kernel's banner: `aarch64`, the pages free, and the initramfs
- `uart`'s line, and that what is typed reaches `sh`
- `rtc`'s line and its time. The mailbox's message is given the page's
  own address, as the BCM2712's firmware node's identity `dma-ranges`
  says, not the Pi 4's 0xC0000000 above it: unconfirmed
- `xhci`'s lines and `usb-hid`'s (see [USB](devices.md#usb))
- `hvs`'s lines: how many displays the firmware brought up, the clocks,
  and each step of its stage, the last of them before any hang
- `hdmi-audio`'s line, and that `play /etc/chime.wav` is heard
- `gem`'s line, its link line once a cable is in, and `inet`'s lease
  (see [The network on the Raspberry Pi 5](network.md#the-network-on-the-raspberry-pi-5))

## Limits

- **L0S on a Raspberry Pi 5 is not yet stable** (see
  [The Raspberry Pi 5](#the-raspberry-pi-5)): `make pi5-card` builds its
  card, and `make pi5-netboot` a TFTP root, which has booted it to a
  shell and the compositor, though some boots corrupt memory or lose
  power. It has no disk, and reaches its RTC only through the
  firmware. Its
  kernel's heap is sized to `PI5_RAM_GB`, 2 by default, and records the
  pages that much RAM has, or about 13 GB on a 16 GB board. Nothing yet
  stops processes taking more on a board with more RAM than the kernel
  was built for, and the kernel would then run out of heap.
