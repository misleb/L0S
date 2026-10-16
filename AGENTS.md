# Working with L0 in this project

L0 is a statically typed language compiled to native code through LLVM.
**There is almost certainly no L0 in your training data**, so familiarity
cannot substitute for reading the specification and running the checker.

## Invariants

**The specification is the only source of truth about L0.** Not this file, not
the examples. If a construct is not in it, it does not exist. `l0 spec --path`
names the file; read it before writing L0 for the first time in a session.

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
parameters, maps and hashing, reading and writing, files and telling their
failures apart, replacing and deleting files, reading in pieces, arrays and
grids, bytes, bits, ordering and sorting, timing, and driving a device,
and tests of them.

Everything these commands show comes from the installed toolchain, so it
always describes the compiler that builds this project. Nothing of it is
copied here.

## Commands

```bash
l0 check hello.l0 main.l0         type check
l0 test  hello.l0 hello_test.l0   run every (def test_NAME () int ...), as TAP
l0 run   hello.l0 main.l0         build and run, reading stdin; -- ARGS after
l0 build hello.l0 main.l0         produce the executable ./hello
l0 doc   [NAME | TEXT]            the standard library, or one name, or a search
l0 spec  --path                   where the specification is
```

Several files are compiled together, since L0 has no module system. The
standard library is linked automatically, and `l0 test` adds its assertions,
so never pass library files on the command line.

`l0 build --target virt` builds an image for QEMU's aarch64 `virt` board,
with no operating system, and `l0 boot IMAGE ARG ... < input` runs one
(`l0 run --target virt -- ARG ...` does both). There the program has
standard input, output, and error, the clock, and arguments, its boot
arguments, which hold no spaces, but no files and no environment: the
spec's section 9.2 says what each builtin gives then. It also has the
board's devices, which a program drives through their registers with
`open_device` and `device_read32` and the rest (`l0 doc IoDevice`); under
an operating system there are none, and opening one fails. `l0 test
--target virt` runs tests on the board, booting the program once a test;
there are no files there, so a golden file's test fails and `--bless` is
refused, and tests that need files stay on this host. A program there can also be a kernel: it
makes address spaces, maps pages into them, and runs threads in them until
they trap, and gives back a page, a space, or a frame once it is done with
it (`space_unmap`, `space_free`, `frame_free`; a frame only once no space
maps it), with the user-mode builtins of the spec's section 6.13 and the
library's `Trap` (`l0 doc Trap`), and sets the timer, and waits for and
ends interrupts, with those of section 6.14. It gives a device memory to
read and write itself, by DMA, as a frame, whose address `frame_address`
gives to write into the device's registers. The board's own devices
include no virtio device; `L0_QEMU_ARGS="-device virtio-gpu-device"` adds
one, and any QEMU options there are added to how `l0 boot`, `l0 run`, and
`l0 test` start the board.

`l0 build --target proc` builds a program as a process for a kernel on
aarch64, in an address space of its own, reaching the kernel through the
system calls the spec's section 10.3 fixes. The kernel decides what the
program gets: files, arguments, and devices, or none. The image is raw,
its bytes from 0xC0000000, as a kernel maps them, so a kernel written in
L0 can take its processes' images from its own standard input, in a
layout of its choosing, and be booted with them by `l0 boot`. No kernel
comes with the toolchain. Such a program also makes
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
were; values of any type can be compared, ordered, hashed, and sorted; and
`int`s have bitwise operations. Memory is reclaimed automatically, and
`clock_ns` times part of a program. A network, the environment, listing or
creating directories, and floating point do not exist yet.

## Two traps specific to L0

**Quadratic output.** Building output by appending is quadratic; it passes
every small test and then appears to hang on real input. Accumulate with
`push` onto a reversed list and call `rev` exactly once at the end.

**Deep nesting and parentheses.** Long `if` and `or` chains end in a dozen
closing parens and are the most common source of parse errors. Use
`split_spaces` with `any_eq` for membership tests, and split any function
nesting more than about four levels deep.

The `l0-code` skill covers both in detail, along with the syntax that differs
from what other languages would lead you to expect.
