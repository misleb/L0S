# L0S

A microkernel written in L0, for QEMU's aarch64 `virt` board, and the start
of an operating system around it.

The kernel is an ordinary L0 program built with `--target virt`. It runs at
EL1 and runs processes at EL0, each in its own address space. It boots from
an **initramfs**: a cpio archive, in the same newc format as Linux's, of the
programs it can run and the files they can read. An `/etc/inittab` inside
says what starts at boot.

A process is any L0 program built with `--target proc`, so it runs
unchanged, and can read the initramfs's files with the ordinary `open_in`.
Processes talk through ports. Device drivers are processes too: the kernel
maps a device's registers into a driver and passes its interrupts on as
messages.

```bash
make demo                                 # boot to the shell on this terminal, and type at it
make all                                  # type check, host tests, board tests, end-to-end
make boot ETC=tests/e2e/ipc/etc           # boot every program with that etc, non-interactively
make -s doc Q=port_send                   # the libraries' documentation, as l0 doc gives the standard library's
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
its virtio-gpu, virtio keyboard and virtio tablet are in a QEMU window.
The window shows a desktop, the compositor's: a wallpaper, a top bar,
and two terminal windows that overlap, each with a title bar and a
shell. The top bar is GNOME Shell's, black across the top of the screen:
the front window's title at its left, and the date and time in its
middle, `Oct 15  22:42`, from the board's real-time clock, which QEMU
sets to this machine's local time. There are three shells in all:

- **The serial line**, in the terminal you ran `make demo` from.
- **`vt1` and `vt2`**, the windows. They're drawn in GNOME's Adwaita
  style by the toolkit in [user/lib/ui](user/lib/ui/README.md): rounded
  corners and a header bar with a bold, centered title, and a thin
  border of the header bar's color down the terminal's sides and along
  its foot. Keys typed in QEMU's window go to the one in front, whose
  header bar and border are `ebebeb`; the other's are lighter, in the
  backdrop, its title dimmed.
  - Click a window to bring it to the front. Drag it by its title bar to
    move it.
  - Click the round close button at the right end of its title bar to
    close it. That kills the window's `vt`, and its shell goes with it.
  - Each is a terminal of 80 by 24 cells: white on GNOME Console's
    `1e1e1e`, scrolling, with a cursor along the foot of its cell.

`run widgets &` at any shell opens the toolkit's gallery: a toolbar and a
sortable data grid of sample processes, the scaffolding for a process
monitor. `run disks &` opens Disks, the disk, its partitions and its
volumes as GNOME Disks shows them.

Each shell runs programs on its own terminal: their standard input,
output and error are its. The demo's [inittab](demo/etc/inittab) starts:

| Pid | Program | What it is |
|---|---|---|
| 1 | `sh` | the serial line's shell, so its `exit` stops the system |
| 2 | `uart` | the serial line's terminal, `console` |
| 3 | `virtio-gpu` | the display driver. It serves `display`, building the screen from the buffers the compositor gives it |
| 4 | `virtio-input keyboard` | the keyboard driver. It serves `keyboard`, telling `wm`, and `run keys`, of each key typed in the window |
| 5 | `virtio-input tablet` | the pointer's driver. It serves `pointer`, telling `wm` where the pointer is and what its buttons do |
| 6 | `wm` | the compositor. It owns the screen and keeps the windows on it, and serves `compositor` |
| 7, 8 | `vt`, `vt` | the windows' terminals, which name themselves `vt1` and `vt2`, the first names free, in the order they start. Each edits the keys `wm` sends it into lines, as `uart` does what the serial line sends, and draws what is written to it into its window |
| 9 | `rtc clock` | the real-time clock's driver. It serves `clock`, telling `wm` the time at the start of every minute, for the top bar |
| 10 | `virtio-blk` | the disk's driver. It serves `disk`, reading and writing the sectors of `build/disk.img` for `fs` and `run disk` |
| 11 | `fs` | the file server. It mounts the disk's volumes at `/Volumes/data` and `/Volumes/scratch`, and serves their files to every program, through the kernel (see [Volumes](#volumes)) |
| 12, 13 | `sh vt1`, `sh vt2` | the windows' shells, which the `vt`s start, not the inittab, in whichever order the two get there, and after any program run before they do. A shell's `exit` ends its `vt` too, and closes its window |

How the display, the compositor and its clients fit together is under
[The desktop](#the-desktop).

The text font is [fonts/l0s-8x16.txt](fonts/l0s-8x16.txt), drawn for
L0S: printable ASCII, 8×16, one glyph per `@ CODE` line and 16 rows of
`#` and `.`, so it can be read and edited as text. The initramfs carries
it as `/etc/font.txt`.

The wallpaper is the splash, drawn by
[tools/mksplash](tools/mksplash/mksplash.l0) into `build/splash.ppm`, at
70% of its brightness, so that what is drawn over it reads.
`make demo SPLASH=picture.ppm` shows any other binary PPM (P6, maxval 255)
instead, centered and cut to fit the 1280×800 screen, on the color of its
top-left pixel.

The window is macOS's (`cocoa`). `QEMU_DISPLAY=gtk` or `sdl` picks
another, and `none` none. What is typed in your terminal goes to `uart`.
What is typed in the window goes to the virtio keyboard, and so through
`virtio-input` and `wm` to the front window's `vt`.

Each shell shows [/etc/motd](demo/etc/motd), then its prompt:

