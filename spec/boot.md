# How it boots

```
make root                                 # build/root: /bin, /sbin, /Applications
tools/mkinitramfs OUT ETC ROOT [IMAGE...] # ROOT as it is, IMAGEs as /bin/NAME, ETC as /etc
l0 boot build/kernel.img < OUT            # the kernel reads the initramfs on stdin
```

`make root` stages every program in `build/root` where the initramfs
keeps it, made anew each time:
- **`/bin`**, the commands, for people and agents: `sh`, `cat`, `hello`,
  `init`, `install`, `ping`, `spin`, `nap`, `draw`, `keys`, `windows`,
  `disk`, `net`, `tftp`, `http`, `random`, those in `user/bin`;
- **`/sbin`**, the drivers and services: `boot`, `uart`, `rtc`,
  `virtio-gpu`, `virtio-input`, `virtio-blk`, `virtio-net`, `virtio-rng`,
  `fs`, `inet`, `wm`, `echo`, those in `user/sbin`;
- **`/Applications`**, the desktop's apps, each in a bundle (below), those
  in `user/apps`.

[tools/mkinitramfs](../tools/mkinitramfs) stages a directory and archives it
with `bsdtar --format newc`, in order of path:
- everything in `ROOT`, its modes kept: programs 0755, the rest 0644;
- each IMAGE becomes `/bin/NAME`, mode 0755, as `tests/e2e.sh` adds its
  hand-made programs;
- everything in `ETC` becomes `/etc/...`, mode 0644.

`bsdtar -tvf build/initramfs.cpio` lists it like any cpio archive.

## Apps

An app is kept as macOS keeps one: a bundle, a directory
`/Applications/NAME.app`, holding its program, under the program's own
name, so that `ps` still says `vt`; its icon, `icon.ppm`; and its
`manifest`, which says what they are, a line each, `#` for a comment
([user/lib/proto/app.l0](../user/lib/proto/app.l0)):

```
name Terminal                  # what the launcher and the top bar call it
exec vt                        # its program, a file in the bundle
icon icon.ppm                  # its icon, a 48×48 binary PPM in the bundle
summary A terminal in a window, with its own shell
```

| Bundle | Program | Name |
|---|---|---|
| `Terminal.app` | `vt` | Terminal |
| `Monitor.app` | `procmon` | System Monitor |
| `Widgets.app` | `widgets` | Widgets |
| `Disks.app` | `disks` | Disks |
| `Files.app` | `files` | Files |
| `Fonts.app` | `fontview` | Fonts |
| `About.app` | `about` | About |

A bundle's name is one word, as the shell and the inittab split at
spaces; an app's name may be several. Its source is the directory beside
its program's, `user/apps/vt/Terminal.app`, holding the manifest and
its icon, which [tools/mkicon](../tools/mkicon/mkicon.l0) draws at build
time, on the launcher's ground, into the 48×48 PPM, and again at scale
2, `icon2x.ppm`, 96×96, for a large screen. The icon is one of:

