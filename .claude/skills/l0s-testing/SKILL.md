---
name: l0s-testing
description: How L0S is tested and what to run when. Host unit tests (l0 test, and what calls give with no kernel), the kernel's board tests (make test-virt), the end-to-end boot cases (tests/e2e), and the screen tests that drive QEMU's keyboard, tablet and screendump (gpu-screen, keyboard, vt, widgets, procmon). Also how to time or debug something running on the board. Use when writing or changing any *_test.l0 or tests/ file, when deciding how to verify an L0S change, or when a test fails.
---

# Testing L0S

Three layers, from fast to slow. Use the fastest that covers the change, and
the full set before calling it done.

| What | Command | Time | Covers |
|---|---|---|---|
| one module | `l0 test FILES... X_test.l0` | seconds | the logic of one file, on this Mac |
| every host test | `make test` | about 90 seconds from nothing; seconds for what changed | every pure module, the libraries, each program's logic |
| the kernel on the board | `make test-virt` | about 3 minutes | each test boots the kernel with hand-assembled threads, as many at once as this machine has CPUs; the whole suite twice, on a board of one CPU and of `VIRT_CPUS` (4) |
| boots and the screen | `make e2e` | about 4 minutes | real programs under the real kernel, then the screen tests (`tests/screens.sh`), each `E2E_JOBS` at once, half this machine's CPUs unless set; `E2E_JOBS=1` one at a time took 15 minutes |

- **A board test must pass on one CPU and on several.** With several, the
  processes a test starts run at once, so one never relies on another
  having run first: it waits for what it needs, as `await_mount`,
  `await_receiving`, `await_exited` and `told_reader` in
  `kernel_virt_test.l0` do, with a loop of calls and `cbnz`. The e2e
  cases and screen tests boot with `QEMU_CPUS` CPUs, which `make` sets
  to `CPUS`, 4 (the scripts run by hand default to 1);
  `QEMU_CPUS=1 make e2e` tries one, and
  a case whose output depends on which program runs first pins itself
  to one with a `cpus` file.
- **Done** means `make check` and `make test` pass. Run `make e2e` too for
  anything that boots, drives a device, draws, or takes input, and
  `make test-virt` for the kernel. Run long ones in the background.
- **The loop**: write, `l0 fmt FILE` (or `make fmt`), which adds the
  closers the indentation shows missing, then `make check`. `make check`
  fails on a file fmt would change, and ends by listing every warning
  its checks gave, those that passed too: `l0 check` warns where an
  update copies a whole map, array or record, which never fails a check
  and in a loop is a copy every time round. Fix what it names, the read
  first and the update last, and leave none but a copy that must be,
  said why where it is.
- **The files to pass `l0 test`** are the Makefile's line for that module:
  `l0 test $(ULIB) $(LIBS_NAME) user/NAME/NAME.l0 user/NAME/NAME_test.l0`.
  Copy them from `make -nB test-each | grep NAME`.
- `make check` and `make test` run each check and test file as a target
  of its own, `build/check/FILE.ok` or `build/test/FILE.ok`, made once it
  passes, with its output in `FILE.log` beside it. So only what changed
  since it last passed runs again (its files, the toolchain, or for a
  test the fonts, the apps' bundles and the sample archive), `JOBS` at
  once, every CPU unless set (`JOBS=1` for one at a time). Nothing is
  shown of what passes but `make check`'s warnings. A failing file's whole output is, `not ok` lines
  and each failing assertion under its test, and the rest still run, so
  every failure is shown. `make test` ends with `make test: N passed, M
  failed, of F files`, counted from every file's log. To run everything
  again, `rm -rf build/check build/test`.

## Host unit tests (`*_test.l0`)

The `l0-code` skill has the test syntax: `(def test_NAME () int ...)`, the
`check_*` assertions summed with `add`, `fail_because` in `match` arms,
`expect_NAME` for runtime errors. In L0S:

- **There is no kernel under `l0 test`.** Every `supervisor_call` gives -3,
  which each wrapper reads as its -3 answer if it has one (`port_send`
  `SendFull`) and otherwise as its type's first failure (`name_wait`
  `NotFound` at once, `proc_kill` `KillNoProc`); every receive gives
  `RecvFailed`, and opening a region fails. To test what a program does
  with each answer, pass it the constructors themselves, as
  `procmon_test.l0`'s `kill_text` tests do; `l0s_test.l0` pins each
  `X_of` against the kernel's codes. So test the pure functions, and test that each program's entry point
  gives up cleanly. Every program has one such test, always commented the
  same way:

  ```
  ; Under an operating system there is no display.
  (def test_no_display () int
    (check_int "fails" (wm) 1))
  ```

