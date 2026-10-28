# 0023: File data through shared memory, in runs of 64 KB

Track: Storage · Status: ready · Needs: – · Spec: syscalls.md, storage.md, kernel.md, programs.md, testing.md

## Why

A program's file read or write on a volume reaches `fs` as a message:
the kernel copies the caller's bytes into a request (`ask_fs_data`),
the caller waits (`AwaitingFs`), and a read's bytes come back in the
reply. A message is at most 4096 bytes, so a call moves at most 4092
bytes ([syscalls.md](../spec/syscalls.md)'s `read`, [storage.md,
Limits](../spec/storage.md#limits)), and a large file is thousands of
round trips. Each one allocates fresh 4 KB `bytes` several times over:
the kernel's joined request, the message `fs` receives, the sectors it
builds. And each is a disk write of its own, after which `fs` writes
the file's metadata again. Counted on the host, a 100 KB file written
as `install` writes it, 25 pieces of 4088 bytes, costs 98 disk requests
and 25 flushes. On the Pi 5's SD card, `install --boot` takes minutes
for its 19.7 MB `input.bin`. A disk faster than a card is held back
more, since the round trips and copies are then all the cost.

Starting a program from a volume takes the same path: once `/` is a
system volume, `boot` and `sh` start every program with
`spawn_from_file` (`user/lib/sys/paths.l0`), which reads its whole ELF
through `fs`, 4092 bytes a message, before `spawn_image`. And it is
most of what 0002 measures: each 4 KB is a round trip of hand-offs,
the caller to the kernel to `fs` to the disk driver and back, which
kernel.md's Limits blames for four CPUs being slower than one; 64 KB
requests make about a sixteenth as many.

The disk side already takes more. `fs` hands its driver up to 128
sectors (64 KB) in one request, through a buffer shared with it
(`DiskBuf`, `disk_put_range`).

## Done when

- A file read or write call of up to 64 KB is one request to `fs`, its
  bytes in pages shared between the kernel and `fs`, not in the
  message; a larger call is split into such requests by the kernel.
- A file written in pieces is written to its disk as data only, in runs
  of up to 64 KB, its metadata at close or flush: the host count for
  the 100 KB file falls from 98 requests to a handful, and the counts
  are pinned in `fs_test`.
- `make test-virt` covers the window: made on a process's first file
  call, reused, freed when it ends; a call past it split; refusals.
- `install` onto a volume, `install --boot`, and a boot from a system
  volume (`make demo-system`'s, to the shell), timed on QEMU on one CPU
  and on four, and on the Pi 5's card, before and after, the times in
  the log here and in 0002's.

## Steps

- [x] The window: a run of 64 KB of pages the kernel takes from the
  frame pool for a process the first time it opens a file of a volume,
  maps into that server's device pages, counted as shared pages are,
  and tells the server of in a notice from pid 0. The server gives it
  back once the process exits; the kernel forgets it then, and when the
  server ends. Bounded: one a process per server, refused as frames
  and `heap_left` are. Board tests in `kernel_virt_test.l0`.
- [x] The fs protocol's `read H N` and `write H N` with the bytes in the
  window: the kernel copies a write's bytes from the caller's memory
  into it, and a read's from it into the caller's buffer, once each;
  `fs` opens the window as a region only for the request and closes it
  after (it keeps at most 64 open, and may have more clients than
  that). A call over 64 KB is answered with what one request moved.
  `syscalls.md`'s `read` and `write` limits and the protocol table
  change; QEMU's e2e cases unchanged.
- [x] `fs` holds an open file's metadata, its size, its clusters'
  marks and its directory entry, until close or its client's exit, so
  that a run of writes is data and nothing else, and joins clusters
  that lie one after another into one disk write. storage.md's crash
  ordering then says that a crash while a file is open loses what was
  written since it was opened.
- [ ] Measure: the host counts in `fs_test`; `install` of the initramfs
  onto an SD volume on QEMU (`sdhci pci`) and onto a virtio disk, the
  e2e cases `install` and `install_boot`, and a boot from a system
  volume, each timed with `QEMU_CPUS=1` and `QEMU_CPUS=4`; and on the Pi
  5, `install` and `install --boot` to the card, timed. The numbers go
  in the log here and in 0002's, whose gap between one CPU and four
  this is expected to narrow.

## Spec changes

- testing.md: the timings.

## Log

- 2026-10-27: written after `install --boot` on the Pi 5 took minutes
  (0022): 4 disk requests and a flush per 4 KB of file, counted on the
  host, against a card where each small write is slow. Chosen over
  only buffering in `fs`, which would cut the disk requests but keep a
  message, its copies and its allocations for every 4 KB: the window
  is what a fast disk needs too. `fs` passing the window on to the disk
  driver, so it copies nothing, is left for after: the pages are the
  kernel's, not `fs`'s, so `shm_share` cannot give them on as it is.
- 2026-10-27: step 1 landed. The window is made in `open_remote`, the
  first open's (`windowed`, `window_made`), not on any file call, since
  every other file call names a handle an open gave. Its records are
  `memory.l0`'s `Window`s in `Mem`, host-tested; the pages are mapped
  by `process.l0`'s `proc_window_alloc`. Two choices changed from the
  goal as written: the server frees the window, not the kernel, since
  `fs` may be in the middle of a killed client's request in it on
  another CPU, and unmapping under it would end `fs`; and the window is
  told by a notice from pid 0, not named in the request's text, which
  any process can forge to make `fs` give up one of its own pages. `fs`
  keeps each client's window (`FsWin`), watches the client, and
  `shm_unmap`s it in `forget_pid`; a second notice for a pid replaces
  and gives back the first, as when an exit notice was lost. Board
  tests: `test_window_notice`, `_names`, `_shared`, `_unmapped`,
  `_once`, `_no_room`; `test_open_routed` and `_request` take the
  notice first. Moved into the spec: kernel.md's "File windows",
  syscalls.md's `open`, programs.md's `fs`, testing.md's board tests.
- 2026-10-27: step 2 landed. `write_remote` copies up to 64 KB into the
  window (`write_windowed`) and sends `writew H N`; `read_remote` sends
  `readw H N`, and `fs_wread_in` copies the answer's bytes out. Without
  a window both use messages as before, so a server that is not `fs`,
  and the host tests, are unchanged. The first board run found that a
  read's answer arrives while the server is making the send call, out
  of the process table, so the copy cannot look at its record: a
  `Window` now holds the server's space, and the kernel keeps every
  window it records mapped whole by forgetting one once the server
  `shm_unmap`s a page of it or has one revoked (`windows_kept`; a
  region's close leaves DMA and shared pages mapped). `fs` reads the
  window a byte at a time into a list, then `bytes`, and writes it a
  byte at a time, since L0 has no other way:
  `probes/bytes/REQUEST-region-bytes.md` asks for one. Board tests:
  `test_window_write`, `_write_request`, `_read`, `_read_count`,
  `_given_up`. Moved into the spec: syscalls.md's `read` and `write`,
  kernel.md's "File windows", storage.md's Limits, programs.md's `fs`,
  testing.md's board tests.
- 2026-10-27: step 3 landed. `written` writes the data spans only, no
  flush, and keeps the volume as changed in memory, the clusters
  marked and the entry adding to the handle's `Pending`; `obey_close`
  and `forget_pid` (a client's exit) flush and then `commit_some` it.
  On FAT the volume counts its own dirty sectors, so any commit writes
  them; `Pending` matters for L0FS. Counting on the host then showed
  that a 64 KB write was still 16 requests, one a cluster: `write_spans`
  now joins spans whose clusters lie one after another into one patch
  of up to `store_chunk`'s 64 sectors, so it is 2. The partial sector a
  write starts in is still read first, but the window's writes are
  whole 64 KB, so only a file's first and last are partial: holding
  that sector was left out as no longer worth it. The host counts, in
  `fs_test`: a write one request and its close one
  (`test_write_requests`), ten of 4000 bytes 19, four of 64 KB 8
  (`test_write_requests_64k`), against 4 a write and a flush before;
  `test_write_pending` shows a file not closed reads back but is not on
  the disk until its client exits. Moved into the spec: storage.md's
  Limits, programs.md's `fs`.
- 2026-10-27: `probes/bytes/REQUEST-region-bytes.md` answered: L0 gives
  `device_read_bytes` and `device_write_bytes`. `fs`'s window and its
  disk buffer, Disks' reads, both network drivers' frames and every
  `put_bytes_range` now copy at once, so the window's 64 KB no longer
  costs `fs` 65,536 calls and as many cons cells.
