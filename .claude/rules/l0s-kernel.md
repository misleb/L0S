---
description: L0S kernel rules, for the kernel and the code it shares with programs
paths:
  - "kernel/**"
  - "common/**"
globs: kernel/**,common/**
alwaysApply: false
---

# L0S kernel rules

The `l0s-dev` skill has the checklist for adding a system call.

- **Nothing a process does can crash the kernel.** Check every buffer,
  count, address, path, pid, port and interrupt number against the kernel's
  own records before it reaches a builtin that could raise a runtime error;
  answer a bad one with an error code from `common/abi.l0`.
- Keep the modules other than `kernel.l0` and `process.l0` pure, and test them
  on the host (`make test`). Test the kernel itself on the board
  (`make test-virt`, `kernel/kernel_virt_test.l0`), refusals included.
- `common/` is linked into the kernel and into every program: a new name
  there must clash with neither.
- A system call's number, decoding, handler, wrapper and README row change
  together.