```
Welcome to L0S, booted from an initramfs.
Programs are in /bin, the disk's files in /Volumes; try ls, df, run hello, ps.
Two more shells run in windows in QEMU's: click one, and type there.
Drag a window by its title bar; run windows lists them; try run widgets &.
Draw on the desktop: run draw circle 640 400 300 cyan; run draw for more.
run keys echoes what the keyboard driver sees, until Esc.

L0S shell, on an L0 microkernel. Type help for the commands.
l0s> ls
  /bin/cat
  /bin/echo
  ...
  /etc/font.txt
  /etc/inittab
  /etc/motd
  /etc/splash.ppm
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
- `NAME` is `/bin/NAME`, or a path if it holds a `/`: `run hello` and
  `run /bin/hello` are the same.
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
[/Volumes](#volumes):

| Command | Does |
|---|---|
| `ls [PATH ...]` | with no path, every file of the initramfs, then of each volume; else each directory's names (`/`, `/bin`, `/Volumes`, `/Volumes/data`), a directory's with a final `/`, or a file's path |
| `cat FILE ...` | shows the files |
| `write FILE WORDS ...` | makes FILE hold the words, spaced, and a newline |
| `append FILE WORDS ...` | adds that line to FILE's end, making it if need be |
| `cp FROM TO` | copies a file; into TO if it is a directory |
| `mv FROM TO` | renames a file, or moves it into TO if it is a directory; between file systems, as from one volume to another, it copies and then removes |
| `rm FILE ...` | removes the files |
| `df` | each volume's size, the room its files take and what is free, in kilobytes of its 4 KB clusters, and how many files it has |
| `format VOLUME` | empties a volume, `/Volumes/LABEL` or just `LABEL`; refused while a file on it is open |

```
l0s> write /Volumes/data/notes hello disk
l0s> append /Volumes/data/notes and again
l0s> cat /Volumes/data/notes
hello disk
and again
l0s> df
  VOLUME              SIZE    USED    FREE  FILES
  /Volumes/data       760K      4K    756K      1
  /Volumes/scratch    252K      0K    252K      0
```

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
      1       0  sh            running
      2       0  uart          waiting for a message on port 1
      3       0  virtio-gpu    waiting for a message on port 10
      4       0  virtio-input  waiting for a message on port 9
      5       0  virtio-input  waiting for a message on port 2
      6       0  wm            waiting for a message on port 13
      7       0  vt            waiting for a message on port 3
      8       0  vt            waiting for a message on port 4
      9       0  rtc           sleeping
     10       0  virtio-blk    waiting for a message on port 6
     11       0  fs            waiting for a message on port 11
     12       7  sh            waiting for a message on port 16
     13       8  sh            waiting for a message on port 17
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
  1 vt2 100 90 640 384 front
  0 vt1 40 40 640 384 -
  pointer 0 0
  ```
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
  lose their devices, so `uart`, `virtio-gpu` and `virtio-input` stay.
  Killing pid 1, the serial shell, from a window's shell stops the
  system, as its `exit` does.

Editing, on any terminal: Backspace erases a character and Ctrl-U erases
the line. Arrow keys are ignored. Ctrl-D on an empty line ends input. In
a window, Ctrl-C, Ctrl-D and Ctrl-U are the keyboard's own.

`exit [STATUS]` at the serial shell stops the system, since it is pid 1;
at a window's shell it ends that shell, and with it the window's `vt`,
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
on it. The demo's disk is `build/disk.img`, 1 MB, which
[tools/mkdisk](tools/mkdisk) makes once, with two empty volumes on it,
so what is written to it stays from one boot to the next; `make clean`
resets it. A `build/disk.img` made before the file system was, holding
raw sectors only, has no volumes, and `fs` says so and serves none: remove it, and
`make demo` makes a new one. `QEMU_MONITOR` and `QEMU_QMP` put QEMU's monitor and
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
makes it.

| Tool | Does |
|---|---|
| `boot` | boots `demo`, `screen`, a `.cpio`, or an `etc` directory packed with every program in `build/bin`, and waits for the serial shell's prompt |
| `shutdown`, `status` | stops the board, by `exit` or by killing QEMU; whether it runs, its exit status, QEMU's stderr |
| `shell` | types a command at the serial shell and returns what it printed before the next prompt |
| `serial_send`, `serial_read` | types anything at the serial line, Ctrl-C included; what it showed since last read, waiting for a pattern |
| `ps`, `windows` | `ps` and `run windows` at the serial shell, parsed |
| `screenshot`, `pixels` | the screen, or part of it, as a PNG, by QMP's `screendump`; the exact colors of pixels |
| `type_keys`, `press_keys` | text, or combinations such as `ctrl-c`, on the virtio keyboard, so to the front window |
| `move`, `click`, `drag`, `scroll` | the virtio tablet, in screen pixels, and its scroll wheel |

Everything the serial line shows is also kept in `build/mcp/serial.out`.

### Terminals

A terminal is a port that edits typed keys into lines and writes what it is
sent. [user/lib/tty.l0](user/lib/tty.l0) has the line editing both share,
and says what a terminal takes, each a request (`request` in `l0s.l0`):

| Request | Does |
|---|---|
| `request REPLY "r"` | sends REPLY the next line typed, with its newline; empty once input has ended |
| `request REPLY "i"` | sends REPLY a lone byte 3 at each Ctrl-C, dropping what is unread |
| `request REPLY "p"` | sends REPLY `tty` at once, so REPLY learns the terminal's pid, the sender, to watch |
| `request 0 ("w" ++ BYTES)` | writes BYTES; no reply |

`uart` is one, as `console`, and each `vt` another, as the first of
`vt1`, `vt2`, and so on that is free: `vt1` and `vt2` in the demo.

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
 sh ─tty─ vt2 ─┼──────────────────▶ wm ─────────────────────────▶ virtio-gpu ──▶ QEMU
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

**The display protocol** ([user/lib/display.l0](user/lib/display.l0)) is
the whole contract between the compositor and the display hardware's
driver. It says nothing about virtio. A driver for other hardware, a
plain framebuffer say, serves the same requests as `display`, and `wm`
runs on it unchanged. Such a driver would compose the layers by copying
pixels, and draw the pointer as a top layer.

| Request | Does |
|---|---|
| `info` | `display W H cursor`: the screen's size, and `cursor` if the driver moves a pointer itself |
| `buffer ID W H VA` | a buffer of W×H 4-byte pixels (b, g, r, and unused, or alpha for a cursor), at VA in the driver, shared there with `shm_share` |
| `forget ID` | the buffer dropped, and the driver's mapping of it given up with `shm_unmap`; refused while it is on the screen or is the pointer's |
| `layers ID X Y TOP ...` | the screen, bottom first: each buffer at X, Y, its rows read from row TOP on, as a ring. The bottom layer covers the screen. Only the bands of rows whose pixels changed are transferred and flushed; the first `layers` shows the whole screen |
| `damage ID X Y W H ...` | each rectangle of its buffer changed, one or more groups of five: shown wherever they are visible, all together, with boxes that overlap transferred and flushed as one |
| `shape ID TL TR BL BR` | the buffer's corners rounded, top left, top right, bottom left, bottom right, each radius from 0 (square) to half its width and height. The driver cannot blend, so it narrows the layer's rows within a corner and the layer beneath shows there. A buffer is square when shared; if it is on the screen, the screen is rebuilt |
| `cursor ID HX HY` | the pointer's image, a 64×64 buffer, and its hot spot |
| `move X Y` | the pointer's hot spot at X, Y |

