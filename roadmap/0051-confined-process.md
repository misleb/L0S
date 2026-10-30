# 0051: A process confined to a directory, reaching no server

Track: Kernel · Status: ready · Needs: – · Spec: kernel.md, syscalls.md, storage.md, programs.md, testing.md

## Why

0043's agent runs programs for the model: anything in `/bin` and
`/Applications`, and a line at `sh`, with no person's yes. What keeps
that safe is that they reach only the agent's home. L0S cannot say so
today. Any process:

- opens, writes, renames and removes any file of any volume, as the
  kernel's file calls check nothing of who asks;
- finds every server by name (`name_lookup`) and sends to any port,
  so it can ask `fs` to `format` a volume, `inet` to open a
  connection, or `wm` anything;
- reaches a volume's server straight, through `mount_at`'s port, for
  `list`, `mkdir`, `stat`, `chmod`, `format`, `relabel` and `unmount`;
- ends any process without a `dev` line (`proc_kill`) and restarts the
  board (`board_restart`).

`spawn_image` already gives no devices, so "no `dev` lines" holds; the
rest needs the kernel. A process started *confined* to a directory, its
home, sees the files under it and, to read and run, `/bin` and
`/Applications`; and reaches no server and no port but its own and its
terminal's. Its children are confined as it is. 0045's programs, which
the agent builds for itself, are run the same way.

## Done when

- `spawn_confined` (call 304) starts a program from its image confined
  to a home, on a terminal port the caller gives, its current directory
  the home. Whatever a confined process starts is confined to the same
  home.
- A confined process's file calls reach only its home, to read and
  write, and `/bin` and `/Applications`, to read; anything else is not
  there (-3), and a write outside the home is refused. `..` does not
  leave the home.
- It finds no name, sends only to its own ports and its terminal, gets
  no mount's port, and may not kill, restart the board, mount, unmount
  or make a volume `/`.
- `list`, `stat`, `mkdir` and `chmod` are asked through the kernel
  (call 305), which checks a confined caller's paths, for every
  program, so a confined `sh` lists and makes directories in its home.
- `run confine DIR PROGRAM [ARG...]` starts a program confined, and an
  e2e case shows a confined shell at work and refused. Board tests
  cover both calls and each refusal. `make check`, `make test`, `make
  e2e` and `make test-virt` pass.

## Steps

- [ ] **The call.** By the system call checklist (`l0s-dev`): the
  kernel's `Life` gains a confinement, the home's absolute path, empty
  for none, given to every process a confined one starts
  (`spawn_entry`, `spawn_entry_with`, `spawn_image`), as the current
  directory is (`k_child_cwd`). Call 304 (or the next number free when
  this is built; 305 below likewise), `spawn_confined`, reads one
  buffer as `spawn_image_bytes` lays it out with the home and the
  terminal's port before (`spawn_confined_bytes path args image home
  tty`): the home must be a directory, checked as `chdir` checks one
  (-3 none, -9 a file), and inside the caller's own home if it has
  one; the port must be the caller's own or its terminal (-1); then as
  287, the child's current directory the home and its terminal that
  port. `l0s.l0`'s `spawn_confined` gives a `Spawn`; `paths.l0`'s
  `spawn_path_confined path args home tty` reads the program's file
  as `spawn_path` does. `proc_info` says a process is confined (a bit
  of its record), and `ps` marks it. Board tests: the child's `getcwd`
  is the home; a grandchild started by `spawn_image` is confined too; a
  home that is a file, is missing, or is outside the caller's; a port
  not the caller's; a bad buffer.
- [ ] **No server, no port.** For a confined caller: `name_lookup` is
  `NotFound` for every name and `name_register` refused (-6);
  `port_send` reaches only its own ports and its terminal's, any other
  `SendNoPort`, so it cannot learn there is one; `mount_at` gives none;
  `proc_kill`, `board_restart`, `fs_mount`, `fs_unmount`,
  `root_switch` and `tty_set` to another's port are refused (-6). Its
  terminal still serves it as now: the kernel's `r` for its standard
  input, its writes, and its own `p` and `i` requests. Board tests, one
  each, from a process the test starts confined.
- [ ] **Its paths.** The kernel's `open`, `rename`, `remove` and
  `chdir`, after `path_resolve`, check a confined caller's path: under
  its home, as now; under `/bin` or `/Applications`, to read only
  (`open` to write, `rename` and `remove` are -4); anywhere else -3, as
  if nothing were there, a rename between the home and outside it
  included. `entry_path_of` (269) gives a confined caller the entries
  under those three only, empty for any other, so `entry_paths` and
  `root_paths` list no more. The checks are a pure `confine_allows
  home path write` in [kernel/process.l0](../kernel/process.l0) or a
  file of its own, host tested: `..` out of the home, a home that is a
  prefix of another name (`/home/a` and `/home/ab`), `/bin` itself,
  the root. Board tests of each call.
- [ ] **Directories through the kernel.** Call 305, `path_ask op path
  [more]`: `list`, `stat`, `mkdir` or `chmod` of path, made absolute
  from the current directory, checked as step 3 checks a confined
  caller's (`list` and `stat` read, `mkdir` and `chmod` write), sent to
  the volume's server as from the caller, as the kernel's file calls
  are (`ask_fs`), and its reply given back in the caller's buffer; the
  initramfs's answered by the kernel as `stat` and `list` would be.
  `fs.l0`'s `fs_path_ask` asks through it for every program, so
  there is one way to a path, and nothing reaches `fs` with a path the
  kernel did not see. storage.md's Limit ("Only `open`, `rename`,
  `remove` and `chdir` take paths in the kernel") goes. Board tests;
  the `files`, `fs`, `dirs` and `tmpfs` e2e cases still pass.
- [ ] **`confine`, and the e2e case.** `user/bin/confine`: `run confine
  DIR PROGRAM [ARG...]` starts PROGRAM, found as `run` finds one,
  confined to DIR on the caller's terminal, waits for it and exits
  with its status. The case `confined`, with a disk and `typed`: `mkdir
  /Volumes/data/box`, `run confine /Volumes/data/box /bin/sh`, and in
  that shell `pwd`, `write note hi`, `mkdir d`, `ls`, `cat note`,
  `run hello`, `cat /etc/motd` (no such file), `ls /Volumes/data` (no
  such directory), `cd ..` (stays), `run net` (no inet), `kill 1` and
  `reboot` (refused), `format data` (refused), `exit`; then, outside,
  `cat /Volumes/data/box/note`. `expected` follows. kernel.md's
  "Confined processes"; syscalls.md's 304 and 305; programs.md's
  `confine` row; testing.md's case.

## Spec changes

- kernel.md: a section, "Confined processes": what a confined process
  reaches and what it is refused, and that its children are confined
  as it is; Limits: the home is a path, kept as text, so a volume
  relabelled or unmounted under it leaves the process seeing nothing.
- syscalls.md: calls 304 and 305; and for each call a confined process
  is refused, its refusal.
- storage.md: `list`, `stat`, `mkdir` and `chmod` asked through the
  kernel; the Limit on paths in the kernel gone.
- programs.md: `confine`'s row; `paths.l0`'s `spawn_path_confined`.
- testing.md: the `confined` case.

## Log

- 2026-10-29: written with 0043's steps, which need it: the agent runs
  programs with no person's yes, so they must reach nothing but its
  home, and L0S had no way to say so. A goal of its own, in the Kernel
  track, since it is the kernel's and 0045's programs need it too, and
  it can be built while 0041 and 0042 are.
