---
description: L0S project rules, for every change
alwaysApply: true
---

# L0S rules

L0S is a microkernel and its programs, in L0. Besides `AGENTS.md` (the L0
language, which `l0 init` writes) there are three L0S skills: `l0s-dev` (the
map, checklists for adding programs, libraries, requests and system calls,
pitfalls), `l0s-testing` and `l0s-ui`. Load the one that fits before
changing code.

- **Look things up first.** `make -s doc` lists every documented name in
  L0S's libraries; `make -s doc Q=NAME` shows one, `Q=FILE` (a stem such as
  `l0s` or `wm`, or the end of a path such as `sbin/wm/wm`) a whole file,
  any other `Q=TEXT` searches. Queries reach the programs' and tools' own
  sources too, after the libraries'. `l0 doc` does the same for the L0
  standard library. Use both before writing a helper, and before grepping
  for a name; grep is for finding where something is used.
- **Done** means `make check` and `make test` pass, and also `make e2e` for
  anything that boots, drives a device, draws or takes input, and
  `make test-virt` for the kernel. Say which ran; never claim L0 code works
  without them.
- **Document every top-level form** with a `;` block directly above it, no
  blank line between, and start every file with `; FILE.l0 -- summary`.
  `make doc` reads exactly that, and `make check` fails on a form without
  one unless `tools/l0sdoc/undocumented.txt` lists it from before. Never
  add a line there; after documenting a listed form, `make doc-prune`.
- **New library?** Add it to the Makefile's `DOC_SRCS`, a `test` line, and
  the `LIBS_` lists that need it.
- **Keep the README's tables true** in the same change: programs,
  libraries, protocols, system calls, the demo's pids, tests, limits.
- **Edit source with the editor tools**, not sed, awk or script rewrites.
- **Commit** only when asked, and never `build/`.
- **If `AGENTS.md` has lost its L0S block** (between `<!-- L0S begin -->`
  and `<!-- L0S end -->`), `l0 init` has replaced it: restore the block from
  git (`git log -p -- AGENTS.md`). The rest of that file is `l0 init`'s and is
  not edited here.
