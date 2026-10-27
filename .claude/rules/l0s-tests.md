---
description: L0S test rules, for unit tests, board tests, e2e cases and screen tests
paths:
  - "**/*_test.l0"
  - "tests/**"
globs: "**/*_test.l0,tests/**"
alwaysApply: false
---

# L0S test rules

The `l0s-testing` skill has the detail; load it before writing tests.

- Under `l0 test` there is no kernel: the kernel's word is -3, which each
  call's typed answer reads as its first failure (or `SendFull`, as -3 is
  err_full), and receives fail. Test
  pure functions, and that each program's entry point returns 1 there,
  commented `; Under an operating system there is no X.`
- Compare structures by rendering them as text (`check_str`), so a failure
  shows where. Pin exact numbers and say in a comment how they follow.
- One to three assertions a test, many tests. A property test checks a few
  hundred seeded cases (`rand_next`) against an obvious version.
- A new system call gets board tests in `kernel/kernel_virt_test.l0`,
  refusals included.
- An e2e case is `tests/e2e/CASE/` with `etc/inittab` and `expected`, plus
  `status`, `stderr`, `typed` (then start `uart noecho`), `font`, `bootargs`,
  `cpus` (the board's CPUs, 1 for a case whose output depends on which
  program runs first, whatever `QEMU_CPUS` asks; otherwise `QEMU_CPUS`,
  1 unless set),
  `gpu` (the virtio-gpu's options, such as a 4K mode), `net` (a
  virtio-net on the QEMU network it names; `serve` and `peer`, host
  commands for the boot, with `@PORT@` a free port), or `disk` with its
  `layout`
  (a fresh virtio-blk disk) as needed.
- Screen tests keep sockets and dumps in `build/`, with relative paths
  (sockets need paths under 104 bytes), each named for its test, as
  `make e2e` runs several at once; a new one joins `SCREEN_TESTS`. Remove any debug output added to
  find a failure.
