# 0024: `fs` serves its clients fairly, small requests first

Track: Storage · Status: done · Needs: 0023 · Spec: storage.md, testing.md

## Why

`fs` serves its one port first come, first served, each request to its
end, its disk requests included, before it takes the next message
(`serve` in [fs.l0](../user/sbin/fs/fs.l0)). It is fair by count only
because every client waits for its answer: the kernel parks a process
in `AwaitingFs` for each file call, and `fs_ask` waits on `port_ask`. So:

- **A cheap request waits behind dear ones.** A `stat` or `open` waits
  for every read and write ahead of it, and for a `format`, `mkfs` or
  `partition` to its end. With 0023's runs of 64 KB a turn is up to 16
  times longer than now, so on a slow card an `ls` crawls while
  `install` writes.
- **Nothing bounds a client.** A program that sends to `fs`'s port
  without waiting fills its queue (32), and every other process's file
  call is then parked on a full queue (`block_on`, woken all at once by
  `ipc_unblock_all`) until `fs` works through them. Exit notices and
  0023's window notices queue there too, and a window notice that finds
  no room has its window taken back.

The kernel has no way for a program to look at its queue (`ipc_peek` is
its own), but none is needed: `fs` can take every message waiting with
`port_try_receive`, read each in place (its first word, the `N` of a
`read H N` or `write H N`, the sender's pid), and choose.

## Done when

- `fs` takes everything waiting on its port each time round and serves
  notices first, then requests by a byte budget for each pid, so that a
  client moving 64 KB a request and one asking `stat`s share its turns;
  a client's queued requests are bounded, and those past the bound
  refused, not left to fill the queue.
- `turns_test` pins the order: a `stat` behind a run of large writes from
  another pid is served within one write; a pid with many requests
  waiting cannot keep another's from being served; notices go first.
- `make test-virt` and `make e2e` pass; `install` onto a volume is no
  slower than after 0023, timed, and an `ls` during it is, in the log.

## Steps

- [x] `fs`'s loop takes every message waiting (`port_try_receive` until
  none) into a pending list of its own, and serves notices before
  requests; requests still in the order they came. An exit notice drops
  its pid's requests still waiting. No change in what any test sees.
- [x] Requests chosen by deficit round robin over pids: each pid a
  budget of bytes a round, a request's cost its `N` for `readw`,
  `writew` and `read`, its bytes for `write`, a sector's worth for the
  rest, and those the size of a volume (`format`, `mkfs`, `partition`,
  `erase`, `rescan`) 16 runs of 64 KB, so that other pids' are served
  first; a pid's own requests stay in the order they came. Host tests
  of the order in `turns_test`.
- [x] A bound on a pid's pending requests in `fs`, past which it
  answers at once with a refusal the client's call reports, -5 and
  why, as for any other failure; a `close` is never refused, since
  the kernel lets go of a stream whatever its answer; storage.md says
  what.
- [x] Measure on QEMU: `install` onto a volume, and an `ls` of a
  directory while it runs, before and after; in the log.

## Spec changes

- storage.md: the fs protocol's order of serving, notices first, then
  by pid in turn by bytes; the bound on a client's pending requests and
  its refusal; Limits: a request is still served to its end, its disk
  request included, so a small one may wait for one run of 64 KB.
- testing.md: the order tests in `turns_test`.

## Log

- 2026-10-27: written after asking whether one process moving much data
  starves others of `fs`: it does not today, since every client waits
  for its answer, but a dear request holds up cheap ones, 0023's 64 KB
  runs make that longer, and a client that does not wait can fill the
  queue. Ordering inside `fs` chosen over two ports sorted by the
  kernel, which would split the rule between them; small-first alone
  rejected, since a stream of `stat`s would starve a copy. Serving
  other requests while a disk request is out is left for after.
