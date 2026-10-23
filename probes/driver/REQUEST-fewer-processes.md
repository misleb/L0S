# Feature request: an l0 driver that starts fewer processes, and runs tests in parallel

Status: landed in part, as newlang commit ddeb7e1: changes 1, 2 and 4
Project: L0S, a microkernel in L0 for QEMU's virt board, heading for the
Raspberry Pi 5

> **Since landing:** `l0 test` looks for a leak report only when a test
> wrote on standard error, and for `(blessed` only under `--bless`, and
> measures a bundle's files with one `wc`. `l0 test -j N`, or `L0_JOBS`,
> runs up to N tests at once, writing their TAP lines in order: one at a
> time on this host unless asked, since tests there share a directory, and
> the CPU count on the board. L0 left out change 3, a file's tests in one
> process, as worth measuring after these. With the driver installed on
> 2026-10-23 from ddeb7e1, the 28-test file below starts 11 helpers in
> all, where it started about 140, and every suite passes:
>
> | Suite | Before | After |
> |---|---|---|
> | `make check` | 48 s | 23 s |
> | `make test` | 441 s | 279 s |
> | `make test` with `L0_JOBS=14` | | 259 s |
> | `make test`'s 127 runs, 4 at a time | 202 s | 90 s |
> | `make test`'s 127 runs, 14 at a time | 209 s | 77 s |
> | `make test-virt` | 72 s | 20 s |
>
> Now that each test no longer starts helpers, compiling and linking
> are most of what is left, about 1 s per test file against about 20 ms
> per test. That is CPU work, so running L0S's test files side by side
> now pays 3.6 times, where it paid 2. L0S's Makefile now does it: each
> check and test file is a target of its own, run `JOBS` at once and only
> once it changes, and `make check` takes 9.9 s and `make test` 84 s from
> nothing, half a second each with nothing changed. `L0_JOBS` on the host
> gains little more. One of L0S's host tests writes a file,
> `build/cli_test.tmp`, from one test only, so it would be safe for them.
>
> **A correction:** L0S has 2,079 host tests, not 4,584 as below and in
> L0's changelog. The larger count also took in a second checkout of
> L0S, under `.claude/worktrees`. The helpers therefore came to about 3
> minutes of the 7 minutes 20 seconds, not 6, which matches the 162 s
> the change saved. The rest of this document describes the driver as it
> was when this was written.

L0S checks its code with `make check` (45 runs of `l0 check`) and tests it
with `make test` (127 runs of `l0 test`, 2,079 tests) and `make
test-virt` (214 tests on the board). On the Mac it is developed on, `make
test` takes 7 minutes 20 seconds, though the whole run uses about 3
minutes of CPU. Most of the rest is the driver, `bin/l0`, starting helper
processes: `grep`, `sed`, `wc` and `tr`, a few for every test and every
source file. Running L0S's commands side by side helps only about 2
times, at 4 jobs or 14 alike, because process launches, not CPU, are
what runs out.

This asks for four changes to the driver, smallest first. None touches
the compiler, the runtime, or the specification, and none changes what
`l0 check` or `l0 test` print.

## Where the time goes

Measured on a 14-core Apple Silicon Mac, macOS 26.6.2, with the toolchain
installed on 2026-10-23 and QEMU 11.1.2. The Mac runs an endpoint
security agent (ThreatLocker) that vets every program launch, as many
company machines do. There, starting any process costs about 15 ms, and
launches barely overlap:

| 280 runs of `/bin/echo` | 1 at a time | 4 at a time | 14 at a time |
|---|---|---|---|
| wall clock | 4.67 s | 3.85 s | 3.44 s |

L0S's suites, run as `make` runs them and then the same commands side by
side through `xargs -P`:

| Suite | 1 at a time | 4 at a time | 14 at a time | CPU time |
|---|---|---|---|---|
| `make check`, 45 `l0 check` | 48 s | 26 s | 27 s | 19 s |
| `make test`, 127 `l0 test`, 2,079 tests | 441 s | 202 s | 209 s | 186 s |

All tests passed in every run. If CPU were the limit, 14 cores would
finish `make test` in well under a minute.

### Per test: about 80 ms of helpers beside 25 ms of test

`l0 test common/abi.l0 common/text.l0 common/text_test.l0`, 28 tests:

| What ran | Wall clock |
|---|---|
| all 28 tests | 4.67 s |
| 1 test (`--match format_size_large`): compiling, linking, one run | 1.66 s |
| so each further test | about 110 ms |

Tracing the same run with `sh -x` shows, for each passing test, one run
of the test program and three helpers:

- `grep -q '^l0: blocks still live' "$TMP/t.err"` (`bin/l0` line 1039),
  even when `t.err` is empty;
- `grep ' (blessed ' "$TMP/t.out" | sed 's/^/  # /'` (line 1062), even
  without `--bless`.

Timed alone, 100 rounds of those three helpers take 8.1 s, 81 ms a test,
and 100 runs of an L0 host program take 2.4 s, 24 ms each. Across L0S's
2,079 tests the helpers alone come to about 3 minutes of the 7 minutes 20
seconds.

