# 0056: Time zones

Track: Desktop · Status: done · Needs: – · Spec: desktop.md, demo.md, storage.md, fat32.md, network.md, programs.md

## Why

L0S had no time zones: the clock's count was shown as it was
([desktop.md](../spec/desktop.md)). On QEMU that count was the host's
local time (`-rtc base=localtime`), so the top bar was right there and
a UUID's or a file's time was off by the zone (storage.md's Limits); on
a Pi 5 set from the network (0055) it is UTC, so the top bar was off by
the zone instead. One count, UTC, with a zone to show it in, makes
both right.

## Done when

- The clock counts UTC everywhere, QEMU booted with `-rtc base=utc`
  wherever it is started.
- A zone, kept in one place every client asks, `rtc clock`: US Pacific
  time for now (the user's choice), PST and PDT by the US rule of 2007,
  until a configuration tool can change it (0029).
- The top bar shows the time in it, and FAT32's local times are written
  in it; UUIDs stay UTC.
- Host tests of the rule around both changes in several years, of the
  `zone` request and its answer, of the top bar's text at a non-zero
  offset, and of FAT's local time; `make e2e` passing with QEMU on UTC.

## Steps

- [x] `proto/clock.l0`: the `zone` request's answer, `zone M U` (M
  minutes east of UTC, in force until the clock says U), `ClockZone`,
  `zone_of`, `clock_zone`, `zone_holds`, `zone_local`, and `utc_text`
  for the logs, with host tests.
- [x] `rtc clock` answers `zone` from `zone.l0`, US Pacific time by the
  US rule, a pure function of the UTC seconds, tested against the tz
  database around March's and November's changes in 2007, 2024 to 2027
  and 2030; `rtc`'s and `ntp`'s lines say `UTC`.
- [x] `wm` asks the zone as it starts, after `listen`'s reply, keeps it
  in `Bar`, shows `clock_text` of the time in it, and asks again, as a
  notice it takes when it comes, once a minute's time reaches its
  until.
- [x] `fs` asks the zone with the time for a FAT32 volume and keeps both
  in the volume's `FatClock`, asks again once the zone's until has
  passed, and dates what it writes there, and a new volume's root, in
  local time.
- [x] QEMU on `-rtc base=utc`: `tools/qemu-boot.sh` (which the screen
  tests, `make demo` and the MCP server boot through), the e2e cases'
  `l0 boot`, and `make boot`.

Decided: the zone is fixed at US Pacific for now, by the user, on QEMU
and the Pi 5 alike, and is no file or boot argument: the configuration
tool, 0029, will be what changes it, in `rtc clock`'s `clock_zone_at`,
the one place. The answer carries its until, so a client never needs
the rule: it asks again when the zone changes, which keeps the rule
(and a tz database later) in `rtc` alone. `zone` is a request of its
own, so `time S` and `listen` are as they were and no client of them
changed.

## Spec changes

- desktop.md: the clock counts UTC, QEMU on `-rtc base=utc`; `zone` and
  the zone the top bar shows, `rtc clock`'s alone; the Limit that the
  zone is fixed at US Pacific, by the 2007 rule (done).
- demo.md: the top bar's time is the host's in UTC, shown in Pacific
  time (done).
- storage.md: a UUID's time is UTC, the Limit about local time gone
  (done). fat32.md: FAT32's times in the zone, asked again as it
  changes (done).
- network.md: `ntp`'s line says UTC, and the Limit that the Pi 5's top
  bar shows UTC gone (done).
- programs.md: `rtc`'s `zone` and `zone.l0`, and `clock.l0`'s row
  (done).

## Log

- 2026-10-30: written with 0055, whose UTC would put the Pi 5's top bar
  off by the zone.
- 2026-10-30: steps written and all done. First planned as a fixed
  offset from a file in `/etc` filled from the host's `date +%z`; the
  user changed it to US Pacific time everywhere, with its summer time,
  until 0029's Settings can choose, so the rule went into `rtc clock`
  and the `zone` answer carries when it next changes. The tz
  database's other zones and rules are [0057](0057-tz-database.md).
  `agent`'s history times stay UTC (`hist_when`), as before.
