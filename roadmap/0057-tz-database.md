# 0057: Any time zone, by the tz database's rules

Track: Desktop · Status: idea · Needs: 0029 · Spec: desktop.md, fat32.md, programs.md

## Why

`rtc clock` serves one zone, US Pacific time, by the US rule of 2007
taken for every year ([desktop.md](../spec/desktop.md)'s Limits; 0056).
A board anywhere else shows the wrong time, and so do Pacific's own
times before 2007. The tz database (IANA's `tzdata`, compiled as TZif
files) has every zone's offsets and rules, past ones included.

## Done when

To be written. What it will at least hold:

- The zone chosen by name (`Europe/Berlin`), kept where 0029's Settings
  keeps settings, and `rtc clock` answering `zone` from that zone's
  TZif data, read as bytes, its transitions and its POSIX TZ rule for
  times past the last; a change seen by `wm` and `fs` as a change of
  summer time is now.
- The zone's abbreviation (`PDT`) available to a client that shows it.

## Steps

To be written. Open: TZif files built into `/etc/zoneinfo` from the
host's at build time, or only the chosen zone's; whether `agent`'s
history and other times a person reads move to the zone too.

## Spec changes

- desktop.md: the zone chosen, and the Limit of 0056 lifted.

## Log

- 2026-10-30: written with 0056, which fixed the zone at US Pacific.