- 2026-10-28: started. 0031's port sets change nothing here: `fs`
  still serves one port, its clock's reply port being one it asks on
  and waits for, not one it serves, so the order stays all its own,
  as written. 0034's idea of one `fs` serving `fs` and `tmpfs` on a
  port each would only change how the loop takes and waits (a note
  there says how); the order, by pid, would cover both. Steps adjusted: the order is kept in a file of its own,
  `user/sbin/fs/turns.l0`, pure, and tested in `turns_test.l0` beside
  it rather than in `fs_test`; a pid's requests are never reordered
  among themselves, since a client's later request may rest on its
  earlier one, so a volume's request is given a large cost instead of
  being moved last; the refusal is -5 with why, the word every client
  and the kernel's `fs_answered` already report, and never of a
  `close`, whose stream the kernel drops whatever the answer, so a
  refused one would leave `fs` a handle. An exit notice, now served
  before requests that came ahead of it, drops its pid's waiting
  requests: served after it, an `open` would make a handle no exit
  would drop.
- 2026-10-28: step 1 landed. `serve` takes every message waiting into
  a `Turns`, notices and requests each a queue, and serves the next of
  it each time round; it blocks on `port_receive` only with nothing
  waiting.
- 2026-10-28: step 2 landed. `Turns` keeps each pid's requests and its
  budget in a map, and the pids in turn in a queue. A pid is given its
  run of 64 KB as it comes and again each time it goes last, not when
  its turn comes round, so that a pid whose budget is spent is served
  as soon as its turn is back rather than a round later: written the
  first way, a writer of runs was served every other round. Costs are
  read in place (`cost_at`, `count_at`): the N up to 16 runs, which
  bounds how many rounds a choice takes. `attach` and `rescan` count as
  a volume's too, since each reads tables and loads volumes whole.
  Kernel clients have one request out each, so for them this is round
  robin by pid in the order they came, as before; it orders requests
  only when one pid has several waiting.
- 2026-10-28: step 3 landed. The bound is 8 (`turn_limit`), checked as
  each message is taken, before it is kept (`taken` in fs.l0), so a
  refused request costs `fs` nothing but its answer. The callers were
  read, not changed: the kernel's `fs_answered` and `fs_wread_in` give
  any word from -1 to -10 to the call as it is, so a refused `open`,
  `read` or `write` fails with -5 as one out of resources does, and
  `fs_ask` returns the -5 and its why as any refusal. Nothing on the
  board sends to `fs` without waiting, so no e2e case or board test
  meets the bound; `turns_test` pins it.
- 2026-10-28: step 4, timed on QEMU, and done. `fs` of 9dc273e (before
  this goal; its `fs.l0` is 3c9c731's) built against this branch's
  libraries, and this branch's, the rest of the initramfs and the
  kernel the same, the e2e `install` case's inittab and disk (System
  of 56000 sectors, a fresh `tools/mkdisk` image each boot), `run
  install System` of 77 files: from the line typed to install's own
  line back, timed on the host from the serial line. Alone, and in the
  background with `ls /Volumes/System` typed every 0.1 s, each ls
  timed from when it was typed, or the prompt before it if later, to
  its prompt. The medians of 3 boots (2 for those alone on 4 CPUs and
  with ls's on 1); an ls's are the medians of each boot's median and
  worst:

  | | before, 1 CPU | before, 4 | after, 1 | after, 4 |
  |---|---|---|---|---|
  | `install` alone | 1.54 s | 1.59 s | 1.41 s | 1.43 s |
  | `install` with the ls's | 1.58 s | 1.70 s | 1.46 s | 1.54 s |
  | an ls during it, median | 7 ms | 18 ms | 7 ms | 18 ms |
  | an ls during it, worst | 17 ms | 40 ms | 12 ms | 41 ms |

  `install` is no slower, a little faster even: the loop that takes
  what waits with `port_try_receive` costs less than it saves. An ls
  waits as long as before, as expected: install and the shell each
  have one request out at a time, so before as after a `list` waits
  for at most the write in progress, which on QEMU's virtio-blk is a
  few milliseconds. The machine was shared, and a boot in three or four
  came out half again as slow throughout (2.40 s and 2.13 s alone,
  2.36 s and 2.27 s with ls's), on either side, which the medians
  leave out; the same was timed first on 3c9c731, before rebasing on
  9dc273e, and came out alike (1.37 s against 1.24 s alone on 1 CPU,
  an ls 7 ms either way). What the goal
  changes, a client with several requests waiting, no program on the
  board does yet; `turns_test` is where it shows. On a slow card, where
  a run takes longer, the wait for the one in progress is the limit
  storage.md names; serving while a disk request is out is 0037, an
  idea written for it.
