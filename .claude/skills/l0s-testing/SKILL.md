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
| every host test | `make test` | about a minute | every pure module, the libraries, each program's logic |
| the kernel on the board | `make test-virt` | minutes | each test boots the kernel with hand-assembled threads |
| boots and the screen | `make e2e` | several minutes | real programs under the real kernel, then the screen tests |

- **Done** means `make check` and `make test` pass. Run `make e2e` too for
  anything that boots, drives a device, draws, or takes input, and
  `make test-virt` for the kernel. Run long ones in the background.
- **The files to pass `l0 test`** are the Makefile's line for that module:
  `l0 test $(ULIB) $(LIBS_NAME) user/NAME/NAME.l0 user/NAME/NAME_test.l0`.
  Copy them from `make -n test | grep NAME`.
- `make test` stops at the first failing module. Look for `not ok` in its
  output; each failing assertion is listed under its test.

## Host unit tests (`*_test.l0`)

The `l0-code` skill has the test syntax: `(def test_NAME () int ...)`, the
`check_*` assertions summed with `add`, `fail_because` in `match` arms,
`expect_NAME` for runtime errors. In L0S:

- **There is no kernel under `l0 test`.** Every `supervisor_call` gives -3,
  which each wrapper reads as its -3 answer if it has one (`port_send`
  `SendFull`) and otherwise as its type's first failure (`name_wait`
  `NotFound` at once, `proc_kill` `KillNoProc`); every receive gives
  `RecvFailed`, and opening a device fails. To test what a program does
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
- **Files**: host tests read only `build/sample.cpio`, which `make test`
  makes first with `bsdtar` (the `sample` target).
- Keep tests to one to three assertions each, and many of them.

## Board tests (`make test-virt`)

`kernel/kernel_virt_test.l0`, run by `l0 test --target virt`, boots the
kernel once a test from an initramfs built in L0, whose programs are threads
hand-assembled by `kernel/asm.l0` (`call_words N` makes a system call). Add
one for every system call and every refusal it makes. There are no files on
the board, so these tests can't read any.

## End-to-end cases (`tests/e2e/CASE/`)

`tests/e2e.sh` boots every case, from an initramfs of every program and the
case's `etc`, and compares. A case is a directory:

| File | Meaning |
|---|---|
| `etc/inittab` | what runs; any other files of `/etc` beside it |
| `expected` | the boot's whole standard output, exactly |
| `status` | the kernel's exit status, if not 0 (the first `start`'s, pid 1's) |
| `stderr` | one line standard error must contain |
| `typed` | lines typed at the serial line by `tools/slowtype`, with pauses |
| `font` | if present, the console font is added as `/etc/font.txt`, for `vt`, and the face for scale 2 as `/etc/face2x` |
| `disk` | if present, the board has a virtio-blk on a fresh `tools/mkdisk` image (`build/e2e/CASE.disk`); without it there is no disk |
| `layout` | that disk's layout, if not mkdisk's 1 MB one: `SECTORS LABEL:START:COUNT[:ARCHIVE[:UUID]]...`, `@` the case's own cpio; give a UUID to boot from it, since mkfs's own differ every run |
| `bootargs` | the kernel's boot arguments, such as `root=UUID` (`l0 boot IMAGE ARGS`, or `QEMU_APPEND` with `typed`) |
| `gpu` | the virtio-gpu's options, such as `xres=3840,yres=2160` for a 4K screen, drawn at scale 2 (`draw_4k`) |

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
- Every boot is killed after 60 s by `tools/deadline`, which exits 124.

## Screen tests (`tests/*.sh`)

These boot with QEMU's monitor and QMP on Unix sockets and check pixels of a
`screendump`. Each can be run alone from the top of the project once its
image exists: `make initramfs` for `vt.sh` (the demo), and
`make screen-initramfs` for `gpu-screen.sh`, `keyboard.sh`, `widgets.sh`,
`procmon.sh` and `launcher.sh` (the demo without the terminals,
`tests/screen/etc`; `launcher.sh` clicks Applications, checks the
launcher's page and Terminal's icon, closes it by Esc and by a click,
and starts Terminal from it, the top bar then naming it), and
`make disks-initramfs` for `disks.sh`, `disks-create.sh` and
`partitions.sh` (that with the clock and the disk's driver and file
server, `tests/disks/etc`, on a disk each makes itself, from
`tools/mkdisk` or `build/mkfs`, and passes as `QEMU_DISK`).
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
| `monitor CMD` | a monitor command, e.g. `sendkey h`, `screendump PATH` |
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
- `vt.sh` relies on pids from the demo's inittab (`vt=$((6 + ...))`).

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
  do. A process the inittab starts writes to the serial line, which a screen
  test saves in `build/NAME.out`. Prefix lines (`DBG`) and grep for them.
  Remove them before finishing.
- **Time a phase**: `(let t0 (clock_ns) ...)` around it and print
  `(div (sub t1 t0) 100000)`, tenths of a millisecond.
- **Drive the pointer from a script**: copy `events`, `at` and `button` from
  `tests/vt.sh`. To send many events quickly, pipe a sequence of
  `input-send-event` commands, with short sleeps, into one `nc -U` on the QMP
  socket instead of one connection each. Then read the result with
  `run windows` typed at the serial line, or a screendump.
- Put sockets and dumps in `build/` (socket paths must be under 104 bytes)
  and remove the sockets afterwards.
- A boot that hangs is killed after a minute by `tools/deadline`; a kernel
  that finds nothing can wake anyone reports a deadlock and exits 124 itself.