- **Fixtures are ordinary defs** at the top of the file, such as `win` and
  `two` in `user/sbin/wm/wm_test.l0`. A test builds a structure and compares a
  rendering of it as text with `check_str`, because a failing string shows
  where it differs: `placed_text` (layers), `hit_text`, `boxes_text`,
  `run_text`, `segs_text`. Write one for any new structure.
- **Drawing is tested on an array.** No region opens under `l0 test`, but
  `render.l0`'s `canvas_new w h color` is a canvas over an array that
  every drawing and painting function takes and returns: draw, then read
  pixels back with `canvas_pixel`, or as `#`/`.` rows (`canvas_art` in
  `render_test.l0`, `px_at` in `paint_test.l0`). `tools/mkicon` draws
  icons the same way, so `mkicon_test.l0` pins their pixels.
- **Pin numbers, not just shapes.** Geometry tests give exact pixels and say
  in a comment how they were worked out (`test_hit_close` in `wm_test.l0`).
  When the geometry changes, recompute and update them, along with the
  screen tests (below).
- **Property tests** thread a seed through `rand_next` and `rand_below`.
  Check a few hundred cases against a slower obvious version, and count the
  mismatches: `test_cached_rows_agree` in `user/sbin/virtio-gpu/virtio-gpu_test.l0`
  checks cached screen rows against a full rebuild; `test_random_never_crashes`
  in `common/initramfs_test.l0`.
- **Files**: host tests read `build/sample.cpio`, which `make test`
  makes first with `bsdtar` (the `sample` target), `fonts/`, and the
  apps' bundles, and `cli_test` writes `build/cli_test.tmp`. Test files
  run side by side, so a test that writes a file names it for its own
  test file. A file a test reads that is not one of these goes in the
  Makefile's `TEST_DATA`, or a change to it won't run the test again.
- Keep tests to one to three assertions each, and many of them.

## Board tests (`make test-virt`)

`kernel/kernel_virt_test.l0`, run by `l0 test --target virt`, boots the
kernel once a test from an initramfs built in L0, whose programs are threads
hand-assembled by `kernel/asm.l0` (`call_words N` makes a system call). Add
one for every system call and every refusal it makes. There are no files on
the board, so these tests can't read any. `make test-virt` gives them the
kernel's own `--heap-mb` and `--stack-mb`, so they run in the layout the
kernel ships with; running `l0 test --target virt` by hand without them
gets L0's defaults, and `in_frame_pool`'s windows no longer match.

## End-to-end cases (`tests/e2e/CASE/`)

`tests/e2e.sh` boots every case, from an initramfs of every program and the
case's `etc`, and compares. A case is a directory:

