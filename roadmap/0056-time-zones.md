# 0056: Time zones

Track: Desktop · Status: idea · Needs: – · Spec: desktop.md, storage.md, fat32.md

## Why

L0S has no time zones: the clock's count is shown as it is
([desktop.md](../spec/desktop.md)). On QEMU that count is the host's
local time (`-rtc base=localtime`), so the top bar is right there and a
UUID's or a file's time is off by the zone (storage.md's Limits); on a
Pi 5 set from the network (0055) it is UTC, so the top bar is off by
the zone instead. One count, UTC, with a zone to show it in, makes
both right.

## Done when

- The clock counts UTC everywhere, QEMU booted with `-rtc base=utc`.
- A zone, an offset at least, set in a file or a boot argument, which
  the top bar shows the time in; FAT32's local times written in it.

## Steps

To be written. Open: an offset alone, or the tz database's rules for
summer time, and where the zone is kept (`/etc`, or 0029's Settings).

## Spec changes

- desktop.md: the zone the top bar shows.
- storage.md, fat32.md: UTC in UUIDs, the zone in FAT32's times.

## Log

- 2026-10-30: written with 0055, whose UTC would put the Pi 5's top bar
  off by the zone.
