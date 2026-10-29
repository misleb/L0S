# 0024: `fs` serves its clients fairly, small requests first

Track: Storage · Status: active · Needs: 0023 · Spec: storage.md, testing.md

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
- [ ] Requests chosen by deficit round robin over pids: each pid a
  budget of bytes a round, a request's cost its `N` for `readw`,
  `writew` and `read`, its bytes for `write`, a sector's worth for the
  rest, and those the size of a volume (`format`, `mkfs`, `partition`,
  `erase`, `rescan`) 16 runs of 64 KB, so that other pids' are served
  first; a pid's own requests stay in the order they came. Host tests
  of the order in `turns_test`.
- [ ] A bound on a pid's pending requests in `fs`, past which it
  answers at once with a refusal the client's call reports, -5 and
  why, as for any other failure; a `close` is never refused, since
  the kernel lets go of a stream whatever its answer; storage.md says
  what.
- [ ] Measure on QEMU: `install` onto a volume, and an `ls` of a
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
  as written. Steps adjusted: the order is kept in a file of its own,
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
