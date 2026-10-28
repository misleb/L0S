# The Raspberry Pi 5

```
make pi5-card     # build/pi5-card: l0.img, input.bin, config.txt, cmdline.txt, the device trees
```

L0S builds for the Pi 5 and has booted on one over the network, to the
shell on the debug UART, the compositor, and the Ethernet link at 1000
Mb/s with an address from DHCP. Seventeen reboots in a row
(`tools/pi5-boot --reboot`) and ten boots from power in a row each
reached all of them, on all four CPUs, with no memory corrupted and no
power lost. `make pi5-card`
does three things:
- builds the kernel with `--target pi5`, as `build/kernel-pi5.img`
- builds the initramfs from `pi5/etc` and the same programs as QEMU's,
  as `build/pi5.cpio`, with the boot files in `/boot` too (below)
- puts the board's device trees in `build/pi5-card` (see [Over the
  network](#over-the-network) for where they come from), and has `l0
  card` write the boot partition's other files beside them

The firmware itself is in the Pi 5's EEPROM, so these are all the files
a card's boot partition needs: copy them onto a FAT32 one, or onto the
boot partition of a card Raspberry Pi OS made. A card holding only them,
partitioned by L0S, has booted the board (see "A card that boots a
system volume"). `l0 card`'s `config.txt` loads the image
at 0x80000 and the initramfs at 0x10000000, leaves RP1 set up
(`pciex4_reset=0`) and forces HDMI's hotplug.

**Making a card from a running L0S.** The Pi 5's initramfs holds its own
boot files in `/boot`, `l0.img`, `config.txt` and `cmdline.txt` as `l0
card` writes them and the two device trees, so a running system, from its initramfs or a system
volume, can make a card boot it, with no other computer, on any disk it
can write ([FAT32 volumes](fat32.md#fat32-volumes)):

```
l0s> partition disk1 1048576 2048
0199c82c-c07b-7123-8456-0123456789ab
l0s> mkfs 0199c82c-c07b-7123-8456-0123456789ab BOOT fat32
l0s> run install --boot BOOT
install: 5 boot files and input.bin, an initramfs of 87 files, written to /Volumes/BOOT
```

or Disks' Create Partition... and Format... with FAT32 chosen. `install
--boot VOLUME [FROM]` copies FROM's files, `/boot` unless given, onto the
volume, and writes `input.bin` beside them, an initramfs of every
directory and file of `/` but `/Volumes`, a file at a time, so the card
boots the system running now, `/boot` and all. The firmware is in the
Pi 5's EEPROM, but it loads the board's device tree from the card,
`bcm2712-rpi-5-b.dtb` (C1) or `bcm2712d0-rpi-5-b.dtb` (D0), which
`/boot` holds with the rest. A FROM without them is copied all the
same, and `install` then says the volume has no device tree, to be
copied there from Raspberry Pi OS's boot partition. Onto a card
Raspberry Pi OS made, `run install --boot bootfs` writes over its
device trees with `/boot`'s; and its `config.txt` or
`cmdline.txt` can be changed in place with `write`, as on any volume.

**A card that boots a system volume.** `install --boot VOLUME [FROM]
--root ROOT` makes the card's `cmdline.txt` say `root=` and ROOT's
UUID, after its other arguments, which it keeps, replacing any `root=`
it had, so that `boot` makes ROOT `/` (see [Booting from a
volume](boot.md#booting-from-a-volume)). ROOT is a volume `install
ROOT` filled, on the same card or another disk; it is checked before
anything is written. On a card Raspberry Pi OS made, its ext4 `rootfs`
can be made L0FS first, by Disks' Format... or `mkfs` (see [FAT32
volumes](fat32.md#fat32-volumes)):

```
l0s> mkfs 12345678-0000-0000-0000-000000000002 root
l0s> run install root
l0s> run install --boot bootfs --root root
install: 5 boot files and input.bin, an initramfs of 87 files, written to /Volumes/bootfs
install: /Volumes/bootfs/cmdline.txt boots /Volumes/root, root=12345678-0000-0000-0000-000000000002
```

A card made so has booted the board, its bootloader reading
`config.txt`, `input.bin`, the device tree, `cmdline.txt` and `l0.img`
from `bootfs`, and `boot` making `System` `/`. So has one with nothing
of Raspberry Pi OS's: erased by Format Disk..., given L0S's GPT, a
FAT32 `bootfs` and an L0FS `System`, and filled by `install System` and
`install --boot bootfs --root System`. The bootloader finds `bootfs` by
its partition type, looks for `overlays/` and goes on without it.

**Over the network.** The Pi 5 keeps its firmware in its EEPROM and can
fetch the rest by TFTP:

```
make pi5-netboot [PI5_BOOT=DIR] [PI5_TFTP_PREFIX=SERIAL]   # build/pi5-tftp
```

This copies the card's files and the board's device trees into
`build/pi5-tftp`, the root a TFTP server serves. The device trees are
`bcm2712-rpi-5-b.dtb` for the C1 stepping and `bcm2712d0-rpi-5-b.dtb`
for D0. They are Raspberry Pi's, built from Linux's sources (GPL-2.0),
so the build fetches them once into `build/pi5-dtb`, from
raspberrypi/firmware's `boot/` at the commit the Makefile pins
(`PI5_DTB_COMMIT`), and keeps each only if its SHA-256 is the one
`pi5/dtb.sha256` names, so every build has the same ones. `PI5_BOOT`
names another directory holding both instead, as Raspberry Pi OS's
boot partition, and nothing is fetched. The Pi's bootloader asks in a directory named for
its serial number, 8 hex digits, which `PI5_TFTP_PREFIX` makes, unless
its EEPROM says `TFTP_PREFIX=1` with no `TFTP_PREFIX_STR`.

The board's EEPROM must try the network: `BOOT_ORDER=0xf21`, from
`rpi-eeprom-config --edit` on Raspberry Pi OS, or from L0S itself with
`eeprom update` (see [The bootloader's
configuration](#the-bootloaders-configuration)), tries the SD card, then
the network. The network's DHCP server must name the TFTP server, as a
proxy can for an existing network; with dnsmasq that is
`dhcp-range=192.168.1.0,proxy`, `pxe-service=0,"Raspberry Pi Boot"`,
`enable-tftp` and `tftp-root=build/pi5-tftp`.

`tools/pi5-boot` is the cycle for a board that network boots, with a
DHCP server already naming this machine (option 66): it runs `make
pi5-netboot`, with `PI5_BOOT` if given, checks that a dnsmasq serves `build/pi5-tftp` (printing the `sudo
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
| `boot` | pid 1, then `/etc/system`: `sh` on the console, `font`, `wm`, a Terminal |
| `uart` | the debug UART, the 3-pin header between the HDMI ports, found as QEMU's is found, at whatever rate the firmware set, which `uart` never changes, as `console`; interrupt 153 |
| `xhci rp1`, `usb-hid keyboard`, `usb-hid mouse` | RP1's two USB controllers, a keyboard and a mouse (see [USB](devices.md#usb)) |
| `hvs` | HDMI0 (see [The display on the Raspberry Pi 5](display.md#the-display-on-the-raspberry-pi-5)), brought up a stage at a time by its argument (`probe`, `list`, `iommu`, or none to serve `display`; `mode` and `hdmi` beside them), at the monitor's preferred mode, which it sets itself (`hdmi=boot` keeps the firmware's 1920×1080, `hdmi=30` asks for 30 Hz). With no monitor on HDMI0 at boot it says so and exits, and `wm` waits for a display. `make pi5-shell` leaves it out |
| `hdmi-audio` | sound on HDMI0, served as `audio`, once `hvs` serves `display` (see [Sound on the Raspberry Pi 5](sound.md#sound-on-the-raspberry-pi-5)); it plays `/etc/chime.wav` as it starts, unless the boot argument `chime=off`, and `play /etc/chime.wav` tries it again. `make pi5-shell` leaves it out too |
| `fs ram` | a volume in memory, `/Volumes/tmp`, registered as `tmpfs`, which keeps nothing over a power cut |
| `sdhci pi5`, `fs` | the microSD card in the slot, through the BCM2712's own SD host controller, `sdio1`, at 0x1000FFF000, interrupt 305 (see [The disk](storage.md#the-disk)), served as a disk; `fs` mounts its volumes, a FAT32 boot partition among them (see [FAT32 volumes](fat32.md#fat32-volumes)). With no card in the slot `sdhci` says so and `fs` finds no disk, and both exit |
| `rtc clock` | the time, from the RTC in the Pi's power controller. Only the firmware reaches it, so `rtc` asks with the firmware's property interface (`GET_RTC_REG`, as Linux's rtc-rpi does) through the VideoCore mailbox, a region, from a DMA page below 4 GB (`firmware.l0` over `mailbox.l0`). It keeps time over a power cut only with a battery on the RTC connector |
| `eeprom` | not started, but flagged `dev` for the mailbox, so that the shell can run it: the bootloader's configuration, read and changed (see [The bootloader's configuration](#the-bootloaders-configuration)) |
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
  and each step of its stage, the last of them before any hang; then
  the screen: black from the firmware's handover, then the wallpaper,
  `branding/wallpaper-dark.svg`, as `hvs` serves, before `wm`'s desktop
  comes over the same image, with nothing black between
- `hdmi-audio`'s line, then 3 s later `playing the chime`, the chord
  heard as it starts, at about the time the desktop comes up, with no
  `no chime:` warning (`chime=off` silences it), and that `play
  /etc/chime.wav` is heard again
- `sdhci`'s lines: `sdio1`'s registers as the firmware left them, then
  the card, its size and its interrupt; and `fs`'s, a line for each
  volume it mounts
- `gem`'s line, its link line once a cable is in, and `inet`'s lease
  (see [The network on the Raspberry Pi 5](network.md#the-network-on-the-raspberry-pi-5))

## The bootloader's configuration

The Pi 5's bootloader keeps its configuration, `BOOT_ORDER`,
`TFTP_PREFIX` and the rest, as the file `bootconf.txt` inside its own
image in the EEPROM. `eeprom` (`/sbin/eeprom`, flagged `dev` in
`pi5/etc/inittab` for the mailbox) reads and changes it:

```
eeprom                                         # the configuration running now
eeprom version                                 # the bootloader's version
eeprom show IMAGE                              # the configuration in a pieeprom.bin
eeprom update IMAGE CONFIG /Volumes/bootfs     # IMAGE with CONFIG, to flash next boot
```

`eeprom` and `eeprom version` ask the firmware's own command line,
vcgencmd's `bootloader_config` and `bootloader_version`, through the
VideoCore mailbox (`GET_GENCMD_RESULT`, 0x00030080, with vcgencmd's 1024
bytes of room), which a board has answered. With no mailbox, as on
QEMU, `eeprom` says so and fails.

L0S never writes the EEPROM itself. `eeprom update` takes a release
image, a `pieeprom.bin` from Raspberry Pi's rpi-eeprom (`firmware-2712/`)
copied onto a volume, puts the file CONFIG in place of its
`bootconf.txt` as `rpi-eeprom-config` does (`image.l0`: the image's
sections walked by their big-endian magic and length; the first
`bootconf.txt` in the first partition, from 64 KiB, rewritten, with room
up to the next section that is not padding; then 0xff and, unless it is
the last section, a padding section over the rest of that room), and
writes `pieeprom.upd`, the new image, and
`pieeprom.sig`, its SHA-256 in hex and a `ts:` line, the update's time,
as `rpi-eeprom-digest` does, into the directory given, the card's boot
partition. As the board next boots from that partition, or from a TFTP
root the two files are put in for a board that boots over the network,
the bootloader checks the image against the signature and flashes
itself (`SELF-UPDATE`, `BOOT-EEPROM: UPDATED` on the debug UART), then
restarts. It takes an
update only if its time is later than the last one's, so the time
`eeprom update` gives is the clock's or, if that is earlier, as on a
board whose RTC has no battery and starts in 1970, the last update's
(bootloader_version's `update-time`) and a second; with neither it
refuses. An update whose time is not later is skipped, so one left in
place is flashed only once. On a Pi 5, `eeprom update` wrote the same
files as `rpi-eeprom-config` and `rpi-eeprom-digest` for the same image,
configuration and time; flashed over the network, they gave the
configuration it was given, which `eeprom` then printed. An image must be 512 KiB or 2 MiB,
and a configuration at most 4076 bytes and no larger than its room;
anything else is refused before a file is written. On the host, for the
release image `pieeprom-2026-09-25.bin` and configurations of 0 to 3406
bytes, `image.l0` wrote the same `pieeprom.upd` and `pieeprom.sig`, byte
for byte, as `rpi-eeprom-config --config` and `rpi-eeprom-digest`, and
the image's own configuration written back gave the image unchanged.

## Limits

- **The Raspberry Pi 5 reaches its RTC only through the firmware**, and
  boots only over the network or from a card `l0 card` or `install
  --boot` wrote. Its
  kernel's heap is sized to `PI5_RAM_GB`, 2 by default, and records the
  pages that much RAM has, or about 13 GB on a 16 GB board. On a board
  with more RAM than the kernel was built for, processes are refused
  pages once its heap is down to its reserve (see
  [The kernel](kernel.md)), so the RAM past what the heap records goes
  unused.
- **The bootloader's configuration changes only through its own
  update**: `eeprom` cannot read the EEPROM's image, only the
  configuration the firmware reports, so an update starts from a
  release image copied onto a volume, not from what is flashed, and is
  flashed only on a boot from the partition it was written to, or
  from a TFTP root it was copied to off the board.
