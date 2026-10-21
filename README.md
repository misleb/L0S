# L0S

A microkernel written in L0, for QEMU's aarch64 `virt` board, and the start
of an operating system around it.

The kernel is an ordinary L0 program built with `--target virt`. It runs at
EL1 and runs processes at EL0, each in its own address space. It boots from
an **initramfs**: a cpio archive, in the same newc format as Linux's, of the
programs it can run and the files they can read. An `/etc/inittab` inside
says what starts at boot. L0S can also be copied onto a volume of the disk,
and booted from it: given `root=UUID`, its first process makes that volume
`/`, the **system volume**, and the kernel gives the initramfs up (see
[Booting from a volume](#booting-from-a-volume)).

A process is any L0 program built with `--target proc`, so it runs
unchanged, and can read the initramfs's files with the ordinary `open_in`.
Processes talk through ports. Device drivers are processes too: the kernel
maps a device's registers into a driver and passes its interrupts on as
messages.

```bash
make demo                                 # boot to the shell on this terminal, and type at it
make demo-system                          # the same, from build/system.img's System volume, a copy of it
make demo SCREEN=3840x2160                # on a 4K screen, the desktop drawn at scale 2
make all                                  # type check, host tests, board tests, end-to-end
make boot ETC=tests/e2e/ipc/etc           # boot every program with that etc, non-interactively
make -s doc Q=port_send                   # the libraries' documentation, as l0 doc gives the standard library's
make -s doc Q=sbin/wm/wm                  # a file by the end of its path; names and searches reach the programs too
```

Agents working on L0S: see the L0S block at the end of
[AGENTS.md](AGENTS.md), the skills in [.claude/skills](.claude/skills) and
the rules in [.claude/rules](.claude/rules).

Requirements:
- `l0`, and Docker running. Board images are linked in l0's container.
- `qemu-system-aarch64`.
- `bsdtar`, which writes the archive. It comes with macOS.

## The interactive demo

`make demo` builds every program and the initramfs, `build/initramfs.cpio`,
and boots it on QEMU. The board's serial line is on your terminal, and
its virtio-gpu, virtio keyboard and virtio tablet are in a QEMU window;
its virtio-net is on QEMU's user network.
The window shows a desktop, the compositor's: a wallpaper, a top bar,
and two windows that overlap, each with a title bar: a terminal with a
shell, and the System Monitor. The top bar is GNOME Shell's, black across
the top of the screen: **Applications** at its left, then the name of the
front window's app (`Terminal`, `System Monitor`), or its title if it is
no app's, and the date and time in its middle, `Oct 15  22:42`, from the
board's real-time clock, which QEMU sets to this machine's local time.
There are two shells in all:

- **The serial line**, in the terminal you ran `make demo` from.
- **`vt1`**, the terminal's window. The windows are drawn in GNOME's
  Adwaita style by the toolkit in [user/lib/ui](user/lib/ui/README.md):
  rounded corners and a header bar with a bold, centered title, and a
  thin border of the header bar's color down the sides and along the
  foot. Keys typed in QEMU's window go to the one in front, whose header
  bar and border are `ebebeb`; the other's are lighter, in the backdrop,
  its title dimmed.
  - Click a window to bring it to the front. Drag it by its title bar to
    move it.
  - Click the round close button at the right end of its title bar to
    close it. For `vt1` that kills its `vt`, and its shell goes with it.
  - It is a terminal of 80 by 24 cells: white on GNOME Console's
    `1e1e1e`, scrolling, with a cursor along the foot of its cell.
    Start another from Applications, or with `run vt &`: it is `vt2`.

The other window, `Processes`, is the System Monitor (`procmon`): the
kernel's processes in a grid, read again every second, and under it the
memory processes are given and how much of it is free (see
[The programs](#the-programs)).

Click **Applications** to open the launcher, GNOME Shell's grid of apps:
a page over the desktop, in place of the windows, of each app's icon and
name. Click one to start it; Esc, a click on the page, or Applications
again closes it. The apps are the desktop's programs, each kept as macOS
keeps one, in a bundle under [/Applications](#apps): Terminal (`vt`),
System Monitor (`procmon`), Widgets (`widgets`), the toolkit's gallery,
and Disks (`disks`), the disk, its partitions and its volumes as GNOME
Disks shows them, where free space can be made a partition and a
partition given a volume. Each also runs from a shell, by its name or its
program's: `run Widgets &` and `run widgets &` are the same.

Each shell runs programs on its own terminal: their standard input,
output and error are its. The demo boots in two stages. Its
[inittab](demo/etc/inittab) starts `boot` and the drivers, from the
initramfs, and `boot` starts the rest, the lines of
[/etc/system](demo/etc/system): from the system volume, if the board was
booted with `root=UUID`, or else from the initramfs.

| Pid | Program | What it is |
|---|---|---|
| 1 | `boot` | the first stage's end: it makes the system volume `/` if `root=` names one, starts `/etc/system`, and waits for its first program, the serial shell, so that shell's `exit` stops the system |
| 2 | `uart` | the serial line's terminal, `console` |
| 3 | `virtio-gpu` | the display driver. It serves `display`, building the screen from the buffers the compositor gives it |
| 4 | `virtio-input keyboard` | the keyboard driver. It serves `keyboard`, telling `wm`, and `run keys`, of each key typed in the window |
| 5 | `virtio-input tablet` | the pointer's driver. It serves `pointer`, telling `wm` where the pointer is and what its buttons do |
| 6 | `rtc clock` | the real-time clock's driver. It serves `clock`, telling `wm` the time at the start of every minute, for the top bar |
| 7 | `virtio-blk` | the disk's driver. It serves `disk`, reading and writing the sectors of `build/disk.img` for `fs` and `run disk` |
| 8 | `fs` | the file server. It mounts the disk's volumes at `/Volumes/data` and `/Volumes/scratch`, and serves their files to every program, through the kernel (see [Volumes](#volumes)) |
| 9 | `virtio-net` | the network card's driver. It serves `nic`, telling `inet` of every frame the card takes, and putting on the wire every frame `inet` gives it |
| 10 | `inet` | the IPv4 stack, at the address and with the name server a DHCP server gives it (`inet dhcp`; 10.0.2.15 and 10.0.2.3 on QEMU's user network), and keeps the lease. It serves `inet`, for `run net`, `run tftp` and `run http` (see [The network](#the-network)) |
| 11 | `virtio-rng` | the entropy device's driver. It serves `random`, the host's randomness, which `fs` makes UUIDs of and `inet` keys TCP's first sequence numbers with |
| 12 | `sh` | the serial line's shell, `/etc/system`'s first program, which `boot` starts |
| 13 | `wm` | the compositor. It owns the screen and keeps the windows on it, and serves `compositor` |
| 14 | `vt` | the window's terminal, Terminal's program, which names itself `vt1`, the first name free. It edits the keys `wm` sends it into lines, as `uart` does what the serial line sends, and draws what is written to it into its window |
| 15 | `procmon` | the System Monitor, a window of the kernel's processes and the memory they are given, read again every second |
| 16 | `sh vt1` | the window's shell, which the `vt` starts, not `/etc/system`, after any program run before it gets there. Its `exit` ends its `vt` too, and closes its window |

How the display, the compositor and its clients fit together is under
[The desktop](#the-desktop).

The text font is [fonts/l0s-8x16.txt](fonts/l0s-8x16.txt), drawn for
L0S: printable ASCII, 8×16, one glyph per `@ CODE` line and 16 rows of
`#` and `.`, so it can be read and edited as text. The initramfs carries
it as `/etc/font.txt`. On a large screen, drawn at scale 2 (see
[A large screen](#a-large-screen)), text is Source Code Pro instead,
[fonts/SourceCodePro-Regular.ttf](fonts/SourceCodePro-Regular.ttf) and
its bold, rasterized with smooth edges into `/etc/face2x` as the build
makes it.

The wallpaper is the splash, drawn by
[tools/mksplash](tools/mksplash/mksplash.l0) into `build/splash.ppm`, at
70% of its brightness, so that what is drawn over it reads; at scale 2,
`build/splash2x.ppm`, the same drawn twice the size.
`make demo SPLASH=picture.ppm` shows any other binary PPM (P6, maxval 255)
instead, centered and cut to fit the screen, on the color of its
top-left pixel.

The window is macOS's (`cocoa`) there and SDL's (`sdl`) elsewhere, as on
Linux. `QEMU_DISPLAY=gtk` picks another (on Wayland it scales the window),
and `none` none. What is typed in your terminal goes to `uart`.

With a render node (`/dev/dri/renderD*`) and QEMU's `virtio-gpu-gl-device`,
which [tools/qemu-gl](tools/qemu-gl) looks for, the demo gives the board
the GL device and the window GL (`sdl,gl=on`), and `virtio-gpu` composes
the screen on the host's GPU with virgl (see
[virtio-gpu's 3D mode](#the-desktop)). `make demo GPU=2d` gives it the plain
device and the 2D mode instead, and so do `make boot` and the tests: QEMU's
`screendump`, which they read the screen with, has no surface to read when
the scanout is a GL texture.
What is typed in the window goes to the virtio keyboard, and so through
`virtio-input` and `wm` to the front window's `vt`.

Each shell shows [/etc/motd](demo/etc/motd), then its prompt:

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
  /Applications/Disks.app/icon.ppm
  /Applications/Disks.app/manifest
  ...
  /bin/cat
  ...
  /etc/font.txt
  /etc/inittab
  /etc/motd
  /etc/splash.ppm
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
`wait`, `kill`, `sleep`, `echo`, `exit`, and those on files below), so a
program can never be mistaken for a command. Here `echo` is both a
command and a program: the command prints, and `run echo &` starts the
server; `cat` is too. A bare program name gets a hint: `sh: no command
hello; to run the program, type run hello`.

The commands on files are the shell's own, as busybox's are. They make
the ordinary file calls, so they work on any file: the initramfs's,
which refuse every change (`permission denied`), and the disk's, under
[/Volumes](#volumes), or anywhere once `/` is the system volume:

| Command | Does |
|---|---|
| `ls [PATH ...]` | with no path, every file of `/`, then of each volume; else each directory's names (`/`, `/bin`, `/sbin`, `/Applications`, `/Applications/Terminal.app`, `/Volumes`, `/Volumes/data`, `/Volumes/data/a/b`), a directory's with a final `/`, or a file's path |
| `cat FILE ...` | shows the files |
| `write FILE WORDS ...` | makes FILE hold the words, spaced, and a newline |
| `append FILE WORDS ...` | adds that line to FILE's end, making it if need be |
| `cp FROM TO` | copies a file; into TO if it is a directory. A program's copy, on a volume, is marked a program too |
| `mv FROM TO` | renames a file or a directory, or moves it into TO if it is a directory; between file systems, as from one volume to another, it copies a file and then removes it |
| `rm FILE ...` | removes the files, and directories with nothing in them |
| `mkdir DIRECTORY ...` | makes each directory, empty, in one that is there, on a volume |
| `df` | each volume's size, the room its files and directories take and what is free, in kilobytes of its 4 KB clusters, and how many files it has |
| `format VOLUME` | empties a volume, `/Volumes/LABEL` or just `LABEL`; refused while a file on it is open, and for the system volume |
| `unmount VOLUME` | takes a volume away: `fs` stops serving it and the kernel unmounts it, until a rescan (Disks' Refresh) finds it again; refused while any file is open, and for the system volume |
| `partition SECTORS [START]` | a new partition of SECTORS in the disk's GPT, from START or where it first fits, and says its UUID (see [Volumes](#volumes)) |
| `mkfs UUID LABEL` | a new, empty volume on the partition with that UUID, mounted at `/Volumes/LABEL` |

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
      1       0  boot          waiting for pid 12
      2       0  uart          waiting for a message on port 1
      3       0  virtio-gpu    waiting for a message on port 14
      4       0  virtio-input  waiting for a message on port 13
      5       0  virtio-input  waiting for a message on port 2
      6       0  rtc           sleeping
      7       0  virtio-blk    waiting for a message on port 5
      8       0  fs            waiting for a message on port 16
      9       0  virtio-net    waiting for a message on port 7
     10       0  inet          waiting for a message on port 8
     11       0  virtio-rng    waiting for a message on port 10
     12       1  sh            running
     13       1  wm            waiting for a message on port 17
     14       1  vt            waiting for a message on port 12
     15       1  procmon       sleeping
     16      14  sh            waiting for a message on port 21
  ```

  It lists the processes that have not exited. The shell asking is always
  `running`, since `ps` runs inside it. A process writing to a terminal
  whose queue is full shows `writing to port N`, one reading its
  standard input from a terminal `reading a line, to port N`, and one
  whose call on a file of a volume its server has yet to answer
  `waiting for the file server on port N`.
- `run rtc`, a driver taking an interrupt.
- `run windows`, to list the windows, front first, and where the pointer
  is. Each line gives a window's id, title, x, y, width and height, and
  `front` for the one in front:

  ```
  l0s> run windows
  1 Processes 100 90 840 429 front
  0 vt1 40 40 640 384 -
  pointer 0 0
  ```

  Which of the two opens first, and so which is in front, varies.
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
    [font](fonts/l0s-8x16.txt), its code 32 to 126, with its top left at
    X, Y. Only its lit pixels are drawn, so what is under the rest shows
    through.
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
  lose their devices, so `uart`, `rtc`, `virtio-gpu`, `virtio-input`, `virtio-blk`,
  `virtio-net` and `virtio-rng` stay.
  Killing pid 12, the serial shell, from a window's shell stops the
  system, as its `exit` does: `boot`, pid 1, waiting for it, exits too.

Editing, on any terminal: Backspace erases a character and Ctrl-U erases
the line. Arrow keys are ignored. Ctrl-D on an empty line ends input. In
a window, Ctrl-C, Ctrl-D and Ctrl-U are the keyboard's own.

`exit [STATUS]` at the serial shell stops the system, since `boot`, pid 1,
waits for it and exits with its status; at a window's shell it ends that shell, and with it the window's `vt`,
which closes the window. Nothing opens it again until the system
restarts. The same happens when a window's shell is killed. Closing the
window instead, or killing its `vt`, ends the shell too: its terminal has
gone (see [Terminals](#terminals)). Jobs the shell left running in the
background carry on, writing to the serial line. To
quit QEMU itself, type Ctrl-A then x in your terminal. (Ctrl-C goes to
the board, not to QEMU.)

The demo boots QEMU through [tools/qemu-boot.sh](tools/qemu-boot.sh), not
`l0 boot`. `l0 boot` gives QEMU no input, so nothing typed would reach the
board. The script copies how `l0` loads the initramfs into the board's
memory; that is not a documented interface, so a change to `l0` may need
the same change there. It also attaches the virtio-gpu, the virtio
keyboard and the virtio tablet, on modern transports, as `l0 boot` does
with `L0_QEMU_ARGS`, and, if `QEMU_DISK` names a raw image, a virtio-blk
on it, and if `QEMU_NET` names a network, as QEMU's `-netdev` does
without its id, a virtio-net on it, at `52:54:00:12:34:56`: the demo's
is `user`, QEMU's own, or what `make demo NET=...` gives. The demo's
disk is `build/disk.img`, 1 MB, which
[tools/mkdisk](tools/mkdisk) makes once, with two empty volumes on it,
so what is written to it stays from one boot to the next; `make clean`
resets it. A `build/disk.img` made before the file system was, holding
raw sectors only, has no volumes, and `fs` says so and serves none: remove it, and
`make demo` makes a new one. One made before L0FS had directories is made
again, once, by itself. `QEMU_APPEND` gives the kernel boot arguments, as
`-append` does, which `make demo ROOT_UUID=UUID` sets to `root=UUID`.
`QEMU_MONITOR` and `QEMU_QMP` put QEMU's monitor and
QMP on sockets, as the screen tests do, to type keys, move the pointer,
and dump the screen.

### Driving L0S from an agent

[tools/l0s-mcp](tools/l0s-mcp) is an MCP server that boots L0S through
`tools/qemu-boot.sh` and drives it as the screen tests do, for an agent
to debug and test a running system. It runs on this machine, not on the
board, so it outlives a kernel that panics or hangs and can boot again.
`make mcp` makes its Python, `build/mcp/venv`, with the MCP SDK; the
project's [.mcp.json](.mcp.json) runs it. It boots one board at a time
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
| `screenshot`, `pixels` | the screen, or part of it, as a PNG, by QMP's `screendump`; the exact colors of pixels |
| `type_keys`, `press_keys` | text, or combinations such as `ctrl-c`, on the virtio keyboard, so to the front window |
| `move`, `click`, `drag`, `scroll` | the virtio tablet, in screen pixels, and its scroll wheel |
| `doc` | `make -s doc Q=...`, with no board: L0S's own documentation, the libraries' first, then the programs' |

Everything the serial line shows is also kept in `build/mcp/serial.out`.

### Terminals

A terminal is a port that edits typed keys into lines and writes what it is
sent. [user/lib/sys/tty.l0](user/lib/sys/tty.l0) has the line editing both share,
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
gets its parent's terminal. The kernel then does the rest:

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

### The desktop

```
 sh ─tty─ vt1 ─┐ compositor protocol                display protocol
     procmon ──┼──────────────────▶ wm ─────────────────────────▶ virtio-gpu ──▶ QEMU
       draw ───┘ (shared buffers)   ▲ ▲                           (or another driver)
                                    │ └── pointer ◀── virtio-input tablet
                                    └──── keyboard ◀── virtio-input keyboard
```

Pixels never travel in messages. They move by sharing pages:

1. A client, such as `vt`, allocates its window's buffer with
   `shm_alloc`, shares it with `wm` with `shm_share`, and draws into it.
2. `wm` shares the same pages on to the display driver.
3. The driver builds the screen from the buffers where they are.

What goes over IPC is only which buffers there are, where each goes, and
which rectangles changed.

**The display protocol** ([user/lib/proto/display.l0](user/lib/proto/display.l0)) is
the whole contract between the compositor and the display hardware's
driver. It says nothing about virtio. A driver for other hardware, a
plain framebuffer say, serves the same requests as `display`, and `wm`
runs on it unchanged. Such a driver would compose the layers by copying
pixels, and draw the pointer as a top layer.

| Request | Does |
|---|---|
| `info` | `display W H cursor scale S`: the screen's size in its own pixels, `cursor` if the driver moves a pointer itself, and the desktop's scale, 1 or 2 (none means 1) |
| `buffer ID W H VA` | a buffer of W×H 4-byte pixels (b, g, r, and unused, or alpha for a cursor), at VA in the driver, shared there with `shm_share` |
| `forget ID` | the buffer dropped, and the driver's mapping of it given up with `shm_unmap`; refused while it is on the screen or is the pointer's |
| `layers ID X Y TOP ...` | the screen, bottom first: each buffer at X, Y, its rows read from row TOP on, as a ring. The bottom layer covers the screen. Only the bands of rows whose pixels changed are transferred and flushed; the first `layers` shows the whole screen |
| `damage ID X Y W H ...` | each rectangle of its buffer changed, one or more groups of five: shown wherever they are visible, all together, with boxes that overlap transferred and flushed as one |
| `shape ID TL TR BL BR` | the buffer's corners rounded, top left, top right, bottom left, bottom right, each radius from 0 (square) to half its width and height. The driver cannot blend, so it narrows the layer's rows within a corner and the layer beneath shows there. A buffer is square when shared; if it is on the screen, the screen is rebuilt |
| `cursor ID HX HY` | the pointer's image, a 64×64 buffer, and its hot spot |
| `move X Y` | the pointer's hot spot at X, Y |

The reply is `ok`, `display W H cursor scale S` for `info`, or
`error: WHY`. The driver counts the screen's own pixels; once `info` has
said the scale, the client side, `display.l0`, counts the desktop's, and
makes every place, rectangle, top row and radius the screen's on the way.

**The compositor protocol** ([user/lib/proto/wm.l0](user/lib/proto/wm.l0)) is what
`wm` serves, as `compositor`, to its clients:

| Request | Does |
|---|---|
| `hello` | `compositor scale S`, so the client learns `wm`'s pid, to share with, and the scale to make its buffer at: S times W×H. Every other number, a window's size, place and damage, its top row, and the pointer, is the desktop's pixels |
| `window W H VA PORT TITLE` | a window of W×H pixels, its buffer at VA in `wm`, shared there with `shm_share`. It opens in front, cascading from 40, 40. Keys typed while it is in front, the pointer in it, and the notices below go to PORT. The reply is `window ID` |
| `damage ID X Y W H ...` | each rectangle of the window changed, ID X Y W H again for each, given to the display in one `damage` and shown together |
| `top ID T` | the window's rows read from its buffer's row T on, as a ring: how a client scrolls |
| `title ID TEXT` | a new title |
| `close ID` | the window gone. A client's windows also go when it exits, since `wm` watches it |
| `desktop CMD ...` | a drawing command, as `draw` takes them, drawn on the desktop |
| `windows` | a line a window, front first, then `pointer X Y` |

`wm`'s own buffers are the desktop (the wallpaper, and what `draw`
draws), buffer 0; the pointer's arrow (Adwaita's), 1; the top bar, 2;
the launcher's page, 3; and each window's title bar and frame, window
i's content, title bar and frame being 4 + 3i, 5 + 3i and 6 + 3i. The
layers it gives the driver are the desktop, then each window from back
to front, its title bar, its frame and then its content, then the top
bar over them all; while the launcher is open, the desktop, the
launcher under the bar, and the bar, the windows left out.

The top bar is GNOME Shell's: 32 rows across the screen, black, with
**Applications** at its left, then the name of the front window's app in
white, or its title if its client is no app, and the date and time,
bold, in its middle, as GNOME shows them by default (`Oct 15  22:42`,
on a 24-hour clock). An app's name is its bundle's manifest's: `wm`
reads every manifest in `/Applications` as it starts, and names a
window by where its client's program is, from `proc_info`. `wm`
repaints the bar when the front window or its title changes, when the
launcher opens or closes, and when the clock says a minute has begun.

**The launcher** ([user/sbin/wm/launcher.l0](user/sbin/wm/launcher.l0)) is GNOME
Shell's grid of apps. A click on Applications, acting on its release
over it, lights the button with a pill and shows a page under the bar,
`242424`, of each app's 48×48 icon with its name under it, in cells
136×104, in rows from 64 below the bar, in the middle of the screen, in
the archive's order. A click on an app closes the page and starts the
app's program, which `wm` watches, as it does any client, so its slot
is free once it exits; it gets the inittab's arguments for it, and
`wm`'s terminal, the serial line. Esc, a click on the page, or
Applications again closes it. While it is open no window is told of
the pointer, the wheel or the keys. Its page is one buffer, painted
once, as the apps never change while the system runs. The clock is
`rtc clock` ([user/sbin/rtc](user/sbin/rtc/rtc.l0)), which serves `clock`
([user/lib/proto/clock.l0](user/lib/proto/clock.l0)): `listen` replies `time S`, S
the PL031's count of seconds, and sends `time S` again at the start of
every minute; `time` replies once. `wm` waits a second for a clock as
it starts, after the keyboard and the pointer; with none, the bar shows
no time. The PL031 has no time zone, and QEMU, booted by
`tools/qemu-boot.sh`, sets it to this machine's local time with `-rtc
base=localtime`, so the bar shows the count as it is.

Windows open below the bar, and a drag stops a window's top at the
bar's foot, so the bar never hides a title bar. A press on the bar does
nothing, and no window is told of the pointer while it is over the bar,
unless a press in its content holds it. Each title bar is an
Adwaita header bar, laid out and painted by the toolkit
([user/lib/ui](user/lib/ui/README.md)), 46 rows, as wide as the window.

Under the content is the window's frame, a buffer of `wm`'s 4 pixels
wider than the content and 2 higher, the content 2 pixels in from its
left: the 2-pixel border down the content's sides and along its foot,
painted in the title bar's ground, `ebebeb` in front and `fafafa` in the
backdrop, and repainted with it. The content covers the rest of the
frame, which is never painted. So a window W×H is W + 4 wide and
46 + H + 2 high; `windows` gives its top left and W and H, its
content's size, and the pointer goes to the client relative to the
content, as before. A press on the border brings the window to the
front and goes to no client. `wm` shapes the title bar's top corners
and the frame's bottom corners to Adwaita's 12-pixel radius, and the
content's bottom corners to 10, inside the frame's, and a press in a
cut corner falls through to what is beneath.

Input:

- **Keys** go to the front window's client, as the `KeyEvent` notices
  the keyboard driver sends.
- **The pointer**'s place, 0 to 32767 on each axis from the tablet, is
  scaled to the screen and sent to the driver as a `move`.
- **A left press** on a window brings it to the front. On its title bar,
  the press starts a drag: the window follows the pointer until the
  button is released. The screen is rebuilt for it once 20 ms have
  passed since the last rebuild ended, timed from its end and not its
  start: a rebuild can take longer than the pointer takes to move
  (about 15 ms with two windows), so the moves that come in while one runs
  only move the window, and the next rebuild shows the latest.
- **The pointer in a window's content** goes to its client as Wayland's
  does: every move and button change as a `PointerEvent` relative to the
  window. After a press in a window's content, everything goes to that
  window until every button is up (an implicit grab), even outside it,
  where x and y may be negative. When the pointer leaves a window, its
  client gets a leave notice (`leave_notice` in
  [user/lib/sys/l0s.l0](user/lib/sys/l0s.l0)).
- **The scroll wheel** goes, as a `WheelEvent` relative to the window, to
  the window the pointer would go to: the one whose content it is over,
  or the one holding it since a press. It counts steps, down and right
  positive, three rows a step in the toolkit's grid.
- **The front window changing** is told to both clients with a focus
  notice (`focus_notice`), so a client can draw itself in the backdrop.
- **A left press on the close button**, the round button at a title
  bar's right end, kills the window's client with `proc_kill`. Its exit
  then closes its windows, as any client's does. If the client cannot be
  killed, being a driver or already gone, `wm` closes the window itself.

**What virtio-gpu's 2D mode does for us.** Without virgl, virtio-gpu
neither blends nor blits. `virtio-gpu` uses the three things it does do,
so that the guest copies no pixels at all:

1. **The host composes the screen**, through scatter-gather backing. The
   screen's resource is backed (`RESOURCE_ATTACH_BACKING`) by a list of
   memory runs. The driver builds that list from the layers, row by row:
   each span of a screen row is a run of the pages of the topmost buffer
   covering it, read from its ring's row. Runs that meet in memory are
   merged. `TRANSFER_TO_HOST_2D` then copies straight out of the
   clients' buffers. Raising, moving or scrolling a window rebuilds the
   list, with `DETACH_BACKING` then `ATTACH_BACKING`.
2. **A hardware cursor**, on the cursor queue: `UPDATE_CURSOR` with a
   64×64 resource, then `MOVE_CURSOR` for each move. Moving the pointer
   costs one small command and no screen update.
3. **Damage-only updates**: a transfer and a flush of just the rectangle
   that changed.

So `vt` scrolls by changing its window's `top`, with no copying anywhere,
and draws only the new row.

**virtio-gpu's 3D mode.** If the device offers `VIRTIO_GPU_F_VIRGL`, as
QEMU's `virtio-gpu-gl-device` does, the driver (`gl.l0`) composes the
screen on the host's GPU instead, with virgl but without a shader:

1. **Each buffer a client shares is a texture** (`RESOURCE_CREATE_3D`),
   backed by the client's own pages and filled by `TRANSFER_TO_HOST_3D`
   when it is shared. The host's copy of it changes only when a `damage`
   says so, so a client must damage what it paints, as every one does;
   `wm` damages the launcher's page once it has painted it.
2. **The screen is composed from copies** (`compose.l0`): the planner turns
   the layers, bottom first, into `RESOURCE_COPY_REGION` commands, which a
   `SUBMIT_3D` carries to the GPU, 128 to a request. A ring's wrap is two
   copies; a corner a layer cuts is rows copied shorter, so what it looks
   like is what 2D mode shows, pixel for pixel. What no layer covers is
   copied from a black texture of 64 rows. `layers` composes all of the
   screen, a `damage` only the boxes it shows in, and each box is flushed.
3. **The cursor is as in 2D mode.**

A restack of a window drag takes about 8 ms there, against about 20 ms in
2D mode, both under `egl-headless`. If the device offers no virgl, or gives
no context, the driver is the 2D one. Nothing is blended or drawn by the
GPU: it only copies.

### A large screen

On a screen of 2560×1440 or more, such as `make demo SCREEN=3840x2160`
(the virtio-gpu's `xres` and `yres`), the desktop is drawn at scale 2, as
GNOME's scale factor does: laid out in pixels of its own, half the
screen's each way, so a 4K screen is a desktop of 1920×1080, and drawn
at the screen's own resolution, each of its pixels 2×2 of the screen's.
Nothing is doubled: text is Source Code Pro, icons and the pointer are
outlines, and corners are rounded at twice the radius, all with smooth
edges. The boot argument `scale=1` or `scale=2` chooses instead.

- **`virtio-gpu`** takes the screen at the mode the device offers and says
  the scale in `info`; it knows nothing else of it.
- **`wm`** lays everything out in the desktop's pixels: windows, the top
  bar, the launcher, the pointer, `draw`'s shapes and the protocol's
  numbers. Its buffers, and its clients', are twice as wide and high.
  `display.l0` makes its places the screen's on the way to the driver.
- **The toolkit** paints its ops twice the size (`paint.l0`). Text, icons
  and the pointer come from the face, `/etc/face2x`
  ([user/lib/ui/face.l0](user/lib/ui/face.l0)): coverage, how much of each
  pixel a shape covers, 0 to 15. Each pixel is mixed with what is under
  it by that much, since layers do not blend.
- **[tools/mkfont](tools/mkfont/mkfont.l0)** makes the face at build time.
  It reads Source Code Pro's TrueType outlines (`ttf.l0`), and the
  icons' and pointer's in [fonts/icons.paths](fonts/icons.paths)
  (`shape.l0`). It rasterizes them (`raster.l0`), curves, arcs and
  strokes worked out in `float`s and rounded to nearest: 16
  samples a pixel row, each crossing to 1/256 of a pixel, by the
  nonzero rule. Glyphs come out 16×32 for text, 32×64 for large text, in
  regular and bold; icons at 32, 64, 96 and 128.
- **`vt`**'s cells are still 8×16 of the desktop's pixels; it scrolls by
  32 of its buffer's rows.
- **The launcher** shows each app's `icon2x.ppm`, which `tools/mkicon`
  draws at 96×96 from the same `icon.draw`.

The GPU composes the screen as it does at scale 1, from the buffers
where they are. It does not draw: the installed QEMU has no virgl, so
the guest's CPU paints every pixel. A 4K screen's backing is more runs
than a 1280×800 one's, so the 64-entry control queue has less to spare
(see [Limits](#limits)).

### The disk

`virtio-blk` ([user/sbin/virtio-blk](user/sbin/virtio-blk/virtio-blk.l0)) drives
QEMU's virtio-blk: the demo's `build/disk.img`, 2048 sectors of 512
bytes. It serves `disk`, raw sectors, to clients, `fs` above all,
through **the disk protocol**
([user/lib/proto/disk.l0](user/lib/proto/disk.l0)). As with the display, no sector
travels in a message. A client shares a buffer of its own pages with the
driver (`shm_share`), and the device reads or writes those pages itself,
by DMA, from a chain of descriptors the driver builds over them. The
driver makes one request of the device at a time, and waits for the
device's interrupt, which the kernel sends to a port of the driver's
own, so that the requests waiting on its other port stay there. It takes
two of the device's features, if it offers them: `VIRTIO_BLK_F_FLUSH`,
so that `flush` empties the disk's write cache, and `VIRTIO_BLK_F_RO`,
so that it knows a disk is read-only (QEMU's `readonly=on`) and refuses
its writes itself.

| Request | Does |
|---|---|
| `info` | `disk SECTORS 512`: the disk's size in sectors, and a sector's in bytes; `disk SECTORS 512 ro` for a read-only disk |
| `read SECTOR COUNT VA` | COUNT sectors from SECTOR, 1 to 128, put by the device into the client's pages shared with the driver at VA |
| `write SECTOR COUNT VA` | the same, taken from those pages and written to the disk |
| `flush` | `ok` once every write answered before it is on the disk itself, not only in its cache; at once for a disk with no cache, which writes through |

The reply is `ok`, `disk SECTORS 512` for `info`, or `error: WHY`: a
count out of range, sectors past the disk's end, a write to a read-only
disk, a buffer not shared with the driver, or the device's own failure.

`run disk info`, `run disk read SECTOR [COUNT]` (shown as `hexdump -C`
shows bytes) and `run disk write SECTOR WORDS...` use it from a shell.
Sectors 1 to 7 of a disk `tools/mkdisk` makes belong to no volume, so a
`disk write` there harms no file.

### Volumes

A disk holds **volumes**, each a partition of it with a file system of
L0S's own, L0FS ([user/lib/format/l0fs.l0](user/lib/format/l0fs.l0)), and a label.
`fs` mounts each at `/Volumes/LABEL`, as macOS mounts disks, and the
kernel sends every call on a file there to it, so every program reads
and writes them with the ordinary `open_in`, `open_out` and the rest:
`run cat /Volumes/data/notes` works as `run cat /etc/motd` does.

The disk, as [tools/mkdisk](tools/mkdisk) makes it with
[tools/mkfs](tools/mkfs/mkfs.l0) (`mkfs OUT SECTORS MS
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
([user/lib/format/gpt.l0](user/lib/format/gpt.l0)), so each has a **UUID** of its
own, which it is given when it is made and keeps: a request names a
partition by it, not by where it is, which another partition made or
removed could change, nor by the label of its volume, which a format
could. The disk has one too. An entry holds the partition's type's
UUID, its own, its first and last sectors, and a name of 36 characters,
its volume's label for one `mkfs` or `tools/mkfs` made. L0FS's type is
`4c304653-0001-4000-8000-4c30534c3046`, `L0FS` in its first field. The
header and its entries are checked by CRC-32
([user/lib/format/crc32.l0](user/lib/format/crc32.l0)), and copied in the disk's last
33 sectors, which `fs` reads if the first copy is bad; it writes both,
and never over a table it found bad.

The UUIDs are of **version 7** ([user/lib/format/uuid.l0](user/lib/format/uuid.l0),
RFC 9562): the time in Unix milliseconds in their first 48 bits, so they
sort in the order they were made, then noise. `fs` asks `rtc clock` the
time, and the board's clock keeps this machine's local time, not UTC
(see [The desktop](#the-desktop)); with no clock, the time is 0. The
noise is `random`'s, the entropy device's bytes (see
[Randomness](#randomness)); on a board without the device it is
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
`partition 400` is refused; [tests/partitions.sh](tests/partitions.sh)'s
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

**The mount table** ([kernel/mounts.l0](kernel/mounts.l0)) is a list
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

- the initramfs: answered as [Calls 1–10](#calls-110-the-process-abi-of-spec-103) say;
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

**The fs protocol** ([user/lib/proto/fs.l0](user/lib/proto/fs.l0)) is what a file
server serves on the port it mounts from. The kernel sends the first
six; programs send `list`, `mkdir`, `stat`, `chmod`, `df`, `format` and
`unmount` themselves, to the port `mount_at` gives, as `ls`, `mkdir`,
`df`, `format` and `unmount` in the shell do (`fs_server_path` gives a path of the system
volume as its server knows it, in `/Volumes/LABEL`), and `rescan`,
`partition` and `mkfs` to the port registered as `fs`. `fs_df_on`,
`fs_format_on`, `fs_rescan_on`, `fs_partition_on` and `fs_mkfs_on` take
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
| `list PATH` | the directory at PATH, a volume's root or any other: how many entries, then a line `NAME SIZE` for each, by name, a directory's NAME ending in `/` and its SIZE 0; -9 for a file |
| `mkdir PATH` | 0, an empty directory at PATH, of a cluster; -9 if its directory is missing, -4 if something is at PATH, -5 for a name a volume cannot hold, -6 with no room |
| `stat PATH` | 0, then `dir`, or `file SIZE x` for a program and `file SIZE -` for any other file; -3 for nothing |
| `chmod PATH +x` | 0, the file at PATH marked a program, or with `-x` not; -8 for a directory |
| `df VOLUME` | 0, then `SECTORS CLUSTERS FREE FILES`: its sectors, its clusters of data, those free, and its files, in every directory |
| `format VOLUME` | 0, the volume empty, its label kept; -4 while a file on it is open, or for the system volume |
| `unmount VOLUME` | 0, the volume no longer served, and unmounted with `fs_unmount`, its label free, until a rescan finds it again; -4 while any file is open, since a handle names its volume by where it is among them, and for the system volume; -3 for a volume not served |
| `rescan` | the partition table and every volume read again, as at the start, and served in place of those before, each new label mounted and each that has gone unmounted: how many volumes there are now, then a line `LABEL` for each; -4 while any file is open; -5 if the table is bad. The system volume's label stays mounted though it has gone, and is answered as a volume not served: -3, or -9 to write |
| `partition COUNT [START]` | a new partition of COUNT sectors in the GPT, both its copies, from START or where it first fits, of L0FS's type, with a new UUID, its first sector zeroed so that no old volume is found there: 0, then the UUID; -6 and why if there is no room or no entry left; -5 if the table is bad. A disk with no table gets one |
| `mkfs UUID LABEL` | a new, empty volume labelled LABEL on the partition with that UUID, the partition named LABEL, mounted at `/Volumes/LABEL` and served: 0, then LABEL; -3 if no partition has the UUID, -4 if LABEL is served or the partition's volume is (`format` empties that), -5 for a bad UUID or label, -6 if the partition is too small |

Each is a request (`request` in `l0s.l0`), its words separated by
spaces; a PATH is whole, `/Volumes/LABEL/NAME...`, and a VOLUME
`/Volumes/LABEL`, so one port serves every volume. The reply is a word,
a little-endian s32, then any bytes: a count, a handle, or a negative
code, as spec §6.3's I/O builtins give them (-3 no such file, -4 denied,
-5 any other failure, -6 no space, -8 a directory, -9 no such
directory, -10 another file system). A handle is the pid that opened
it, the sender, so a process can use only its own.

**`fs`** ([user/sbin/fs](user/sbin/fs/fs.l0)) opens the disk with a buffer of a
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
made or changed on the disk since is served without a reboot.
`partition` and `mkfs` make partitions and volumes on the running
system, `fs` being the disk's only writer: a volume `mkfs` makes is
served at once, after those served before, so open files keep theirs. A
disk with no volume on it, or none that can be served, or no table at
all, is no reason to stop: `fs` says so, registers, and serves nothing
until `mkfs` makes a volume or a rescan finds some.
With no disk at all, where nothing could ever be made, it says so and
exits 0.

### The network

Two processes make the network, a driver and a stack above it, as the
disk is `virtio-blk` and `fs`:

```
net, tftp,  ──inet──▶ inet ──nic──▶ virtio-net ──DMA──▶ virtio-net card ──▶ QEMU's user network
http        ◀─pong, udp,─      ◀─frm──                                      10.0.2.2: gateway, TFTP,
              tcp notices                                                     the host's loopback
```

`virtio-net` ([user/sbin/virtio-net](user/sbin/virtio-net/virtio-net.l0))
drives QEMU's virtio-net. It takes the card's address from its
configuration (`VIRTIO_NET_F_MAC`), keeps 16 receive buffers of 2048
bytes on the card's receive queue, in DMA pages, and takes its interrupt
as a message: each frame the card has written is told to every process
listening, and its buffer given back. A frame fits in a message, so
frames travel in messages, not shared pages, both ways: one to send is
copied into the one transmit buffer, offered on the transmit queue, and
waited for, as `virtio-blk` waits. It serves **the nic protocol**
([user/lib/proto/nic.l0](user/lib/proto/nic.l0)) as `nic`:

| Request | Does |
|---|---|
| `info` | `nic MAC`: the card's Ethernet address, as `52:54:00:12:34:56` |
| `stats` | `rx N tx N dropped N`: frames taken and sent, and those lost |
| `listen` | `ok`; then every frame taken comes to the reply port as a notice, `frm` and the frame, 14 to 1514 bytes |
| `send FRAME` | the frame, without its check sequence, put on the wire, padded to 60 bytes; answered only if the request names a reply port |

`inet` ([user/sbin/inet](user/sbin/inet/inet.l0)) is IPv4: Ethernet,
ARP, IPv4, ICMP, UDP and TCP, with each packet built and read in
[packet.l0](user/sbin/inet/packet.l0) and [segment.l0](user/sbin/inet/segment.l0)
(TCP's). It listens to `nic`, and is
started as `inet dhcp`, which takes its address, netmask, router and
name server from a DHCP server (below), or as `inet [ADDR/PREFIX
[GATEWAY [DNS]]]`, which sets them, by default 10.0.2.15/24 behind
10.0.2.2, with 10.0.2.3 as the name server, QEMU's user network's own.
It answers ARP for its address and
keeps up to 64 neighbours' addresses that ARP tells it; holds up to 16
datagrams for 3 seconds while ARP finds their next hop, the gateway for
any address off the link, asking again after a second; answers ICMP echo
requests; and gives each UDP datagram to the client bound to its port,
answering one to a port no one is bound to with ICMP's port
unreachable. A datagram to its own address goes no further than `inet`.
It does not fragment, nor take fragments, so a datagram's data is at
most 1472 bytes. Everything it sends while dealing with one message,
frames and notices alike, waits in its state until that message is
done, which is how its tests see it. It serves **the inet protocol**
([user/lib/proto/inet.l0](user/lib/proto/inet.l0)) as `inet`:

| Request | Does |
|---|---|
| `info` | `inet ADDR MASK GATEWAY MAC`: the interface |
| `dns` | `dns ADDR`: the name server the interface has, `0.0.0.0` for none, which a client's `inet_resolve` asks |
| `stats` | `rx N tx N dropped N arp N`: frames taken and sent, those passed over or lost, and the neighbours known |
| `arp` | a line `ADDR MAC` for each neighbour, by address |
| `bind PORT` | `bound PORT`: UDP datagrams to PORT come to the reply port from now on, as notices `udp SRC SPORT DPORT`, a newline, and the data; `bind 0` for a port `inet` picks, from 49152. Refused if another client holds PORT |
| `unbind PORT` | `ok`: no more of them; refused if PORT is another's |
| `send SPORT DST DPORT` | then a newline and the data: a datagram from SPORT to DPORT at DST; answered only if refused, or with `ok` if the request names a reply port |
| `ping DST SEQ` | an ICMP echo request to DST, whose id is the reply port's: answered only if refused; its reply comes to the reply port as `pong SRC SEQ TTL BYTES` |
| `connect ADDR PORT NPORT` | a TCP connection opened to PORT at ADDR, its notices to the client's port NPORT: `connecting ID LPORT`, the connection's number and local port. It is open once a notice says so |
| `listen PORT NPORT` | `listening PORT`: TCP connections to PORT are made, and told to NPORT; `listen 0` for a port `inet` picks, from 49152. Refused if PORT is listened to |
| `unlisten PORT` | `ok`: no more are made; those made go on. Only by the process that listens |
| `write ID` | then a newline and the data: given to connection ID, which sends it as the peer's window lets it; answered only if the request names a reply port. More than 16384 bytes not yet acknowledged resets the connection |
| `finish ID` | `ok`: connection ID is closed once its data is sent (a FIN) |
| `reset ID` | `ok`: connection ID is given up, with a reset |
| `tcp` | a line `ID STATE LPORT ADDR:RPORT` for each connection, then `listen PORT` for each listener; `none` for neither |

A client lets go of what it bound with `unbind`, and `inet` lets go of a
client whose port has gone when it next has something for it.

**TCP** (RFC 9293). A connection is made by `connect` or by a SYN to a
port that is listened to, goes through the three-way handshake, and is
a state machine, in [tcp.l0](user/sbin/inet/tcp.l0), of the states of
the RFC's diagram. The machine is pure: an event, a segment, the application's `write` or
`finish`, or a timer's deadline, takes a connection and the time and
gives it back with the acts it calls for, which
[tcpstack.l0](user/sbin/inet/tcpstack.l0) turns into frames, in `inet`'s
queue, and notices, and keeps the connections, 32 at most, and the
listeners. It keeps sequence and acknowledgement numbers modulo 2^32,
holds the data it has sent until it is acknowledged, and sends it again
when no acknowledgement comes: after 1 second, then 2, 4, 8, 16 and 16
more, and then gives up with a reset and `closed timeout`. A window of 8192 bytes is offered
always, the data being given to the client as it comes; the peer's is
kept, and a closed one probed with a byte. A segment that comes before
the bytes ahead of it is held, cut to the window, up to 16 of them, and
given to the client with them once they come, so that a segment lost
costs only itself. Segments carry at most 1460 bytes,
or what the peer's SYN says, so that no frame is over 1514. FIN
closes in either order, or both together, and TIME-WAIT, 4 seconds, lets
the client know the connection ended at once. A RST ends a connection
only if it is where the next byte is expected, as RFC 5961 has it, and a
segment to no connection or listener is answered with one. The TCP
checksum covers IPv4's pseudo-header. A connection to `inet`'s own address
is made inside it, with no frame. Its first sequence number is RFC
6528's: a clock that ticks every 4 microseconds, moved on by a hash of
the connection's ends keyed with a secret `inet` asks `random` for when
its first connection is made, so that one who does not know the secret
cannot guess where another's connection starts.

A client asks through its own reply port, and has the connection's notices
come to another, named in `connect` and `listen`, so that an answer is never
taken for a notice; it owns its connections by its pid. The notices, to that
port, are `tcp ID up` (opened), `tcp ID accepted SRC SPORT LPORT` (to
the listener, which is then the owner), `tcp ID data` and a newline and the data,
`tcp ID fin` (the peer will send no more), and the last of each connection,
`tcp ID closed WHY`: `closed`, `reset`, `refused`, `timeout`, `aborted` or
`overflow`. A client whose port has gone, or is full, loses its
connections, with a reset.

While it holds a connection `inet` looks at their timers every millisecond;
with none, it waits for a message.

**DHCP.** `inet dhcp` (the demo's line) starts with no address, and gets
one as a DHCP client (RFC 2131) before it registers as `inet`, so that
clients' `name_wait` waits for it. The messages are built and read in
[dhcp.l0](user/sbin/inet/dhcp.l0), and the exchange is
[lease.l0](user/sbin/inet/lease.l0), run over the stack itself: `inet`
binds UDP port 68 to its own port, so the stack takes what servers send
as it takes any datagram, to 255.255.255.255, which is ours at any
address, or to the address offered, once there is one; and it sends a
DISCOVER, and then a REQUEST of the offer it takes, from 0.0.0.0 port 68
to 255.255.255.255 port 67, as datagrams of its own, which wait in the
same queue as every frame it sends. The OFFER of an address and a
server, for this card and this exchange's xid, is taken; the ACK of that
address gives the stack its address, the netmask it names, or the
address's class's, the first router it names, or none, and the first
name server, or none; a NAK begins again. It sends again every 2
seconds, 5 times in all, and if no server has answered says so and
exits 1. Giving the demo another
network, `make demo NET=user,net=192.168.7.0/24,dhcpstart=192.168.7.50`,
shows the address it takes is the server's.

The lease is kept. Port 68 stays bound, and `inet` asks `rtc clock` to
tell it the time every minute, when it looks at the lease: once half
its time is gone it sends a REQUEST from its address to the server that
gave it (RENEWING), and once seven eighths are, broadcast to any server
(REBINDING), each asked again every minute until it is answered; an
ACK begins the lease again, and a NAK, or the lease running out, takes
the address away, and the exchange begins again from a DISCOVER. A
lease of 0xFFFFFFFF seconds is for ever.

**Names** (RFC 1035). A client resolves a name itself, with
`inet_resolve` in [inet.l0](user/lib/proto/inet.l0): it asks `inet`
for its name server (`dns`), binds a UDP port, sends the query for the
name's IPv4 address, built in [dns.l0](user/lib/format/dns.l0), to port
53 there, and reads the first A record of the answer, past any CNAME;
an address dotted is taken as it is, with nothing asked. It waits 2
seconds for the answer, asks 3 times in all, and drops anything else
that comes to its port meanwhile. `net`, `tftp` and `http` take names
this way.

`run net` uses it from a shell, as `ifconfig` and `ping` would, and
`run tftp HOST FILE [PATH]` fetches a file over TFTP, from QEMU's TFTP
server, which serves a directory at the gateway when the demo is made
with `make demo NET=user,tftp=DIR`:

```
l0s> run net
inet 10.0.2.15 netmask 255.255.255.0 gateway 10.0.2.2
ether 52:54:00:12:34:56
l0s> run net ping 10.0.2.2
64 bytes from 10.0.2.2: seq 1 ttl 255 time 5.4 ms
64 bytes from 10.0.2.2: seq 2 ttl 255 time 4.9 ms
64 bytes from 10.0.2.2: seq 3 ttl 255 time 5.0 ms
3 sent, 3 received
l0s> run net arp
10.0.2.2 52:55:0a:00:02:02
l0s> run net dns
dns 10.0.2.3
l0s> run net resolve example.com
104.20.23.154
```

QEMU's user network answers pings to its gateway itself, its TFTP
server is there too, and its name server, 10.0.2.3, asks the host's;
what goes beyond the gateway is QEMU's to carry. `run net resolve NAME
[SERVER [PORT]]` resolves a name, as the interface's name server
answers, or another's; `run net ping HOST` and `run net send HOST PORT
TEXT...` take names too, and `run net recv PORT` waits for a datagram
and shows it.

`run http [-i] [http://]HOST[:PORT][/PATH]` fetches a page over HTTP/1.0
(RFC 1945), through TCP, and writes it, with its header first for `-i`.
QEMU's user network reaches the host's loopback as 10.0.2.2, so a server
on the host, say `python3 -m http.server 8000 --bind 127.0.0.1`, is
fetched with `run http 10.0.2.2:8000/`. HOST is a name, resolved first,
or an address. It does not follow a redirect; a status that is not
2xx is said, after the page, and fails the command. `run net tcp` shows
the connections, and `run net echo PORT` listens to TCP PORT, sends back
what the first connection sends, and says how much, for a connection
from the host to a port forwarded to the board
(`make demo NET=user,hostfwd=tcp:127.0.0.1:7000-:7000`, then `nc 127.0.0.1
7000`).

### Randomness

`virtio-rng` ([user/sbin/virtio-rng](user/sbin/virtio-rng/virtio-rng.l0))
drives QEMU's virtio-rng, which every boot gives the board
(`tools/qemu-boot.sh`, the Makefile's `DEVICES`, `tests/e2e.sh`), and
which reads the host's `/dev/urandom`. It serves **the random protocol**
([user/lib/proto/random.l0](user/lib/proto/random.l0)) as `random`:

| Request | Does |
|---|---|
| `bytes N` | `random HEX`: N bytes, 1 to 1024, that the device gave, as 2N lowercase hex digits |

`random_bytes` asks for some, at once with no waiting, and says why
there are none when no driver has registered `random`, so its clients do
without on a board with no device: `fs`, which makes the noise of a new
partition's UUID of it (see [Volumes](#volumes)), falling back to the
clock's mixer, and `inet`, which keys TCP's first sequence numbers with
a word of it (see [The network](#the-network)), falling back to the
clock alone. `run random [N]` writes N bytes.

## How it boots

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

[tools/mkinitramfs](tools/mkinitramfs) stages a directory and archives it
with `bsdtar --format newc`, in order of path:
- everything in `ROOT`, its modes kept: programs 0755, the rest 0644;
- each IMAGE becomes `/bin/NAME`, mode 0755, as `tests/e2e.sh` adds its
  hand-made programs;
- everything in `ETC` becomes `/etc/...`, mode 0644.

`bsdtar -tvf build/initramfs.cpio` lists it like any cpio archive.

### Apps

An app is kept as macOS keeps one: a bundle, a directory
`/Applications/NAME.app`, holding its program, under the program's own
name, so that `ps` still says `vt`; its icon, `icon.ppm`; and its
`manifest`, which says what they are, a line each, `#` for a comment
([user/lib/proto/app.l0](user/lib/proto/app.l0)):

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

A bundle's name is one word, as the shell and the inittab split at
spaces; an app's name may be several. Its source is the directory beside
its program's, `user/apps/vt/Terminal.app`, holding the manifest and
`icon.draw`, the icon as lines of `run draw`'s commands, which
[tools/mkicon](tools/mkicon/mkicon.l0) draws at build time, on the
launcher's ground, into the 48×48 PPM, with the desktop's own drawing on
a canvas over an array: a rounded square and a symbolic
icon at twice its size (`round 0 0 48 48 10 dark_3`,
`icon 8 8 utilities-terminal 2 white`). It draws the same again at scale
2, `icon2x.ppm`, 96×96, its icon from the face, for a large screen.
Making an app is making that directory; the Makefile finds it, and the
launcher finds the bundle.

The kernel keeps the whole archive in memory, parses its entries
([common/initramfs.l0](common/initramfs.l0)), and reads `/etc/inittab`
([kernel/inittab.l0](kernel/inittab.l0)). One directive a line:

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
services' paths are `/sbin/...`, and in its `/etc/system` the terminals'
`/Applications/Terminal.app/vt`.

### Booting from a volume

L0S can be copied onto a volume and booted from it, the volume made `/`,
the **system volume**, as a Linux initramfs hands over to its root file
system. The kernel itself still comes from QEMU (`-kernel`): the virt
board has no firmware to load it from a disk. So the initramfs boots
only the first stage, the drivers and `fs`, which a disk needs, and
[/sbin/boot](user/sbin/boot/boot.l0) the rest:

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
   `spawn_path` ([user/lib/sys/paths.l0](user/lib/sys/paths.l0)): it
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
  but `/Volumes` onto the volume, marking each program's copy a program,
  and says its UUID for `root=`. It copies from the initramfs, or from
  another system volume, never onto the one `/` is.

Programs never ask where `/` is: `root_paths` lists it, `program_found`
finds a program in it, and `spawn_path` starts one, from the initramfs's
entry or a volume's file, as the shell, `init`, `wm`, `vt` and `boot` do.

## The kernel

There is one event loop, `schedule` in `kernel/kernel.l0`. Each turn:

1. Wake any sleeper whose time has come.
2. Take the next ready process.
3. Arm the timer for a 10 ms slice, and `user_run` the process until it
   traps.
4. Handle the trap:
   - a system call is answered;
   - a touch of an unmapped heap, stack or bss page gets a zeroed frame;
   - any other fault kills the process (status 139, with a line on stderr);
   - a timer interrupt preempts the process;
   - a device interrupt becomes a message to the port bound to it.

When nothing is ready, the kernel waits for an interrupt. If there is no
sleeper and no bound interrupt, nothing can ever wake anyone: it reports a
deadlock and exits with 124.

**Nothing a process does can crash the kernel.** Every buffer, count,
address, path and interrupt number is checked against the kernel's own
records before it reaches a builtin that could raise a runtime error.
`kernel_virt_test.l0` fuzzes this with threads that make hundreds of calls
with random registers.

| File | What it holds |
|---|---|
| `common/abi.l0` | call numbers, error codes, limits, the address-space layout, little-endian helpers, argument encoding |
| `common/initramfs.l0` | the newc archive: parsing it, paths, entry kinds, and a writer for tests |
| `common/queue.l0` | a FIFO queue of any type, shared with user programs |
| `kernel/inittab.l0` | `/etc/inittab`: parsing it, and checking it against the archive |
| `kernel/memory.l0` | what each address is for, by where a process's image lies; which pages to map before a copy, and which it may write; where device regions and DMA pages go; which frames to free when a process ends |
| `kernel/elf.l0` | a program's ELF: its headers read and checked against spec §10.3, its segments, entry, and heap |
| `kernel/mounts.l0` | the mount table: the initramfs or the system volume at `/` and the volumes at `/Volumes/LABEL`, where a path's file is and the path its server is asked for, and where a rename goes |
| `kernel/ipc.l0` | ports, their message queues, names, and the mount table, whose volumes go with their ports |
| `kernel/sched.l0` | sleepers and the timer's deadline |
| `kernel/pids.l0` | which slot of the process table, and which pid, a new process gets |
| `kernel/syscall.l0` | a trapped context decoded into a `Call` |
| `kernel/process.l0` | creating a process from its ELF's segments, demand-paging, copying in and out of, mapping devices and DMA pages into, and the open files of a process |
| `kernel/kernel.l0` | the state, every call's handler, traps, the loop, and boot |

All of these except `process.l0` and `kernel.l0` are pure and tested on the
host. The kernel itself is tested on the board.

### Processes and pids

The process table has 255 slots, so at most 255 processes are alive at
once, but any number may run over the kernel's life. A pid names a slot
in its low 8 bits, and in the bits above, how many times that slot was
given before: the first 255 pids are 1 to 255, and slot 2's second
process is pid 258. So a slot is reused but a pid never is, and a pid
kept after its process has gone, by a waiter, a typed `kill`, or a
queue, names nothing rather than whoever has its slot now: calls on it
give -1, as for a pid never used.

A process that exits keeps its slot, so that `proc_wait`, `proc_watch`
and `proc_info` can still report its status, until a new process needs
the slot. The kernel ([kernel/pids.l0](kernel/pids.l0)) gives a new
process, searching on from the slot it last gave:
1. a slot never used;
2. otherwise one whose process exited, and whose status was given to
   someone, by a wait or an exit notice, or whose parent has gone, so no
   one will ask;
3. otherwise the oldest other exited one, whose status is then lost.

It gives none, and spawning fails with -5, only when all 255 are alive.

### A process's memory

The layout is fixed by spec §10.3. A program's image is an ELF, as
`l0 build --target proc` writes them, and
[kernel/elf.l0](kernel/elf.l0) reads and checks its headers.

| Address | What | Mapped |
|---|---|---|
| `0xC0000000` | the image's segments, code, rodata, and data, ending below `0xD0000000` | at load, the pages holding the file's bytes, each with its segment's flags: code readable and executable, rodata readable, data readable and writable |
| the rest of a segment | its bss, zero | on first touch, with the segment's flags |
| from the page after the image to `0xD8000000` | heap | on first touch, RW |
| to `0xE8000000` | stack, `sp` starting at the top | on first touch, RW |
| `0xE8000000` up | device regions, DMA pages, and shared pages | by the `region` and `dma_alloc` calls, for programs with a `dev` line only; by `shm_alloc` and `shm_share`, for any |

A process starts at its image's `e_entry`. The kernel starts only an ELF
of spec §10.3's for this CPU: static, `ET_EXEC`, at most three
page-aligned `PT_LOAD`s in order, none writable and executable, within
its file and the image's range; anything else, the raw images earlier
toolchains wrote among it, is "not a program", -6. A store to its code
or rodata faults, and the process is killed, as does a touch of a page
between its segments.

The kernel copies in and out of a process only through pages it mapped
itself. A buffer on a device's registers, or outside the user range, gets
-5, and so does one the kernel would write into the process's code or
rodata, which it may not write itself. DMA pages are ordinary memory the
kernel mapped, so a buffer there is accepted.

**DMA.** A device such as the virtio-gpu reads and writes memory itself,
at addresses it is given in its registers. `dma_alloc n` maps n fresh
frames at the caller's next device pages and returns the first one's
address; `dma_address va` gives where the device reaches the page holding
va, from L0's `frame_address`. The pages are consecutive in the process,
but not necessarily for the device, so a driver gives the device one
address per page, or merges the runs that happen to be consecutive.
A `region` call over DMA pages (`dma_open` in `l0s.l0`) returns the same
address, so the driver reads and writes them with `device_read32` and the
rest. The proc runtime keeps at most 64 regions open, which is why the
pages are mapped together rather than as one region each.

**Shared memory.** `shm_alloc n` is `dma_alloc` for any process: n zeroed
pages at its next device pages, with no `dev` line needed.
`shm_share va n pid` maps n of the caller's shared or DMA pages from va
into pid's next device pages as well. They are the same frames, so a
write by either is seen by both. It returns where pid sees them, for the
caller to tell pid. A `region` over one's own shared pages works without
a `dev` line too, so any process reads and writes them with `dma_open`.
`dma_address` stays for drivers alone: only they learn where a device
reaches memory.

**Taking it back.** Both are L0's `space_unmap` (spec §6.13).
`shm_unmap va n` gives up n of the caller's own shared or DMA pages from
va: they are unmapped, and each frame is freed once no process maps it.
If they were the last device pages it was given, its next ones start at
va again, so a process that shares and gives up in turn reuses the same
pages. A driver may give up its own too: its doing so says its device is
done with them. `shm_revoke va n pid` takes back from pid every mapping
it has of the caller's n pages from va, so a process can withdraw what
it shared; never from a driver, whose device may have been given their
addresses, as a driver cannot be killed either. Either way, a process
that touches a page it no longer has is ended, as for any device page
with nothing mapped.

When a window closes, the display driver and `wm` both give up its three
buffers, the content's, the title bar's and the frame's: the driver once the screen
no longer shows them, on `forget`, and `wm` after that. So a closed
window's memory is freed once its `vt` has ended too.

**Freeing.** When a process ends, the kernel gives back its space with
`space_free`, which takes its page tables and every mapping with it, and
then, with `frame_free`, every frame of it that no other space maps
(spec §6.13; `kernel/memory.l0`'s `Mem` decides which):
- Its image, heap and stack frames are its alone, so they are freed at
  once.
- A shared or DMA frame may be mapped by other processes too, so the
  kernel counts each frame's mappings, and frees it once the last process
  mapping it has ended. Freeing one still mapped would be a runtime error,
  `frame still mapped`.
- A driver's DMA and shared frames are never freed: its device may still
  hold their addresses, as the device keeps going after its driver ends.

A frame the host gives again is zeroed, so a process sees only zeroed
memory, whatever ran before it. If the host runs out while a process is
being made, what was made for it is freed again.

## System calls

`x8` holds the call number, `x0`–`x3` the arguments, and the result comes
back in `x0`. From L0, use the wrappers in `user/lib/sys/l0s.l0`.

### Calls 1–10: the process ABI of spec §10.3

The kernel answers these itself for the initramfs, a read-only file
system, and for a file of a volume under `/Volumes`, or of the system
volume once `/` is one, sends them to the volume's file server, as
[Volumes](#volumes) says, its answer the call's:

| Call | What the kernel does |
|---|---|
| open | modes 1 to 3, else -5. In the initramfs, to read: a new stream (3 and up), or -3 no such file, -8 a directory, -5 if the process has 16 open. To write: -8 a directory, -4 where the directory exists, -9 where it does not. In a volume: a new stream, once its server opens the file. A relative path is taken from `/` |
| read | stream 0 reads a line from the process's terminal, if it has one (see Terminals), and otherwise the inittab's `stdin` file, with one cursor for everyone, until the initramfs is given up. Other streams read the file opened on them, from where the process left off, 0 at the end; a volume's at most 4092 bytes a call; one of the initramfs's, once it is given up, reads as at its end |
| close | 0, or -5 for a stream that isn't open; a volume's file is closed by its server too |
| rename, remove | in the initramfs, -3 if there's no such file; otherwise -4 (-8 to remove a directory). In a volume, as its server says; between two file systems, -10 |
| write | streams 1 and 2 go to the process's terminal, if it has one, at most 4091 bytes per call, waiting while its queue is full; otherwise to the kernel's stdout and stderr, at most 64 KiB per call. A stream open on a volume's file is written by its server, a message's worth a call; any other is -5 |
| exit | the process ends with that status |
| arg_count, arg | the process's arguments: those it was spawned with by `spawn_entry_with` or `spawn_image`, or else the inittab's `args` for its path |
| region | maps device registers for programs with a `dev` line, so `open_device` works, or for a range of the caller's DMA pages, returns where they are; -3 for any other |

### The kernel's own calls, 256 up

An *entry* is an index into the initramfs's entries, numbered from 0.

The kernel answers each call with a word, as the table's Result says. A
wrapper that can fail reads that word as a type of its own, whose
constructors are every answer the call can have, so a `match` on what it
returns must handle each of them: `port_send` gives a `Sending`, one of
`(Sent)`, `(SendNoPort)`, `(SendFull)` and `(SendTooBig)`. Each type has
an `X_of` that reads the word (`sending_of`), and some a `X_why` that
says a failure in words (`sending_why`, `spawn_why`). With no kernel
beneath, as under `l0 test`, every word is -3, which a wrapper reads as
its -3 answer if it has one (`SendFull`, `WatchFull`, `IrqAbsent`) and
otherwise as its type's first failure.

| # | Wrapper | Returns | Result |
|---|---|---|---|
| 256 | `l0s_yield` | `int` | 0, after the others have run |
| 257 | `l0s_pid` | `int` | the caller's pid |
| 258 | `port_new` | `int` | a new port, which only the caller may receive on |
| 259 | `port_send port payload` | `Sending`: `Sent`, `SendNoPort`, `SendFull`, `SendTooBig` | 0, or -1 no such port, -3 its queue (32) is full, -4 over 4096 bytes |
| 260 | `port_receive port` | `Message`: `Message`, `RecvFailed` | waits; `(Message sender payload)`, where sender 0 is the kernel |
| 261 | `port_try_receive port` | `Message` | the same, or `(RecvFailed)` at once if no message is waiting |
| 262 | `name_register port name` | `Registration`: `Registered`, `RegisterNoPort`, `RegisterTaken`, `RegisterTooLong` | 0, or -1 not your port, -2 the name is taken, -4 a name over 256 bytes |
| 263 | `name_lookup name` | `Lookup`: `Found`, `NotFound` | a port, or -1 (`name_await` retries with yields, `name_wait` with sleeps) |
| 264 | `spawn_entry e` | `Spawn`: `Spawned`, `SpawnNoEntry`, `SpawnNotProgram`, `SpawnTooBig`, `SpawnNoRoom` | a pid, or -1 no entry e, or the initramfs given up, -6 not a program, or not an ELF the kernel starts, -5 out of address spaces. `spawn_path` starts a program by its path, wherever `/` is |
| 265 | `wait_pid pid` | `Reaped`: `Reaped`, `WaitNoProc` | waits; the pid's exit status, or -1, which a status of -1 reads as too |
| 266 | `sleep_until t`, `sleep_ns n` | `int` | 0, once `clock_ns` reaches t |
| 267 | `irq_bind irq port` | `IrqBinding`: `IrqBound`, `IrqAbsent`, `IrqDenied`, `IrqNoPort`, `IrqTaken` | 0, or -6 no `dev` line for the program, -1 not your port, -2 already bound, -3 no such interrupt on the board. After this, each interrupt sends the message `irq_notice irq` to the port |
| 268 | `irq_ack irq` | `IrqAck`: `IrqAcked`, `IrqNotPending` | 0, ending the interrupt once the driver has quieted its device; -1 if it is not yours or not taken |
| 269 | `entry_path_of e`, `entry_is_program e` | `(list int)`, `bool` | the entry's path, with a final `/` for a directory, or empty if there is no entry e or the initramfs has been given up; the kernel follows a program's with a NUL and `x`. `entry_paths` lists them all, and `program_entry` finds a program by name; `root_paths` lists `/` wherever it is |
| 270 | `proc_kill pid` | `Kill`: `Killed`, `KillNoProc`, `KillDenied` | 0, ending pid with status 130, any process but the caller; -6 if pid's program has a `dev` line, -1 if there is no such process or it is the caller. Ending pid 1 stops the system with status 130 |
| 271 | `proc_watch pid port` | `Watch`: `Watched`, `WatchNoProc`, `WatchFull` | 0, and the kernel sends `exit_notice pid status` to the caller's port when pid exits, or at once if it has. -1 if there is no such pid, or the port is not the caller's; -3 if 32 ports watch pid already. `exit_of` reads the notice |
| 272 | `spawn_entry_with e args` | `Spawn` | as `spawn_entry`, but the process gets args (sent as `encode_args` writes them) in place of the inittab's; -5 if they are not well formed, -4 over 4096 bytes |
| 273 | `proc_info pid`, `proc_path pid` | `(Option ProcInfo)`, `(list int)` | a `ProcInfo`: state (`state_running` … `state_exited`), parent, the program's entry, -1 for one started from an image, a detail (the port or pid it waits on, or an exited process's status), and its pages of memory: its own (image, heap and stack, as far as it has touched them) and those at its device pages (shared and DMA memory, which other processes may map too); none if no process has that pid now: none has had it, or its slot has gone to another process (see [Processes and pids](#processes-and-pids)). After the record's 24 bytes, as many as there is room for, the program's path, its entry's or its image's, which `proc_path` reads. To list every process, ask `proc_slot` for each slot's pid |
| 274 | `dma_alloc n` | `DmaAlloc`: `DmaPages`, `DmaDenied`, `DmaTooMany`, `DmaNoRoom` | the address of n zeroed pages a device can reach, at the caller's next device pages; -6 no `dev` line, -4 n below 1 or over 16384 (64 MB, a 4K screen's buffer), -5 out of frames or device pages. They last until the system stops |
| 275 | `dma_address va` | `DmaWhere`: `DmaAddress`, `DmaAddressDenied`, `NotDma` | where a device reaches the caller's DMA page holding va, page aligned; -1 if no DMA page holds va, -6 no `dev` line |
| 276 | `tty_set port` | `TtyChange`: `TtySet`, `TtyNoPort` | 0, making port, a terminal, the caller's standard input, output and error, and those of every process it starts from then on; 0 gives back the kernel's own; -1 if there is no such port |
| 277 | `tty_get` | `Terminal`: `Terminal`, `KernelTerminal` | the caller's terminal's port, or 0 for the kernel's own |
| 278 | `shm_alloc n` | `ShmAlloc`: `ShmPages`, `ShmNoRoom`, `ShmTooMany` | the address of n zeroed pages to share, at the caller's next device pages, for any process; -4 n below 1 or over 16384 (64 MB, a 4K screen's buffer), -5 out of frames or device pages. They are freed once every process that maps them has ended, unless one of those drives devices |
| 279 | `shm_share va n pid` | `ShmShare`: `ShmShared`, `ShmShareNoProc`, `ShmShareTooMany`, `ShmShareFailed` | where pid sees the caller's n shared or DMA pages from va, now mapped into pid's next device pages too, the same frames; -1 no such pid, -4 n below 1 or over 16384 (64 MB, a 4K screen's buffer), -5 pages that are not the caller's, or pid out of device pages |
| 280 | `proc_slot i` | `Slot`: `SlotHeld`, `SlotUnused`, `NoSlot` | the pid slot i of the process table holds, live or exited, or last held; 0 if it has held none; -1 for no slot i, outside 1 to 255 |
| 281 | `shm_unmap va n` | `ShmUnmap`: `ShmUnmapped`, `ShmUnmapNotYours`, `ShmUnmapTooMany` | 0, the caller's n shared or DMA pages from va unmapped, each frame freed once no process maps it; -4 n below 1 or over 16384 (64 MB, a 4K screen's buffer), -5 pages that are not the caller's, when none is unmapped |
| 282 | `shm_revoke va n pid` | `ShmRevoke`: `ShmRevoked`, `ShmRevokeNoProc`, `ShmRevokeDenied`, `ShmRevokeTooMany`, `ShmRevokeNotYours` | how many mappings pid had of the caller's n shared or DMA pages from va, all now unmapped; -1 no such pid, -6 pid is the caller or drives devices, -4 n below 1 or over 16384 (64 MB, a 4K screen's buffer), -5 pages that are not the caller's |
| 283 | `fs_mount label uuid port` | `Mounting`: `Mounted`, `MountNoPort`, `MountTaken`, `MountBadLabel` | 0, the caller's volume label, of the partition whose UUID that is, as text, or none, mounted at `/Volumes/LABEL` from port, whose server is sent every call on a file there (see [Volumes](#volumes)) until the port goes; -1 not the caller's port, -2 the label is mounted already, -5 no label (1 to 15 letters, digits, `-`, `_`) or a UUID that is none |
| 284 | `mount_at i`, `mount_list` | `(Option MountInfo)` | mount i of the table, from 0, `/`: where it is, the port of its server, 0 for the kernel's own, and its partition's UUID, empty for none; none past the last. `mount_list` gives them all, and `fs_system_volume` the system volume's `/Volumes/LABEL` |
| 285 | `boot_args` | `(list (list int))` | the board's boot arguments, QEMU's `-append`, split at spaces; none under another operating system |
| 286 | `root_switch label` | `Switch`: `Switched`, `SwitchDenied`, `SwitchDone`, `SwitchNoVolume`, `SwitchBadLabel` | 0, the volume mounted as label made `/`, the system volume, for good, and the initramfs's bytes given up (see [Booting from a volume](#booting-from-a-volume)); -6 if the caller's program is not the initramfs's, -2 if `/` is a volume already, -1 if no such volume is mounted, -5 no label |
| 287 | `spawn_image path args image` | `Spawn` | as `spawn_entry`, but a program started from image, its bytes, named path, which `proc_path`, `ps` and the inittab's `args` know it by; given no args, the inittab's for path. It never drives a device. -6 for no image, or not an ELF the kernel starts, -4 the whole over 64 MB of image with the path and arguments, -5 bytes not laid out as `spawn_image_bytes` lays them |
| 288 | `mem_info` | `(Option MemInfo)` | a `MemInfo`: the pages processes' memory comes from, those given and those L0's `frame_free_count` says are left, about 765 MB with `-m 2G`, and how many of them are given, each process's own and every shared or DMA page once, however many processes map it; none under another operating system. What is not given is free; the kernel's page tables take from it, so the total moves a little |
| 289 | `fs_unmount label port` | `Unmounting`: `Unmounted`, `UnmountNotMounted`, `UnmountDenied`, `UnmountBadLabel` | 0, the volume label, which the caller mounted from port, unmounted: `/Volumes/LABEL` is in no volume from then on, and the label free; -1 if the port is not the caller's or mounted no such volume, -6 for the system volume, which is `/` for good, -5 no label |

Listening to a driver, `keyboard_listen`, `pointer_listen` and
`input_listen`, gives a `Listen`: `Listening`, `NoDriver` or
`ListenRefused`.

IPC is asynchronous. A send copies the payload into the port's queue and
returns at once. A receive blocks until there is a message, and is given the
sender's pid with it. A request that wants an answer carries a reply port:
see `request` and `request_reply` in `l0s.l0`, `server.l0`, and `user/sbin/echo`.

When a process exits or is killed, its ports, names, interrupt bindings and
open files go with it. Whoever waits for it is woken with its status, and
every port watching it gets a notice. Waiting with `watch` instead of `wait`
lets a process hear about an exit and other messages on one port. That is
how the shell waits for a job and for Ctrl-C at the same time.

## The programs

Each one is the usual three files, `NAME.l0`, `NAME_test.l0` and
`main.l0`, in a directory whose place says where the program goes in the
initramfs, so that the Makefile finds it there:

| Directory | What | In the initramfs |
|---|---|---|
| `user/bin/NAME` | a command: `sh`, `cat`, `disk`, `draw`, `hello`, `http`, `init`, `install`, `keys`, `nap`, `net`, `ping`, `random`, `spin`, `tftp`, `windows` | `/bin/NAME` |
| `user/sbin/NAME` | a driver or a service: `boot`, `uart`, `rtc`, `virtio-gpu`, `virtio-input`, `virtio-blk`, `virtio-net`, `virtio-rng`, `fs`, `inet`, `wm`, `echo` | `/sbin/NAME` |
| `user/apps/NAME` | an app, with its bundle's source `APP.app/` beside it: `vt`, `procmon`, `widgets`, `disks` (see [Apps](#apps)) | `/Applications/APP.app/NAME` |

A program may have more files of its own, each with its tests beside it,
as `sh` has `files.l0`, `wm` `launcher.l0` and `inet` `packet.l0`, `segment.l0`, `tcp.l0`, `tcpstack.l0`, `dhcp.l0` and `lease.l0`:
every `.l0` in its directory is part of it.

| Program | What it does |
|---|---|
| `boot` | the first stage's end, pid 1 of a two-stage inittab (see [Booting from a volume](#booting-from-a-volume)): given `root=UUID`, waits for that volume, makes it `/` if it holds `/etc/system`, and says so or why not; starts `/etc/system`'s programs by path, and exits with the first one's status |
| `sh` | the shell, on the terminal its argument names, `console` unless given (`sh vt1` is a window's): reads commands from it; runs programs by name or path, from `/` wherever it is or from a volume, on its terminal, and waits for them, with Ctrl-C for the foreground job; has busybox's commands on files, `ls`, `cat`, `write`, `append`, `cp`, `mv`, `rm`, `mkdir`, `df`, `format` and `unmount`, on the initramfs and the volumes alike; also `ps`, `kill`, `sleep`, `echo` and `exit`. Shows `/etc/motd` at start. Exits with status 129 if its terminal's process exits |
| `install` | `install VOLUME`: copies every directory and file of `/` but `/Volumes` onto the volume, a label or `/Volumes/LABEL`, marking each program's copy a program, and says the volume's UUID, for `root=`; refused for a volume not mounted, and for `/`'s own |
| `uart` | the serial line's terminal, `console`: a driver for the PL011 serial port. It takes receive interrupt 33, edits lines, echoes them (unless given `noecho`), and hands a line to each process that asks. Ctrl-C drops unread input and sends a lone byte 3 to the port that asked to hear of it. What it is sent to write, it writes to the serial line |
| `vt` | Terminal, a terminal in a window, `vt [COLS ROWS]`, 80×24 unless given. First thing, it registers as NAME, the first of `vt1`, `vt2`, and so on that no one has, which is also its window's title. Once its window is open it starts its own shell, `sh NAME`, and watches it: when the shell exits, `vt` closes the window and exits with the shell's status. The same line editing as `uart`'s, fed the characters of the keys `wm` sends while its window is in front. What it is sent to write, and the echo, it draws into its window's buffer, shared with `wm`, in the 8×16 font (at scale 2, cells of 16×32 in the face's Source Code Pro), in the toolkit's terminal colors, GNOME Console's white on `1e1e1e`. It scrolls by moving the buffer's top row, with `top`, and so copies nothing. Its cursor is a line along the last row of a cell, which no glyph uses. Each batch drawn is one `damage` |
| `cat` | writes the files its arguments name, through the ordinary `open_in`, the initramfs's or a volume's; reports each it can't read, and exits 1 if any |
| `hello` | prints its pid and arguments, and answers a line: typed at its terminal, with `console_line` |
| `init` | starts the programs its arguments name, from `/` wherever it is (`NAME&` runs one in the background), waits for the rest, and reports each one's status |
| `echo` | a server: registers as `echo` and sends every request's body back |
| `ping` | a client: finds `echo` by name and checks that N requests come back |
| `spin` | loops forever without a call; other processes still run, thanks to the timer |
| `nap` | sleeps for N ms and checks that the time passed |
| `rtc` | a user-space driver for the PL031 real-time clock: it maps the device, sets an alarm, receives interrupt 34 as a message, and acks it. `rtc clock` instead serves `clock`, the time, to whoever asks, and at the start of every minute to each process listening, as `wm` does; it looks for both every quarter of a second, and leaves the interrupt to `rtc` |
| `virtio-gpu` | a user-space driver for QEMU's virtio-gpu, serving the display protocol as `display` (see [The desktop](#the-desktop)). It finds the device among the 32 virtio-mmio transports and sets up its control queue and cursor queue in DMA pages. It makes the screen resource 1 on scanout 0, at the mode the device offers, and builds its backing from the layers' buffers, so the host composes the screen. Its `info` says the scale, 2 on a screen of 2560×1440 or more, or as the boot argument `scale=` says (see [A large screen](#a-large-screen)). It keeps every row of the backing, so a `layers` request builds again only the rows a layer that moved, scrolled or changed covers, and writes the backing's runs straight into the queue's memory. A `damage` is a transfer and a flush of that rectangle. The pointer is the device's cursor, resource 2. Until it is given layers, the screen is black. With no virtio-gpu on the board it says so on stderr and exits 0. It polls the queues rather than taking interrupts. If the device offers virgl, as QEMU's `virtio-gpu-gl-device` does, it composes the screen on the host's GPU instead: a texture for each buffer and copies of them onto the screen (`gl.l0`, `compose.l0`, `virgl.l0`; see [The desktop](#the-desktop)) |
| `virtio-input` | a user-space driver for QEMU's virtio input devices, started once a device. It keeps the event queue's 16 buffers in a DMA page and takes the device's interrupt as a message. `virtio-input keyboard` finds the device whose name holds `Keyboard`, serves `keyboard`, and sends each key event to every port that asked it to `listen`: a `KeyEvent` of the Linux key code, pressed, released or repeated, and the character it types on a US layout, with Shift and Caps Lock, and Ctrl with a letter as its control character. `virtio-input tablet` finds `Tablet`, serves `pointer`, and at each report's end sends a `PointerEvent`: x and y, 0 to 32767, and the buttons; before it, if the scroll wheel turned in the report (`REL_WHEEL`, `REL_HWHEEL`), a `WheelEvent` of its steps, down and right positive. With no such device on the board it says so on stderr and exits 0 |
| `virtio-blk` | a user-space driver for QEMU's virtio-blk, serving the disk protocol as `disk` (see [The disk](#the-disk)). It finds the device, reads its capacity from its config, and sets up its request queue in one DMA page. Each `read` or `write` it checks against the disk's size and the pages the client shared, then has the device move the sectors straight into or out of those pages, a descriptor a page, and waits for the device's interrupt, on a port of its own. It accepts FLUSH, for `flush`, and RO, refusing a read-only disk's writes itself. With no virtio-blk on the board it says so on stderr and exits 0 |
| `virtio-net` | a user-space driver for QEMU's virtio-net, serving the nic protocol as `nic` (see [The network](#the-network)). It finds the card, takes its address from its config, sets up its receive and transmit queues in DMA pages, and takes its interrupt as a message: each frame the card takes it tells every port that asked it to `listen`, and each frame it is sent it copies into its transmit buffer and waits for the card to take. With no virtio-net on the board it says so on stderr and exits 0 |
| `virtio-rng` | a user-space driver for QEMU's virtio-rng, the entropy device, which draws on the host's `/dev/urandom`, serving the random protocol as `random` (see [Randomness](#randomness)). It finds the device, sets up its one queue of 8 entries in a DMA page, and for `bytes N` offers the device a buffer to fill, again until it has N, waiting for each as `virtq_wait` does. With no virtio-rng on the board it says so on stderr and exits 0 |
| `inet` | the IPv4 stack, `inet dhcp` or `inet [ADDR/PREFIX [GATEWAY [DNS]]]`: the address, netmask, router and name server a DHCP server gives it, its lease renewed and rebound as the clock's minutes pass, or those given, 10.0.2.15/24 behind 10.0.2.2, with 10.0.2.3 as the name server, by default (see [The network](#the-network)): a client of `nic`, which answers ARP and ICMP echo requests, keeps the neighbours ARP finds, routes to the link or the gateway, gives UDP datagrams to the clients bound to their ports, and sends their datagrams and echo requests, serving the inet protocol as `inet`. With no `nic` within 5 seconds it says there is no card and exits 0 |
| `net` | a client of `inet`: `net` shows the interface, `net stats`, `net arp`, `net dns` and `net tcp` what `inet` counts and knows (the last, its TCP connections and listeners), `net resolve NAME [SERVER [PORT]]` resolves a name, `net ping [-q] HOST [COUNT]` pings, a second apart, and says how long each reply took, failing if none came, `net send HOST PORT TEXT...` sends a datagram, `net recv PORT` waits for one and shows it, and `net echo PORT` listens to a TCP port and sends back what its first connection sends. A HOST is a name, resolved first, or an address |
| `http` | a client of `inet`: `http [-i] [http://]HOST[:PORT][/PATH]` fetches a page over HTTP/1.0 (RFC 1945) through TCP, and writes its body, and with `-i` its header first; says the status, after the page, if it is not 2xx, and fails; HOST is a name, which `inet`'s name server resolves, or an address |
| `tftp` | a client of `inet`: `tftp HOST FILE [PATH]` fetches FILE over TFTP (RFC 1350), from a host named or dotted, in blocks of 512 bytes each acknowledged, asking again for one that does not come within a second, and writes it to PATH or standard output; says what the server says if it refuses |
| `random` | a client of `random`: `random [N]` writes N bytes of the entropy device's, 16 if not given, 1 to 1024, as hex digits and a newline, waiting a second at most for the driver to register; fails, saying why, without one |
| `disk` | a client of `disk`: `disk info` prints its size; `disk read SECTOR [COUNT]` prints COUNT sectors, 1 unless given, as `hexdump -C` does, a `*` for repeated lines; `disk write SECTOR WORDS...` writes the words, spaced, and a newline as sector SECTOR, zeros after them. A refusal goes to stderr, with status 1 |
| `fs` | the file server (see [Volumes](#volumes)): a client of `disk`, which mounts each volume of L0S's file system on the disk at `/Volumes/LABEL`, with its partition's UUID, and serves the fs protocol for them, the kernel's requests for every program's file calls there, in directories at any depth, and `list`, `mkdir`, `stat`, `chmod`, `df`, `format`, `unmount`, `rescan`, `partition` and `mkfs`; then registers as `fs`, though the disk has no volume, or no partition table, yet. It reads the disk's GPT, and makes partitions in it, each with its UUID, and volumes on them, the disk's only writer. With no disk it says so on stderr and exits 0 |
| `wm` | the compositor (see [The desktop](#the-desktop)): waits for `display`, `keyboard` and `pointer`, and a second for `clock`, paints the wallpaper on the desktop, sets the pointer's arrow, draws the top bar, reads every app's manifest and paints the launcher's page of them, and serves `compositor`. Its top bar names the front window's app; its launcher starts apps. At scale 2 it lays the desktop out at half the screen's size each way and draws it at the screen's resolution. It needs no `dev` line |
| `windows` | a client of `compositor`: prints its `windows` reply, the windows front first and where the pointer is |
| `draw` | a client of `compositor`: sends it `desktop` and the command its arguments make (`line`, `circle`, `disc`, `rect`, `fill`, `clear`, `char`, the toolkit's `round`, `button` and `icon X Y NAME [SCALE [COLOR]]`, `splash`, `restore`, `size`, `font`), which `wm` draws on the desktop. Colors may be Adwaita's by name (`blue_3`, `dark_4`, `accent`…). It checks the command with the toolkit's parser first, so a bad one fails without asking `wm`. It prints the size, or the error on stderr with status 1. With no arguments it lists the commands |
| `widgets` | Widgets, the toolkit's gallery ([user/lib/ui](user/lib/ui/README.md)): a window with a toolbar (Refresh, and End Process, sensitive only with a row selected) over a data grid of sample processes, sortable by any column, selected by click or the arrow keys. It's the scaffolding for a process monitor; it reads no real processes and ends none |
| `disks` | Disks, `run disks &`, as GNOME Disks is: a sidebar of drives; the drive's model, size and partitioning; a bar of its partitions and the free space between them, each as wide as its share of the disk, one selected by click or Left and Right; and the selected part's size, usage, files, contents, partition type, partition UUID and sectors. It reads the GPT and each partition's first sector through `disk` itself, so a partition no server serves still shows, and asks `fs` how full each mounted volume is, through one reply port. Refresh has `fs` `rescan` and reads the disk again. Under the bar, one button for the selected part: on free space, Create Partition... asks its size in kB, all the free space unless another is typed, with the space it leaves said as it is typed, then has `fs` `partition` it there and selects the new partition; on a mounted volume, Format Volume... asks in a dialog, then has `fs` `format` it; on any other partition, Format... asks the new volume's name, a label `fs` will take, and has `fs` `mkfs` it by the partition's UUID, mounted at `/Volumes/NAME`. Each dialog's entry has the focus as it opens, and Enter is its button; a refusal is said in the line at the foot. With no disk it shows a status page |
| `procmon` | System Monitor, the process monitor, `run procmon &`: a toolkit window with the kernel's process table in a data grid (pid, program, state and its detail, parent, and its memory: its own, and what it shares or a device reaches), read again every second and on Refresh, sortable by any column, and under it the memory processes are given, from `mem_info`: how much is used of how much, with a level bar, and how much is available. When there are more rows than fit, the scroll wheel scrolls them, three a step, and so does dragging the overlay scrollbar's slider, or pressing its strip. End Process, sensitive with a row selected, ends that process as `kill` does; a driver cannot be ended |
| `keys` | a client of `keyboard`, for checking `virtio-input`: echoes each printable character typed in QEMU's window to its terminal, Enter as a newline and Backspace as a rub-out, until Esc |

The libraries are in `common/`, shared by the kernel, every program and
the host tools, and in `user/lib/`, grouped by what they are: `sys/`, the
kernel's calls and what programs do alike; `proto/`, the protocols of
the servers, as their clients speak them; `format/`, data as bytes,
pure, which the host tools link too; `gfx/`, drawing; and `ui/`, the
toolkit. Each is linked into every program (`ULIB`), or into those that
need it, by the Makefile's `LIBS_` lists. L0 has one namespace, so a
name in a library is taken in every program that links it.

| Library | What it holds | Linked into |
|---|---|---|
| [common/abi.l0](common/abi.l0) | what the kernel and its processes agree on: the calls' numbers, error codes, limits, the address space, bytes least significant first, the arguments' encoding, a volume's label, lists to arrays and back | the kernel, every program, the host tools |
| [common/text.l0](common/text.l0) | lists and strings as the standard library lacks them: `nth`, `take`, `drop`, `last`, `concat`, `repeat`, joining and splitting words and lines, `up_to`, padding, `is_number` and `word_number`, `ceil_div`, `format_size` (a size as GNOME says it, `782.3 kB`) | the kernel, every program, the host tools |
| [common/initramfs.l0](common/initramfs.l0), [queue.l0](common/queue.l0) | the cpio archive the kernel boots with; a queue | the kernel, every program |
| [sys/l0s.l0](user/lib/sys/l0s.l0) | the call wrappers; requests, and asking a server (`port_ask`, `reply_why`); shared memory (`shm_region`, `shm_share_to`); `KeyEvent`, `PointerEvent`, `WheelEvent` and listening for them; the compositor's leave and focus notices; `name_wait`, which waits for a server to register; `fs_mount`, `fs_unmount` and the mount table; the boot arguments, `root_switch` and `spawn_image` | every program |
| [sys/paths.l0](user/lib/sys/paths.l0) | the files of `/`, wherever it is: `root_paths` lists them, `program_found` finds a program among them, `path_is_program` says whether a file is one, and `spawn_path` starts one, from the initramfs's entry or a volume's file (`PATHS`, with `proto/fs.l0` and `uuid.l0`) | `sh`, `init`, `install`, `boot`, `wm`, `vt` |
| [sys/server.l0](user/lib/sys/server.l0) | what servers do alike: taking a name and an interrupt, or saying why not; a request's op and numbers; `Served`, ok and error answers, and answering a request; the ports listening, told in order | every program |
| [sys/cli.l0](user/lib/sys/cli.l0) | what programs and tools do alike: `complain_as` and `note_as`, `say`, a number argument, a file read or written whole | every program, the host tools |
| [sys/procs.l0](user/lib/sys/procs.l0) | the live processes, and a state in words, as `ps` says it | `sh`, `procmon` |
| [sys/tty.l0](user/lib/sys/tty.l0) | a terminal's line editing and protocol | `uart`, `vt` |
| [sys/virtio.l0](user/lib/sys/virtio.l0) | the transports' registers, finding a device and making it ready (`virtio_probe`, and with the device's own features a driver wants, `virtio_probe_features`), a queue's memory and rings, offering it requests (`virtq_offer`) and waiting for them (`virtq_wait`), the used ring's entries, descriptors and runs of memory | `virtio-gpu`, `virtio-input`, `virtio-blk`, `virtio-net`, `virtio-rng` |
| [proto/display.l0](user/lib/proto/display.l0) | the display protocol, as a client sends it, in the desktop's pixels, made the screen's at the scale `info` says; its rectangles are `rect.l0`'s | `wm` |
| [proto/wm.l0](user/lib/proto/wm.l0) | the compositor protocol, as a client sends it, and the scale `hello` says; its rectangles are `rect.l0`'s | `vt`, `windows`, `draw`, `widgets`, `procmon`, `disks` |
| [proto/clock.l0](user/lib/proto/clock.l0) | the clock protocol, and the date and time as the top bar shows them | `rtc`, `wm`, `fs`, `inet` |
| [proto/disk.l0](user/lib/proto/disk.l0) | the disk protocol, as a client sends it, its flush too, and a buffer shared with the driver to move sectors through | `disk`, `fs`, `disks` |
| [proto/random.l0](user/lib/proto/random.l0) | the random protocol: its request and reply, and `random_bytes` and `random_word`, which ask `virtio-rng` for bytes and do without when it is not there (`RANDOM`) | `virtio-rng`, `random`, `fs`, `inet` |
| [proto/fs.l0](user/lib/proto/fs.l0) | the fs protocol: its replies, and `list`, `mkdir`, `stat`, `chmod`, `df` and `format` as a program sends them, to the port the mount table gives, and `rescan`, `partition` and `mkfs`, to `fs`'s; `_on` versions take a reply port the caller keeps; the system volume, and a path of it as its server knows it | `fs`, `disks`, and every program `PATHS` is in |
| [proto/nic.l0](user/lib/proto/nic.l0) | the nic protocol: frames as notices and as requests to send, and Ethernet's addresses as text (`NICLIB`) | `virtio-net`, and with `INETLIB` |
| [proto/inet.l0](user/lib/proto/inet.l0) | the inet protocol, as a client sends it: the interface, binding a UDP port, sending a datagram, pinging, opening, listening to, writing to and closing TCP connections, and reading the notices of datagrams, echoes' replies and connections' events; resolving a name, `inet_resolve`, by asking the interface's name server over UDP; and IPv4's addresses as text and as netmasks (`INETLIB`, with `nic.l0` and `dns.l0`) | `inet`, `net`, `tftp`, `http` |
| [proto/app.l0](user/lib/proto/app.l0) | apps: a bundle's manifest, read and checked; the bundles in `/Applications`, wherever `/` is; the app whose program is at a path; and an app's program, found by its bundle's name | `sh`, `wm` |
| [format/uuid.l0](user/lib/format/uuid.l0) | UUIDs, RFC 9562: their text, GPT's byte order, and new ones of version 7, the time in milliseconds then noise | `fs`, `disks`, `tools/mkfs`, and every program `PATHS` is in |
| [format/dns.l0](user/lib/format/dns.l0) | DNS's messages, RFC 1035: the query for a name's IPv4 address, and the first A record read out of an answer, past CNAMEs and name pointers (`DNSLIB`, in `INETLIB`) | with `INETLIB` |
| [format/crc32.l0](user/lib/format/crc32.l0) | CRC-32, as zlib and GPT reckon it | `fs`, `disks`, `tools/mkfs` |
| [format/gpt.l0](user/lib/format/gpt.l0) | the GUID partition table, as bytes: the protective MBR, the header and entries and their backup, checked by CRC-32; the partitions and the free space between them, in order (`gpt_layout`); and where a new partition fits | `fs`, `disks`, `tools/mkfs` |
| [format/l0fs.l0](user/lib/format/l0fs.l0) | the file system on a partition, as bytes: a volume's superblock, cluster table and directories, their layout, paths walked through directories, making, growing and removing them, allocating clusters, which clusters a read or a write touches, walking a chain on from a place in it, and which sectors of the metadata and directories a change touches | `fs`, `disks`, `tools/mkfs` |
| [format/ppm.l0](user/lib/format/ppm.l0) | binary PPM images, read and written, and colors' channels | every program that draws, `tools/mksplash`, `tools/mkicon` |
| [gfx/rect.l0](user/lib/gfx/rect.l0) | `Rect`, x, y, width and height, the one rectangle of the screen, the protocols and the toolkit: its clip, union, overlap and inset, whether it holds a point, its place at a scale (`rect_scaled`), and its numbers in a damage request; and damage's rectangles merged until no two overlap (`rect_merge`), as both a window and the display driver send and show them | with `render.l0` (`RENDER` holds `RECT`), and `windows`, which links `proto/wm.l0` alone |
| [gfx/render.l0](user/lib/gfx/render.l0) | drawing on a canvas, a shared buffer of pixels or, for host tools and tests, an array (`canvas_new`), each drawing returning the canvas drawn on: shapes, the font, the wallpaper, a corner's cut, and `draw`'s commands | `virtio-gpu`, `wm`, `vt`, `draw`, `widgets`, `procmon`, `disks`, `tools/mkicon` |
| [ui/](user/lib/ui/README.md) | the toolkit, in Adwaita's look: theme, icons, the face it draws text, icons and the pointer with at scale 2 (`face.l0`), painting at either scale, the data grid and a page of one, panes (a sidebar, a segment bar, property rows, an alert dialog, and one that asks for something), a text entry with a cursor, the desktop's drawing commands (`UI_CORE`), and client windows (`UI_WINDOW`) | `wm`, `vt`, `draw` (`UI_CORE`); `widgets`, `procmon`, `disks` (both) |

## Tests

| Command | What it runs |
|---|---|
| `make check` | `l0 check` of the kernel, every program with its libraries, and the host tools; then `l0sdoc --check`: every file read by `make doc` starts with `; FILE.l0 -- summary`, and every form has a `;` block, its own or its group's, except those [tools/l0sdoc/undocumented.txt](tools/l0sdoc/undocumented.txt) lists from before the check. A listed form documented since fails it too, until `make doc-prune` takes its line off, so the list only shrinks |
| `make test` | `l0 test` on this host: every pure module, the user library, and each program's logic. It first has `bsdtar` make `build/sample.cpio`, so the parser is tested on a real archive. Last, `python3` runs the MCP server's tests of what it parses and encodes (`tools/l0s-mcp/test_board.py`) |
| `make test-virt` | `l0 test --target virt`: the kernel booted on the board, once per test, from initramfses built in L0 (`kernel/asm.l0`) holding hand-assembled threads, each an ELF of its code and a bss up to `0xC0400000`. Covers exit, demand paging, faults, bad buffers, files, devices, DMA, shared memory, terminals, IPC, spawn and wait, preemption, deadlock, freed memory and spaces, shared pages given up and taken back, mounts with their UUIDs and the file calls a volume's server answers, its request, its answer, and its going, the boot arguments, a volume made `/` and the initramfs given up, programs started from images, ELF images (`asm.l0`'s `elf_image`) mapped by their segments' flags, a bss past 4 MB, and images refused for another CPU or bad headers, and the fuzz tests |
| `make e2e` | real L0 processes under the real kernel (`tests/e2e.sh`), then the screen (`tests/gpu-screen.sh`), a 4K screen drawn at scale 2 (`tests/hidpi.sh`), the keyboard (`tests/keyboard.sh`), the windows, their terminals and shells (`tests/vt.sh`), the toolkit's gallery (`tests/widgets.sh`), the process monitor (`tests/procmon.sh`), Disks (`tests/disks.sh`), a partition and a volume made with Disks (`tests/disks-create.sh`), and partitions made and volumes made on them, by UUID (`tests/partitions.sh`), and the launcher, opened and closed, starting Terminal, which the top bar then names (`tests/launcher.sh`) |

Each case of `tests/e2e/` is a directory:
- `etc/`, with its `inittab` and any other files;
- `expected`, its standard output; or `pattern`, for output that
  differs every boot, an extended regular expression its one line must
  match whole;
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
  host's loopback, chosen for the boot.

`tests/e2e.sh` builds each case's initramfs from every program and its
`etc`, boots it, and compares. Twenty-three cases type a session through
[tools/slowtype](tools/slowtype), which pauses after each line and each
Ctrl-C as a person would:
- `shell` includes a backspace, Ctrl-U and an arrow key;
- `jobs` covers Ctrl-C at a foreground job, at a `wait`, and at the prompt,
  and `kill` of the shell's own job and of a driver, which is refused;
- `kill` ends `spin`, which the inittab started, not the shell, and is
  refused `uart`, a driver;
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
- `dirs` makes directories on a volume, nested, writes, lists, moves and
  removes in them, is refused a directory where one is, in one that is
  not, the removal of one with something in it, and one in the
  initramfs; and runs `hello` copied onto a volume, its copy marked a
  program, and is told a text file copied there is not one;
- `install`, on a disk of 16 MB whose layout gives System a known UUID,
  has `install` copy the initramfs onto it, lists and reads the copy,
  runs `hello` from it, and is refused a volume not mounted and no volume;
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
  [tests/e2e/net/tftp](tests/e2e/net/tftp), starts `virtio-net` and
  `inet`, and has `net` show the interface, ping the gateway, which ARP
  finds first, and show what ARP found; `tftp` fetch a file of one block
  and one of four full blocks, which the server ends with an empty
  one, and be told of a file the server does not have; and `net` ping `inet`'s own address;
- `dhcp`, on a QEMU user network of 192.168.7.0/24 whose server offers
  192.168.7.50, starts `inet dhcp`, and has `net` show that address, the
  netmask and the router, which only the server's ACK can have given it,
  and the name server, 192.168.7.3, ping the router, and show what ARP
  found;
- `dns`, with [a small name server](tests/e2e/dns/server.py) on the
  host's loopback, has `net dns` show the interface's name server, and
  `net resolve` ask the host's for a name with an address, an alias of
  it, answered with a CNAME and then the address, a name with no
  address, and one it does not know; and take an address as it is;
- `http`, with [a small server](tests/e2e/http/server.py) on the host's
  loopback, has `http` fetch a page, the same with its header, one of
  300 lines, more than a window holds, and one that is not there, said
  to be after the page, and be refused by a port nothing listens to; and
  `net tcp` show no connection is left;
- `net_echo`, with a forward from a port of the host's loopback to port
  7000 of the board, has `net echo` listen to it, take the connection
  [a client on the host](tests/e2e/net_echo/peer.py) makes, which sends
  12000 bytes and closes its end, and send them back, which that client
  checks; and `net tcp` show no connection is left.

`files` reads the initramfs through `cat`. `virtio-gpu_nodev`,
`virtio-blk_nodev` and `virtio-net_nodev` start a driver with no `dev`
line, which is refused the device, `virtio-blk_nodisk` the disk's driver
on a board with no disk, `fs_nodisk` the file server there,
`virtio-net_nocard` the network's driver on a board with no card, and
`inet_nocard` the stack with no driver, and `virtio-rng_nodev` the
entropy device's driver on a board with none, none of which is a
failure. `virtio-blk_ro` has `disk` write to a read-only disk, which the
driver refuses itself, having learnt it from the device, and
`virtio-rng` has `random` ask the driver for 1024 bytes, 2048 hex digits
of a line, which its `pattern` checks. `garbage`
and `noinit` check that a boot without a valid archive or inittab is
refused with a message. Every boot has a virtio-gpu, which no window
shows, a virtio keyboard, a virtio tablet, and a virtio-rng unless the
case has a `norng` file; only a case with a `disk`
file has a virtio-blk, and only one with a `net` file a virtio-net.

[tests/gpu-screen.sh](tests/gpu-screen.sh) boots the initramfs of
[tests/screen/etc](tests/screen/etc/inittab), the demo's without its
windows, which would cover the wallpaper, with QEMU's monitor on a socket
and the serial line on a FIFO. It checks pixels of a `screendump` at each
step, all of them from the compositor's desktop buffer, composed by the
host:
- the wallpaper: the corner, its ground color, and a pixel of the L of
  "L0S", where centering on a 1280×800 screen puts it, both at 70%;
- after typing `run draw line 0 32 1279 799 red`, both of the line's ends;
- after typing `run draw circle 640 400 300 cyan`, its left and right
  edges.

[tests/hidpi.sh](tests/hidpi.sh) boots the same on a 4K virtio-gpu,
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

[tests/keyboard.sh](tests/keyboard.sh) boots the same way, types
`run keys` at the serial line, then presses `h`, `i`, Shift-1, Space,
Shift-A and Enter on the virtio keyboard with the monitor's `sendkey`, as
typing in the window would. It checks that the serial line shows `hi! A`,
and that after Esc the shell runs the next command typed.

[tests/vt.sh](tests/vt.sh) boots the demo's own initramfs (`make
vt-initramfs`), every shell running, but with two Terminals whatever the
demo's `/etc/system` starts after its first ([tests/vt/etc/system](tests/vt/etc/system)), with QMP on a socket as well, to work the tablet. Which `vt`
opens first, and so where each window is, varies, so it learns where they
are from `run windows` at the serial shell. Then:
- the title bars: the front window's header bar active, `ebebeb`, the
  other's in the backdrop, `fafafa`; and the front window's top left
  pixel, cut by its shape, showing what is under it;
- once the front window's prompt's cursor is drawn, `echo hi`, typed with
  `sendkey`: the screendump shows the `h` of the answer on its row 8,
  under the motd, the banner and the prompt;
- `run nap 30000 &`: `ps` at the serial shell shows `nap`, its parent
  that window's shell, whose parent is the window's `vt`;
- a click on the other window's title bar, through QMP's
  `input-send-event`: it comes to the front, as `run windows` and its
  title bar's color show;
- a drag of its title bar: `run windows` shows it moved as far as the
  pointer did;
- `run cat /etc/inittab` typed into it three times, more than its 24
  rows: it scrolls, and the prompt's cursor ends on its last row;
- `exit` typed into it: its shell ends, and so does its `vt`, which
  closes the window. `run windows` shows only the other, in front, and
  `ps` shows neither process;
- a click on that one's close button: `run windows` shows no window, and
  `ps` shows neither its `vt`, which was killed, nor its shell, which
  hung up.

[tests/widgets.sh](tests/widgets.sh) boots the screen initramfs, types
`run widgets &`, and learns where the gallery's window is from
`run windows`. Then, by screendump:
- its header bar, active;
- the toolbar on the window's ground, the line under the grid's header,
  and End Process faded, with no row selected;
- a click on the second row, through QMP: the press and release go
  through `wm` to the window, and the row is tinted with the accent and
  End Process turns red.

[tests/procmon.sh](tests/procmon.sh) boots the screen initramfs, types
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

[tests/disks.sh](tests/disks.sh) boots
[tests/disks/etc](tests/disks/etc/inittab), the screen tests' with the
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

[tests/disks-create.sh](tests/disks-create.sh) boots the same, on a
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

[tests/partitions.sh](tests/partitions.sh) boots the same, with `rtc
clock`, on a disk `build/mkfs` makes with room between its volumes, and
at the serial shell: `partition 400`, which says a UUID of version 7
that begins with the clock's time; `mkfs` of that UUID, whose volume is
listed in `/Volumes`, holds a file written to it, and is counted by
`df`; a second `mkfs` of it, refused; and, booted again on the same
disk, the volume mounted at once, its file there, and the UUID still
naming its partition.

[tests/launcher.sh](tests/launcher.sh) boots the screen tests' initramfs
and clicks the top bar's Applications with the tablet: the launcher
opens, Applications on its pill and the page's ground showing, and
Terminal's icon, its dark square, in the grid's third cell. Esc closes
it, and so does a click on the page. A click on Terminal starts it: `run
windows` lists `vt1`'s window, in front, and the top bar names it
Terminal, a lit pixel of the `T`, where its title, `vt1`, would show none.

Every boot is killed after a minute by [tools/deadline](tools/deadline),
since macOS has no `timeout`. `tests/e2e.sh` also builds three programs
of a few aarch64 instructions each, each an ELF of one code segment it
writes with `printf`, for what L0 code cannot do on purpose: fault, pass
a bad buffer, and wait on nothing.

## Limits

- **At most 255 processes alive at once**, the table's slots (see
  [Processes and pids](#processes-and-pids)), and a status no one asked
  for is lost once 255 newer processes have needed its slot.
- A process's image, heap and stack pages stay mapped until it ends. Its
  runtime reuses what it frees within its own heap, but L0's runtime has
  no way to tell a kernel which pages it no longer needs, so the kernel
  cannot unmap them while it runs. Only shared and DMA pages can be given
  up or taken back early.
- A device page given up returns to the process's pool of device pages
  only if it was the last given; otherwise its address is not used again,
  and a process that gives up pages out of order can run out of its 384
  MB of them though its memory is freed. At scale 2 every window's
  buffers are four times as many pages, so `virtio-gpu`, which maps them
  all, gets there four times as soon.
- **A screen's backing is at most 15,870 runs**, what the virtio-gpu's
  control queue of 64 entries can carry in one request. A 4K desktop
  whose pages are all apart, with a 1280×800 window over it, at scale 2,
  takes 10,500; more windows over pages apart could reach the limit, and
  the driver then says the screen is in too many pieces. Pages given
  together usually lie together, and their runs join.
- **Nothing is drawn by the GPU.** With virgl (the GL device) it copies
  the layers into the screen, and in 2D mode the host composes them
  from the clients' pages, but every pixel in them is painted by the
  guest's CPU, at scale 2 four times as many. Nothing is blended.
- **The screen tests run in 2D mode** (`GPU=2d`, the default of
  `tools/qemu-boot.sh`): `screendump` fails with "no surface" on a GL
  scanout. The 3D mode is tried by `make demo`.
- One CPU, and round-robin scheduling with 10 ms slices. A process woken by
  a message runs at the end of the current slice, not at once.
- **The initramfs is read-only.** Nothing in it can be written, renamed
  or removed. Booted from it, the apps are fixed at boot: the launcher
  shows the bundles in `/Applications` as `wm` started, and an app copied
  to another volume is not one. There is no current directory, so a relative path is taken
  from `/`. No call lists a directory: the initramfs's are `entry_paths`,
  which lists everything, and a volume's its server's `list`; `root_paths`
  lists `/` either way, a system volume a directory at a time.
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
- **The volumes are small and simple** (see [Volumes](#volumes)). Their
  directories hold names of at most 55 bytes with no spaces, and a
  program mark, but no other permissions, owners or times; a directory
  never shrinks; a volume has at most 65534 clusters of 4 KB; and a disk
  at most the GPT's 128. One
  file server, `fs`, serves the first disk's volumes, one request at a
  time, and a read moves at most 4092 bytes, what a reply holds. A
  write is as safe as the order it is made in, its data, a flush, and
  then the metadata, and no more: a crash between the two loses the
  write's changes to the file's size and chain; on a volume whose
  metadata is more than a cluster, a crash between the table's sector
  and the directory's leaves the two disagreeing, and `fs` refuses the
  volume rather than follow it; and nothing flushes the metadata after
  it, so a write answered may still be in the disk's cache. A flush
  each write costs what the host's sync does. A file open
  cannot be removed or renamed over, where Unix would let it go once
  closed. Any process may mount a label no one has, as any may register
  a name. `unmount`, as a rescan, is refused while any file is open, on
  any volume, since a handle names its volume by where it is among
  `fs`'s; and the system volume is never unmounted, though a rescan no
  longer finds it. Nothing removes or resizes a partition.
- **A UUID's time is local, and its noise needs the device.** The board's
  clock, `rtc clock`, keeps this machine's local time, not UTC, so a
  UUID's time is off by its zone, 0 where no clock runs. Its noise is the
  entropy device's, but on a board with no virtio-rng a mixer's, seeded
  from the clock, which can be guessed.
- **The disk is one virtio-blk, one request at a time.** `virtio-blk`
  drives the first disk on the board and moves at most 128 sectors a
  request. It waits for the device's interrupt with no timeout, so a
  device that never answers holds it, and every client of the disk,
  for good.
- **The network is one card, IPv4's datagrams and a small TCP.**
  `virtio-net` drives the first card on the board, sends one frame at a
  time and waits for the card to take it, and accepts no feature but
  its address, so it neither offloads checksums nor merges buffers.
  `inet` has one interface, set by its arguments or by DHCP, which
  takes no other options than the mask, the first router and the first
  name server. Its lease is looked at only when `rtc clock` tells it a
  minute has begun, so with no clock running it is never renewed, and
  a lease shorter than two minutes runs out before it is; one taken
  away leaves the clients' sockets and connections bound to an address
  that is gone. A name is resolved by each client, with no cache, to
  its first IPv4 address only, from one name server, over UDP alone, so
  an answer cut short is not asked again over TCP; while it waits the
  resolver drops anything else that comes to its client's port, and
  its query's id is the clock's. It neither
  fragments nor takes fragments, so a datagram holds at most 1472 bytes;
  it has no IP options, and passes over every protocol but ICMP, UDP
  and TCP, without saying so; and it keeps at most 64 neighbours,
  starting again from one when it has as many, and 16 datagrams waiting
  for ARP, for 3 seconds. Any process may bind any port no one holds,
  and send from any port, bound or not.
- **TCP has the essentials, and little else.** `inet` holds 32
  connections, each with at most 16384 bytes of the client's data not
  yet acknowledged (more resets it), and offers a window of 8192 bytes
  that never changes. At most 16 segments that arrive out of order are
  held, within the window; one more is dropped, and asked for again once
  those before it come. The retransmission timeout
  is 1 second, doubled each time, whatever the round trip is, and every
  segment is acknowledged at once. There is no congestion control, no
  selective acknowledgement, window scaling, timestamps, urgent data,
  nor simultaneous open, and no MSS but the peer's SYN's; ICMP's errors
  do not end a connection, only the retransmissions' running out does
  (after 47 seconds). A client must take its notices as they come: if its
  port holds 32 messages, `inet` resets the connection that
  overflows it. Notices carry what came in the segments it came in, at
  most 1460 bytes each, so a client sees no message boundary of the
  sender's. A connection's owner is the pid that opened it, which is all
  the check there is. The first sequence number's offset is L0's `hash`
  of the ends and the secret, which is no cryptographic hash, and on a
  board with no virtio-rng there is no secret, so the first sequence
  number is the clock's, and guessable.
- **Disks shows the one disk, and cannot take anything away.** It can
  make a partition of free space, give a partition a new volume, format
  a mounted volume, keeping its label and size, and have `fs` rescan;
  it cannot delete, resize or relabel a partition or a volume, nor
  choose a partition's type or name. Sizes are typed in kB, whatever the
  disk's size. Its window is a fixed 880 by 520, as every window is, and
  it reads the disk only when it opens and when asked.
- **A text entry does not scroll or select.** Its text is cut short with
  `...`, so an entry is made as wide as what it will hold, and there is no
  selecting, copying or pasting.
- Images are copied from the archive, or a volume's file, into fresh
  frames for every process that runs them. Only pages made with `shm_alloc` or `dma_alloc` can be
  shared, and a share cannot be taken back from a driver.
- A terminal is shared by every process on it: their output interleaves,
  and lines typed go to whoever asks first. A process with no terminal,
  one the inittab starts, writes to the kernel's own stdout, and its
  standard input, the inittab's `stdin` file, has one cursor for all.
- Output a terminal has not yet taken when pid 1 exits is lost, since the
  system stops at once. A shell writes its prompt before it reads, so a
  typed session ends cleanly.
- A window's terminal has no scrollback, and draws only what is written:
  it keeps no copy of its text.
- Windows cannot be resized. `wm` opens two regions for each window,
  its title bar's and its frame's, and the proc runtime closes none and
  keeps at most 64 open, so `wm`, which keeps four of its own (the
  desktop, the pointer, the top bar and the launcher), can open only so
  many windows over its life, closed ones included. The close button kills its client at
  once: the client is not asked first, and cannot refuse. The pointer has
  one button that does anything, the left.
- The display driver attaches a whole new backing, a run list of some
  thousands of entries, for every raise, move or scroll, though it builds
  again only the rows that changed. A rebuild takes about 15 ms with two
  windows on QEMU, so a drag shows a few dozen positions a second, not
  every one.
- Interrupts the kernel enables stay enabled (L0 cannot disable one). If a
  driver exits while its device keeps the interrupt raised, the kernel ends
  each one as it comes.
- Only ELF images run: a raw one, as toolchains before L0's roadmap item
  0093 wrote them, is refused, so programs built by one must be built
  again. An image's pages are copied for each process, and none is shared
  between processes running the same program, its code and rodata
  included.
- Instruction-cache maintenance after loading an image is left to the board's
  host file. This is fine under QEMU.
- A failed receive reports no reason. `supervisor_receive` gives no bytes
  when the kernel's word is negative (spec §6.15), so `RecvFailed` stands
  for every failure, and for no message yet.
- `wait_pid`'s word is a status or -1 for no such process, so a process
  that exits with -1 reads as `WaitNoProc`.