| File | Meaning |
|---|---|
| `etc/inittab` | what runs; any other files of `/etc` beside it |
| `expected` | the boot's whole standard output, exactly |
| `pattern` | instead of `expected`, for output that differs every boot: an extended regular expression its one line must match whole (BSD grep: no repeat over 255) (`virtio-rng`) |
| `contains` | instead of `expected`, for output of which part is the board's or the start order's (a time, the port a driver waits on): lines each of which must be somewhere in standard output; `status` and `stderr` are still checked (`dmesg`, `usb`) |
| `status` | the kernel's exit status, if not 0 (the first `start`'s, pid 1's) |
| `stderr` | one line standard error must contain |
| `typed` | lines typed at the serial line by `tools/slowtype`, with pauses |
| `font` | if present, the face (the pointers) is added as `/etc/face`, and the fonts and the desktop's strikes as `/etc/fonts`, for a case that starts `/sbin/font`, as any with `wm` must |
| `disk` | if present, the board has a virtio-blk on a fresh `tools/mkdisk` image (`build/e2e/CASE.disk`); without it there is no disk |
| `layout` | that disk's layout, if not mkdisk's 1 MB one: `SECTORS LABEL:START:COUNT[:ARCHIVE[:UUID]]...`, `@` the case's own cpio; give a UUID to boot from it, since mkfs's own differ every run |
| `readonly`, `norng` | for a case that types nothing: the disk read-only (`virtio-blk_ro`); no virtio-rng, which every other boot has (`virtio-rng_nodev`) |
| `usb` | if present, the keyboard and pointer are a `usb-kbd` and `usb-mouse` on a `qemu-xhci`, not virtio's (`QEMU_INPUT=usb` for a typed case); for `pcie`, `xhci`, `usb-hid` |
| `bootargs` | the kernel's boot arguments, such as `root=UUID` (`l0 boot IMAGE ARGS`, or `QEMU_APPEND` with `typed`) |
| `gpu` | the virtio-gpu's options, such as `xres=3840,yres=2160` for a 4K screen, drawn at scale 2 (`draw_4k`) |
| `net` | if present, the board has a virtio-net on the network its line names, as `-netdev` takes one without its id: `user`, or `user,tftp=tests/e2e/CASE/tftp` for QEMU's TFTP server at 10.0.2.2 (`net`); without it there is no card |
| `serve`, `peer` | a command line `e2e.sh` runs on the host for the boot: `serve` a server the board reaches at 10.0.2.2, killed at the end (`http`), `peer` a client of a port the board listens to, which must exit 0 (`net_echo`, with `user,hostfwd=tcp:127.0.0.1:@PORT@-:7000` in `net`). `@PORT@` in these, in `net` and in `typed` is a free port of the host's loopback |

- A case with `typed` should start `uart noecho`, so the output doesn't
  depend on how the echo interleaves.
- On failure the case's output, stderr and diff are in `build/e2e/CASE.*`.
- There is no filter: `tests/e2e.sh` runs every case (after `make root`,
  which stages every program in `build/root` as `/bin`, `/sbin` and
  `/Applications`; the script's hand-made programs, each an ELF of a few
  instructions, go in `/bin`).
- An inittab names a program where it is: `/bin/sh`, `/sbin/uart`,
  `/Applications/Terminal.app/vt`. A case that starts `vt` without `wm`
  and needs a quiet ending gives it a `font`, so it waits for a
  compositor rather than failing at once (`apps`).
- An app's manifest is read on the host by `app_test.l0`'s
  `test_app_sources`, from its source directory.
- Every boot is killed after 120 s by `tools/deadline`, which exits 124.
  The cases boot `E2E_JOBS` at once, so `install_boot`, 55 s alone,
  takes longer beside the others.
