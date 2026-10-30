# Storage

## The disk

A disk is served by its driver under a name of its own, `disk0`,
`disk1` and so on: the first number free when the driver registers it,
so the first disk found is `disk0`. In the demo `virtio-blk` serves its
disk as `disk0`, and `sdhci` the SD card as `disk1`. A driver of
several disks registers each one's name, and may do so on one port, since
every request names its disk first. Once a driver has registered a disk,
it tells `fs`, which takes it on (`attach`, under
[Volumes](#volumes)).

`virtio-blk` ([user/sbin/virtio-blk](../user/sbin/virtio-blk/virtio-blk.l0)) drives
QEMU's virtio-blk: the demo's `build/disk.img`, 2048 sectors of 512
bytes. It serves raw sectors to clients, `fs` above all, through **the
disk protocol** ([user/lib/proto/disk.l0](../user/lib/proto/disk.l0)). As with the display, no sector
travels in a message. A client shares a buffer of its own pages with the
driver (`shm_share`), and the device reads or writes those pages itself,
by DMA, from a chain of descriptors the driver builds over them. The
driver makes one request of the device at a time, and waits for the
device's interrupt, which the kernel sends to a port of the driver's
own, so that the requests waiting on its other port stay there. A
request that takes more than 30 seconds fails, and so does every later
one, since the device may still be working on it: the disk has stopped
answering. It takes two of the device's features, if it offers them: `VIRTIO_BLK_F_FLUSH`,
so that `flush` empties the disk's write cache, and `VIRTIO_BLK_F_RO`,
so that it knows a disk is read-only (QEMU's `readonly=on`) and refuses
its writes itself.

| Request | Does |
|---|---|
| `NAME info` | `disk SECTORS 512`: the disk's size in sectors, and a sector's in bytes; `disk SECTORS 512 ro` for a read-only disk |
| `NAME read SECTOR COUNT VA` | COUNT sectors from SECTOR, 1 to 128, put into the client's pages shared with the driver at VA |
| `NAME write SECTOR COUNT VA` | the same, taken from those pages and written to the disk |
| `NAME flush` | `ok` once every write answered before it is on the disk itself, not only in its cache; at once for a disk with no cache, which writes through |

NAME is the disk's, `disk0` say. The reply is `ok`, `disk SECTORS 512`
for `info`, or `error: WHY`: no such disk, a count out of range, sectors
past the disk's end, a write to a read-only disk, a buffer not shared
with the driver, or the device's own failure.

`run disk list` lists the disks there are; `run disk [NAME] info`, `run
disk [NAME] read SECTOR [COUNT]` (shown as `hexdump -C` shows bytes),
`run disk [NAME] write SECTOR WORDS...` (one sector) and `run disk
[NAME] zero SECTOR [COUNT]` (COUNT sectors of zeros in one request) use
one from a shell, `disk0` unless NAME is given. Sectors 1 to 7 of a disk `tools/mkdisk` makes
belong to no volume, so a `disk write` there harms no file.

**The SD card.** `sdhci` ([user/sbin/sdhci](../user/sbin/sdhci/sdhci.l0))
drives SD cards behind SD Host Controllers: with `pci`, those `pcie`
finds; with `pi5`, the Raspberry Pi 5's microSD slot, behind the
BCM2712's own `sdio1` at 0x1000FFF000, whose card detect it points at
the slot (its `cfg` block's pin select, as Linux's `sdhci-brcmstb`
does), whose base clock is 200 MHz should its capabilities not say,
and whose interrupt is 305; it has read and written a 64 GB card
there. The QEMU one is `sdhci-pci` (the demo's `build/sd.img`, a blank 256 MB, made once and
kept; `QEMU_SD` in `tools/qemu-boot.sh`). It brings each card up as the
SD specifications say, at 400 kHz then its default speed, 25 MHz: CMD0,
CMD8, ACMD41 until the card is ready, CMD2, CMD3 for its address, CMD9,
whose CSD gives its size, of either version, and CMD7 to select it
(`sd.l0`). It moves blocks through the controller's buffer a word at a
time, between the card and the client's pages, which it opens as a
region for each request: no DMA, so it needs neither the device's view
of memory nor, on the Raspberry Pi 5, the cache's cleaning. A standard
card is addressed by byte, a high-capacity one by block, and many blocks
go in one command, ended by Auto CMD12. It serves every card it finds
on one port, each under its own name. A command or a block not done at
once is waited for by the controller's interrupt, an MSI if `pcie` can
give it one and otherwise its INTx line (QEMU's `sdhci-pci` has no
MSI), bound to a port of the slot's own so that requests queue on the
other; it turns the controller's interrupt signals on only while it
waits. A slot with no interrupt, or one another driver has bound, is
polled, and so is every card while it is brought up.

## Volumes

A disk holds **volumes**, each a partition of it with a file system of
L0S's own, L0FS ([user/lib/format/l0fs.l0](../user/lib/format/l0fs.l0)), or FAT32 (see
[FAT32 volumes](fat32.md#fat32-volumes)), and a label.
`fs` mounts each at `/Volumes/LABEL`, as macOS mounts disks, and the
kernel sends every call on a file there to it, so every program reads
and writes them with the ordinary `open_in`, `open_out` and the rest:
`run cat /Volumes/data/notes` works as `run cat /etc/motd` does.

**`fs` serves in turn** ([user/sbin/fs/turns.l0](../user/sbin/fs/turns.l0)).
Each time round it takes every message waiting on its ports, `fs`'s and,
started `fs ram`, `tmpfs`'s, a set of ports, with `port_try_receive_set`
until none is, oldest first, into a list of its own (waiting with
`port_receive_set` when there is none), and serves
the notices from pid 0 first, the kernel's exit and window notices, so
that one never waits behind requests or finds the port's queue full.
An exit drops the requests its pid still has waiting. Then it serves
the requests, one each time round, by pid in turn, by bytes (deficit
round robin): each pid with requests waiting is given a budget of a run
of 64 KB a turn and is served its requests, in the order they came, while
their costs fit what it has left, so that a client moving 64 KB a
request and one asking `stat`s take turns, and a `stat` behind another
pid's writes waits for one of them. A request's cost is read from its
message in place: the N of `readw H N`, `writew H N` and `read H N`, a
`write H BYTES`'s length, 16 runs for one of a whole volume or disk
(`format`, `mkfs`, `partition`, `erase`, `attach`, `rescan`), so that other pids'
requests are served before it, and 512 bytes for any other. A pid's
own requests are never reordered. A pid has at most 8 requests
waiting: one more is answered at once, -5 and `too many requests
waiting from this process`, which the kernel gives the call as its -5
and `fs_ask` as its reply, and is not kept; a `close` is never
refused, since the kernel drops its stream whatever the answer. A
client that waits for each answer, as the kernel's file calls and
`fs_ask` do, has one waiting at most, so only one that sends without
waiting meets the bound.

The disk, as [tools/mkdisk](../tools/mkdisk) makes it with
[tools/mkfs](../tools/mkfs/mkfs.l0) (`mkfs OUT SECTORS MS
LABEL:START:COUNT[:ARCHIVE[:UUID]]...`, a host program, built into
`build/mkfs`; MS is the Unix time in milliseconds, which mkdisk gives it
from `date`, since a host program has no clock that is a date). An
ARCHIVE, a newc cpio such as `build/initramfs.cpio`, fills its volume,
its directories, files, and which are programs; a UUID is its
partition's, in place of one made from MS; mkfs says each volume's
label and UUID. `tools/mkdisk OUT SECTORS SPEC...` makes such a disk,
and with only OUT this one:

| Sectors | What |
|---|---|
| 0 | a protective MBR, one partition of type `EE` over the whole disk, so that what knows only MBRs leaves it be |
| 1–33 | the GPT: its header, and 128 entries of 128 bytes (below) |
| 34–39 | nothing |
| 40–1535 | the volume `data`, 1496 sectors: 186 clusters of data, 744 KB, the root directory's one of them |
| 1536–2014 | the volume `scratch`, 479 sectors: 58 clusters, 232 KB |
| 2015–2047 | the GPT's backup: its entries, and its header in the last sector |

A `build/disk.img` made before the disk had a GPT has an MBR, which
nothing reads now: `fs` finds no table on it. `rm build/disk.img`, or
`make clean`, and the next `make demo` makes a disk of GPT.

**Partitions.** A disk's partitions are in a **GPT**, UEFI's GUID partition table
([user/lib/format/gpt.l0](../user/lib/format/gpt.l0)), so each has a **UUID** of its
own, which it is given when it is made and keeps: a request names a
partition by it, not by where it is, which another partition made or
removed could change, nor by the label of its volume, which a format
could. The disk has one too. An entry holds the partition's type's
UUID, its own, its first and last sectors, and a name of 36 characters,
its volume's label for one `mkfs` or `tools/mkfs` made. L0FS's type is
`4c304653-0001-4000-8000-4c30534c3046`, `L0FS` in its first field, and
in an MBR, which only a disk made elsewhere has, `7F` (see [FAT32
volumes](fat32.md#fat32-volumes)). The
header and its entries are checked by CRC-32
([user/lib/format/crc32.l0](../user/lib/format/crc32.l0)), and copied in the disk's last
33 sectors, which `fs` reads if the first copy is bad; it writes both,
and never over a table it found bad.

The UUIDs are of **version 7** ([user/lib/format/uuid.l0](../user/lib/format/uuid.l0),
RFC 9562): the time in Unix milliseconds in their first 48 bits, so they
sort in the order they were made, then noise. `fs` asks `rtc clock` the
time, and the board's clock keeps this machine's local time, not UTC
(see [The desktop](desktop.md#the-desktop)); with no clock, the time is 0. The
noise is `random`'s, the entropy device's bytes (see
[Randomness](devices.md#randomness)); on a board without the device it is
splitmix64's, seeded from the clock, which tells apart UUIDs made apart
but can be guessed.

```
l0s> partition 400
01a1474e-dca3-7a16-8dac-ed4ff93e46f2
l0s> mkfs 01a1474e-dca3-7a16-8dac-ed4ff93e46f2 made
l0s> ls /Volumes
  data/
  made/
  scratch/
```

On the demo's disk, whose only room is the 6 sectors before data, that
`partition 400` is refused; [tests/partitions.sh](../tests/partitions.sh)'s
disk has room.

A volume, its sectors counted from its partition's first, in clusters of
8 sectors, 4 KB:

| Where | What |
|---|---|
| sector 0 | the superblock: `L0FS`, version 2, the label (1 to 15 letters, digits, `-`, `_`) in 16 bytes from 8, then u32s from 24: its sectors, clusters, the table's first sector and sectors, the first cluster of data, and the root directory's first cluster, the same |
| sector 1 on | the cluster table, a u16 a cluster, a sector for each 256: 0 free, `FFFF` a chain's last, `FFFE` the metadata's, else the next cluster, so each file and each directory is a chain, as in FAT |
| from the first cluster after these | the root directory's first cluster, then the files' data and the other directories' clusters |

A **directory** is a chain of clusters like a file's, 64 entries of 64
bytes each: a name of 1 to 55 printable bytes with no space or `/`, nor
`.` or `..`, NUL padded in 56; the size at 56; the first cluster at 60
(0 for an empty file); and flags at 62: 1 in use, 2 a directory, 4 a
program. A directory with every entry in use grows by a cluster, and
never shrinks. A path is a walk from the root, a directory at a time.
A volume of version 1, whose one directory was flat, is not read: `fs`
says so (`L0FS version 1, not 2`), and `mkfs` on its partition makes it
anew.

The superblock and table, rounded up to whole clusters, are the
metadata: for these volumes cluster 0, one 8-sector read. A volume holds
at most 65534 clusters, so 256 MB. `fs` checks all of it, the layout
against the size, every mark of the table, and every directory from the
root down, each entry's name and every file's chain against its size,
and refuses a directory met twice, before it serves a volume, so a
damaged disk is refused rather than followed.

## Limits

- **The SD card has run on QEMU and the Pi 5**, and slowly: `sdhci`
  moves every word through the controller's buffer, on one data line at
  25 MHz, and polls while it brings a card up. No DMA, no 4-bit bus, no
  high-speed modes, and a card is found only at boot. At most 16 disks, `disk0` to `disk15`, are named; a
  disk's name is its driver's place in the order they register, so a
  driver that registers late gets a later name.
- **The volumes are small and simple** (see [Volumes](#volumes)). Their
  directories hold names of at most 55 bytes with no spaces, and a
  program mark, but no other permissions, owners or times; a directory
  never shrinks; a volume has at most 65534 clusters of 4 KB; and a disk
  at most the GPT's 128. FAT32 ([FAT32 volumes](fat32.md#fat32-volumes)) is read
  only with 512-byte sectors, clusters of up to 32 KB and at most 2M of
  them (64 GB of 32 KB clusters), the whole FAT and every directory held
  in `fs`'s memory, and no smaller than its 65525 clusters, 33 MB; not
  FAT12, FAT16 or exFAT, nor a disk that is one FAT volume with no
  table; a name with a space, or past ASCII, is kept but unreachable,
  since a path cannot hold one; it holds no programs; and an MBR is
  read, its extended partitions not followed, and written only to
  change a partition's type when `mkfs` makes a volume on it: L0S
  makes no partitions in one. One
  file server, `fs`, serves the first disk's volumes, one request at a
  time, each to its end, its disk requests included, so a small request
  may wait for one run of 64 KB (see [Volumes](#volumes)), and for the
  whole of a `format`, `mkfs` or `partition` once that has begun; and a read or a write moves at most 64 KB, what a client's
  file window holds (see [File windows](kernel.md#a-processs-memory)),
  which `fs` copies in and out of with L0's `device_read_bytes` and
  `device_write_bytes`, as it does its disk's buffer. A
  file's writes are written as data alone, its clusters one after
  another on the disk joined into requests of up to 32 KB, and the
  metadata they change, the file's size and chain, is kept in `fs`'s
  memory until the file is closed, or its client exits, when the disk is
  flushed and then the metadata written. So a crash while a file is
  open loses every write since it was opened, the data on the disk but
  nothing pointing at it, which a reader of the file sees in the
  meantime from `fs`'s memory. A crash during the close, on a volume
  whose metadata is more than a cluster, between the table's sector and
  the directory's, leaves the two disagreeing, and `fs` refuses the
  volume rather than follow it; and nothing flushes the metadata after
  it, so a close answered may still be in the disk's cache. A file open
  cannot be removed or renamed over, where Unix would let it go once
  closed. Any process may mount a label no one has, as any may register
  a name. `unmount`, as a rescan, is refused while any file is open, on
  any volume, since a handle names its volume by where it is among
  `fs`'s; and the system volume is never unmounted, though a rescan no
  longer finds it. Nothing removes or resizes a partition.
- **A UUID's time is local, and its noise needs the device.** The board's
  clock, `rtc clock`, keeps this machine's local time, not UTC, so a
  UUID's time is off by its zone; where no clock runs its seconds are 0,
  and only the milliseconds of `clock_ns` are left. Its noise is the
  entropy device's, but on a board with no virtio-rng a mixer's, seeded
  from the clock, which can be guessed.
- **The disk is one virtio-blk, one request at a time.** `virtio-blk`
  drives the first disk on the board and moves at most 128 sectors a
  request. It gives a request 30 seconds; one that takes longer fails,
  and the disk is then taken to have stopped answering, so every later
  request fails too, until the board is started again, since the
  request it gave up on may still be in the device's queue.