- **`icon.svg`**, the app's own GNOME icon, full color: Terminal's is
  GNOME Console's, System Monitor's, Disks' and Files' their GNOME
  apps', each under its project's license ([icons/](../icons) has them and
  where each came from). mkicon draws it with the SVG library, and also
  into `icon.face`, its images at 16, 32, 48, 64 and 96 with their alpha
  (`face.l0`'s `image.N`), which the bundle keeps for Files to paint on
  its own ground (`UiPImage`), as the PPMs, drawn on the launcher's,
  cannot be shown on another with no alpha.
- **`icon.draw`**, the icon as lines of `run draw`'s commands, drawn with
  the desktop's own drawing on a canvas over an array: Widgets' is a
  rounded square and a symbolic icon at twice its size (`round 0 0 48
  48 10 purple_3`, `icon 8 8 view-app-grid 2 white`). The bundle keeps
  it, and Files paints the icon from it.

A bundle with neither, as one copied in by hand, shows the generic app
icon in Files. Making an app is making that directory; the Makefile
finds it, and the launcher finds the bundle.

The kernel keeps the whole archive in memory, parses its entries
([common/initramfs.l0](../common/initramfs.l0)), and reads `/etc/inittab`
([kernel/inittab.l0](../kernel/inittab.l0)). One directive a line:

```
start PATH [ARG ...]   start PATH at boot, in order: the first is pid 1; with ARGs, given those
dev PATH               PATH may map devices and bind interrupts, whoever starts it
args PATH ARG ...      PATH's arguments when started without any
stdin PATH             the file every process reads as standard input
```

The boot fails with a message naming the problem if:
- there's no inittab;
- a line is not one of these;
- a `start` path isn't an executable file in the archive.

Only files with an execute bit are programs. The system runs until pid 1
exits; the kernel then exits with pid 1's status.

Device authority comes only from `dev` lines, and only to a program of
the initramfs. The demo grants it to `uart`,
`rtc`, `virtio-gpu`, `virtio-input`, `virtio-blk`, `virtio-net` and `virtio-rng`, so the shell can start `rtc`
without having it itself. `wm`, `vt`, `fs` and `inet` have none: they reach only
memory they share, and messages. In the demo's inittab, then, the drivers' and
services' paths are `/sbin/...`, as are those of its `/etc/system`, which
starts the system's services and no app: an app, such as
`/Applications/Terminal.app/vt`, is started from the launcher.

## Booting from a volume

L0S can be copied onto a volume and booted from it, the volume made `/`,
the **system volume**, as a Linux initramfs hands over to its root file
system. The kernel itself still comes from QEMU (`-kernel`): the virt
board has no firmware to load it from a disk. So the initramfs boots
only the first stage, the drivers and `fs`, which a disk needs, and
[/sbin/boot](../user/sbin/boot/boot.l0) the rest:

1. The board is booted with `root=UUID` among its boot arguments
   (`l0 boot build/kernel.img root=UUID`, `QEMU_APPEND=root=UUID`, or
   `make demo ROOT_UUID=UUID`), UUID a GPT partition's, as `partition` and
   mkfs say it. The kernel gives its boot arguments to any process that
   asks, call 285.
2. `boot`, pid 1, waits for `fs` to mount the volume of that partition,
   as `mount_list`'s UUIDs show: until `fs` registers, which it does once
   it has mounted every volume, or 10 s if it never does, as on a board
   with no disk. It checks that the volume holds `/etc/system`.
3. It makes the volume `/` with call 286, `root_switch`. From then on
   every path outside `/Volumes` is the system volume's, and it is in
   `/Volumes/LABEL` too; the kernel gives the initramfs's bytes up,
   since every process started from it already has its image in frames
   of its own. Its entries stay, a few names, to name those processes
   and say which drive devices and what arguments a path gets; but no
   entry can be started or read again, and stream 0's `stdin` file ends.
   The heap's copy goes back to the kernel's heap. The raw copy QEMU's
   loader put at 0x50000000, which the kernel read its standard input
   from, joined the frame pool as soon as the kernel had read it at
   boot (spec 10.3), so that one is processes' memory already.
4. `boot` starts `/etc/system`'s programs, now the volume's, with
   `spawn_path` ([user/lib/sys/paths.l0](../user/lib/sys/paths.l0)): it
   reads each program's file, marked a program, and starts it from its
   bytes with call 287, `spawn_image`, which never gives a device. It
   waits for the first, the serial shell, and exits with its status.

With no `root=`, a UUID no mounted volume has, or a volume without
`/etc/system`, `boot` says why and starts the initramfs's own
`/etc/system`, the system as it was: that is the only fallback. Once
`/` is a volume it is for good: if `fs` died, every call on `/` would be
answered -5, with no initramfs left to go back to.

`/etc/system` is a line each, `#` for a comment:

```
start PATH [ARG ...]   start PATH, in order: the first is waited for; with ARGs, given those
```

To make a system volume:
- **From the host**, `make sysdisk` makes `build/system.img`, 64 MB, with
  `System` filled from `build/initramfs.cpio` by mkfs and `data` empty, and
  writes System's UUID to `build/system.uuid`; `make demo-system` makes it
  anew and boots from it.
- **In L0S**, `run install VOLUME` copies every directory and file of `/`
  but `/Volumes` and `/boot` (the Pi 5's boot files, which `install
  --boot` puts on the card's FAT32 partition) onto the volume, marking each program's copy a program,
  and says its UUID for `root=`. It copies from the initramfs, or from
  another system volume, never onto the one `/` is.

**With no disk, `/` can be a RAM file system.** `fs ram [MB]` serves
one volume, `tmp`, in its own memory (32 MB unless given, at most 255),
mounted at `/Volumes/tmp` with the UUID
`00000000-0000-7000-8000-000000000000` from a port registered as
`tmpfs`, before anything else; then, as `fs` alone does, it waits up to
5 seconds for `disk0` and mounts the disks' volumes from a port
registered as `fs`, which it registers though there be no disk, and
serves both ports as one set: one process, on a board with a disk or
none. Until the disks are mounted, `tmp`'s requests wait. `tmp` has no
partition table, so `partition`, `erase` and `attach` of the disk `tmp`
and `relabel` of its volume are refused (-5), `mkfs` and `rescan` pass it
over, and nothing in it outlives `fs`. A program can
use it as any volume, as the shell does (`cp /bin/hello /Volumes/tmp/bin`,
`run /Volumes/tmp/bin/hello`). Booted with `root=tmpfs`, `boot` has
`install tmp` copy the initramfs onto it, which takes the moments of its
65 files, and then makes it `/` as for a system volume, so that `/` can be
written, directories made, and apps installed (see [the
launcher](desktop.md#the-desktop)), with no disk on the board. The inittab starts
`fs ram` beside `boot`, as `tests/e2e/rootboot_tmpfs` does; without it,
or with the volume missing, `boot` says so and starts the initramfs's own
`/etc/system`. As for any system volume, the drivers and `fs` are the
initramfs's, started before the switch, and a program started after it
never drives a device.

Programs never ask where `/` is: `root_paths` lists it, `program_paths`
lists the directories a program can be in, `program_found` finds a
program among those, and `spawn_path` starts one, from the initramfs's
entry or a volume's file, as the shell, `init`, `wm`, `vt` and `boot` do.
On a system volume `program_paths` lists `/bin`, `/sbin`,
`/Applications` and each bundle in it, a level each, and nothing else,
so the shell's `run`, its unknown words and `init` take as long on a
volume full of other files as on one without; a program run by a path
elsewhere is asked of the file server (`fs_stat`). The apps
(`app_bundles`) are a listing of `/Applications`, and a file command
asks only for what it names; the shell's `ls` with no path, which lists
every file, and `install` are all that walk `/`.

## Limits

- **The initramfs is read-only.** Nothing in it can be written, renamed
  or removed. Booted from it alone, the apps are fixed at boot, and `/`
  cannot be written: a system volume, or `root=tmpfs` on a board with
  `fs ram` and no disk, makes it writable (a RAM file system is small,
  32 MB unless `fs ram` is given more, up to 255, and is gone with the
  board). Once `/` is a
  volume, the launcher shows the bundles in `/Applications` as of the
  last time it opened; an app copied to another volume is not one. The
  current directory is a path, kept as text, so it stays what it is when
  a volume is made `/`, and it is the program's own: `cd` in the shell
  is the shell's and every program it then runs. Only `open`, `rename`,
  `remove` and `chdir` take paths in the kernel; the file server's
  `list`, `mkdir`, `stat` and `chmod` are asked by programs, which make a
  relative path absolute themselves (`path_abs`). No call lists a directory: the initramfs's are `entry_paths`,
  which lists everything, and a volume's its server's `list`, a message
  of entries at a time; `root_paths` lists `/` either way, a system
  volume a directory at a time, every directory of it, which takes the
  longer the more the volume holds: the shell's `ls` with no path and
  `install` do, and nothing that looks for a program or an app.
- **Booting from a volume needs the initramfs still.** The kernel comes
  from QEMU, and the drivers and `fs` from the initramfs, which are the
  only programs that may drive devices: a program started from a
  volume's file never may, whatever the inittab says of its path. The
  system volume is chosen once, at boot, by `root=`, and is `/` for good:
  nothing switches back, and if its server goes, `/` answers -5. The
  kernel heap's copy of the archive is freed into the kernel's heap,
  which no process's pages come from; the loader's raw copy is frames
  from the moment it has been read. A volume's
  programs are read whole into their starter's memory before they start,
  and copied again into the new process.