- **USB** (`pcie`, `xhci`, `usb-hid`): the e2e cases `pcie` and `usb`,
  and the screen test `tests/usb.sh` (`make usb-initramfs`, booted
  with `QEMU_INPUT=usb`), which types on the USB keyboard with `sendkey`
  and moves the USB mouse with QMP's relative `input-send-event`. The
  xHCI's logic is tested on the host: `core_test.l0` drives `core.l0`
  through whole enumerations, as scripted events in and acts out,
  rendered as text; change a case there before the board. On the board,
  `L0_QEMU_ARGS="... -trace usb_xhci_*"` (or the same in
  `tools/qemu-boot.sh`'s command) shows QEMU's side of every command and
  transfer, and `xhci`'s lines on stderr its own.

## Screen tests (`tests/*.sh`)

They run in 2D mode (`tools/qemu-boot.sh`'s `GPU` defaults to `2d`): on the
GL device (`GPU=gl`) QEMU's `screendump` says "no surface". To look at
virgl's 3D mode, boot headless with `GPU=gl QEMU_DISPLAY=none` and read the
screen back from inside the driver (a temporary `TRANSFER_FROM_HOST_3D` of
the screen into a page, sampled and printed), or `make demo` and look. They
also need `python3`, for `tools/qsock`, and `responsive.sh` needs `nc`
(netcat), which is not on every machine.

**Wait on what is checked, never on the clock.** Every monitor command and
input event goes through `tools/qsock SOCKET`, which returns once QEMU has
carried it out (a screendump is whole), in some 20 ms; `nc -U -w 1`, which
these used, waited out its second on every call, as QEMU keeps the
connection open, and so made one click 6 s. A click sleeps 0.1 s between
its events and none after; what it does is waited for by the check after
it (`shows`, `waits_for`, `listed`), each polling every 0.2 s against a
deadline in seconds (`end=$((SECONDS + 30))`), not a count of tries. A
click that needs the last one's effect, an icon in the launcher just
opened, waits for that effect first (`launches` in `launch.sh` waits for
the launcher's pill). `run windows` typed at the serial shell is read
once the shell's next `l0s> ` follows it. A fixed sleep is left only
where nothing can be seen to wait for: a check that something does *not*
happen, or a settle right after boot.

These boot with QEMU's monitor and QMP on Unix sockets and check pixels of a
`screendump`. Each can be run alone from the top of the project once its
image exists: `make vt-initramfs` for `vt.sh` (the demo, with
`tests/vt/etc/system`'s two Terminals over its own), and
`make screen-initramfs` for `gpu-screen.sh`, `keyboard.sh`, `widgets.sh`,
`resize.sh` (drags the gallery's edges and corner with the tablet),
`procmon.sh` and `launcher.sh` (the demo without the terminals,
`tests/screen/etc`; `launcher.sh` clicks Applications, checks the
launcher's page and Terminal's icon, closes it by Esc and by a click,
and starts Terminal from it, the top bar then naming it), and
`make disks-initramfs` for `disks.sh`, `disks-create.sh`, `files.sh`,
`launch.sh` (apps launched while they run, and `run open`),
`responsive.sh` (a hover answered at once, timed over QMP and monitor
connections kept open, as QEMU's sockets take one client at a time) and
`partitions.sh` (that with the clock and the disk's driver and file
server, `tests/disks/etc`, on a disk each makes itself, from
`tools/mkdisk` or `build/mkfs`, and passes as `QEMU_DISK`), and
`make launcher-install-initramfs` for `launcher-install.sh` (boot and the
disk's driver and file server, `tests/launcher-install/etc`, copied onto a
System volume of its disk and booted with `root=`; it installs an app from
the shell and checks the launcher shows it).
`disks-create.sh` types into Disks's entries with the monitor's
`sendkey`, one key a call (`keys m a d e`, `keys ret`), and checks an
entry's focus by its ring and a dialog's input by its button, faded or
not; a check point on a button must miss its label's white ink.
`partitions.sh` checks only the serial line, and reads
a UUID the board makes from it to type it back, since an e2e case's
`typed` input cannot hold what is made as it runs.
`hidpi.sh` (`make screen-initramfs`) boots on a 4K screen,
`QEMU_GPU=xres=3840,yres=2160`, drawn at scale 2: its screendump is
3840×2160 with a 17-byte header, and every pin is the desktop's pixel ×2.
It checks text is smoothed by counting the colors along a row through a
title, and boots again with `QEMU_APPEND=scale=1`. It keeps the 2x screen
in `build/hidpi-2x.ppm` for looking at.

Their helpers, copied in each script:

| Helper | Does |
|---|---|
| `monitor CMD` | a monitor command through `tools/qsock`, e.g. `sendkey h`, `screendump PATH`, done when it returns |
| `pixel X Y` | the R G B of a 1280×800 dump, its header 16 bytes |
| `shows NAME "X Y R G B"...` | retries for 30 s until every pixel matches; `procmon.sh` also takes `!R G B`, any other color |
| `waits_for REGEX` | waits for the serial line to show a line |
| `windows` / `window` | types `run windows` and reads the front and back windows' title, x, y, width, height |
| `typekeys "text"` | types on the virtio keyboard with `sendkey`, then Enter |
| `events EV...`, `at X Y`, `button true\|false` | the tablet through QMP's `input-send-event`; `at` scales screen pixels to the tablet's 0..32767 |
| `wheel wheel-down\|wheel-up` | a step of the scroll wheel, an `input-send-event` button that QEMU's tablet reports as `REL_WHEEL` (`procmon.sh`) |

- **Colors they pin**: active header bar and border `235 235 235`, backdrop
  `250 250 250`, the terminal's ground `30 30 30`, its ink and cursor white,
  the toolkit's selected row `205 224 248`, a hovered row `247 247 247`, and
  the scrollbar's slider `173 173 173`, `132 132 132` under the pointer. A
  change to the theme breaks them on purpose: update them in the same change.
- **The pointer's place rounds** through the tablet's axes: `at X Y` can land
  a pixel above or left of Y. Aim at a row's middle, not its edge.
- **Geometry they assume**: the top bar is 32 rows, header bars 46, a
  window's content starts `edge` (2) pixels in from its left, and `windows`
  gives the content's size. Pick check points away from rounded corners, text
  and the cursor unless that is what is checked: a point in a corner is cut
  to show what is beneath.
- `vt.sh` relies on pids from the demo's inittab and `tests/vt/etc/system`
  (the windows' `vt`s are `$((16 + 1))` and `$((16 + 2))`; which is
  which it learns from `nap`'s shell's parent): a `start` line added
  there shifts them.

## Trying things on a running board: the l0s MCP server

To look at a change before writing a screen test for it, or to find out
why one fails, use the `l0s` MCP server's tools (`tools/l0s-mcp`, set up by
`make mcp`, run by `.mcp.json`) rather than copying the helpers above into
a scratch script. `boot` (`demo`, `screen`, or an `etc` directory), then
`shell` for commands at the serial shell, `ps` and `windows` parsed,
`screenshot` and `pixels` for the screen, `type_keys`/`press_keys` for the
keyboard and `click`/`drag`/`move`/`scroll` for the tablet and its wheel. It does not build:
`make initramfs` (or `screen-initramfs`) first, and boot again after.
The windows' shells come up after the serial shell's prompt, so look at
the screen before typing into a window. It is for exploring; what must
keep working still goes in a test.

## Timing or debugging on the board

- **Print from a process**: `write_err`, then `file_flush (IoFile 2)`.
  Without the flush nothing shows until the process exits, and servers never
  do. What a process the inittab starts writes to standard error is the
  serial line's, which a screen test saves in `build/NAME.out` and an e2e
  case in `NAME.err`; its standard output is the diffed `expected`'s, so
  never print a debug line there. Prefix lines (`DBG`) and grep for them.
  Remove them before finishing. For a line that should stay, `debug_as`
  keeps it in the kernel's log without printing it.
- **Read what booted**: `dmesg` at the shell (or the MCP's `dmesg` tool)
  lists the kernel's log, every driver's line with its time since boot,
  after the serial line has scrolled past or on a board with none.
- **Time a phase**: `(let t0 (clock_ns) ...)` around it and print
  `(div (sub t1 t0) 100000)`, tenths of a millisecond.
- **Count copies**: `L0_ARRAY_STATS=1` on a run, or on the `l0 test`
  line of a module's tests, prints at exit how many updates copied, how
  many were in place, and the words the copies moved, records' fields
  counted with arrays'. Compare a loop's counts before and after a
  change: a new copy each time round is the hidden whole copy.
- **Check reference counting**: `L0_RC_CHECK=1` on a test run reports
  any block still live at exit and any use of a freed one.
- **Drive the pointer from a script**: copy `events`, `at` and `button` from
  `tests/vt.sh`. To send many events quickly, pipe a sequence of
  `input-send-event` commands, with short sleeps, into one `tools/qsock` on
  the QMP socket instead of one connection each. Then read the result with
  `run windows` typed at the serial line, or a screendump.
- Put sockets and dumps in `build/` (socket paths must be under 104 bytes)
  and remove the sockets afterwards. Name every file a test writes for
  the test (`build/NAME.sock`, `build/NAME-test.img`): `make e2e` runs
  the screen tests several at once, so two that wrote one file would
  break each other. A new screen test goes in the Makefile's
  `SCREEN_TESTS`, longest first.
- A boot that hangs is killed after a minute by `tools/deadline`; a kernel
  that finds nothing can wake anyone reports a deadlock and exits 124 itself.

## Booting the Raspberry Pi 5

`tools/pi5-boot` builds the TFTP root, checks dnsmasq serves it, and reads
the debug UART into `build/pi5-serial.log` (header of the script for its
options; without Docker, set `L0_VIRT_LD=/usr/bin/ld.lld`).

- **Reboot it yourself while its console answers**: `tools/pi5-boot
  --reboot` types `reboot` at the shell of the L0S already running there,
  the board restarts (`board_reset`, PSCI `SYSTEM_RESET`) and fetches the
  new build. It says whether the kernel's `l0s: restarting the board`
  line came; if not, the console is dead and the user must power-cycle,
  so ask them then, and only then.
- A boot that hung the board, or ended with `exit` or Shut Down (a halt,
  `Halt:` in the firmware's log), leaves no console to type at: that one
  needs a power-cycle by hand.
- `--until REGEX` stops at a line; `--wait` bounds the read. Save
  `build/pi5-serial.log` under another name before the next boot
  overwrites it.