The reply is `ok`, `display W H cursor` for `info`, or `error: WHY`.

**The compositor protocol** ([user/lib/wm.l0](user/lib/wm.l0)) is what
`wm` serves, as `compositor`, to its clients:

| Request | Does |
|---|---|
| `hello` | `compositor`, so the client learns `wm`'s pid, to share with |
| `window W H VA PORT TITLE` | a window of W×H pixels, its buffer at VA in `wm`, shared there with `shm_share`. It opens in front, cascading from 40, 40. Keys typed while it is in front, the pointer in it, and the notices below go to PORT. The reply is `window ID` |
| `damage ID X Y W H ...` | each rectangle of the window changed, ID X Y W H again for each, given to the display in one `damage` and shown together |
| `top ID T` | the window's rows read from its buffer's row T on, as a ring: how a client scrolls |
| `title ID TEXT` | a new title |
| `close ID` | the window gone. A client's windows also go when it exits, since `wm` watches it |
| `desktop CMD ...` | a drawing command, as `draw` takes them, drawn on the desktop |
| `windows` | a line a window, front first, then `pointer X Y` |

`wm`'s own buffers are the desktop (the wallpaper, and what `draw`
draws), the pointer's arrow (Adwaita's), the top bar, and each window's
title bar and frame. The layers it gives the driver are the desktop,
then each window from back to front, its title bar, its frame and then
its content, then the top bar over them all.

The top bar is GNOME Shell's: 32 rows across the screen, black, with
the front window's title in white at its left and the date and time,
bold, in its middle, as GNOME shows them by default (`Oct 15  22:42`,
on a 24-hour clock). `wm` repaints it when the front window or its
title changes, and when the clock says a minute has begun. The clock is
`rtc clock` ([user/rtc](user/rtc/rtc.l0)), which serves `clock`
([user/lib/clock.l0](user/lib/clock.l0)): `listen` replies `time S`, S
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
  [user/lib/l0s.l0](user/lib/l0s.l0)).
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

### The disk

`virtio-blk` ([user/virtio-blk](user/virtio-blk/virtio-blk.l0)) drives
QEMU's virtio-blk: the demo's `build/disk.img`, 2048 sectors of 512
bytes. It serves `disk`, raw sectors, to clients, `fs` above all,
through **the disk protocol**
([user/lib/disk.l0](user/lib/disk.l0)). As with the display, no sector
travels in a message. A client shares a buffer of its own pages with the
driver (`shm_share`), and the device reads or writes those pages itself,
by DMA, from a chain of descriptors the driver builds over them. The
driver makes one request of the device at a time, and waits for it by
polling the used ring, as `virtio-gpu` does (`virtq_wait` in
[user/lib/virtio.l0](user/lib/virtio.l0)).

| Request | Does |
|---|---|
| `info` | `disk SECTORS 512`: the disk's size in sectors, and a sector's in bytes |
| `read SECTOR COUNT VA` | COUNT sectors from SECTOR, 1 to 128, put by the device into the client's pages shared with the driver at VA |
| `write SECTOR COUNT VA` | the same, taken from those pages and written to the disk |

The reply is `ok`, `disk SECTORS 512` for `info`, or `error: WHY`: a
count out of range, sectors past the disk's end, a buffer not shared
with the driver, or the device's own failure.

`run disk info`, `run disk read SECTOR [COUNT]` (shown as `hexdump -C`
shows bytes) and `run disk write SECTOR WORDS...` use it from a shell.
Sectors 1 to 7 of a disk `tools/mkdisk` makes belong to no volume, so a
`disk write` there harms no file.

### Volumes

A disk holds **volumes**, each a partition of it with a file system of
L0S's own, L0FS ([user/lib/l0fs.l0](user/lib/l0fs.l0)), and a label.
`fs` mounts each at `/Volumes/LABEL`, as macOS mounts disks, and the
kernel sends every call on a file there to it, so every program reads
and writes them with the ordinary `open_in`, `open_out` and the rest:
`run cat /Volumes/data/notes` works as `run cat /etc/motd` does.

The disk, as [tools/mkdisk](tools/mkdisk) makes it with
[tools/mkfs](tools/mkfs/mkfs.l0) (`mkfs OUT SECTORS
LABEL:START:COUNT...`, a host program, built into `build/mkfs`):

| Sectors | What |
|---|---|
| 0 | an MBR, its four entries at 446, `55 AA` at 510: here two partitions of type `0x4C` |
| 1–7 | nothing |
| 8–1535 | the volume `data`, 1528 sectors: 190 clusters of data, 760 KB |
| 1536–2047 | the volume `scratch`, 512 sectors: 63 clusters, 252 KB |

A volume, its sectors counted from its partition's first, in clusters of
8 sectors, 4 KB:

| Where | What |
|---|---|
| sector 0 | the superblock: `L0FS`, version 1, the label (1 to 15 letters, digits, `-`, `_`) in 16 bytes from 8, then u32s from 24: its sectors, clusters, the table's first sector and sectors, the directory's, the first cluster of data, and the entries |
| sector 1 on | the cluster table, a u16 a cluster, a sector for each 256: 0 free, `FFFF` a file's last, `FFFE` the metadata's, else the file's next cluster, so each file is a chain, as in FAT |
| the next 6 sectors | the directory, flat: 48 entries of 64 bytes, a name of 1 to 55 printable bytes with no space or `/`, NUL padded in 56, the size at 56, the first cluster at 60 (0 for an empty file), and 1 at 62 if the entry is in use |
| from the first cluster after these | the files' data |

The superblock, table and directory, rounded up to whole clusters, are
the metadata: for these volumes cluster 0, one 8-sector read. A volume
holds at most 65534 clusters, so 256 MB. `fs` checks all of it, the
layout against the size, every mark of the table and every file's chain
against its size, before it serves a volume, so a damaged disk is
refused rather than followed.

