# 0018: `tftp` fetches a file of megabytes on the Pi 5

Track: Network · Status: idea · Needs: – · Spec: network.md

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

To be written: first find where it stops, with `PI5_ARGS=debug` and
`dmesg`, and whether a smaller file does the same.

## Spec changes

- network.md: what `tftp` does on the Pi 5.

## Log

- 2026-10-27: written after the hang, met while testing 0016's
  `eeprom update` on a board.
- 2026-10-27: a lead, from a survey of bulk data in messages: `tftp`
  (`user/bin/tftp/tftp.l0`, `blocked`) gathers the whole file as a
  `(list int)`, a cons cell a byte, so a 2 MiB file is tens of MB of
  heap, against "bytes, not lists"; then writes it with `write_whole`,
  through `fs` 4 KB a message (0023), and polls its port with 1 ms
  sleeps. Any of these may be the hang, or make it look like one.
