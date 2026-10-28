# Tests

| Command | What it runs |
|---|---|
| `make check` | `l0 check` of the kernel, every program with its libraries, and the host tools; then `l0sdoc --check`: every file read by `make doc` starts with `; FILE.l0 -- summary`, and every form has a `;` block, its own or its group's, except those [tools/l0sdoc/undocumented.txt](../tools/l0sdoc/undocumented.txt) lists from before the check. A listed form documented since fails it too, until `make doc-prune` takes its line off, so the list only shrinks |
| `make test` | `l0 test` on this host: every pure module, the user library, and each program's logic. It first has `bsdtar` make `build/sample.cpio`, so the parser is tested on a real archive. `python3` runs the MCP server's tests of what it parses and encodes (`tools/l0s-mcp/test_board.py`), and those of the knowledge graph's L0 parser and of `graph-usage` (`tools/graphify-l0/test_l0_graph.py`, `test_graph_usage.py`). Last, it says how many tests passed and failed, of how many files |
| `make test-virt` | `l0 test --target virt`, twice, on a board of one CPU and then of `VIRT_CPUS` (4), after `make test-virt-heap`, which runs `test_heap_runs_low` alone on a kernel heap of 96 MB, too small to record the pool, which is refused pages rather than stopping: the kernel booted on the board, once per test, from initramfses built in L0 (`kernel/asm.l0`) holding hand-assembled threads, each an ELF of its code and a bss up to `0xC0400000`. Covers exit, demand paging, faults, bad buffers, files, devices, DMA, shared memory, terminals, IPC, spawn and wait, preemption, deadlock, freed memory and spaces, heap pages released, device regions unmapped and their pages given again by unregion, code shared between processes of the same bytes and freed with the last, shared pages given up and taken back, mounts with their UUIDs and the file calls a volume's server answers, its request, its answer, and its going, file windows (the server's notice from pid 0 naming the client and its pages, made once a client, given back by `shm_unmap`, an open refused when the server has no device pages left, a write's bytes found in the window and a read's taken from it, and a window given up early that writes go back to messages for), the boot arguments, a volume made `/` and the initramfs given up, programs started from images, ELF images (`asm.l0`'s `elf_image`) mapped by their segments' flags, a bss past 4 MB, and images refused for another CPU or bad headers, and the fuzz tests |
| `make e2e` | real L0 processes under the real kernel (`tests/e2e.sh`), then the screen (`tests/gpu-screen.sh`), a 4K screen drawn at scale 2 (`tests/hidpi.sh`), the keyboard (`tests/keyboard.sh`), a USB keyboard typing and a USB mouse clicking the launcher open, through `pcie`, `xhci` and `usb-hid` (`tests/usb.sh`), the windows, their terminals and shells (`tests/vt.sh`), the toolkit's gallery (`tests/widgets.sh`), its windows resized by dragging their edges (`tests/resize.sh`), the process monitor (`tests/procmon.sh`), Disks (`tests/disks.sh`), a partition and a volume made with Disks (`tests/disks-create.sh`), Files, in a window that draws its own header bars and is dragged by them, making, renaming and deleting files and relabelling a volume (`tests/files.sh`), and partitions made and volumes made on them, by UUID (`tests/partitions.sh`), FAT32 checked by the host's own tools both ways, what L0S makes and writes and a volume the host made on an MBR (`tests/fat.sh`), and the launcher, opened and closed, starting Terminal, which the top bar then names (`tests/launcher.sh`), the L0S menu, opened, closed, starting About and shutting the board down (`tests/logo-menu.sh`), and an app installed on a system volume showing in it (`tests/launcher-install.sh`). The cases, then the screen tests (`tests/screens.sh`), boot `E2E_JOBS` at once, half this machine's CPUs unless set: about 4 minutes on 8, where one at a time took 15 |

`make check` and `make test` run each check and each test file as a
target of its own, `build/check/FILE.ok` or `build/test/FILE.ok`, made once
it passes, with its output kept in `FILE.log`. So they run again only what
changed since it last passed: its files, the toolchain, or for a test the
fonts, the apps' bundles and the sample archive. They run `JOBS` at once,
one for each CPU unless `JOBS=N` says otherwise. Nothing of what passes is
shown; a failure shows its whole output, and the rest still run. To run
everything again, `rm -rf build/check build/test`.

Each case of `tests/e2e/` is a directory:
- `etc/`, with its `inittab` and any other files;
- `expected`, its standard output; or `pattern`, for output that
  differs every boot, an extended regular expression its one line must
  match whole; or `contains`, lines each of which must be somewhere in
  it, for output of which part is the board's or the start order's, such
  as the port a driver waits on (`usb`, `dmesg`);
- `status`, if not 0;
- `stderr`, a line standard error must hold;
- `typed`, keys to type at the serial line;
- `font`, if the console font is to be added to `etc`, for `vt`;
- `disk`, if the board is to have a virtio-blk, a fresh disk from
  `tools/mkdisk` for each run;
- `layout`, that disk's, if not mkdisk's own: SECTORS, then each volume
  as mkfs takes it, `LABEL:START:COUNT[:ARCHIVE[:UUID]]`, `@` the case's
  own initramfs, to fill a volume with;
- `readonly`, if that disk is to be read-only, for a case that types
  nothing;
- `norng`, if the board is to have no virtio-rng, for a case that types
  nothing;
- `bootargs`, the kernel's boot arguments, such as `root=UUID`;
- `gpu`, the virtio-gpu's options, such as `xres=3840,yres=2160`;
- `net`, if the board is to have a virtio-net: the network it is on, as
  QEMU's `-netdev` names one without its id, such as `user` or
  `user,tftp=DIR`;
- `serve`, a command line run on the host for the length of the boot, a
  server the board reaches at 10.0.2.2, killed after; and `peer`, one run
  from its start that must exit 0, a client of a port the board listens
  to. `@PORT@` in either, in `net` and in `typed` is a free port of the
  host's loopback, chosen for the boot;
- `usb`, if the board's keyboard and pointer are to be a `usb-kbd` and a
  `usb-mouse` on a `qemu-xhci`, not virtio's;
- `sd`, if the board is to have an SD card in a `sdhci-pci`, a blank
  image of 64 MB made for the boot.

Two cases are USB's: `pcie`, the bus's server waiting once it has set
the bus up, and `usb`, `run lsusb` listing the keyboard and the mouse
`xhci` brought up on MSI 80, which its stderr names, and `ps` showing
`xhci` waiting for a message, not polling. `sdhci` (with `sd`) brings a
blank SD card up as `disk0` on its INTx line, 37, which its stderr
names, lists the disks, writes a sector and reads it back, is refused
past the card's end, and reads its last sector.

`tests/e2e.sh` builds each case's initramfs from every program and its
`etc`, boots it, and compares; given case names, as `tests/e2e.sh cwd`,
only those. Thirty-five cases type a session through
[tools/slowtype](../tools/slowtype), which pauses after each line and each
Ctrl-C as a person would:
- `shell` includes a backspace, Ctrl-U and an arrow key;
- `jobs` covers Ctrl-C at a foreground job, at a `wait`, and at the prompt,
  and `kill` of the shell's own job and of a driver, which is refused;
- `kill` ends `spin`, which the inittab started, not the shell, and is
  refused `uart`, a driver;
- `reboot` restarts the board: the kernel says so on its standard
  error, and QEMU, run with `-no-reboot` (`QEMU_NO_REBOOT=1`, which
  every typed case has), ends with status 0, nothing typed after it
  answered;
- `args` runs programs with arguments and without, by name and by path, in
  the foreground and the background, and `cat`s a file;
- `draw` sends the compositor, over the display driver, a line, `size`,
  an unknown command, a bad color, and nothing. `draw`'s complaints, on
  its standard error, are on the shell's terminal, the serial line; and
  `draw_4k` the same on a 4K screen, whose `size` is the desktop's at
  scale 2, 1920×1080;
- `virtio-gpu` starts the display driver, the input drivers, `wm`, and
  one `vt`, and checks with `run windows` that its window opened where
  the first one goes, in front;
- `tty` checks that a program's standard input, output and error are its
  shell's terminal: `cat`'s complaint about a missing file, and `hello`'s
  question, answered;
- `virtio-input` and `virtio-input_tablet` start the input driver for
  the keyboard and for the tablet, and check with `ps` that it is
  serving: it found its device, set up its queue, and bound its
  interrupt;
- `virtio-blk`, on a disk of its own, has `disk` show the disk's size
  and its first sector as `tools/mkdisk` made it, the GPT's protective
  MBR, write a sector and read it back, read the last sector a partition
  may use, and be refused one past the disk's end;
- `fs`, on a disk of its own, starts the file server and has the shell
  show `df` and `ls /Volumes`; `write` a file and `cat` it back, `append`
  to it and read it with `run cat`, a program, so through the kernel;
  `cp` it into the other volume, `mv` it within a volume and across
  volumes, `ls` everything, `rm` it; be refused a `write` to the
  initramfs; `cp` a file of the initramfs to a volume; and `format` a
  volume, `ls` showing it empty;
- `unmount`, on a disk of its own, writes a file on scratch, then
  `unmount`s scratch: `df` and `ls /Volumes` show data alone, the file is
  in no volume, and scratch cannot be unmounted again, nor what is not a
  volume;
- `relabel`, on a disk of its own, writes a file on scratch, then
  `relabel`s it `notes`: `ls /Volumes` and `df` show data and notes, the
  file is read from notes and not from scratch, and a label served
  already, or none, is refused;
- `dirs` makes directories on a volume, nested, writes, lists, moves and
  removes in them, is refused a directory where one is, in one that is
  not, the removal of one with something in it, and one in the
  initramfs; and runs `hello` copied onto a volume, its copy marked a
  program, and is told a text file copied there is not one;
- `tmpfs`, with no disk and `fs ram`, writes, reads and lists in
  `/Volumes/tmp`, makes a directory there, copies `hello` onto it and runs
  it from there, and formats it;
- `bigdir`, with `fs ram`, makes 80 directories of long names in one,
  whose listing is more than a message holds, and `ls` shows them all,
  in order, `fs` answering `list` a page at a time;
- `rootboot_tmpfs`, with `fs ram` and `root=tmpfs`, has `boot` copy the
  initramfs onto the RAM file system and make it `/`: writes there,
  makes a directory, `cd`s to it, is refused a format of the system
  volume, and runs `hello` from the copy;
- `cwd` has the shell `cd` and `pwd` in the initramfs and on a volume,
  with `.`, `..` and `//` in the path, is told there is no such
  directory, or that a file is one, and `ls`, `write`, `cat`, `mv` and a
  program it runs, `run cat`, start in the directory it is in;
- `install`, on a disk of 16 MB whose layout gives System a known UUID,
  has `install` copy the initramfs onto it, lists and reads the copy,
  runs `hello` from it, and is refused a volume not mounted and no volume;
- `install_boot`, on a disk whose BOOT is FAT32, made by `tools/mkfs`,
  has `install --boot` make it a Pi 5's boot partition from stand-in boot
  files: from `/etc/nodtb`, their copies and `input.bin`, and the note
  that it lacks a device tree; then from `/etc/boot`, a device tree
  among them, with no note, and with `--root data`, an L0FS volume of a
  fixed UUID, its `cmdline.txt` saying `root=` it; then it is refused no boot
  files, no volume, and the boot volume as its own root;
- `fat` unmounts scratch, an L0FS volume of 33 MB, and has `mkfs ...
  fat32` make it FAT32, BOOT: a file written and read back by its name
  in capitals, a directory made, a program of a long name copied into
  it, a file moved into it and read, one removed, a program refused, as
  FAT has none, BOOT relabelled bootfs, and `df`;
- `fat_mbr`, on a disk with an MBR and bootfs on it, FAT32 of type 0C
  filled from the initramfs, as Raspberry Pi's Imager makes a card:
  served, its files read, `config.txt` written and read back, and a
  `partition` refused; then `erase disk0` gives it a new, empty GPT,
  and bootfs is unmounted;
- `rootboot` boots with `root=` System's UUID, System filled from the
  case's own initramfs: `boot` makes it `/`, and the shell, started from
  it, lists `/` and `/Volumes`, writes in `/etc` and reads that back, from
  `/` and from `/Volumes/System`, makes a directory in `/`, reads
  `/etc/system`, is refused a `format` of `/`, and runs `hello` from it;
- `rootboot_missing` boots with `root=` a UUID no partition has: `boot`
  says so and starts the initramfs's system, which still refuses a
  `write`;
- `apps` lists `/Applications` and a bundle, shows Terminal's manifest,
  is told there is no app `Nope`, by name or by path, and runs
  `Terminal` by its name, which the shell finds through its manifest;
- `net`, on QEMU's user network with its TFTP server serving
  [tests/e2e/net/tftp](../tests/e2e/net/tftp), starts `virtio-net` and
  `inet`, and has `net` show the interface, ping the gateway, which ARP
  finds first, and show what ARP found; `tftp` fetch a file of one block
  and one of four full blocks, which the server ends with an empty
  one, and be told of a file the server does not have; and `net` ping `inet`'s own address;
- `dhcp`, on a QEMU user network of 192.168.7.0/24 whose server offers
  192.168.7.50, starts `inet dhcp`, and has `net` show that address, the
  netmask and the router, which only the server's ACK can have given it,
  and the name server, 192.168.7.3, ping the router, and show what ARP
  found;
- `dns`, with [a small name server](../tests/e2e/dns/server.py) on the
  host's loopback, has `net dns` show the interface's name server, and
  `net resolve` ask the host's for a name with an address, an alias of
  it, answered with a CNAME and then the address, a name with no
  address, and one it does not know; and take an address as it is;
- `http`, with [a small server](../tests/e2e/http/server.py) on the host's
  loopback, has `http` fetch a page, the same with its header, one of
  300 lines, more than a window holds, and one that is not there, said
  to be after the page, and be refused by a port nothing listens to; and
  `net tcp` show no connection is left;
- `net_echo`, with a forward from a port of the host's loopback to port
  7000 of the board, has `net echo` listen to it, take the connection
  [a client on the host](../tests/e2e/net_echo/peer.py) makes, which sends
  12000 bytes and closes its end, and send them back, which that client
  checks; and `net tcp` show no connection is left.

`files` reads the initramfs through `cat`. `virtio-gpu_nodev`,
`virtio-blk_nodev` and `virtio-net_nodev` start a driver with no `dev`
line, which is refused the device, `virtio-blk_nodisk` the disk's driver
on a board with no disk, `fs_nodisk` the file server there,
`virtio-net_nocard` the network's driver on a board with no card, and
`inet_nocard` the stack with no driver, `virtio-rng_nodev` the
entropy device's driver on a board with none, `hvs_nohvs` the Pi 5's
display driver on a board with no HVS, and `gem_norp1` its network
driver on a board with no RP1, none of which is a failure.
`eeprom_nombox` asks for the Pi 5's bootloader configuration on a board
with no mailbox, and `eeprom_show` reads a file that is no bootloader
image, both of which fail, saying why. `virtio-blk_ro` has `disk` write to a read-only disk, which the
driver refuses itself, having learnt it from the device, and
`virtio-rng` has `random` ask the driver for 1024 bytes, 2048 hex digits
of a line, which its `pattern` checks. `garbage`
and `noinit` check that a boot without a valid archive or inittab is
refused with a message. Every boot has a virtio-gpu, which no window
shows, a virtio keyboard, a virtio tablet, and a virtio-rng unless the
case has a `norng` file; only a case with a `disk`
file has a virtio-blk, and only one with a `net` file a virtio-net.

[tests/gpu-screen.sh](../tests/gpu-screen.sh) boots the initramfs of
[tests/screen/etc](../tests/screen/etc/inittab), the demo's without its
windows, which would cover the wallpaper, with QEMU's monitor on a socket
and the serial line on a FIFO. It checks pixels of a `screendump` at each
step, all of them from the compositor's desktop buffer, composed by the
host:
- the wallpaper: the corner, its ground color, and a pixel of the L of
  "L0S", where centering on a 1280×800 screen puts it, both at 70%;
- after typing `run draw line 0 32 1279 799 red`, both of the line's ends;
- after typing `run draw circle 640 400 300 cyan`, its left and right
  edges.

[tests/hidpi.sh](../tests/hidpi.sh) boots the same on a 4K virtio-gpu,
3840×2160, and by screendump checks:
- the screen is the mode's size, and the top bar is 64 rows, twice its 32;
- `run draw size` says 1920x1080, the desktop's;
- `run draw line 0 32 1919 1079 red` ends in dots of 2×2;
- after `run widgets &`, the gallery's bold title is smooth: a row through
  it has more colors than its ground and its text;
- after `run Terminal &`, `vt1`'s text, which `vt` draws itself, is smooth
  the same way;
- booted again with `scale=1`, the same screen has a bar of 32 rows.

It keeps the screen at scale 2 in `build/hidpi-2x.ppm`, to look at.

[tests/keyboard.sh](../tests/keyboard.sh) boots the same way, types
`run keys` at the serial line, then presses `h`, `i`, Shift-1, Space,
Shift-A and Enter on the virtio keyboard with the monitor's `sendkey`, as
typing in the window would. It checks that the serial line shows `hi! A`,
and that after Esc the shell runs the next command typed.

[tests/vt.sh](../tests/vt.sh) boots the demo's own initramfs (`make
vt-initramfs`), every shell running, but with two Terminals whatever the
demo's `/etc/system` starts after its first ([tests/vt/etc/system](../tests/vt/etc/system)), on its USB keyboard and mouse (`QEMU_INPUT=usb`), with QMP on a socket as well, to work the mouse, which it moves into the screen's top left corner before each move to a pixel. Which `vt`
opens first, and so where each window is, varies, so it learns where they
are from `run windows` at the serial shell. Each window draws its own
header bar, so `run windows` gives all of it, the terminal under its
header bar. Then:
- the header bars: the front window's active, `303030`, the other's in
  the backdrop, `242424`; the front window's top left pixel, cut by its
  shape, showing what is under it; and the terminal's ground under its
  header bar;
- once the front window's prompt's cursor is drawn, `echo hi`, typed with
  `sendkey`: the screendump shows the `h` of the answer on its row 8,
  under the motd, the banner and the prompt;
- `run nap 30000 &`: `ps` at the serial shell shows `nap`, its parent
  that window's shell, whose parent is the window's `vt`, one of the two
  `/etc/system` started, pids 17 and 18;
- a click on the other window's header bar, through QMP's
  `input-send-event`: it comes to the front, as `run windows` and its
  header bar's color show;
- a drag of its header bar: `run windows` shows it moved as far as the
  pointer did;
- `run cat /etc/inittab` typed into it three times, more than its 24
  rows: it scrolls, and the prompt's cursor ends on its last row;
- a step of the wheel up over it: the view goes three rows back, drawn
  from its cells, with the toolkit's overlay scrollbar along its right;
  Backspace typed brings it back to the bottom, the slider gone and the
  cursor on the last row again;
- a line of 50 columns typed and not entered, then the window's right
  edge dragged in to 320, 40 columns: the line is wrapped again, the
  cursor 10 into the last row; dragged out to 640, it is whole again,
  the cursor 50 in;
- a click on the new-tab button: `run windows` shows the window titled
  `vt3`, the new tab's name, and the tab bar shows under the header
  bar, the new tab raised; `echo hi` typed in it is answered in it, and
  `ps` shows both tabs' shells started by the window's `vt`;
- a click on the first tab: the title is its name again, its prompt on
  its last row, 21 rows under the tab bar, and `echo hi` typed is
  answered in it;
- a click on the second tab's close button: its shell ends, the tab
  bar goes and the terminal is under the header bar again;
- `exit` typed into the tab left: its shell ends, and with the last tab
  the window closes and its `vt` exits. `run windows` shows only the
  other, in front, and `ps` shows neither the `vt` nor anything it
  started;
- a click on that one's close button: `run windows` shows no window, and
  `ps` shows neither its `vt` nor its tab's relay and shell, which it
  ended.

[tests/widgets.sh](../tests/widgets.sh) boots the screen initramfs, types
`run widgets &`, and learns where the gallery's window is from
`run windows`. Then, by screendump:
- its header bar, active;
- the toolbar on the window's ground, the line under the grid's header,
  and End Process faded, with no row selected;
- a click on the second row, through QMP: the press and release go
  through `wm` to the window, and the row is tinted with the accent and
  End Process turns red;
- the tab bar along its foot, three tabs, the first raised; a click on
  the third raises it, and a click on the second's close button closes
  it, the two left sharing the bar, the third still raised.

[tests/resize.sh](../tests/resize.sh) boots the screen initramfs, types
`run widgets &`, and drags the gallery's edges with the tablet, through
QMP, checking `run windows` and, by screendump, what is shown:
- the lower right corner dragged 100 right and 60 down: the window is 100
  wider and 60 higher, in the same place, and End Process, at the
  content's right end, has moved 100 right;
- the left edge dragged 30 left: the window is 30 wider and its left
  30 less, so its right is where it was;
- the pointer, as `run windows` names it: `ew-resize` over the frame's
  right side, `nwse-resize` over the lower right corner, the arrow over
  the content;
- the top left corner grabbed just outside the window, by its rounded
  corner, and dragged 30 right and 20 down: the window that much smaller
  and its top left that much further in;
- a double click on `wm`'s own title bar: the window maximized, 1276 by
  720 at 0, 32, and another: put back, at its place and size.

[tests/procmon.sh](../tests/procmon.sh) boots the screen initramfs, types
`run procmon &`, and learns where the monitor's window is. Then, by
screendump:
- its header bar, its toolbar, the grid's header, End Process faded, and
  its own row, the seventh, with no eighth; and under the grid the
  memory's line, its level bar filled in the accent;
- after `run nap 600000 &`, nap's row, read again with nothing pressed;
- a click on it, selecting it, then on End Process, which ends it: its
  row gone, and `ps` listing no `nap`;
- after six more naps, thirteen rows, more than the ten that fit, and
  the overlay scrollbar's slider at the top;
- a step of the scroll wheel, through QMP, over the rows: scrolled to the
  end, the slider there, and the row now under the pointer tinted;
- the pointer on the scrollbar's strip: the slider wider and darker;
  then the slider dragged back up, and the rows at the top again.

[tests/disks.sh](../tests/disks.sh) boots
[tests/disks/etc](../tests/disks/etc/inittab), the screen tests' with the
disk's driver and file server, on a fresh disk from `tools/mkdisk`,
writes a file on data, types `run disks &`, and learns where its window
is. Then, by screendump:
- the sidebar's ground and its drive's row, selected;
- the bar: data selected in the accent, the free space before it on the
  window's ground, and scratch on white;
- a click on scratch, selecting it;
- Format Volume..., whose dialog shows its red Format button over the
  window dimmed, and Esc, which closes it;
- Format Volume... again, and the dialog's Format: then `ls
  /Volumes/data` at the serial shell lists no file.

[tests/disks-create.sh](../tests/disks-create.sh) boots the same, on a
disk `build/mkfs` makes with 496 sectors free between data and scratch,
and by screendump:
- a click on that free space, selecting it;
- Create Partition..., whose dialog shows its entry focused, in the
  accent's ring, and Create in the accent;
- 999 typed through the monitor's `sendkey` for the size, too much,
  fading Create, and then 254, which fits;
- Enter: the dialog gone, and the new partition selected where the
  free space was;
- Format..., whose dialog has its entry focused and Format faded, for
  no name; `made` typed, and Format in the accent;
- Enter: the dialog gone; then `ls /Volumes` at the serial shell lists
  `made`, and a file written to it is read back.

[tests/files.sh](../tests/files.sh) boots the same, writes a file on data,
types `run files &`, and learns where its window is, its content at its
own top left, as `wm` draws no title bar for it. Then, by screendump, the
tablet through QMP, its right button too, and keys through the monitor:
- its own two header bars' ground, the sidebar's, Computer's row
  selected, and `/`'s folders' tiles in the accent;
- a click on data's row, selecting it; a double click on the file, which
  shows its text as a list of its lines; and Esc, back to the tiles;
- a drag of the place's header bar's ground, which asks `wm` to `move`
  the window: `windows` says it is 100 right and 80 down; a double click
  there, which asks `wm` to `maximize` it: 1280 by 768 at 0, 32; and
  another, which puts it back, at its place and size; then drags from
  inside its edges, which ask `wm` to resize it by `edges`: its right
  side 60 right, 60 wider; its bottom left corner 60 right and 40 down,
  its left side moved and 40 taller; and its bottom 40 up, its height
  back;
- the toggle to the list, its header's line;
- a right click on the file, Rename..., a new name typed and Enter: `ls`
  at the serial shell lists the file so;
- the menu button's New Folder..., a name and Enter: the folder made;
  Delete, and the dialog's Delete: it gone again;
- Volumes, scratch selected, F2, `notes` and Enter: `ls /Volumes` lists
  `notes`, relabelled;
- the header bar's own close button: `windows` lists no Files.

[tests/partitions.sh](../tests/partitions.sh) boots the same, with `rtc
clock`, on a disk `build/mkfs` makes with room between its volumes, and
at the serial shell: `partition 400`, which says a UUID of version 7
that begins with the clock's time; `mkfs` of that UUID, whose volume is
listed in `/Volumes`, holds a file written to it, and is counted by
`df`; a second `mkfs` of it, refused; and, booted again on the same
disk, the volume mounted at once, its file there, and the UUID still
naming its partition.

[tests/logo-menu.sh](../tests/logo-menu.sh) boots the screen tests' initramfs
and clicks the top bar's logo: the pill and the card show, Esc closes
them, About L0S opens the About window (`run windows` lists it),
Restart resets the board, which the kernel says and QEMU boots again,
and Shut Down stops the board.

[tests/launcher.sh](../tests/launcher.sh) boots the screen tests' initramfs
and clicks the top bar's Applications with the tablet: the launcher
opens, Applications on its pill and the page's ground showing, and
Terminal's icon, its dark square, in the grid's fourth cell. Esc closes
it, and so does a click on the page. A click on Terminal starts it: `run
windows` lists `vt1`'s window, in front, and the top bar names it
Terminal, a lit pixel of the `T`, where its title, `vt1`, would show none.

[tests/launcher-install.sh](../tests/launcher-install.sh) boots a system
volume (`root=`) with `wm` and no window, opens the launcher with five
apps, and installs a sixth from the shell, a bundle `Extra.app` of a copy
of Terminal's program and icon and a manifest `write` and `append` make.
Opened again, the launcher shows it in the second cell, and a click on it
starts it, the top bar naming it Extra.

Every boot is killed after two minutes by [tools/deadline](../tools/deadline),
since macOS has no `timeout`. The longest, `install_boot`, takes about
3 s alone, and longer beside other boots writing their disks: it took
25 s on one CPU, and 55 s on a busier host, before file data went
through windows (roadmap 0023's log has the timings). `tests/e2e.sh` also builds three programs
of a few aarch64 instructions each, each an ELF of one code segment it
writes with `printf`, for what L0 code cannot do on purpose: fault, pass
a bad buffer, and wait on nothing.

## Limits

- **The screen tests run in 2D mode** (`GPU=2d`, the default of
  `tools/qemu-boot.sh`): `screendump` fails with "no surface" on a GL
  scanout. The 3D mode is tried by `make demo`.
