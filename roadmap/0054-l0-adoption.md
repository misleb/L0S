# 0054: L0S written in the L0 of roadmap 0132 to 0144

Track: Tooling · Status: done · Needs: L0 0132, 0133, 0134, 0135, 0136, 0137, 0138, 0139, 0140, 0141, 0144 · Spec: testing.md, kernel.md, storage.md, syscalls.md, toolkit.md, boot.md

## Why

L0 gained named fields, `l0 fmt`, a `let` of several bindings and an
`if` of several tests, functions as arguments, word wrappers that cost
nothing, an `and` and `or` that stop at the operand that decides, the
library's regions under their own names, a warning wherever an update
copies a whole map, array or record, and a specification in several
files. [l0s-adoption.md](l0s-adoption.md), L0's guide, says what each
is and where L0S gains. Nothing L0S compiled stopped compiling, but
`l0 spec --path` naming every file broke the Makefile's `L0LIB`, and
L0S was written around the forms these replace: 418 functions that read
one field, 189 that rebuild a record to replace one, and closers in
runs of a dozen.

## Done when

- `make check` runs `l0 fmt --check` over every `.l0` file and shows
  every warning `l0 check` gives, and gives none but the two rollbacks
  the Log names.
- The guide's greps for the old region names, for one-field accessors
  and for one-field rebuilds find nothing in L0S.
- The graph and `make doc` read the new forms: a named field, a `let`
  of several, a generic def, a def passed by name.
- The skills, rules and spec teach the new forms, and none the old.
- `make check`, `make test`, `make test-virt` and `make e2e` pass.

## Steps

- [x] The Makefile's `L0LIB` from the first file `l0 spec --path`
  names; `make fmt`, the format check in `make check`, and the
  warnings `make check` shows; the six files `l0 fmt` would change
  made as it leaves them.
- [x] `tools/graphify-l0` reads named fields, a `let` of several,
  generic defs and their type parameters, and `.field`;
  `make doc Q=NAME` finds a type by a field's name.
- [x] The copy warnings `make check` showed, 38, made none but two.
- [x] Every region named as `lib/io.l0` names it now: `IoRegion`,
  `open_region`, `region_get32` and the rest.
- [x] Named fields for every type of one constructor, its accessor and
  one-field rebuild functions gone, area by area.
- [x] The sugar where it shortens: one `let` for a nest of them, one
  `if` for a chain, `and` and `or` for guards, a function parameter
  for families of loops alike but in one call, and word wrappers for
  the kernel's spaces and frames.
- [x] The skills, rules and spec say so.

## Spec changes

- testing.md: `make check` checks the format, `make fmt` writes it, and
  `make check` ends with every warning its checks gave.
- kernel.md, storage.md, syscalls.md: regions by L0's names now.
- toolkit.md: L0 passes functions as arguments but keeps none in a
  value, so a widget still carries an action's name.
- kernel.md, syscalls.md, boot.md: "spec 10.3" names its file, `l0 spec
  process` or `l0 spec runtime`.

## Log

- 2026-10-30: written from L0's guide. Under the new toolchain all 61
  checks and 3,541 host tests, 276 board tests and every e2e and screen
  test passed as they were, once `L0LIB` took the first path.
- 2026-10-30: `l0 fmt --check` would have changed six files: three
  lacked a final newline; three had a `match`'s arms, or a call's last
  arguments, indented left of the form they belong to, which fmt reads
  as a dedent and would have closed early. Those were indented under
  their form. fmt did as its guide says, so nothing went to L0.
- 2026-10-30: the copy warnings, 38, came to 2. Most read a value after
  handing it to a function that updates it: the reads now come first
  (`k_forget`, fs's `settled`, `emptied`, `written`, `do_partition`,
  `fv_rename_over`; xhci's port lines; vt's `refreshed`). Where a
  function gave nothing back to go on with, it now does: fs's
  `TurnNone` carries the turns, virtio-gpu's `fl_retire_one` the
  flight, wm's `draw_bar` and `titles` the `Wm` with its bar canvas
  drawn on, and painters' callers keep the canvas they return, as
  `render.l0`'s `Canvas` asks. fs's `relabel_table` takes the store and
  UUID, not an `Fs`; virtio-gpu's `drv_replied` the old layers, not the
  old driver, which removed a copy of the driver on every request; svg's
  `svg_inherit` makes the child's few properties a map of their own.
  The two left are `hvs`'s and virtio-gpu's first frame, which go back
  to the driver as it was if the wallpaper cannot be shown: the copy is
  that rollback, once a boot.
- 2026-10-30: the regions renamed, 831 names in 41 files, the probes'
  too; the guide's grep for the old names finds nothing. The kernel and
  spec pages' prose say the new names. `make check`, `make test` (3,542),
  `make test-virt` and `make e2e` (69 cases, 19 screen tests) pass.
- 2026-10-30: named fields. 153 types of one constructor name them, and
  some 360 accessors and 70 one-field setters are gone, their 3,200 calls
  now `(.f x)` and `(.f x v)`; a rebuild that computes its new value is
  a field replacement now. The guide's grep for accessors finds three
  reads, of `LeaseRun`, which has two constructors; its grep for
  rebuilds finds those that change two fields or more, which stay
  matches. A field read where the record still holds it, which the
  accessors had hidden, showed as new copy warnings: the kernel's ports
  and CPUs and l0fs's cluster table were each copied whole on every
  update through them. They are taken apart and built again now
  (`k_port_new`, `k_registered`, `k_cpus_back`, `k_unmapped`,
  `vol_alloc_in`, font's `font_swept`), or read first. `make check`
  (2 warnings), `make test` (3,542, and with `L0_RC_CHECK=1`),
  `make test-virt` and `make e2e` pass.
- 2026-10-30: the shorter forms, through every file: 991 lets of several
  bindings where nests of them were, chains of `if` made one `if` of
  several tests, and `and` and `or` for guards, 781 of them where there
  were 3. Lines ending in nine closers or more went from 1,092 to 777,
  most of those left closing nested matches; the sources are 96,768
  lines, 1,500 fewer. A guard whose branch is a loop's recursive call
  stays an `if`, as `or`'s second operand is no tail position;
  `user/lib/ui/metrics.l0` stays as `mkmetrics` writes it. No family of
  loops was folded into a function parameter: the ones alike differ in
  more than one call, or would need a wrapper a call. The kernel's
  address spaces are a type, `memory.l0`'s `Space`, `(.id s)` at each
  builtin; frames stay ints, as typing them would retype every page map
  of `memory.l0` and `process.l0`.
- 2026-10-30: done. The skills (`l0s-dev`, `l0s-testing`, `l0s-ui`), the
  rules and `AGENTS.md`'s own part teach the new forms, `make fmt`, the
  copy warnings, `L0_ARRAY_STATS` and `L0_RC_CHECK`; the spec names the
  regions by their new names and `l0 spec process` for what was "spec
  10.3". `make check` (2 warnings, the rollbacks), `make test` (3,542,
  and again with `L0_RC_CHECK=1`), `make test-virt` (276, on one CPU and
  on four), `make e2e` (69 cases, 19 screen tests) and `make graph`
  pass. `e2e`'s `cpu_usage` failed once in five whole runs, `ping`
  finding no `echo` 300 ms after starting it while three spins held the
  other CPUs and the host booted many boards; it passed alone every
  time, and the run after.
