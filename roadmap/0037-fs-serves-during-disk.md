# 0037: `fs` serves other requests while a disk request is out

Track: Storage · Status: idea · Needs: – · Spec: storage.md

## Why

0024 made `fs` choose what it serves next fairly, by pid and by bytes
([user/sbin/fs/turns.l0](../user/sbin/fs/turns.l0)), but it still serves
each request to its end, its disk requests included
([storage.md's Limits](../spec/storage.md#limits)). So a `stat` that
needs nothing from the disk still waits for the run of 64 KB in
progress, and for the whole of a `format`, `mkfs` or `partition` once
one has begun. On QEMU's virtio-blk a run takes milliseconds (0024's
Log); on the Pi 5's SD card, through `sdhci`'s one data line, a run
takes far longer, and a `format` of a large volume longer still.

Serving while the disk works means `fs` sends a disk request, goes on
with requests that need no disk or another disk, and takes the
driver's reply as one more message, so a request's work splits into
steps around each disk request, with what it holds kept between them
and two requests on one file kept apart. Whether that is worth it, or
a `format` split into many short disk requests between turns is enough,
is the first question.

## Log

- 2026-10-28: written as 0024 ended, which left serving while a disk
  request is out for after.
