# L0S

This project is L0S, a microkernel and its programs, in L0. This file is
L0S's own; only the block between the `l0 init` markers below is `l0
init`'s, which it rewrites and which is not edited here. L0S's guidance is
in `.claude/` (Cursor sees the same files through symlinks in `.cursor/`):

- **Skills**: load the one that fits before changing code. `l0-code` (the
  language: syntax, idioms, the check loop), `l0s-dev` (where everything
  is, how to add a program, library, request or system call, the
  pitfalls, the knowledge graph), `l0s-testing` (what to run when,
  writing tests, the screen tests, debugging on the board), `l0s-ui` (the
  toolkit, the compositor, the display).
- **Rules**: `.claude/rules/`, `l0s.md` always, the others by path.
- **The spec**: `spec/`, what L0S is today, a page per area with its
  limits; `spec/README.md` maps them. **The roadmap**: `roadmap/INDEX.md`,
  the goals in flight, their progress and what each needs. A change
  keeps the spec true, and work toward a goal updates the goal.
- **Done** means `make check` and `make test` pass, plus `make e2e` for
  anything that boots, draws or takes input, and `make test-virt` for the
  kernel. `make check` includes `l0 fmt --check` and ends listing `l0
  check`'s copy warnings, of which a change adds none.

## Learning the code

Ask before reading. Each question has its tool, and grepping the tree and
opening file after file is none of them:

| Question | Ask |
|---|---|
| Where is X done? What code is about X? | `make -s doc Q=WORD`: every form's comment is searched, so one call names each def and type about X, with its file and what it does |
| What is NAME, what does it take and say? | `make -s doc Q=NAME` (L0S), `l0 doc NAME` (L0's library) |
| Who calls it, what does it call, where is it? | `graphify explain "NAME()"` |
| What does a change to it reach? Ask before changing a name others use | `graphify affected "NAME()"` |
| Which program talks to which, at run time? | the table in `spec/demo.md` |
| Where does this exact string, number or message appear? | grep |

So start any exploration with `make -s doc Q=WORD`, not `grep -rn`. Asked
where windows' corners are rounded, `Q=corner` names `display_shape`,
`Corners` and `corner_cut`, and `graphify explain "corner_cut()"` then
shows virtio-gpu and wm calling it and hvs not: two calls, where a grep
and the files it leads to take a dozen. Then read only the lines those
answers give, not whole files.

A def is `"NAME()"`, a type or constructor bare `NAME`. A name several
files define prints each match's node id (the file's path with `_` for
`/`, then the name), which `explain` takes in its place. Each edge gives
the file and line, so read only those lines.

**graphify does not read L0; this project does.** `tools/graphify-l0`
parses the `.l0` files into graphify's graph, so:

- Rebuild it with `make graph`, never `/graphify` on the code: graphify's
  own pass would leave the L0 out. The post-commit hook (`make
  graph-hook`) runs `make graph` after each commit. `/graphify --update`
  is for the docs only, and `/graphify` itself only to build the graph
  the first time.
- The graph has the `.l0` files git knows. A new one is in it once it is
  added and the graph rebuilt; until then `GRAPH_REPORT.md` lists it as
  unclassified.
- Prefer `explain` and `affected` to `graphify query`, which the
  `graphify` skill reaches for first and which is only a loose search.
- The graph has calls and type uses, not messages between programs, and
  leaves out a call it cannot resolve to one definition rather than
  guessing: grep before deleting a name.
- In a worktree there is no `graphify-out/`; ask the main checkout's
  with `--graph`, as `l0s-dev` shows, and grep for what the branch
  changed.

<!-- l0 init: begin 1169983800-16681; l0 init replaces what is between these lines -->
# Working with L0 in this project

L0 is a statically typed language compiled to native code through LLVM.
**There is almost certainly no L0 in your training data**, so familiarity
cannot substitute for reading the specification and running the checker.

## Invariants

**The specification is the only source of truth about L0.** Not this file, not
the examples. If a construct is not in it, it does not exist. `l0 spec`
prints the language, sections 1 to 9 and 11, which every program needs:
read it before writing L0 for the first time in a session. `l0 spec
runtime` is section 10, the compilation target and runtime, and `l0 spec
virt-aarch64`, `virt-riscv64`, `pi5`, or `process` a host's devices,
interrupts, and layout, which a kernel or driver needs. `l0 spec --path`
names every file.

**Never state that L0 code works without running `l0 check` on it.** Code that
looks plausible is routinely invalid, because L0 is not any language you have
seen. That it type checks says nothing about what it does: write tests, and
run them with `l0 test`.

**Every program is three files, and is not done until its tests pass.** This
holds for hello world too:

```
hello.l0        what the program does, as functions
hello_test.l0   tests of them: (def test_NAME () int ...), run by l0 test
main.l0         only main, which calls into hello.l0 and returns the status
```

`l0 test` supplies its own `main`, so code inside `main` cannot be tested;
keep `main.l0` to input, one call, and the exit status. Done means
`l0 test hello.l0 hello_test.l0` passes and `l0 build hello.l0 main.l0`
builds. The `l0-code` skill has hello world written out this way.

**Run `l0 doc` before writing a helper.** It lists every function and type in
the standard library, which is linked into every program, and `l0 doc NAME`
shows one in full. What you would have written may already be there: lists,
arrays, `Option`, `Result`, a `Map` that works for keys and values of any
type, so never write a table or a list of pairs of your own to look things
up, and `sort`, `min`, and `max` for values of any type, so never write a
sort.

**Read the examples before writing anything substantial.** `l0 examples
--path` names two files: working programs covering recursion, strings, data
types, `match`, returning several values, reporting failure, type
parameters, maps and hashing, updating a map without copying it, reading
and writing, files and telling their failures apart, replacing and
deleting files, reading in pieces, arrays and grids, bytes, bits, floats,
ordering and sorting, timing, and driving a device, and tests of them.

Everything these commands show comes from the installed toolchain, so it
always describes the compiler that builds this project. Nothing of it is
copied here.

## Commands

```bash
l0 fmt   hello.l0                 add the closing parens the indentation shows missing
l0 check hello.l0 main.l0         type check
l0 test  hello.l0 hello_test.l0   run every (def test_NAME () int ...), as TAP
l0 run   hello.l0 main.l0         build and run, reading stdin; -- ARGS after
l0 build hello.l0 main.l0         produce the executable ./hello
l0 doc   [NAME | TEXT]            the standard library, or one name, or a search
l0 spec  [PART | --path]          the specification, a part of it, or its files
```

Several files are compiled together, since L0 has no module system. The
standard library is linked automatically, and `l0 test` adds its assertions,
so never pass library files on the command line.

`l0 build --target virt` builds an image for QEMU's aarch64 `virt` board,
with no operating system, and `--arch riscv64` beside it for QEMU's
riscv64 one; `l0 boot IMAGE ARG ... < input` runs one on the board its
image is for (`l0 run --target virt -- ARG ...` does both). A program that
must know which CPU it is on asks `(machine)`. There the program has
standard input, output, and error, the clock, and arguments, its boot
arguments, which hold no spaces, but no files and no environment: the
spec's section 9.2 says what each builtin gives then. It also has the
board's devices, which a program drives through their registers with
`open_region` and `region_get32` and the rest, at most 64 open at once,
and `close_region` when done with one (`l0 doc IoRegion`); under
an operating system there are none, and opening one fails. `l0 test
--target virt` runs tests on the board, booting the program once a test,
as many at once as there are CPUs; there are no files there, so a golden
file's test fails and `--bless` is refused, and tests that need files stay
on this host. `l0 test -j N`, or `L0_JOBS=N`, runs up to N tests at once
on either, and writes their results in order; on this host it is one at a
time unless asked, since tests there share a directory and may write the
same files. A program there can also be a kernel: it
makes address spaces, maps pages into them, and runs threads in them until
they trap, and gives back a page, a space, or a frame once it is done with
it (`space_unmap`, `space_free`, `frame_free`; a frame only once no space
maps it), with the user-mode builtins of the spec's section 6.13 and the
library's `Trap` (`l0 doc Trap`), answering its threads' system calls with
`call_number`, `call_arg`, and `call_result`, which find a call's registers
on whichever CPU `(machine)` says it is, and sets the timer, and waits for and
ends interrupts, with those of section 6.14. It gives a device memory to
read and write itself, by DMA, as a frame, whose address `frame_address`
gives to write into the device's registers, and `(frame_sync f 1)` before
the device reads the frame and `(frame_sync f 2)` before reading what it
wrote, on every board, since on some DMA does not see the CPU's caches.
The board's own devices include the PCIe ECAM and MMIO window on the
aarch64 board, for a driver that finds and sets up a PCIe device
itself. `(frame_free_count)` says how
many pages are left for frames and tables, so it can refuse work that would
not fit; the pages standard input was loaded into join them once a read
reaches its end. `(heap_left)` says the same of its own heap, how many
bytes are free, counting what it freed at once, so a kernel can refuse
work before `heap exhausted` ends it; keep a few megabytes in reserve,
since free bytes in pieces may not make one value. It is -3 under an
operating system. `(board_reset)` restarts the board, on the
Pi 5 and the aarch64 board, and is -3 elsewhere, where `exit` is all there
is. A kernel can run threads on the other CPUs too, with the builtins of
the spec's section 6.18: `(cpu_count)` says how many there are, its own
included, `cpu_run` hands one a thread and returns at once,
`cpu_trapped` takes back the next that trapped, its context with the
CPU and a tag of the kernel's after it, and `cpu_wait` waits for that or
an interrupt. The program itself stays on CPU 0. The aarch64 board has as
many CPUs as `L0_QEMU_ARGS="-smp 4"` gives it, and one by default; the
Pi 5 has four; every other host has one. The board's own devices
include no virtio device; `L0_QEMU_ARGS="-device virtio-gpu-device"` adds
one, and any QEMU options there are added to how `l0 boot`, `l0 run`, and
`l0 test` start the board.

`l0 build --target pi5` builds an image for the Raspberry Pi 5, with no
operating system, which no emulator runs, so `l0 boot` refuses it. `l0 card
IMAGE DIR ARG ... < input` writes the files its SD card's boot partition
needs, beside the firmware's own: the image, `config.txt`, `cmdline.txt`
for the arguments, with `--l0-args` first so that the firmware's own, which
it puts before them, are not given to the program, and the input as an
initramfs. Its standard output and error are its debug UART; a status that
is not 0 is written there, and the board is powered off. It has run on a
Pi 5 (changelog, "The Raspberry Pi 5"), and its DMA is not coherent, so
`frame_sync` matters there.

Driving a Pi 5's devices, as seen on a 2 GB board (spec section 10.3 has
the tables; the values below were read there, through the regions):

- RP1, the chip with the USB, Ethernet, GPIO, and serial ports, is behind
  the PCIe controller at 0x1000120000, which is a region. Its window, at
  0x1F00000000, reads `0xdeaddead` until a driver sets, in the
  controller's registers: the root port's bus numbers, 0x00010100 at
  offset 0x18; its memory window, 0x00300000 at 0x20; RP1's BAR1 to 0,
  by writing 0x100000 (bus 1) to the configuration index at 0x9000 and 0
  to 0x8014, the data window's 0x8000 plus the register; and the
  outbound window, 0 at 0x400C and 0x1F at 0x4080 and at 0x4084. Then
  0x1F00000000 reads RP1's chip ID, 0x20001927. The link itself is up
  (status 0x3E0B0 at 0x4068); do not reset it.
- Any device's configuration space behind that controller is read and
  written the same way: bus << 20 | device << 15 | function << 12 at
  0x9000, then the register at 0x8000 plus its offset. The root port's
  own is at the controller's offset 0 (14e4:2712); RP1 is bus 1 device 0
  (1de4:0001).
- A device on RP1 reaches RAM at a bus address 0x1000000000 above the
  CPU's: a driver adds it to `frame_address` before giving it to the
  device.
- The VideoCore firmware answers property requests on the mailbox, at
  0x107C013880: write a request into a frame (little-endian words: total
  size, 0, then tags, each its ID, its value's size, 0, and the value;
  a 0 tag ends it), `(frame_sync f 1)`, wait while bit 31 of 0x38 is
  set, write the frame's address plus 8, the channel, to 0x20, wait
  while bit 30 of 0x18 is set, read 0x00, `(frame_sync f 2)`, and read
  the reply over the request: word 1 is 0x80000000 on success. The
  frame's address is the firmware's bus address, unchanged. Tag
  0x00010002 gives the board's revision.
- The HVS, the display's compositor, answers only if a monitor was on
  HDMI0 when the board booted (the firmware's log says `hotplug 1`).
  Without one, the first read of its registers hangs the board, with no
  fault and nothing printed.
- The system timer's four compare channels, registers at 0x0C to 0x18 of
  its region, raise interrupts 96 to 99; a write of 1 << channel to its
  offset 0 clears the match, before `interrupt_done`. All four are free.
- The debug UART is a real PL011 with its FIFOs on: its transmit
  interrupt comes only as the FIFO drains through its trigger level, not
  after each byte as on QEMU. A driver that waits for it after every byte
  first waits for the UART to be idle (UARTFR, 0x18, reads 0x80 under
  mask 0x88) and turns the FIFOs off (clear bit 4 of UARTLCR_H, 0x2C).
- RP1's interrupts come as MSIs, interrupts 160 to 223, edge-triggered:
  a write of n to bus address 0xFF_FFFFF000 is interrupt 160 + n, which
  the host has set up. To reach RP1's MSI-X table, also write 0x00400000
  to the root's memory window at 0x20, 0x400000 to BAR2 (0x8018), and
  0x410000 to BAR0 (0x8010); the table is then at 0x1F00410000. For RP1's
  vector v (its interrupt number, 0 to 60): write at 0x1F00410000 + 16 v
  the words 0xFFFFF000, 0xFF, n, and 0; OR 0x80000000 into
  configuration word 0xB0; then write 1 (enable), or 9 (enable and level)
  for a level-triggered source, to 0x1F00108808 + 4 v. After handling a
  level one, write 4 there to acknowledge it, or RP1 sends no more of it.
  These are set bits: the same at 0x1F00108C08 + 4 v clears them.
  Writing 2 there raises v as a test, which stays set until cleared.
- A kernel written in L0 runs on a Pi 5 as on QEMU, its processes'
  images in its standard input, which `l0 card` puts in the initramfs:
  `tests/virt/user/kernel.l0` has run there with its processes, the
  serial driver among them given the UART at 0x107D001000 and interrupt
  153.

`l0 build --target proc` builds a program as a process for a kernel on
aarch64, or riscv64 with `--arch riscv64`, in an address space of its own, reaching the kernel through the
system calls the spec's section 10.3 fixes. The kernel decides what the
program gets: files, arguments, and devices, or none. The image is a
static ELF, which section 10.3 lists: its code, rodata, and data are
segments a kernel maps from 0xC0000000, each with its own permissions,
and its heap starts at the page after them. What a kernel shares with a
process it maps from 0xE8000000 up to 0x100000000, or, for more than
that 384 MB, in the high user range, 128 GB from 0x2000000000 to
0x4000000000, which no image, heap, or stack uses. A kernel written in L0 can
take its processes' images from its own standard input, in a layout of
its choosing, read their headers as bytes, and be booted with them by
`l0 boot`. No kernel comes with the toolchain. Such a program also makes
its kernel's own calls, numbered from 256, with `supervisor_call`,
`supervisor_send`, and `supervisor_receive` (section 6.15); what each
means is that kernel's.

`l0 check` accepts files with no `main`, so `hello.l0` checks on its own;
`l0 build` and `l0 run` need one, and say so. `l0 run` builds into a
temporary directory, `$TMPDIR` or else `/tmp`, and deletes it when the
program ends; to keep the executable, or to build somewhere else, use
`l0 build ... -o PATH`.

When a declaration does not parse, `l0 check` reports that and checks the
rest; a use of the declaration that failed is not reported again, so fix
the syntax error and check once more.

**A function you define shadows a prelude function or builtin of the same
name**, and the prelude keeps calling the original, so a name L0 or the
standard library already took is never something you have to work around.
A type or constructor you declare shadows the library's of the same name in
the same way.

## When L0 cannot express something

**The L0 toolchain is read-only here.** Never edit the installed prelude or
compiler, and never vendor a patched copy. L0 is changed in its own
repository, not from projects that use it.

If L0 cannot express what was asked, say so plainly and name what could not be
written. Do not ship something that quietly narrows the task: a program that
does something adjacent to what was asked, with tests written from the same
narrowed contract, passes and is still wrong.

Anything a ten-line function solves is not a language limitation. A prompt, a
confirmation, or progress during a run is not one either: write it with a
`main` that takes no parameters and reads and writes as it goes, as the
`l0-code` skill shows, and so are files and command-line arguments. Files can
be renamed, deleted, and read in pieces; failures of each say which they
were; values of any type can be compared, ordered, hashed, and sorted; a
constructor can name its fields, which `(.field value)` reads and `(.field
value new)` replaces; a function can be passed by name to a parameter of
function type, `(fn (T) K)`, so a loop is written once; and `int`s have
bitwise operations. Memory is reclaimed automatically, and
`clock_ns` times part of a program, and `float` does IEEE arithmetic, with
`float_sin` and `float_cos` in the library. A network, the environment, listing or
creating directories do not exist yet. Floating point does, as `float`.

## Three traps specific to L0

**Quadratic output.** Building output by appending is quadratic; it passes
every small test and then appears to hang on real input. Accumulate with
`push` onto a reversed list and call `rev` exactly once at the end.

**The hidden whole copy.** `map_put`, `map_remove`, `array_set`, and a
field replacement `(.f r v)` update in place only when nothing else still
holds the map, array, or record, and otherwise copy it whole, with the same
results, so a loop of them turns quadratic unseen. Two shapes do it with no second name in sight: reading the map in a
later operand of the expression that updates it, as in `(Seen (map_put m k
true) (if (map_has m k) ...))`, and using a value after a call that updates
a map inside it, as in `(let t (space_put s ...) (... (space_number s)))`.
Read first, with `let`, and update last; `L0_ARRAY_STATS=1` on a run counts
the copies.

**Deep nesting and parentheses.** Long `if` and `or` chains end in a dozen
closing parens and are the most common source of parse errors. Indent each
line under its form and run `l0 fmt` before `l0 check`, which adds the
closers a dedent or the next declaration shows missing and drops those with
nothing to close; write several bindings as one `let`, `(let (a 1 b 2)
body)`, and a run of tests as one `if`, `(if c1 e1 c2 e2 else)`; use `split_spaces` with `any_eq` for
membership tests, and split any function nesting more than about four
levels deep.

The `l0-code` skill covers all three in detail, along with the syntax that
differs from what other languages would lead you to expect.
<!-- l0 init: end -->