**The mount table** ([kernel/mounts.l0](kernel/mounts.l0)) is a list
whose first mount is the initramfs at `/`, which the kernel answers for
itself; after it come the volumes, each at `/Volumes/LABEL` from the
port of the server that mounted it with `fs_mount`. They go when that
port does. `/Volumes` itself is always there, a directory holding only
the volumes: nothing can be made in it, only in one of them. The kernel
takes a path, made absolute, to where it is mounted:

- the initramfs: answered as [Calls 1–10](#calls-110-the-process-abi-of-spec-103) say;
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

**The fs protocol** ([user/lib/fs.l0](user/lib/fs.l0)) is what a file
server serves on the port it mounts from. The kernel sends the first
six; programs send `list`, `df` and `format` themselves, to the port
`mount_at` gives, as `ls`, `df` and `format` in the shell do, and
`rescan` to the port registered as `fs`. `fs_df_on`, `fs_format_on`
and `fs_rescan_on` take a reply port the program keeps, for one that
asks again and again; `fs_df` and `fs_format` make one each call, which
never goes.

| Request | Reply |
|---|---|
| `open MODE PATH` | MODE 1 to read, 2 to write anew, 3 to add to the end, making the file if it is not there: a handle |
| `read H N` | at most N bytes of handle H from where it is, those of one cluster: the count, then the bytes; 0 at the end |
| `write H BYTES` | BYTES written to H, at its end for mode 3: how many, all of them, or -6 if the volume has no room |
| `close H` | 0 |
| `rename FROM TO` | 0, a file named TO replaced, unless it is open, -4; both in one volume, else -10 |
| `remove PATH` | 0, unless the file is open, -4 |
| `list VOLUME` | how many files, then a line `NAME SIZE` for each, by name |
| `df VOLUME` | 0, then `SECTORS CLUSTERS FREE FILES`: its sectors, its clusters of data, those free, and its files |
| `format VOLUME` | 0, the volume empty, its label kept; -4 while a file on it is open |
| `rescan` | the partition table and every volume read again, as at the start, and served in place of those before, each new label mounted: how many volumes there are now, then a line `LABEL` for each; -4 while any file is open. A label that has gone stays mounted, there being no unmount, and is answered as a volume not served: -3, or -9 to write |

Each is a request (`request` in `l0s.l0`), its words separated by
spaces; a PATH is whole, `/Volumes/LABEL/NAME`, and a VOLUME
`/Volumes/LABEL`, so one port serves every volume. The reply is a word,
a little-endian s32, then any bytes: a count, a handle, or a negative
code, as spec §6.3's I/O builtins give them (-3 no such file, -4 denied,
-5 any other failure, -6 no space, -8 a directory, -9 no such
directory, -10 another file system). A handle is the pid that opened
it, the sender, so a process can use only its own.

**`fs`** ([user/fs](user/fs/fs.l0)) opens the disk with a buffer of a
cluster, reads the partition table, checks and loads each volume's
metadata, mounts each by its label from one port, and then registers
that port as `fs`, so that a program can wait for every volume with
`name_wait`. It keeps the metadata in memory and writes it back after
the data whenever it changes. It reads only the sectors a read needs,
and reads a sector before a write only where the write keeps some of
its bytes. It watches each process that opens a file, and drops its
handles when it exits. A `rescan` does the reading again, so a volume
made or changed on the disk since is served without a reboot. A disk
with no volume on it, or none that can be served, is no reason to stop:
`fs` says so, registers, and serves nothing until a rescan finds some.
With no disk at all, where nothing could ever be made, it says so and
exits 0.

## How it boots

```
tools/mkinitramfs OUT ETC IMAGE...        # programs as /bin/NAME, ETC as /etc
l0 boot build/kernel.img < OUT            # the kernel reads the initramfs on stdin
```

[tools/mkinitramfs](tools/mkinitramfs) stages a directory and archives it
with `bsdtar --format newc`, in order of path:
- each image becomes `/bin/NAME`, mode 0755;
- everything in `ETC` becomes `/etc/...`, mode 0644.

`bsdtar -tvf build/initramfs.cpio` lists it like any cpio archive.

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

Device authority comes only from `dev` lines. The demo grants it to `uart`,
`rtc`, `virtio-gpu`, `virtio-input` and `virtio-blk`, so the shell can start `rtc`
without having it itself. `wm`, `vt` and `fs` have none: they reach only
memory they share.

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
| `kernel/memory.l0` | what each address is for; which pages to map before a copy; where device regions and DMA pages go; which frames to free when a process ends |
| `kernel/mounts.l0` | the mount table: the initramfs at `/` and the volumes at `/Volumes/LABEL`, where a path's file is, and where a rename goes |
| `kernel/ipc.l0` | ports, their message queues, names, and the mount table, whose volumes go with their ports |
| `kernel/sched.l0` | sleepers and the timer's deadline |
| `kernel/pids.l0` | which slot of the process table, and which pid, a new process gets |
| `kernel/syscall.l0` | a trapped context decoded into a `Call` |
| `kernel/process.l0` | creating, demand-paging, copying in and out of, mapping devices and DMA pages into, and the open files of a process |
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

The layout is fixed by spec §10.3.

| Address | What | Mapped |
|---|---|---|
| `0xC0000000` | the image | at load, readable, writable and executable |
| to `0xC0400000` | the rest of the image's 4 MB (bss) | on first touch, RWX |
| to `0xD8000000` | heap | on first touch, RW |
| to `0xE8000000` | stack, `sp` starting at the top | on first touch, RW |
| `0xE8000000` up | device regions, DMA pages, and shared pages | by the `region` and `dma_alloc` calls, for programs with a `dev` line only; by `shm_alloc` and `shm_share`, for any |

The kernel copies in and out of a process only through pages it mapped
itself. A buffer on a device's registers, or outside the user range, gets
-5. DMA pages are ordinary memory the kernel mapped, so a buffer there is
accepted.

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
back in `x0`. From L0, use the wrappers in `user/lib/l0s.l0`.

### Calls 1–10: the process ABI of spec §10.3

The kernel answers these itself for the initramfs, a read-only file
system, and for a file of a volume under `/Volumes` sends them to the
volume's file server, as [Volumes](#volumes) says, its answer the
call's:

