# FAT32 volumes

`fs` serves **FAT32** too ([user/lib/format/fat.l0](../user/lib/format/fat.l0)), the
file system a Raspberry Pi boots from and every other system reads,
through the same requests ([user/sbin/fs/volume.l0](../user/sbin/fs/volume.l0) is
the one layer between them): so a running L0S, from the initramfs or a
system volume, can make a card's boot partition, fill it with a system
(`install --boot`, [The Raspberry Pi 5](pi5.md#the-raspberry-pi-5)), and
change one, `config.txt` or `cmdline.txt`, made by anything else.

- **Where.** On a GPT, a partition of Microsoft's basic data type
  (`ebd0a0a2-b9e5-4433-87c0-68b6b72699c7`), which `mkfs UUID LABEL
  fat32` gives the partition it formats, or an EFI system partition. On
  a disk with no GPT but an **MBR**, as Raspberry Pi's Imager and
  Raspberry Pi OS write one ([user/lib/format/mbr.l0](../user/lib/format/mbr.l0)),
  each primary partition of type `0B`, `0C` or `EF`. An MBR has no
  UUIDs, so `fs` mounts its volumes by one it makes of the disk's
  signature and the partition's number, `SSSSSSSS-0000-0000-0000-0000000000NN`.
  L0S makes no partitions in an MBR: `partition` on such a disk is -5,
  and Disks offers no Create Partition there. `mkfs UUID LABEL
  [fat32]` makes a volume on any of its partitions, as Raspberry Pi OS's
  ext4 rootfs, by that UUID, and changes only the partition's type
  byte in sector 0, the boot code, the signature and the other entries
  kept: `0C` for FAT32, and `7F`, the type set aside for an operating
  system of one's own, for L0FS, whose volumes `fs` mounts from an MBR
  by that type. `format` and `relabel` work on its volumes.
- **The volume.** `mkfs` lays it out as mkfs.fat does: clusters of a
  sector below 260 MB, 4 KB below 8 GB and larger after, 32 reserved
  sectors holding the boot sector and FSInfo and their backups at 6 and
  7, two FATs, the root directory at cluster 2, and the label in the
  boot sector and as the root's label entry. A volume made elsewhere is
  read whatever its clusters, 512 bytes to 32 KB.
- **Names.** Long names, of up to 255 bytes, as every system has had
  since Windows 95: a name of 8.3 in one case is a short entry alone,
  its case in the NT byte, so `config.txt` stays `config.txt`; any other
  has its long name's slots before a short alias, `LONGFI~1.TXT`. Names
  are found ignoring case. A name L0S cannot spell, with a space or
  past ASCII, is kept, but not listed or found.
- **The label** is the root's label entry's, else the boot sector's,
  each byte `label_ok` refuses made `_`; one with none is mounted as
  `FAT-` and its serial number. `relabel` rewrites both, at most 11.
- **Programs.** FAT has no mark for one, so every file `stat`s as no
  program, `chmod` is -8, and `cp` copies a program there as a plain
  file. The system volume stays L0FS.
- **Times.** What `fs` makes or writes is dated by the clock's time
  once `rtc clock` answers; before that, 1980's first moment.
- **Kept in memory** as an L0FS volume is: the FAT as an array of a
  sector's 128 marks each, so a change copies a sector's, and every
  directory as its slots' bytes. A change writes the FAT's sectors it
  touched, in both copies, FSInfo's count of free clusters, and the
  directory sectors it touched, after the data and a flush. `fs` checks
  every chain when it loads a volume, refusing one with a cluster two
  chains claim, a loop, or a file shorter than its size, and says so if
  the volume was not put away cleanly, then serves it all the same.

`tools/mkfs` makes FAT32 volumes too, an ARCHIVE of `fat32`, or
`fat32=PATH` to fill one from a cpio, and with `mbr` before the volumes
writes an MBR, as Imager does, in place of a GPT:
`tools/mkdisk build/card.img 71680 mbr bootfs:2048:67584:fat32=build/initramfs.cpio`.
[tests/fat.sh](../tests/fat.sh) checks the result both ways with the
host's own tools: `fsck_msdos` or `fsck.fat` finds nothing wrong with
what L0S makes or writes, and L0S reads and writes a volume the host
made, which the host then finds its files on.

**The mount table** ([kernel/mounts.l0](../kernel/mounts.l0)) is a list
whose first mount is `/`: the initramfs, which the kernel answers for
itself, until `root_switch` makes a volume the system volume, `/` for
good. After it come the volumes, each at `/Volumes/LABEL` from the port
of the server that mounted it with `fs_mount`, with its partition's
UUID; the system volume is there too. A volume goes when its server
unmounts it with `fs_unmount`, or when that port goes, but for `/`,
which stays the system volume's though its server goes, and is
then answered -5, as any call on a gone server's files is: there is no
going back to the initramfs, which the kernel gave up. `/Volumes`
itself is always there, a directory holding only the volumes: nothing
can be made in it, only in one of them. The kernel takes a path, made
absolute, to where it is mounted:

- the initramfs: answered as [Calls 1–13](syscalls.md#calls-113-the-process-abi-of-spec-103) say;
- the system volume, any path outside `/Volumes` once `/` is one: its
  server is asked for the same path in `/Volumes/LABEL`, as for a volume;
- `/Volumes`: a directory, -8; straight in it, nothing there, -3, and
  nothing can be made, -4; in a volume not mounted, -3, or -9 to write;
- a volume: its server is sent the call as a request of the fs protocol,
  below, *from the calling process*, and the process waits for the reply
  on a port the kernel makes for it, which goes once the reply has come.
  ps shows it `waiting for the file server on port N`. A rename between
  two mounts is -10, another file system, as is one between the
  initramfs and a volume. A file opened is a stream of the process's
  like any other, which holds the server's handle. If the server's queue
  is full, the process waits for room and calls again; if the server
  goes, every process waiting for it is answered -5, and so is any later
  call on its files. Only the server's own reply is taken: anything else
  sent to the reply port is dropped.

**The fs protocol** ([user/lib/proto/fs.l0](../user/lib/proto/fs.l0)) is what a file
server serves on the port it mounts from. The kernel sends the first
six; programs send `list`, `mkdir`, `stat`, `chmod`, `df`, `format`,
`relabel` and `unmount` themselves, to the port `mount_at` gives, as `ls`, `mkdir`,
`df`, `format`, `relabel` and `unmount` in the shell do (`fs_server_path` gives a path of the system
volume as its server knows it, in `/Volumes/LABEL`), and `rescan`,
`partition` and `mkfs` to the port registered as `fs`. `fs_df_on`,
`fs_format_on`, `fs_relabel_on`, `fs_rescan_on`, `fs_partition_on` and `fs_mkfs_on` take
a reply port the program keeps, for one that asks again and again;
`fs_df` and `fs_format` make one each call, which never goes. A
refusal's word may be followed by why, in words.

| Request | Reply |
|---|---|
| `open MODE PATH` | MODE 1 to read, 2 to write anew, 3 to add to the end, making the file if it is not there, in a directory that is: a handle; -8 for a directory, -3 or, to write, -9 where a directory on the way is missing |
| `read H N` | at most N bytes of handle H from where it is, and at most 4092, what a reply holds after its word, on across the end of a cluster if the file goes on: the count, then the bytes; 0 at the end |
| `write H BYTES` | BYTES written to H, at its end for mode 3: how many, all of them, or -6 if the volume has no room |
| `close H` | 0 |
| `rename FROM TO` | 0, a file or a directory, to another directory too, a file named TO replaced, unless it is open, -4; a directory there is -8, a directory over a file -4, and into itself -5; both in one volume, else -10. Handles open on a file moved follow it |
| `remove PATH` | 0, a file, unless it is open, or a directory with nothing in it, else -4 |
| `list PATH [FROM]` | the directory at PATH, a volume's root or any other, and nothing below it: how many entries it has, then a line `NAME SIZE` for each from the FROMth (0 unless given), by name, as many as fit in one message, a directory's NAME ending in `/` and its SIZE 0; none past the last; -9 for a file. `fs_list` asks again from where each reply ended until it has every entry, so a directory of any size is listed |
| `mkdir PATH` | 0, an empty directory at PATH, of a cluster; -9 if its directory is missing, -4 if something is at PATH, -5 for a name a volume cannot hold, -6 with no room |
| `stat PATH` | 0, then `dir`, or `file SIZE x` for a program and `file SIZE -` for any other file; -3 for nothing |
| `chmod PATH +x` | 0, the file at PATH marked a program, or with `-x` not; -8 for a directory, and for any file of a FAT32 volume, which keeps no programs |
| `df VOLUME` | 0, then `SECTORS CLUSTERS FREE FILES`: its sectors, its clusters of data, those free, and its files, in every directory; clusters of 4 KB, a FAT32 volume's counted as so many 4 KB |
| `format VOLUME` | 0, the volume empty, its label kept; -4 while a file on it is open, or for the system volume |
| `unmount VOLUME` | 0, the volume no longer served, and unmounted with `fs_unmount`, its label free, until a rescan finds it again; -4 while any file is open, since a handle names its volume by where it is among them, and for the system volume; -3 for a volume not served |
| `relabel VOLUME LABEL` | 0, then LABEL: the volume called LABEL, written in its superblock and as its partition's name in the GPT, mounted at `/Volumes/LABEL` with `fs_mount` first, so that a label mounted already by any server changes nothing, and then unmounted from its old place; it keeps its place among the volumes, so open files stay open. -5 for a label that is none, -4 for one served or mounted already and for the system volume, whose label the kernel keeps, -3 for a volume not served; -5 on a RAM file system, and if the disk cannot be written, the old label kept |
| `rescan` | every disk taken on, those registered since too, and each one's partition table and every volume read again, as at the start, and served in place of those before, each new label mounted and each that has gone unmounted: how many volumes there are now, then a line `LABEL` for each; -4 while any file is open. A disk whose table is bad has no volumes, and is said so on stderr. The system volume's label stays mounted though it has gone, and is answered as a volume not served: -3, or -9 to write |
| `partition DISK COUNT [START]` | a new partition of COUNT sectors in the GPT of the disk DISK (`disk1`, say), both its copies, from START or where it first fits, of L0FS's type, with a new UUID, its first sector zeroed so that no old volume is found there: 0, then the UUID; -6 and why if there is no room or no entry left; -5 if the table is bad, or the disk has an MBR's, which L0S never writes over; -3 if there is no such disk. A disk with no table gets one |
| `attach DISK` | the disk DISK taken on, and its volumes mounted and served after those before: 0, then how many; 0 and 0 for a disk taken on already; -3 if there is no such disk. A driver asks it, with no reply port, once it has registered a disk |
| `mkfs UUID LABEL [l0fs\|fat32]` | a new, empty volume labelled LABEL on the partition with that UUID, on whichever disk's GPT has it, L0FS's unless `fat32` is asked for, the partition named LABEL and given L0FS's type or the basic data type, mounted at `/Volumes/LABEL` and served: 0, then LABEL; -3 if no partition has the UUID, -4 if LABEL is served or the partition's volume is (`format` empties that), -5 for a bad UUID or label, or a FAT32 label of more than 11, -6 if the partition is too small (FAT32 needs 33 MB) |

Each is a request (`request` in `l0s.l0`), its words separated by
spaces; a PATH is whole, `/Volumes/LABEL/NAME...`, and a VOLUME
`/Volumes/LABEL`, so one port serves every volume. The reply is a word,
a little-endian s32, then any bytes: a count, a handle, or a negative
code, as spec §6.3's I/O builtins give them (-3 no such file, -4 denied,
-5 any other failure, -6 no space, -8 a directory, -9 no such
directory, -10 another file system). A handle is the pid that opened
it, the sender, so a process can use only its own.

**`fs`** ([user/sbin/fs](../user/sbin/fs/fs.l0)) opens the disk with a buffer of a
cluster, reads the GPT, checks and loads the volume on each partition of
L0FS's type, its
metadata and every directory, mounts each by its label, with its
partition's UUID, from one port, and then registers
that port as `fs`, so that a program can wait for every volume with
`name_wait`. It keeps the metadata and the directories in memory and
writes them back after the data whenever they change, with a `flush`
of the disk between, so that its cache cannot put the metadata down
before the data it points at; only the sectors
that changed: the table's that hold the marks a change made, and the
directory's that holds the entry, every sector of a directory's new
cluster, those within a cluster of each other in one request:
on these volumes a write's metadata is one request, and on the largest,
whose metadata is 33 clusters, at most two rather than 33. A handle
open to read holds the cluster it read last, the file's bytes in it,
read whole, and its place in the file's chain: the next read takes
what it can from there and finds the next cluster from it, so a file
read in order reads each cluster from the disk once and walks each
link of its chain once. A handle open to write holds the place of the
cluster it wrote last, and a write walks on from it only through the
clusters it touches, so a file written in order walks each link once
too. A write to the file drops the bytes its readers hold, keeping
their places, since a write only adds to a chain's end; an `open 2`
drops both. It reads
a sector before a write only where the write keeps some of its bytes.
It watches each process that opens a file, and drops its
handles when it exits. A `rescan` does the reading again, so a volume
made or changed on a disk since is served without a reboot.
`partition` and `mkfs` make partitions and volumes on the running
system, `fs` being every disk's only writer: a volume `mkfs` makes is
served at once, after those served before, so open files keep theirs. A
disk with no volume on it, or none that can be served, or no table at
all, is no reason to stop: `fs` says so, registers, and serves nothing
until `mkfs` makes a volume or a rescan finds some.
With no disk at all, where nothing could ever be made, it says so and
exits 0.

`fs` serves every disk there is from one port, each volume knowing which
disk it is on. It waits for `disk0`, then takes on every disk registered
by then; one whose driver registers it later, as `sdhci`'s card comes
after `pcie` has set the bus up, is taken on when that driver asks it to
`attach` the disk, or, if `fs` was still loading the others then, as
soon as `fs` has registered. `partition` names the disk it is of, and
`mkfs` finds its partition on whichever disk has it.

Its limits are under [Limits](storage.md#limits), with the volumes'.
