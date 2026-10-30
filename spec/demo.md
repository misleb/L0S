# The interactive demo

`make demo` builds every program and the initramfs, `build/initramfs.cpio`,
and boots it on QEMU. The board's serial line is on your terminal, and
its virtio-gpu is in a QEMU window, with a USB keyboard and mouse on a
`qemu-xhci` (see [USB](devices.md#usb)); its virtio-net is on QEMU's user network.
It has four CPUs (`CPUS`; `make demo CPUS=1` for one): the kernel on CPU
0, running there too the processes that pass messages, and those that
compute on CPUs 1 to 3 ([kernel.md](kernel.md)).
The mouse moves relatively, as a real one does, so a click in the window
grabs your pointer, and Ctrl-Alt-G (Ctrl-Option-G on a Mac) lets it go.
The window shows a desktop, the compositor's: a wallpaper and a top bar,
and no windows, since `/etc/system` starts the system's services and no
app. The top bar is GNOME Shell's, black across the top of the screen:
the L0S logo and **Applications** at its left, then the name of the
front window's app (`Terminal`, `System Monitor`), or its title if it is
no app's, and the date and time in its middle, `Oct 15  22:42`, from the
board's real-time clock, which QEMU sets to this machine's local time.
There is one shell at boot, and one more for each Terminal opened:

- **The serial line**, in the terminal you ran `make demo` from.
- **`vt1`**, the tab of the first Terminal opened from **Applications**
  (or with `run vt &`). The windows are drawn in GNOME's
  Adwaita style by the toolkit in [user/lib/ui](toolkit.md):
  rounded corners and a header bar with a bold, centered title, and a
  thin border of the header bar's color down the sides and along the
  foot, in Adwaita's dark style (the theme's `ui_style`, the one place a
  setting for it will be read). Keys typed in QEMU's window go to the
  one in front, whose header bar and border are `303030`; the other's
  are darker, `242424`, in the backdrop, its title dimmed.
  - Click a window to bring it to the front. Drag it by its title bar to
    move it.
  - Click the round close button at the right end of its title bar to
    close it. For the Terminal that ends each tab's shell, and its `vt`.
  - The Terminal draws its own header bar, as GNOME Console does, with
    no border, and a button at its start that opens a tab, `vt2`, with
    its own shell; with two tabs a tab bar shows under the header bar,
    where a click selects a tab and its close button closes it. Each
    tab is a terminal of 80 by 24 cells, or as many as the window holds
    once its edge is dragged or it is maximized: white on GNOME
    Console's `1e1e1e`, scrolling, with a cursor along the foot of its
    cell. The wheel scrolls back through the last 10,000 lines.
    Start another Terminal from Applications, or with `run vt &`.

The System Monitor (`procmon`), opened the same way, shows the
kernel's processes in a grid, read again every second, and under it the
memory processes are given and how much of it is free (see
[The programs](programs.md#the-programs)).

Click **Applications** to open the launcher, GNOME Shell's grid of apps:
a page over the desktop, in place of the windows, of each app's icon and
name. Click one to start it; Esc, a click on the page, or Applications
again closes it. The apps are the desktop's programs, each kept as macOS
keeps one, in a bundle under [/Applications](boot.md#apps): Terminal (`vt`),
System Monitor (`procmon`), Widgets (`widgets`), the toolkit's gallery,
Disks (`disks`), the disk, its partitions and its volumes as GNOME
Disks shows them, where free space can be made a partition and a
partition given a volume, and Files (`files`), the computer's files and
the volumes' as GNOME 45's Files shows them, in a window that draws its
own header bars, where folders are made and things renamed and deleted,
a volume renamed relabelled. Each also runs from a shell, by its name or
its program's: `run Widgets &` and `run widgets &` are the same.

Each shell runs programs on its own terminal: their standard input,
output and error are its. The demo boots in two stages. Its
[inittab](../demo/etc/inittab) starts `boot` and the drivers, from the
initramfs, and `boot` starts the rest, the lines of
[/etc/system](../demo/etc/system): from the system volume, if the board was
booted with `root=UUID`, or else from the initramfs.

| Pid | Program | What it is |
|---|---|---|
| 1 | `boot` | the first stage's end: it makes the system volume `/` if `root=` names one, starts `/etc/system`, and waits for its first program, the serial shell, so that shell's `exit` stops the system |
| 2 | `uart` | the serial line's terminal, `console` |
| 3 | `virtio-gpu` | the display driver. It serves `display`, building the screen from the buffers the compositor gives it |
| 4 | `rtc clock` | the real-time clock's driver. It serves `clock`, telling `wm` the time at the start of every minute, for the top bar |
| 5 | `virtio-blk` | the disk's driver. It serves `disk0`, reading and writing the sectors of `build/disk.img` for `fs` and `run disk` |
| 6 | `fs` | the file server. It mounts the disks' volumes, the disk's at `/Volumes/data` and `/Volumes/scratch`, and any made on the SD card, and serves their files to every program, through the kernel (see [Volumes](storage.md#volumes)) |
| 7 | `virtio-net` | the network card's driver. It serves `nic`, telling `inet` of every frame the card takes, and putting on the wire every frame `inet` gives it |
| 8 | `inet` | the IPv4 stack, at the address and with the name server a DHCP server gives it (`inet dhcp`; 10.0.2.15 and 10.0.2.3 on QEMU's user network), and keeps the lease. It serves `inet`, for `run net`, `run tftp` and `run http` (see [The network](network.md#the-network)) |
| 9 | `virtio-rng` | the entropy device's driver. It serves `random`, the host's randomness, which `fs` makes UUIDs of and `inet` keys TCP's first sequence numbers with |
| 10 | `pcie virt` | the PCIe bus's server. It puts each device's registers in the bus's window, and serves `pci`, telling `sdhci` and `xhci` where the SD host controller and the USB one are, and the interrupt each raises |
| 11 | `sdhci pci` | the SD card's driver. It serves `disk1`, reading and writing the sectors of `build/sd.img`, blank until Disks formats it, waiting on its controller's INTx line, interrupt 37 |
| 12 | `xhci pci` | the USB host controller's driver, QEMU's `qemu-xhci`. It brings up the keyboard and the mouse on its ports, and serves `usb`, telling `usb-hid` of its devices' reports. It takes the controller's interrupt, MSI 80, which `pcie` sets up for it (see [USB](devices.md#usb)) |
| 13 | `usb-hid` | the keyboard's and the mouse's driver, one process waiting on three ports. It serves `keyboard`, telling `wm`, and `run keys`, of each key typed in the window, and `pointer`, telling `wm` how far the mouse moved and what its buttons and wheel do |
| 14 | `sh` | the serial line's shell, `/etc/system`'s first program, which `boot` starts |
| 15 | `font` | the font service. It owns the fonts in `/etc/fonts`, and serves `font`, giving every program with a window, `wm` first, its text's glyphs: each face at each line height a strike in pages it shares with each asker, the desktop's made at the build, any other rasterized once, on its first ask |
| 16 | `wm` | the compositor. It owns the screen and keeps the windows on it, and serves `compositor` |
| 17 | `agentd` | the agent's server ([agent.md](agent.md)), last. With no `/etc/agent/config` and token, as the demo has unless `make agent-etc` made them, it says so in the log and exits. Otherwise it waits for `fs` to mount its home's volume, `/Volumes/data`, and serves `agent`, for `run agent`: it asks the model through `inet`'s TCP and the host's proxy, reads and writes its files through `fs`, by the kernel, and starts the programs its `run` and `sh` tools run, their terminal a port of its own |

An app opened then takes the next pids. A Terminal, the first opened,
is two: `vt`, its window, with a tab, `vt1`, the first name free,
which it registers on a port of its own and waits on with its window's,
which edits the keys `wm` sends it into the selected tab's lines, as
`uart` does what the serial line sends, and draws what is written to
the tab into its window; and `sh vt1`, the tab's shell, which the `vt`
starts, whose `exit` closes its tab, letting its name go, and, as it
is the last, the window, ending its `vt`. Each tab opened is one more
process, its shell. Terminal launched again, from the launcher or with
`run open Terminal`, is a second window of the same `vt`, with a tab
of its own: one process more, its shell; `vt` ends with its last
window.

How the display, the compositor and its clients fit together is under
[The desktop](desktop.md#the-desktop).

The interface's font is Source Sans 3,
[fonts/SourceSans3-Regular.ttf](../fonts/SourceSans3-Regular.ttf) and
its bold, each character its own width, and the terminals' is Source
Code Pro, [fonts/SourceCodePro-Regular.ttf](../fonts/SourceCodePro-Regular.ttf)
and its bold, in cells 8×16: printable ASCII, rasterized with smooth
edges by the font service, `font`, which every program with a window
asks for the sizes it draws (see [A large screen](desktop.md#a-large-screen)), and
which shares each with all of them. The sizes the desktop draws at
scales 1 and 2 come rasterized already, by
[tools/mkstrike](../tools/mkstrike/mkstrike.l0) at the build, into
`/etc/fonts` beside the fonts, which the initramfs
carries; `/etc/face` holds the pointers.

The wallpaper is L0S's own,
[branding/wallpaper-dark.svg](../branding/wallpaper-dark.svg): block
letters and colors over a grid, the kernel and its
processes as a hub and ports. [tools/mkwallpaper](../tools/mkwallpaper/mkwallpaper.l0)
draws it at the build into `build/wallpaper.qoi`, 1920×1080, and at
scale 2, `build/wallpaper2x.qoi`, 3840×2160, which `wm` shows at full
brightness, centered and cut to fit the screen, on the color of its
top-left pixel. `make demo WALLPAPER_SVG=picture.svg` draws another SVG
the SVG library can draw instead.

The window is macOS's (`cocoa`) there and SDL's (`sdl`) elsewhere, as on
Linux. `QEMU_DISPLAY=gtk` picks another (on Wayland it scales the window),
and `none` none. What is typed in your terminal goes to `uart`.

With a render node (`/dev/dri/renderD*`) and QEMU's `virtio-gpu-gl-device`,
which [tools/qemu-gl](../tools/qemu-gl) looks for, the demo gives the board
the GL device and the window GL (`sdl,gl=on`), and `virtio-gpu` composes
the screen on the host's GPU with virgl (see
[virtio-gpu's 3D mode](desktop.md#the-desktop)). `make demo GPU=2d` gives it the plain
device and the 2D mode instead, and so do `make boot` and the tests: QEMU's
`screendump`, which they read the screen with, has no surface to read when
the scanout is a GL texture.
What is typed in the window goes to the USB keyboard, and so through
`xhci`, `usb-hid` and `wm` to the front window's `vt`.

Each shell shows [/etc/motd](../demo/etc/motd), then its prompt:

```
Welcome to L0S. Try ls, df, ps, run hello; run install VOLUME copies L0S.
Commands in /bin, services in /sbin, apps in /Applications, files in /Volumes.
Another shell runs in the Terminal in QEMU's window: click it, and type there.
Applications, on the top bar, starts apps; drag a window by its title bar.
Draw on the desktop: run draw circle 640 400 300 cyan; run draw for more.
run keys echoes what the keyboard driver sees, until Esc.

L0S shell, on an L0 microkernel. Type help for the commands.
l0s> ls
  /Applications/Disks.app/disks
  /Applications/Disks.app/icon.face
  /Applications/Disks.app/icon.ppm
  /Applications/Disks.app/manifest
  ...
  /bin/cat
  ...
  /etc/face
  /etc/icons
  /etc/images/computer.face
  ...
  /etc/inittab
  /etc/motd
  /etc/wallpaper.qoi
  /etc/wallpaper2x.qoi
  /sbin/echo
  ...
  /Volumes/data/notes
l0s> run echo &
[pid 3 running]
l0s> run ping
ping: echo (pid 3) said ping 1
...
l0s> exit
```

Programs only run through `run NAME [ARG ...]`, with a final `&` to leave
one running in the background:
- `NAME` is `/bin/NAME`, else `/sbin/NAME`, else an app's program
  `/Applications/APP.app/NAME`, else the app `/Applications/NAME.app`,
  whose manifest names its program; or a path if it holds a `/`, to a
  program or an app's bundle. `run hello` and `run /bin/hello` are the
  same, and so are `run vt`, `run Terminal` and
  `run /Applications/Terminal.app`.
- Arguments given replace the ones the inittab gives the program. Plain
  `run NAME` keeps the inittab's.
- Arguments are split at spaces; there is no quoting.
- Only a final `&` means the background. An `&` anywhere else is passed
  along as an argument.

Any other word must be one of the shell's own commands (`help`, `ps`,
`wait`, `kill`, `sleep`, `echo`, `exit`, `reboot`, `cd`, `pwd`, `dmesg`, and those on files
below), so a
program can never be mistaken for a command. Here `echo` is both a
command and a program: the command prints, and `run echo &` starts the
server; `cat` is too. A bare program name gets a hint: `sh: no command
hello; to run the program, type run hello`.

`cd [DIR]` makes DIR the shell's current directory, `/` if none is given,
and `pwd` says it. A path that does not start with `/` is from it, for
these commands, `run` of a name with a `/`, and every program the shell
runs, which inherits it; `.` and `..` are taken out. `ls` with no path
lists the current directory, every file of `/` and each volume when that
is `/`.

The commands on files are the shell's own, as busybox's are. They make
the ordinary file calls, so they work on any file: the initramfs's,
which refuse every change (`permission denied`), and the disk's, under
[/Volumes](storage.md#volumes), or anywhere once `/` is the system volume:

| Command | Does |
|---|---|
| `ls [PATH ...]` | with no path, every file of `/`, then of each volume, or, if the current directory is not `/`, its names; else each directory's names (`/`, `/bin`, `/sbin`, `/Applications`, `/Applications/Terminal.app`, `/Volumes`, `/Volumes/data`, `/Volumes/data/a/b`), a directory's with a final `/`, or a file's path |
| `cat FILE ...` | shows the files |
| `write FILE WORDS ...` | makes FILE hold the words, spaced, and a newline |
| `append FILE WORDS ...` | adds that line to FILE's end, making it if need be |
| `cp FROM TO` | copies a file; into TO if it is a directory. A program's copy, on a volume, is marked a program too, but for FAT32's, which keeps no programs |
| `mv FROM TO` | renames a file or a directory, or moves it into TO if it is a directory; between file systems, as from one volume to another, it copies a file and then removes it |
| `rm FILE ...` | removes the files, and directories with nothing in them |
| `mkdir DIRECTORY ...` | makes each directory, empty, in one that is there, on a volume |
| `df` | each volume's size, the room its files and directories take and what is free, in kilobytes of 4 KB clusters (a FAT32 volume's counted as so many 4 KB), and how many files it has |
| `format VOLUME` | empties a volume, `/Volumes/LABEL` or just `LABEL`; refused while a file on it is open, and for the system volume |
| `unmount VOLUME` | takes a volume away: `fs` stops serving it and the kernel unmounts it, until a rescan (Disks' Refresh) finds it again; refused while any file is open, and for the system volume |
| `relabel VOLUME LABEL` | renames a volume: `fs` writes LABEL in its superblock and as its partition's name in the GPT, and the kernel mounts it at `/Volumes/LABEL` in place of where it was; its open files stay open. Refused for a label served or mounted already, one that is no label, and the system volume. A process whose current directory was on it under its old name is left there, as after `unmount` |
| `partition [DISK] SECTORS [START]` | a new partition of SECTORS in the GPT of DISK, `disk0` unless named, from START or where it first fits, and says its UUID (see [Volumes](storage.md#volumes)) |
| `erase DISK` | DISK, always named, given a new, empty GPT in place of every partition it had, its volumes unmounted first (see [FAT32 volumes](fat32.md#fat32-volumes)) |
| `mkfs UUID LABEL [fat32]` | a new, empty volume on the partition with that UUID, mounted at `/Volumes/LABEL`: L0FS, or FAT32 with `fat32`, which a Raspberry Pi boots from (see [FAT32 volumes](fat32.md#fat32-volumes)) |

```
l0s> write /Volumes/data/notes hello disk
l0s> append /Volumes/data/notes and again
l0s> cat /Volumes/data/notes
hello disk
and again
l0s> df
  VOLUME              SIZE    USED    FREE  FILES
  /Volumes/data       744K      8K    736K      1
  /Volumes/scratch    232K      4K    228K      0
```

Each volume's root directory takes a cluster of its own, so an empty
volume's `USED` is 4K.

Things to try:
- `run hello one two`, and `run ping 5` once `run echo &` has started the
  server.
- `run cat /etc/inittab`, to read a file of the initramfs.
- `run spin`, then Ctrl-C to interrupt it.
- `run spin &`. Then run anything else: the shell stays responsive, because
  the timer takes the processor back from `spin`. `kill PID` ends it.
- `ps`, to see what is running and what each process waits for:

  ```
    PID  PARENT  PROGRAM       STATE
      1       0  boot          waiting for pid 14
      2       0  uart          waiting for a message on port 7
      3       0  virtio-gpu    waiting for a message on port 24
      4       0  rtc           sleeping
      5       0  virtio-blk    waiting for a message on port 5
      6       0  fs            waiting for a message on port 22
      7       0  virtio-net    waiting for a message on port 6
      8       0  inet          waiting for a message on port 9
      9       0  virtio-rng    waiting for a message on port 10
     10       0  pcie          waiting for a message on port 1
     11       0  sdhci         waiting for a message on port 17
     12       0  xhci          waiting for a message on port 20
     13       0  usb-hid       waiting for a message on 3 ports
     14       1  sh            running
     15       1  font          waiting for a message on port 19
     16       1  wm            waiting for a message on port 29
  ```

  Ports are numbered as the drivers make them, which on four CPUs
  differs from boot to boot. A process waiting on a set of ports, as
  `usb-hid` waits on its own and `keyboard`'s and `pointer`'s, says how
  many.

  It lists the processes that have not exited: `agentd`, pid 17, only
  with `/etc/agent` set up, waiting on 3 ports. The shell asking is always
  `running`, since `ps` runs inside it. Every driver waits, for a request
  or its device's interrupt, which comes as a message too. A process writing to a terminal
  whose queue is full shows `writing to port N`, one reading its
  standard input from a terminal `reading a line, to port N`, and one
  whose call on a file of a volume its server has yet to answer
  `waiting for the file server on port N`.
- `run rtc`, a driver taking an interrupt.
- `run windows`, to list the windows, front first, and where the pointer
  is. Each line gives a window's id, title, x, y, width and height,
  `front` for the one in front or `-`, its client's pid, then `buffer`
  and the display's id of the content it shows, which flips between the
  window's two at each frame a toolkit window paints, and `frames` and
  how many frames `wm` has told its client. With a Terminal and then the
  System Monitor opened from Applications:

  ```
  l0s> run windows
  1 Processes 100 90 840 429 front 20 buffer 10 frames 3
  0 vt1 40 40 640 384 - 18 buffer 4 frames 0
  pointer 0 0
  ```

  At boot there are none, and it lists only the pointer.
- `run draw`, to draw on the desktop, behind the windows. Each change
  shows before the shell's next prompt. Pixels count from 0, 0 at the top
  left of the 1280×800 desktop, and a shape may run off its edge:

  ```
  l0s> run draw line 0 0 1279 799 red
  l0s> run draw circle 640 400 300 cyan
  l0s> run draw disc 200 200 50 ff8800
  l0s> run draw fill 900 600 200 100 amber
  l0s> run draw size
  1280x800
  l0s> run draw splash
  ```

  The commands are `line`, `circle`, `disc`, `rect`, `fill`, `clear`,
  `char`, `splash`, `restore`, `size` and `font`; plain `run draw` lists
  them. A color is a name (`white`, the default, `black`, `red`, `green`,
  `blue`, `yellow`, `cyan`, `magenta`, `amber`, `gray`) or six hex digits
  `RRGGBB`. More examples:

  ```
  l0s> run draw splash 30
  l0s> run draw char 8 16 65 amber ; char 16 16 66 amber
  l0s> run draw restore 8 16 16 16
  ```

  - `char X Y CODE` draws a character of the 8×16
    [font](../fonts/SourceCodePro-Regular.ttf), its code 32 to 126, with its
    top left at X, Y. Each pixel is mixed with what is under it by how
    much the glyph covers it.
  - `splash 30` redraws the wallpaper at 30% of its brightness.
  - `restore` puts the wallpaper back over a rectangle, as `splash` last
    drew it.
  - Commands separated by `;` are done together and shown at once.
- `run keys` at the serial shell, then click QEMU's window and type there,
  to see what the keyboard driver sends: each printable character as its
  key goes down, held keys repeating, Enter as a new line and Backspace as
  a rub-out, with Shift and Caps Lock, on a US layout. The front window's
  shell sees the same keys meanwhile. Esc ends it, as Ctrl-C at its
  terminal does:

  ```
  l0s> run keys
  keys: type in QEMU's window; Esc ends
  Hello, L0S!

  l0s>
  ```
- `sleep 500`.

Job control:
- **Ctrl-C** ends the job running in the foreground. The shell reports
  `[pid N interrupted]`.
- During `wait PID`, Ctrl-C stops the wait and leaves the process running.
- At the prompt, Ctrl-C drops the line being typed.
- Lines typed ahead and not yet read are dropped too, as a terminal does.
- **`kill PID`** ends any process but the shell itself: a background
  job, another shell's job, another shell, or `wm`. Drivers, the
  programs with a `dev` line, can't be killed, since the system would
  lose their devices, so `uart`, `rtc`, `virtio-gpu`, `virtio-blk`,
  `virtio-net`, `virtio-rng`, `pcie`, `sdhci` and `xhci` stay. The
  `usb-hid` drives no device, so killing it takes the keyboard and the
  mouse away until the next boot.
  Killing pid 14, the serial shell, from a window's shell stops the
  system, as its `exit` does: `boot`, pid 1, waiting for it, exits too.

Editing, on any terminal: Backspace erases a character and Ctrl-U erases
the line. Arrow keys are ignored. Ctrl-D on an empty line ends input. In
a window, Ctrl-C, Ctrl-D and Ctrl-U are the keyboard's own.

`reboot`, at any shell, restarts the board as its reset would, with
nothing told first, as Shut Down: on QEMU the board boots again (or QEMU
ends, run with `-no-reboot`), and a Pi 5's bootloader starts as at
power-on, fetching a new build over the network.

`exit [STATUS]` at the serial shell stops the system, since `boot`, pid 1,
waits for it and exits with its status; at a window's shell it ends that shell, and with it the window's `vt`,
which closes the window. Nothing opens it again until the system
restarts. The same happens when a window's shell is killed. Closing the
window instead, or killing its `vt`, ends the shell too: its terminal has
gone (see [Terminals](#terminals)). Jobs the shell left running in the
background carry on, writing to the serial line. To
quit QEMU itself, type Ctrl-A then x in your terminal. (Ctrl-C goes to
the board, not to QEMU.)

The demo boots QEMU through [tools/qemu-boot.sh](../tools/qemu-boot.sh), not
`l0 boot`. `l0 boot` gives QEMU no input, so nothing typed would reach the
board. The script copies how `l0` loads the initramfs into the board's
memory; that is not a documented interface, so a change to `l0` may need
the same change there. It also attaches the virtio-gpu, the virtio
keyboard and the virtio tablet, on modern transports, as `l0 boot` does
with `L0_QEMU_ARGS`, or with `QEMU_INPUT=usb`, as the demo boots, a
`qemu-xhci` with a `usb-kbd` and a `usb-mouse` in place of those two;
and, if `QEMU_DISK` names a raw image, a virtio-blk
on it, and if `QEMU_NET` names a network, as QEMU's `-netdev` does
without its id, a virtio-net on it, at `52:54:00:12:34:56`: the demo's
is `user`, QEMU's own, or what `make demo NET=...` gives. The demo's
disk is `build/disk.img`, 1 MB, which
[tools/mkdisk](../tools/mkdisk) makes once, with two empty volumes on it,
so what is written to it stays from one boot to the next; `make clean`
resets it. A `build/disk.img` made before the file system was, holding
raw sectors only, has no volumes, and `fs` says so and serves none: remove it, and
`make demo` makes a new one. One made before L0FS had directories is made
again, once, by itself. `QEMU_APPEND` gives the kernel boot arguments, as
`-append` does, which `make demo ROOT_UUID=UUID` sets to `root=UUID`.
Two are the kernel's own, for finding what goes wrong on a board:
`debug` writes its debug lines, each process it starts among them, to
the serial line as it does the rest, and `noshare` gives each process
its own copy of its read-only segments rather than sharing them with
other processes of the same bytes. `QEMU_MONITOR` and `QEMU_QMP` put QEMU's monitor and
QMP on sockets, as the screen tests do, to type keys, move the pointer,
and dump the screen.

## Driving L0S from an agent

[tools/l0s-mcp](../tools/l0s-mcp) is an MCP server that boots L0S through
`tools/qemu-boot.sh` and drives it as the screen tests do, for an agent
to debug and test a running system. It runs on this machine, not on the
board, so it outlives a kernel that panics or hangs and can boot again.
`make mcp` makes its Python, `build/mcp/venv`, with the MCP SDK; the
project's [.mcp.json](../.mcp.json) runs it. It boots one board at a time
and does not build: run `make initramfs` or `make screen-initramfs` first.
Each boot gets a fresh disk, `build/mcp/disk.img`, as `tools/mkdisk`
makes it, and a network card on QEMU's user network.

| Tool | Does |
|---|---|
| `boot` | boots `demo`, `screen`, a `.cpio`, or an `etc` directory packed with every program as `make root` stages them in `build/root`, and waits for the serial shell's prompt |
| `shutdown`, `status` | stops the board, by `exit` or by killing QEMU; whether it runs, its exit status, QEMU's stderr |
| `shell` | types a command at the serial shell and returns what it printed before the next prompt |
| `serial_send`, `serial_read` | types anything at the serial line, Ctrl-C included; what it showed since last read, waiting for a pattern |
| `ps`, `windows` | `ps` and `run windows` at the serial shell, parsed |
| `dmesg` | `dmesg` at the serial shell, parsed: each message of the kernel's log with its time since boot, which the board keeps, so no tool keeps a log of its own |
| `screenshot`, `pixels` | the screen, or part of it, as a PNG, by QMP's `screendump`; the exact colors of pixels |
| `type_keys`, `press_keys` | text, or combinations such as `ctrl-c`, on the keyboard, so to the front window: USB's for an image whose inittab starts `usb-hid`, as the demo's does, virtio's otherwise |
| `move`, `click`, `drag`, `scroll` | the pointer, in screen pixels, and its scroll wheel: the virtio tablet, or the USB mouse, which `move` takes into the screen's top left corner and then as far as the pixel, since it moves relatively |
| `doc` | `make -s doc Q=...`, with no board: L0S's own documentation, the libraries' first, then the programs' |

Everything the serial line shows is also kept in `build/mcp/serial.out`.

## Terminals

A terminal is a port that edits typed keys into lines and writes what it is
sent. [user/lib/sys/tty.l0](../user/lib/sys/tty.l0) has the line editing both share,
and says what a terminal takes, each a request (`request` in `l0s.l0`):

| Request | Does |
|---|---|
| `request REPLY "r"` | sends REPLY the next line typed, with its newline; empty once input has ended |
| `request REPLY "i"` | sends REPLY a lone byte 3 at each Ctrl-C, dropping what is unread |
| `request REPLY "p"` | sends REPLY `tty` at once, so REPLY learns the terminal's pid, the sender, to watch |
| `request 0 ("w" ++ BYTES)` | writes BYTES; no reply |

`uart` is one, as `console`, and each `vt` another, as the first of
`vt1`, `vt2`, and so on that is free: `vt1` in the demo, and `vt2` for
the next one started.

A process's terminal is its standard input, output and error. `sh TTY`
finds the terminal named TTY, `console` unless given, sets it as its own
with `tty_set`, and so as that of every program it starts, since a child
gets its parent's terminal (and its current directory, whichever call
starts it). The kernel then does the rest:

- A write to stream 1 or 2 is sent to the terminal as a `w`, at most 4091
  bytes a message. If the terminal's queue is full, the writer waits until
  there is room, and tries again.
- A read of stream 0 asks the terminal for a line with `r`, on a port the
  kernel makes for the process, and waits for it. What the process has no
  room for is kept for its next read.
- With no terminal, or if its terminal has gone, output is the kernel's
  own, the serial line, and input the inittab's `stdin` file.

So `run hello`'s question and its answer, `run cat FILE`'s output and its
complaints all appear on the terminal of the shell that ran them, and a
program reading with `read_line` reads what is typed there.
`console_line` in `l0s.l0` reads standard input when there is a terminal,
and otherwise asks the console driver.

If a process is killed while it waits for a line, the next line still goes
to whoever asks next, not to the dead process.

**Hangup.** A shell asks its terminal for lines itself, on its own port,
so that it hears Ctrl-C and its jobs' exits there too. The kernel carries
none of those reads, and so cannot end them when the terminal goes.
Instead, the shell asks `p` at start and watches the process that
answers. When that process exits, the shell exits with status 129, as a
Unix shell does on SIGHUP. A read the kernel does carry, a program's
`read_line`, gets the end of input.

## Limits

- A terminal is shared by every process on it: their output interleaves,
  and lines typed go to whoever asks first. A process with no terminal,
  one the inittab starts, writes to the kernel's own stdout, and its
  standard input, the inittab's `stdin` file, has one cursor for all.
- Output a terminal has not yet taken when pid 1 exits is lost, since the
  system stops at once. A shell writes its prompt before it reads, so a
  typed session ends cleanly.
- A window's terminal has no scrollback, and draws only what is written:
  it keeps no copy of its text.