| Call | What the kernel does |
|---|---|
| open | modes 1 to 3, else -5. In the initramfs, to read: a new stream (3 and up), or -3 no such file, -8 a directory, -5 if the process has 16 open. To write: -8 a directory, -4 where the directory exists, -9 where it does not. In a volume: a new stream, once its server opens the file. A relative path is taken from `/` |
| read | stream 0 reads a line from the process's terminal, if it has one (see Terminals), and otherwise the inittab's `stdin` file, with one cursor for everyone. Other streams read the file opened on them, from where the process left off, 0 at the end; a volume's at most 4092 bytes a call |
| close | 0, or -5 for a stream that isn't open; a volume's file is closed by its server too |
| rename, remove | in the initramfs, -3 if there's no such file; otherwise -4 (-8 to remove a directory). In a volume, as its server says; between two file systems, -10 |
| write | streams 1 and 2 go to the process's terminal, if it has one, at most 4091 bytes per call, waiting while its queue is full; otherwise to the kernel's stdout and stderr, at most 64 KiB per call. A stream open on a volume's file is written by its server, a message's worth a call; any other is -5 |
| exit | the process ends with that status |
| arg_count, arg | the process's arguments: those it was spawned with by `spawn_entry_with`, or else the inittab's `args` for it |
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
| 264 | `spawn_entry e` | `Spawn`: `Spawned`, `SpawnNoEntry`, `SpawnNotProgram`, `SpawnTooBig`, `SpawnNoRoom` | a pid, or -1 no entry e, -6 not a program, -4 an image over 4 MB, -5 out of address spaces |
| 265 | `wait_pid pid` | `Reaped`: `Reaped`, `WaitNoProc` | waits; the pid's exit status, or -1, which a status of -1 reads as too |
| 266 | `sleep_until t`, `sleep_ns n` | `int` | 0, once `clock_ns` reaches t |
| 267 | `irq_bind irq port` | `IrqBinding`: `IrqBound`, `IrqAbsent`, `IrqDenied`, `IrqNoPort`, `IrqTaken` | 0, or -6 no `dev` line for the program, -1 not your port, -2 already bound, -3 no such interrupt on the board. After this, each interrupt sends the message `irq_notice irq` to the port |
| 268 | `irq_ack irq` | `IrqAck`: `IrqAcked`, `IrqNotPending` | 0, ending the interrupt once the driver has quieted its device; -1 if it is not yours or not taken |
| 269 | `entry_path_of e` | `(list int)` | the entry's path, with a final `/` for a directory, or empty if there is no entry e. `entry_paths` lists them all, and `program_entry` finds a program by name |
| 270 | `proc_kill pid` | `Kill`: `Killed`, `KillNoProc`, `KillDenied` | 0, ending pid with status 130, any process but the caller; -6 if pid's program has a `dev` line, -1 if there is no such process or it is the caller. Ending pid 1 stops the system with status 130 |
| 271 | `proc_watch pid port` | `Watch`: `Watched`, `WatchNoProc`, `WatchFull` | 0, and the kernel sends `exit_notice pid status` to the caller's port when pid exits, or at once if it has. -1 if there is no such pid, or the port is not the caller's; -3 if 32 ports watch pid already. `exit_of` reads the notice |
| 272 | `spawn_entry_with e args` | `Spawn` | as `spawn_entry`, but the process gets args (sent as `encode_args` writes them) in place of the inittab's; -5 if they are not well formed, -4 over 4096 bytes |
| 273 | `proc_info pid` | `(Option ProcInfo)` | a `ProcInfo`: state (`state_running` … `state_exited`), parent, the program's entry, and a detail (the port or pid it waits on, or an exited process's status); none if no process has that pid now: none has had it, or its slot has gone to another process (see [Processes and pids](#processes-and-pids)). To list every process, ask `proc_slot` for each slot's pid |
| 274 | `dma_alloc n` | `DmaAlloc`: `DmaPages`, `DmaDenied`, `DmaTooMany`, `DmaNoRoom` | the address of n zeroed pages a device can reach, at the caller's next device pages; -6 no `dev` line, -4 n below 1 or over 4096, -5 out of frames or device pages. They last until the system stops |
| 275 | `dma_address va` | `DmaWhere`: `DmaAddress`, `DmaAddressDenied`, `NotDma` | where a device reaches the caller's DMA page holding va, page aligned; -1 if no DMA page holds va, -6 no `dev` line |
| 276 | `tty_set port` | `TtyChange`: `TtySet`, `TtyNoPort` | 0, making port, a terminal, the caller's standard input, output and error, and those of every process it starts from then on; 0 gives back the kernel's own; -1 if there is no such port |
| 277 | `tty_get` | `Terminal`: `Terminal`, `KernelTerminal` | the caller's terminal's port, or 0 for the kernel's own |
| 278 | `shm_alloc n` | `ShmAlloc`: `ShmPages`, `ShmNoRoom`, `ShmTooMany` | the address of n zeroed pages to share, at the caller's next device pages, for any process; -4 n below 1 or over 4096, -5 out of frames or device pages. They are freed once every process that maps them has ended, unless one of those drives devices |
| 279 | `shm_share va n pid` | `ShmShare`: `ShmShared`, `ShmShareNoProc`, `ShmShareTooMany`, `ShmShareFailed` | where pid sees the caller's n shared or DMA pages from va, now mapped into pid's next device pages too, the same frames; -1 no such pid, -4 n below 1 or over 4096, -5 pages that are not the caller's, or pid out of device pages |
| 280 | `proc_slot i` | `Slot`: `SlotHeld`, `SlotUnused`, `NoSlot` | the pid slot i of the process table holds, live or exited, or last held; 0 if it has held none; -1 for no slot i, outside 1 to 255 |
| 281 | `shm_unmap va n` | `ShmUnmap`: `ShmUnmapped`, `ShmUnmapNotYours`, `ShmUnmapTooMany` | 0, the caller's n shared or DMA pages from va unmapped, each frame freed once no process maps it; -4 n below 1 or over 4096, -5 pages that are not the caller's, when none is unmapped |
| 282 | `shm_revoke va n pid` | `ShmRevoke`: `ShmRevoked`, `ShmRevokeNoProc`, `ShmRevokeDenied`, `ShmRevokeTooMany`, `ShmRevokeNotYours` | how many mappings pid had of the caller's n shared or DMA pages from va, all now unmapped; -1 no such pid, -6 pid is the caller or drives devices, -4 n below 1 or over 4096, -5 pages that are not the caller's |
| 283 | `fs_mount label port` | `Mounting`: `Mounted`, `MountNoPort`, `MountTaken`, `MountBadLabel` | 0, the caller's volume label mounted at `/Volumes/LABEL` from port, whose server is sent every call on a file there (see [Volumes](#volumes)) until the port goes; -1 not the caller's port, -2 the label is mounted already, -5 no label (1 to 15 letters, digits, `-`, `_`) |
| 284 | `mount_at i`, `mount_list` | `(Option MountInfo)` | mount i of the table, from 0, the initramfs at `/`: where it is and the port of its server, 0 for the kernel's own; none past the last. `mount_list` gives them all |

Listening to a driver, `keyboard_listen`, `pointer_listen` and
`input_listen`, gives a `Listen`: `Listening`, `NoDriver` or
`ListenRefused`.

IPC is asynchronous. A send copies the payload into the port's queue and
returns at once. A receive blocks until there is a message, and is given the
sender's pid with it. A request that wants an answer carries a reply port:
see `request` and `request_reply` in `l0s.l0`, and `user/echo`.

When a process exits or is killed, its ports, names, interrupt bindings and
open files go with it. Whoever waits for it is woken with its status, and
every port watching it gets a notice. Waiting with `watch` instead of `wait`
lets a process hear about an exit and other messages on one port. That is
how the shell waits for a job and for Ctrl-C at the same time.

## The programs

Each one is the usual three files under `user/NAME/`: `NAME.l0`,
`NAME_test.l0` and `main.l0`. Each becomes `/bin/NAME` in the initramfs.

| Program | What it does |
|---|---|
| `sh` | the shell, on the terminal its argument names, `console` unless given (`sh vt1` is a window's): reads commands from it; runs programs by name or path, on its terminal, and waits for them, with Ctrl-C for the foreground job; has busybox's commands on files, `ls`, `cat`, `write`, `append`, `cp`, `mv`, `rm`, `df` and `format`, on the initramfs and the volumes alike; also `ps`, `kill`, `sleep`, `echo` and `exit`. Shows `/etc/motd` at start. Exits with status 129 if its terminal's process exits |
| `uart` | the serial line's terminal, `console`: a driver for the PL011 serial port. It takes receive interrupt 33, edits lines, echoes them (unless given `noecho`), and hands a line to each process that asks. Ctrl-C drops unread input and sends a lone byte 3 to the port that asked to hear of it. What it is sent to write, it writes to the serial line |
| `vt` | a terminal in a window, `vt [COLS ROWS]`, 80×24 unless given. First thing, it registers as NAME, the first of `vt1`, `vt2`, and so on that no one has, which is also its window's title. Once its window is open it starts its own shell, `sh NAME`, and watches it: when the shell exits, `vt` closes the window and exits with the shell's status. The same line editing as `uart`'s, fed the characters of the keys `wm` sends while its window is in front. What it is sent to write, and the echo, it draws into its window's buffer, shared with `wm`, in the 8×16 font, in the toolkit's terminal colors, GNOME Console's white on `1e1e1e`. It scrolls by moving the buffer's top row, with `top`, and so copies nothing. Its cursor is a line along the last row of a cell, which no glyph uses. Each batch drawn is one `damage` |
| `cat` | writes the files its arguments name, through the ordinary `open_in`, the initramfs's or a volume's; reports each it can't read, and exits 1 if any |
| `hello` | prints its pid and arguments, and answers a line: typed at its terminal, with `console_line` |
| `init` | starts the programs its arguments name (`NAME&` runs one in the background), waits for the rest, and reports each one's status |
| `echo` | a server: registers as `echo` and sends every request's body back |
| `ping` | a client: finds `echo` by name and checks that N requests come back |
| `spin` | loops forever without a call; other processes still run, thanks to the timer |
| `nap` | sleeps for N ms and checks that the time passed |
| `rtc` | a user-space driver for the PL031 real-time clock: it maps the device, sets an alarm, receives interrupt 34 as a message, and acks it. `rtc clock` instead serves `clock`, the time, to whoever asks, and at the start of every minute to each process listening, as `wm` does; it looks for both every quarter of a second, and leaves the interrupt to `rtc` |
| `virtio-gpu` | a user-space driver for QEMU's virtio-gpu, serving the display protocol as `display` (see [The desktop](#the-desktop)). It finds the device among the 32 virtio-mmio transports and sets up its control queue and cursor queue in DMA pages. It makes the screen resource 1 on scanout 0, and builds its backing from the layers' buffers, so the host composes the screen. It keeps every row of the backing, so a `layers` request builds again only the rows a layer that moved, scrolled or changed covers, and writes the backing's runs straight into the queue's memory. A `damage` is a transfer and a flush of that rectangle. The pointer is the device's cursor, resource 2. Until it is given layers, the screen is black. With no virtio-gpu on the board it says so on stderr and exits 0. It polls the queues rather than taking interrupts |
| `virtio-input` | a user-space driver for QEMU's virtio input devices, started once a device. It keeps the event queue's 16 buffers in a DMA page and takes the device's interrupt as a message. `virtio-input keyboard` finds the device whose name holds `Keyboard`, serves `keyboard`, and sends each key event to every port that asked it to `listen`: a `KeyEvent` of the Linux key code, pressed, released or repeated, and the character it types on a US layout, with Shift and Caps Lock, and Ctrl with a letter as its control character. `virtio-input tablet` finds `Tablet`, serves `pointer`, and at each report's end sends a `PointerEvent`: x and y, 0 to 32767, and the buttons; before it, if the scroll wheel turned in the report (`REL_WHEEL`, `REL_HWHEEL`), a `WheelEvent` of its steps, down and right positive. With no such device on the board it says so on stderr and exits 0 |
| `virtio-blk` | a user-space driver for QEMU's virtio-blk, serving the disk protocol as `disk` (see [The disk](#the-disk)). It finds the device, reads its capacity from its config, and sets up its request queue in one DMA page. Each `read` or `write` it checks against the disk's size and the pages the client shared, then has the device move the sectors straight into or out of those pages, a descriptor a page. With no virtio-blk on the board it says so on stderr and exits 0. It polls the queue rather than taking interrupts |
| `disk` | a client of `disk`: `disk info` prints its size; `disk read SECTOR [COUNT]` prints COUNT sectors, 1 unless given, as `hexdump -C` does, a `*` for repeated lines; `disk write SECTOR WORDS...` writes the words, spaced, and a newline as sector SECTOR, zeros after them. A refusal goes to stderr, with status 1 |
| `fs` | the file server (see [Volumes](#volumes)): a client of `disk`, which mounts each volume of L0S's file system on the disk at `/Volumes/LABEL` and serves the fs protocol for them, the kernel's requests for every program's file calls there and `list`, `df`, `format` and `rescan`; then registers as `fs`, though the disk has no volume yet. With no disk it says so on stderr and exits 0 |
| `wm` | the compositor (see [The desktop](#the-desktop)): waits for `display`, `keyboard` and `pointer`, and a second for `clock`, paints the wallpaper on the desktop, sets the pointer's arrow, draws the top bar, and serves `compositor`. It needs no `dev` line |
| `windows` | a client of `compositor`: prints its `windows` reply, the windows front first and where the pointer is |
| `draw` | a client of `compositor`: sends it `desktop` and the command its arguments make (`line`, `circle`, `disc`, `rect`, `fill`, `clear`, `char`, the toolkit's `round` and `button`, `splash`, `restore`, `size`, `font`), which `wm` draws on the desktop. Colors may be Adwaita's by name (`blue_3`, `dark_4`, `accent`…). It checks the command with the toolkit's parser first, so a bad one fails without asking `wm`. It prints the size, or the error on stderr with status 1. With no arguments it lists the commands |
| `widgets` | the toolkit's gallery ([user/lib/ui](user/lib/ui/README.md)): a window with a toolbar (Refresh, and End Process, sensitive only with a row selected) over a data grid of sample processes, sortable by any column, selected by click or the arrow keys. It's the scaffolding for a process monitor; it reads no real processes and ends none |
| `disks` | Disks, `run disks &`, as GNOME Disks is: a sidebar of drives; the drive's model, size and partitioning; a bar of its partitions and the free space between them, each as wide as its share of the disk, one selected by click or Left and Right; and the selected part's size, usage, files, contents, partition type and sectors. It reads the partition table and each partition's first sector through `disk` itself, so a partition no server serves still shows, and asks `fs` how full each mounted volume is, through one reply port. Refresh has `fs` `rescan` and reads the disk again; Format Volume..., for a mounted volume, asks in a dialog, then has `fs` `format` it. With no disk it shows a status page |
| `procmon` | the process monitor, `run procmon &`: a toolkit window with the kernel's process table in a data grid (pid, program, state and its detail, parent), read again every second and on Refresh, sortable by any column. When there are more rows than fit, the scroll wheel scrolls them, three a step, and so does dragging the overlay scrollbar's slider, or pressing its strip. End Process, sensitive with a row selected, ends that process as `kill` does; a driver cannot be ended |
| `keys` | a client of `keyboard`, for checking `virtio-input`: echoes each printable character typed in QEMU's window to its terminal, Enter as a newline and Backspace as a rub-out, until Esc |

The libraries in `user/lib/` are linked into every program
(`l0s.l0`, `tty.l0`, `virtio.l0`), or into those that need them, by the
Makefile's `LIBS_` lists:

| Library | What it holds | Linked into |
|---|---|---|
| [l0s.l0](user/lib/l0s.l0) | the call wrappers; requests; `KeyEvent`, `PointerEvent`, `WheelEvent` and listening for them; the compositor's leave and focus notices; `name_wait`, which waits for a server to register; `fs_mount` and the mount table | every program |
| [tty.l0](user/lib/tty.l0) | a terminal's line editing and protocol | every program |
| [virtio.l0](user/lib/virtio.l0) | the transports' registers, finding a device by ID, negotiating, setting up a queue, descriptors, and waiting for the device to use a request (`virtq_wait`) | every program |
| [render.l0](user/lib/render.l0) | drawing into a buffer of pixels: shapes, the font, PPM images, the wallpaper, and `draw`'s commands | `virtio-gpu`, `wm`, `vt`, `draw`, `widgets` |
| [display.l0](user/lib/display.l0) | the display protocol, as a client sends it | `wm` |
| [wm.l0](user/lib/wm.l0) | the compositor protocol, as a client sends it | `vt`, `windows`, `widgets` |
| [clock.l0](user/lib/clock.l0) | the clock protocol, and the date and time as the top bar shows them | `rtc`, `wm` |
| [disk.l0](user/lib/disk.l0) | the disk protocol, as a client sends it, and a buffer shared with the driver to move sectors through | `disk`, `fs` |
| [l0fs.l0](user/lib/l0fs.l0) | the file system on a disk, as bytes: the MBR, a volume's superblock, cluster table and directory, their layout, allocating clusters, and which clusters a read or a write touches | `fs`, `tools/mkfs` |
| [fs.l0](user/lib/fs.l0) | the fs protocol: its replies, and `list`, `df` and `format` as a program sends them, to the port the mount table gives, and `rescan`, to `fs`'s; `_on` versions take a reply port the caller keeps | `fs`, `sh` |
| [ui/](user/lib/ui/README.md) | the toolkit, in Adwaita's look: theme, icons, painting, widgets, the data grid, panes (a sidebar, a segment bar, property rows, an alert dialog), the desktop's drawing commands (`UI_CORE`), and client windows (`UI_WINDOW`) | `wm`, `vt`, `draw` (`UI_CORE`); `widgets`, `procmon`, `disks` (both) |

## Tests

| Command | What it runs |
|---|---|
| `make test` | `l0 test` on this host: every pure module, the user library, and each program's logic. It first has `bsdtar` make `build/sample.cpio`, so the parser is tested on a real archive. Last, `python3` runs the MCP server's tests of what it parses and encodes (`tools/l0s-mcp/test_board.py`) |
| `make test-virt` | `l0 test --target virt`: the kernel booted on the board, once per test, from initramfses built in L0 (`kernel/asm.l0`) holding hand-assembled threads. Covers exit, demand paging, faults, bad buffers, files, devices, DMA, shared memory, terminals, IPC, spawn and wait, preemption, deadlock, freed memory and spaces, shared pages given up and taken back, mounts and the file calls a volume's server answers, its request, its answer, and its going, and the fuzz tests |
| `make e2e` | real L0 processes under the real kernel (`tests/e2e.sh`), then the screen (`tests/gpu-screen.sh`), the keyboard (`tests/keyboard.sh`), the windows, their terminals and shells (`tests/vt.sh`), the toolkit's gallery (`tests/widgets.sh`), the process monitor (`tests/procmon.sh`), and Disks (`tests/disks.sh`) |

Each case of `tests/e2e/` is a directory:
- `etc/`, with its `inittab` and any other files;
- `expected`, its standard output;
- `status`, if not 0;
- `stderr`, a line standard error must hold;
- `typed`, keys to type at the serial line;
- `font`, if the console font is to be added to `etc`, for `vt`;
- `disk`, if the board is to have a virtio-blk, a fresh disk from
  `tools/mkdisk` for each run.

`tests/e2e.sh` builds each case's initramfs from every program and its
`etc`, boots it, and compares. Eleven cases type a session through
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
  its standard error, are on the shell's terminal, the serial line;
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
  and its first sector as `tools/mkdisk` made it, the partition table,
  write a sector and read it back, read the last sector, and be refused
  one past it;
- `fs`, on a disk of its own, starts the file server and has the shell
  show `df` and `ls /Volumes`; `write` a file and `cat` it back, `append`
  to it and read it with `run cat`, a program, so through the kernel;
  `cp` it into the other volume, `mv` it within a volume and across
  volumes, `ls` everything, `rm` it; be refused a `write` to the
  initramfs; `cp` a file of the initramfs to a volume; and `format` a
  volume, `ls` showing it empty.

`files` reads the initramfs through `cat`. `virtio-gpu_nodev` and
`virtio-blk_nodev` start a driver with no `dev` line, which is refused
the device, `virtio-blk_nodisk` the disk's driver on a board with no
disk, and `fs_nodisk` the file server there, neither of which is a
failure. `garbage`
and `noinit` check that a boot without a valid archive or inittab is
refused with a message. Every boot has a virtio-gpu, which no window
shows, a virtio keyboard, and a virtio tablet; only a case with a `disk`
file has a virtio-blk.

[tests/gpu-screen.sh](tests/gpu-screen.sh) boots the initramfs of
[tests/screen/etc](tests/screen/etc/inittab), the demo's without its
windows, which would cover the wallpaper, with QEMU's monitor on a socket
and the serial line on a FIFO. It checks pixels of a `screendump` at each
step, all of them from the compositor's desktop buffer, composed by the
host:
- the wallpaper: the corner, its ground color, and a pixel of the L of
  "L0S", where centering on a 1280×800 screen puts it, both at 70%;
- after typing `run draw line 0 0 1279 799 red`, both of the line's ends;
- after typing `run draw circle 640 400 300 cyan`, its left and right
  edges.

[tests/keyboard.sh](tests/keyboard.sh) boots the same way, types
`run keys` at the serial line, then presses `h`, `i`, Shift-1, Space,
Shift-A and Enter on the virtio keyboard with the monitor's `sendkey`, as
typing in the window would. It checks that the serial line shows `hi! A`,
and that after Esc the shell runs the next command typed.

[tests/vt.sh](tests/vt.sh) boots the demo's own initramfs, every shell
running, with QMP on a socket as well, to work the tablet. Which `vt`
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
  its own row, the seventh, with no eighth;
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

Every boot is killed after a minute by [tools/deadline](tools/deadline),
since macOS has no `timeout`. `tests/e2e.sh` also builds three raw programs
of a few aarch64 instructions each, for what L0 code cannot do on purpose:
fault, pass a bad buffer, and wait on nothing.

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
  MB of them though its memory is freed.
- One CPU, and round-robin scheduling with 10 ms slices. A process woken by
  a message runs at the end of the current slice, not at once.
- **The initramfs is read-only.** Nothing in it can be written, renamed
  or removed. There is no current directory, so a relative path is taken
  from `/`. No call lists a directory: the initramfs's are `entry_paths`,
  which lists everything, and a volume's its server's `list`.
- **The volumes are small and simple** (see [Volumes](#volumes)). Each
  has one flat directory of at most 48 files, with names of at most 55
  bytes and no spaces, and no subdirectories, permissions or times; at
  most 65534 clusters of 4 KB; and a disk at most the MBR's four. One
  file server, `fs`, serves the first disk's volumes, one request at a
  time, and a read moves at most a cluster. A write is as safe as the
  order it is made in, its data and then the metadata, and no more: a
  crash between the two loses the write's changes to the file's size
  and chain, and the disk's own cache is never flushed. A file open
  cannot be removed or renamed over, where Unix would let it go once
  closed. Any process may mount a label no one has, as any may register
  a name, and nothing unmounts a volume but its server's port going:
a label that a `rescan` no longer finds stays mounted, answered -3,
and a rescan is refused while any file is open.
- **The disk is one virtio-blk, one request at a time.** `virtio-blk`
  drives the first disk on the board, polls for each request rather than
  taking the interrupt, and moves at most 128 sectors a request. It
  accepts no device features, so it never flushes a write cache and
  never learns a disk is read-only, whose writes the device then fails.
- **Disks shows the one disk, and changes it only two ways.** It can
  format a mounted volume, keeping its label and size, and have `fs`
  rescan; it cannot partition, resize, relabel or make a new volume, nor
  format a partition `fs` does not serve. Its window is a fixed 880 by
  520, as every window is, and it reads the disk only when it opens and
  when asked.
- Images are copied from the archive into fresh frames for every process
  that runs them. Only pages made with `shm_alloc` or `dma_alloc` can be
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
  keeps at most 64 open, so `wm` can open only so many windows over its
  life, closed ones included. The close button kills its client at
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
- The image is mapped RWX, because a raw `--target proc` image does not say
  where its code ends.
- Instruction-cache maintenance after loading an image is left to the board's
  host file. This is fine under QEMU.
- A failed receive reports no reason. `supervisor_receive` gives no bytes
  when the kernel's word is negative (spec §6.15), so `RecvFailed` stands
  for every failure, and for no message yet.
- `wait_pid`'s word is a status or -1 for no such process, so a process
  that exits with -1 reads as `WaitNoProc`.