### Per command: two processes for every source file

`write_bundle` (line 281) measures each file with `size=$(wc -c < "$f" |
tr -d ' ')`, and `setup` (lines 324 and 327) measures the prelude the
same way. An L0S program is 15 to 25 files, so each `l0 check` of one
starts 40 or so `wc` and `tr`: `sh -x` counts 20 of each for the kernel's
check. At 15 ms a launch that is about 0.6 s of the kernel's 1.2 s check,
and the compiler's work is the rest.

### On the board: one boot per test

`l0 test --target virt` boots QEMU once a test (`run_one`, line 1012).
`make test-virt`'s 214 tests took 72 s on the Mac, a third of a second a
boot, one after another, using 47 s of CPU on one core while the other 13
idled. Each boot is one launch and then QEMU's emulation, mostly CPU, so
these, unlike the host's helpers, should run side by side at close to
full speed.

## Smallest change that would help

Four changes, each worth having alone, in the order they pay.

### 1. Start no helper whose answer is known

- Look for `blocks still live` only when `t.err` is not empty:
  `[ -s "$TMP/t.err" ] && grep -q ...`. A test that passes writes nothing
  there.
- Look for `(blessed` only when `--bless` was given, which is the only
  time a test writes it.

That leaves one process a passing test, the test itself, and takes about
80 ms off each: some 3 minutes off L0S's `make test` on this Mac. What is
printed is unchanged.

### 2. Measure every file with one `wc`

`wc -c FILE ...` prints every size in one process. `write_bundle` and
`setup` could read its lines with the shell's own `read`, instead of a
`wc` and a `tr` a file. That takes about 0.6 s off each `l0 check`, `l0
build` and `l0 test` of an L0S program here, 30 s off `make check`.

### 3. Run a file's tests in one process

The generated `main` takes one test's name today. It could take several,
or none for all, run them in order, and write one line a test, its name
and its status, after each one. The driver would turn those lines into
TAP as now. Then:

- a test that dies with a runtime error ends the process; the driver
  reports it from the line it never got, and starts the program again on
  the tests after it;
- an `expect_NAME` test, which must die, keeps a process of its own, as
  now;
- the leak check of section 10.3 runs once, at the end; if it reports
  blocks still live, the driver runs the tests again one at a time to say
  which one leaked, so a leak is still blamed on its test.

That takes another 25 ms a test off here, and on any machine turns 2,079
launches into about 130. It needs nothing of the language: the generated
`main` already compares a name with each test's, and would only loop.

### 4. `l0 test -j N`, for the board most of all

Run up to N tests at once, each in its own temporary directory, and
print their TAP lines in test order, as now. `-j` could default to 1, so
nothing changes unasked, or to the number of cores; `L0_JOBS` could set
it for a whole project. On the host, after change 3, this matters less.
On `--target virt`, where each test is a boot, it should cut
`test-virt`'s 72 s by close to the number of cores, though that is
untried.

## Left out, on purpose

- **Caching compiled programs.** A check takes about 0.6 s of the
  compiler's time for L0S's largest programs. Reusing earlier work would
  need the compiler to compile files apart, which L0 doesn't do, and the
  project's `make` already skips images whose sources haven't changed.
- **Dependency tracking.** L0 has no imports: the command line lists
  every file, so a project's Makefile already knows what each program
  depends on. Running only the tests whose files changed is L0S's to do.
- **Parallel compiling.** One program is compiled in one piece, and the
  machine's other cores are better spent on other programs or tests.

## Which deliberate restriction this breaks

None. These are changes to `bin/l0` alone. The language, the compiler,
the runtime and the specification stay as they are, and `l0 check` and
`l0 test` print what they do now, in the same order.

## Alternatives considered

- **Running more of L0S's commands at once.** Measured above: about 2
  times faster, and no further from 4 jobs to 14, because each command
  still starts its helpers, and launches don't overlap here.
- **A machine without the agent.** Launches there are cheaper, so the
  helpers matter less; this wasn't measured. But agents like this one are
  common on company machines, and changes 1 to 3 cost nothing where
  launches are cheap.
- **A test runner of L0S's own.** It would have to repeat what `l0 test`
  does: find the tests, generate `main`, compile, run, and write TAP,
  and keep up with every change to it. Every other L0 project would pay
  the same costs.

## To reproduce

From the top of L0S, in bash:

```bash
time (seq 280 | xargs -n1 -P 1 /bin/echo > /dev/null)
```

```bash
time l0 test common/abi.l0 common/text.l0 common/text_test.l0
```

```bash
time l0 test --match format_size_large common/abi.l0 common/text.l0 common/text_test.l0
```

```bash
sh -x "$(command -v l0)" test common/abi.l0 common/text.l0 common/text_test.l0 2>&1 >/dev/null | grep -cE '^\+ (grep|sed)'
```

That prints 84: three helpers for each of the 28 tests.

```bash
time make -s test
```
