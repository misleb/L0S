---
description: L0S project rules, for every change
alwaysApply: true
---

# L0S rules

L0S is a microkernel and its programs, in L0. Besides `AGENTS.md` (L0S's
overview, with the L0 language in the block `l0 init` writes) there are three L0S skills: `l0s-dev` (the
map, checklists for adding programs, libraries, requests and system calls,
pitfalls), `l0s-testing` and `l0s-ui`. Load the one that fits before
changing code.

- **Look things up first.** `make -s doc` lists every documented name in
  L0S's libraries; `make -s doc Q=NAME` shows one, `Q=FILE` (a stem such as
  `l0s` or `wm`, or the end of a path such as `sbin/wm/wm`) a whole file,
  any other `Q=TEXT` searches. Queries reach the programs' and tools' own
  sources too, after the libraries'. `l0 doc` does the same for the L0
  standard library. Use both before writing a helper, and before grepping
  for a name. For who calls a name and what a change to it reaches, ask
  the knowledge graph, `graphify explain "NAME()"` and `graphify affected
  "NAME()"` (AGENTS.md's "Learning the code"), before opening files; grep
  is for text, and for what the graph cannot resolve.
- **Done** means `make check` and `make test` pass, and also `make e2e` for
  anything that boots, drives a device, draws or takes input, and
  `make test-virt` for the kernel. Say which ran; never claim L0 code works
  without them.
- **Document every top-level form** with a `;` block directly above it, no
  blank line between, and start every file with `; FILE.l0 -- summary`.
  `make doc` reads exactly that, and `make check` fails on a form without
  one unless `tools/l0sdoc/undocumented.txt` lists it from before. Never
  add a line there; after documenting a listed form, `make doc-prune`.
- **Bytes, not lists.** Data that arrives or leaves as bytes (messages,
  files, sectors, frames, images) stays `bytes`, read in place (`msg_`
  accessors, `le_u32`, `be16_at`, `bytes_is_at`) and sent as a range
  (`port_send_bytes`, `port_forward`, `put_bytes_range`). Make a list only
  to parse text or build output, and convert once. Never round-trip
  through a list, and never `bytes_from_list` a list to read a field. The
  `l0s-dev` skill's "Bytes, not lists" has the helpers.
- **New library?** Add it to the Makefile's `DOC_SRCS`, an `l0_test` line, and
  the `LIBS_` lists that need it.
- **Keep the README's tables true** in the same change: programs,
  libraries, protocols, system calls, the demo's pids, tests, limits.
- **Edit source with the editor tools**, not sed, awk or script rewrites.
- **Commit** only when asked, and never `build/`.
- **`AGENTS.md` is L0S's**, except the block between the
  `<!-- l0 init: begin ... -->` and `<!-- l0 init: end -->` lines, which
  `l0 init` rewrites and which is not edited here. Keep L0S's own text
  outside those markers.
