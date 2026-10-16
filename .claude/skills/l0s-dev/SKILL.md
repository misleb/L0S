---
name: l0s-dev
description: Map of the L0S operating system (a microkernel and user programs written in L0) and checklists for changing it. Where each piece lives, how files are linked together, how to add a program, a library, a server request or a system call, the server/listen/driver patterns, and the pitfalls that cost time. Use before any change to L0S code, the Makefile, an inittab, or a protocol, and whenever you need to find where something is done. Pairs with l0-code (the language), l0s-testing and l0s-ui.
---

# Working on L0S

L0S is a microkernel for QEMU's aarch64 `virt` board and the programs that
run on it, all in L0. Read the `l0-code` skill for the language; this one is
about the system. `README.md` is the full human description: go to it for
detail, but use this skill and `make -s doc` to find things fast.

## Find things before reading files

```bash
make -s doc                    # every documented name in the libraries, one line each
make -s doc Q=port_send        # one name in full: def, data type, or constructor
make -s doc Q=l0s              # one library file in full (its stem: l0s, wm, widget, kernel...)
make -s doc Q=damage           # every name or doc line mentioning the text
l0 doc NAME                    # the L0 standard library, which is linked into everything
```

Run both before writing a helper: L0S's libraries already have list, number,
request and drawing helpers that the standard library lacks. The docs are
the `;` comment block directly above each form, so write yours that way
(below).

## Where things are

| Path | What |
|---|---|
| `kernel/` | the kernel, `--target virt`. `kernel.l0` is the state, every call's handler (`do_*`), `dispatch`, traps and the loop; `syscall.l0` decodes registers into a `Call`; `process.l0`, `memory.l0`, `ipc.l0`, `sched.l0`, `pids.l0`, `inittab.l0` are its parts. `asm.l0` hand-assembles threads for board tests |
| `common/` | shared by kernel and programs: `abi.l0` (call numbers `call_*`, error codes, limits, little-endian helpers), `initramfs.l0` (the cpio archive), `queue.l0` |
| `user/lib/` | linked into programs: `l0s.l0` (call wrappers, `request`, `KeyEvent`, `PointerEvent`, notices, `name_wait`), `tty.l0`, `virtio.l0` in every program; `render.l0`, `display.l0`, `wm.l0`, `clock.l0` and `ui/` only where a `LIBS_` list says |
| `user/NAME/` | one program each: `NAME.l0`, `NAME_test.l0`, `main.l0` (only `main`). Becomes `/bin/NAME` |
| `demo/etc/` | the demo's `inittab`, `motd`; `tests/screen/etc/` the screen tests' |
| `tools/` | `qemu-boot.sh` (boots with the serial line on a terminal, monitor and QMP sockets), `mkinitramfs`, `deadline` (timeout, macOS has none), `slowtype`, `mksplash/` (an L0 tool), `l0sdoc/` (`make doc`) |
| `tests/` | `e2e.sh` and `e2e/CASE/`, the screen tests `gpu-screen.sh`, `keyboard.sh`, `vt.sh`, `widgets.sh`, `procmon.sh` |
| `build/` | everything make makes; ignored by git |

Who talks to whom at run time is the table under "The interactive demo" in
the README, and the desktop's diagram under "The desktop".

## Linking: one namespace

L0 has no modules. Every file on the command line is one program, so **two
files defining the same name do not compile**. That's why the Makefile links
the optional libraries only into the programs that need them:

```make
ULIB := common/abi.l0 common/initramfs.l0 common/queue.l0 user/lib/l0s.l0 user/lib/tty.l0 user/lib/virtio.l0
LIBS_wm := $(RENDER) $(DISPLAY) $(UI_CORE) $(CLOCK)
```

- A new name in a library must not clash with **any** program that links it.
  Check with `make check`, which checks every program with its libraries.
  Real clashes met so far: `fill_rows` (render.l0 vs a driver), `Command` and
  `parse_command` (render.l0 vs sh), `Reply` (display.l0 vs draw),
  `display_info` (display.l0 vs virtio-gpu).
- The toolkit prefixes every name `ui_` and every type `Ui`; do the same in
  any new library that many programs link. Programs never linked together
  may reuse names (`complain`, `serve`, `requested`).
- A name of yours shadows the L0 standard library's, so a library name is
  never something to work around.

## Adding things: checklists

**A program**
1. `user/NAME/NAME.l0`, `NAME_test.l0`, `main.l0`. `main` only calls in:
   `(def main () int (NAME))`. A name with a hyphen gets an underscored
   function (`virtio-gpu` → `virtio_gpu`).
2. Makefile: add NAME to `PROGRAMS`, and `LIBS_NAME := ...` if it needs more
   than `ULIB`. Its check, test, image and initramfs rules follow from those.
3. To start it at boot, a `start /bin/NAME [ARGS]` line in `demo/etc/inittab`.
   A program that maps devices or binds interrupts needs `dev /bin/NAME`.
   Adding a `start` line shifts later pids: update the README's pid table and
   `ps` sample, and check `tests/vt.sh`'s pid arithmetic.
4. Its row in the README's programs table.

**A library** in `user/lib/`
1. Its file header `; NAME.l0 -- summary`, a doc block on every def.
2. Makefile: a variable for it, added to each `LIBS_` that needs it; a
   `$(L0) test ... user/lib/NAME_test.l0` line in `test`; add it to `DOC_SRCS`
   so `make doc` sees it.
