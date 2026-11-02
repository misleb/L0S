# 0018: `tftp` fetches a file of megabytes on the Pi 5

Track: Network · Status: done · Needs: – · Spec: network.md

## Why

On a Pi 5, `run tftp 192.168.254.200 pieeprom.bin
/Volumes/tmp/pieeprom.bin`, a 2 MiB file from the dnsmasq that serves
the board's network boot, had not finished after ten minutes, and the
shell waiting on it never answered again, though the board still
answered pings and echoed what was typed; only a power cycle ended it.
At the 75 ms the board's pings then took, its 4096 blocks, one in
flight at a time, would take about five minutes, so this is a hang, not
only slowness. Where it stops (`tftp`, `inet`, `gem`, or the write to
the RAM volume) is not known. [network.md](../spec/network.md) says
what `tftp` does on QEMU only.

## Done when

- `run tftp` of a file of at least 2 MiB to `/Volumes/tmp` finishes on
  a Pi 5 with the right bytes, and a failure ends `tftp` with a reason
  rather than hanging the shell.

## Steps

- [x] `tftp` lean, whatever the file's size: each block read in place
  from `inet`'s notice, not as a list; the file written as it comes,
  64 KB at a time, not gathered whole; each block waited for on the
  kernel's alarm, not by polling; what a failure wrote removed. On
  QEMU, 2 MB in 4 s and Whistle's model, 17 MB, in 31 s, the same
  bytes; the `tftp_big` e2e case.
- [x] On a Pi 5: `run tftp` of Whistle's model, 17 MB, to a volume, its
  bytes checked; if it still stops, find where, with `PI5_ARGS=debug`
  and `dmesg`.

## Spec changes

- network.md: what `tftp` does on the Pi 5, and its Limits.

## Log

- 2026-10-27: written after the hang, met while testing 0016's
  `eeprom update` on a board.
- 2026-10-27: a lead, from a survey of bulk data in messages: `tftp`
  (`user/bin/tftp/tftp.l0`, `blocked`) gathers the whole file as a
  `(list int)`, a cons cell a byte, so a 2 MiB file is tens of MB of
  heap, against "bytes, not lists"; then writes it with `write_whole`,
  through `fs` 4 KB a message (0023), and polls its port with 1 ms
  sleeps. Any of these may be the hang, or make it look like one.
- 2026-11-01: met again: dnsmasq timed out sending Whistle's model, 17
  MB, to `tftp` on the Pi 5. Step 1 done, as the user asked: all three
  of the lead's suspects gone. On QEMU the old `tftp` fetched 2 MB
  whole; the new one fetches 17 MB in 31 s.
- 2026-11-01: step 2 done, and the goal: on a Pi 5, by the user,
  `run tftp` fetched Whistle's model, 17 MB, from the dnsmasq to the
  data volume, and `listen` loaded it and heard the Yeti's speech
  right, which a byte wrong in the model would not have; how long the
  fetch took was not timed.