3. Its row in the README's libraries table.

**A request to a server** (the compositor; the display driver is alike)
1. Server: `user/wm/wm.l0` `requested` takes word arguments (`hello`,
   `windows`, `desktop`, `title`); `requested_window` takes numbers
   (`window`, `damage`, `top`, `close`). Add an `(if (eq op "X") ...)` branch
   returning `Answered` through `okay` or `refused`. The dispatcher is split
   in two to keep nesting shallow; split again rather than nest deeper.
2. Client: a wrapper in `user/lib/wm.l0` (`compositor_ask`, `ask_nums`,
   `wm_error`), and its line in that file's header table.
3. The README's compositor protocol table, and tests on both sides.
   For the display: `user/virtio-gpu/virtio-gpu.l0` `requested` /
   `requested_pointer`, `user/lib/display.l0`'s header, the README's display
   table.

**A system call** (`shm_revoke`, 282, is a complete example)
1. `common/abi.l0`: `(def call_NAME () int N)` with its contract as a
   trailing comment; numbers from 256 are L0S's own.
2. `kernel/syscall.l0`: a constructor in `Call`, and its line in the right
   `decode_own_*` function; `kernel/syscall_test.l0`: a `decoded` check.
3. `kernel/kernel.l0`: `do_NAME`, and its arm in `dispatch`. Check every
   argument against the kernel's own records before it reaches a builtin
   that can fail: nothing a process passes may crash the kernel.
4. `user/lib/l0s.l0`: the wrapper over `supervisor_call`.
5. `kernel/kernel_virt_test.l0`: tests through `asm.l0`'s `call_words`, run
   by `make test-virt`; include refusals.
6. The README's table of the kernel's own calls.

## Patterns to copy

- **A server** (`user/echo/echo.l0`): `port_new`, `name_register port
  "name"` (non-zero: taken), then a loop on `port_receive`. A request is
  `(request REPLY BODY)`: read it with `request_reply` and `request_body`,
  answer with `port_send (request_reply payload) reply`. Replies are `ok`,
  `error: WHY`, or the request's own answer. Clients find a server with
  `name_wait NAME ns`.
- **Listening to a driver** (`user/virtio-input/virtio-input.l0`, server
  side; `input_listen` in `l0s.l0` and `listen_pid` / `clock_listen` in
  `wm.l0`, client side): a `listen` request adds the reply port to the
  driver's list, which it then sends each event. Drop a listener whose send
  fails (`told` in `user/rtc/rtc.l0`).
- **Waiting for a message or a time.** A receive cannot time out. Either a
  device interrupt arrives as a message (`irq_bind`), or the loop polls with
  `port_try_receive` and `sleep_ns` (`rtc clock`, `procmon`).
- **Failing.** Each program has
  `(def complain ((why (list int))) int (let w (write_err (append "NAME: " (append why "\n"))) 1))`.
  A driver whose device is absent says so and exits 0: no device is no
  failure.
- **A state record** is one `data` with many fields, matched and rebuilt in
  every function (`Wm`, `Drv`, `Win`). Adding a field means updating every
  pattern: the Edit tool's replace-all on the exact pattern text does most
  of them; then `l0 check` names the rest, with their different binding
  names.

## Documenting

The first lines of every file: `; FILE.l0 -- summary`, a few lines, a blank
line. Above every def or data, a block of `;` lines with no blank line
between: what it is or does, in plain words. One comment may cover a group
of one-liners directly beneath it. Section dividers are
`; ---------------------------------------------------------------- name`.
`make doc` reads exactly this, so an undocumented def is invisible there.

## Pitfalls that have cost time

- **Writes are held back.** A process's stdout and stderr reach the terminal
  only when flushed or when it exits, and `wm`, the drivers and servers
  never exit. `(file_flush (IoFile 1))` after a prompt; for a debug line,
  `(let f (file_flush (IoFile 2)) ...)` after the `write_err`. Processes the
  inittab starts write to the serial line; in a screen test that is the
  `build/NAME.out` file.
- **The proc runtime keeps at most 64 regions open and closes none.** Every
  `ui_buffer` and `dma_open` is one; `wm` opens two per window (title bar
  and frame), so it can only ever open so many windows.
- **Ports** hold 32 messages of at most 4096 bytes. A message must carry
  numbers, never pixels: pixels go through shared pages (`shm_alloc`,
  `shm_share`).
- **Docker must be running**: board images (`--target virt` and `proc`) are
  linked in l0's container. Homebrew's `ld.lld` is blocked on this machine.
- **QEMU's Unix sockets** must have paths under 104 bytes: put them in
  `build/` and use relative paths, as the tests do. A scratch directory's
  path is too long.
- **`main` cannot be tested**: keep it to one call.
- **Edit source with the editor tools**, not sed, awk or scripts: a shell
  rewrite with a stale line number once overwrote the top of a file.
- **The README's tables** (programs, libraries, protocols, calls, pids,
  tests) are relied on by people and agents; update them in the same change.

## Done

`make check` and `make test` pass. For anything that boots, draws or takes
input, `make e2e` too (see `l0s-testing`). Never say L0 code works without
having run them.
