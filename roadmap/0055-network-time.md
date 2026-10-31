# 0055: The time from the network, once it comes up

Track: Network · Status: done · Needs: – · Spec: network.md, desktop.md, pi5.md, programs.md, demo.md, testing.md

## Why

A Pi 5 has no clock that survives a power cut without a battery on its
RTC connector ([pi5.md](../spec/pi5.md), `rtc clock`), so a board
without one boots in 1970: the top bar shows the wrong time, `fs` dates
what it writes from 1970, UUIDs' times are wrong, and `inet`'s lease is
reckoned from it. The board almost always has a network, and DHCP gives
it a router to the Internet. SNTP (RFC 4330, NTPv4's client part, RFC
5905) gives the time in one datagram each way, over the UDP `inet`
already serves, so the clock can be set as soon as `inet` registers,
which it does once DHCP has given it an address.

## Done when

- `ntp`, a service, waits for `inet`, asks an NTP server the time over
  UDP, and has `rtc clock` take it: `rtc clock` then serves that time,
  and on the Pi 5 also writes it to the RTC, so that a reboot without a
  power cut keeps it. It asks again every hour, and again sooner if it
  had no answer.
- The server is the one `ntp`'s argument names, else the one DHCP
  names (option 42), else `pool.ntp.org`.
- `rtc clock` takes `set S` and tells every listener the time at once;
  `wm`'s top bar shows it then, and `fs` dates what it writes from it.
- Host tests of the packets (a request's bytes, an answer read and
  refused: a wrong mode, stratum 0, a kiss-o'-death, an origin that is
  not ours) and of `rtc clock`'s `set`; an e2e case boots with a
  stand-in NTP server on the host and sees the time it sent; a Pi 5
  booted with no battery shows the right time once the link is up.

## Steps

- [x] `format/ntp.l0`: SNTP's 48-byte request and its answer read in
  place, the NTP era's seconds to Unix time, with host tests.
- [x] `rtc clock` takes `set S`: kept as an offset from the board's
  clock, every listener told at once; on the Pi 5 also written to the
  RTC through the firmware (`SET_RTC_REG`, 0x00038087).
- [x] `inet` asks DHCP for option 42 and answers `ntp` as it answers
  `dns`: the first NTP server it was given, or 0.0.0.0.
- [x] `ntp`, in `user/sbin/ntp`: waits for `inet`, picks the server,
  resolves it, asks from a UDP port inet picks, 3 times 2 seconds
  apart, checks the answer, and sets the clock; then again every hour
  on the kernel's alarm. Started by the Pi 5's inittab after `inet`.
- [x] The e2e case: a stand-in SNTP server on the host (QEMU's user
  network takes 10.0.2.2 to it), `ntp 10.0.2.2:PORT`, and `rtc clock`'s
  time the one it sent.
- [x] On a Pi 5 with no battery (the user's): the top bar's time right
  a few seconds after the link comes up, and after a reboot.

Open: whether QEMU's demo starts `ntp` too. Its board's clock is the
host's local time (`-rtc base=localtime`), and NTP's is UTC, so while
L0S has no time zones ([0056](0056-time-zones.md)) the demo keeps the
host's and leaves `ntp` to the Pi 5. An answer is taken as it comes,
with no correction for the time it took to arrive, which on a LAN or
the Internet is milliseconds; the clock counts seconds.

## Spec changes

- network.md: `ntp`, the server it picks, when it asks, what it checks
  in an answer, and its Limit; DHCP's option 42 and `inet`'s `ntp`
  request (done).
- desktop.md: `rtc clock`'s `set S` (done, with its Limit).
- pi5.md: `ntp` in the board's table, the RTC written, and the Limit
  that a board without a battery is in 1970 until the network is up
  (done).
- programs.md: `ntp`'s row, the library's, `datagram_at`, and `rtc`'s
  `set` (done). demo.md lists no Pi 5 pids, so nothing shifts there.
- testing.md: the e2e case (done).

## Log

- 2026-10-30: written, when the user asked for network time on the
  Pi 5; started with step 1, the packets.
- 2026-10-30: step 2, `rtc clock`'s `set S` and `clock_set` in
  `proto/clock.l0`; the RTC's write through the firmware has not run on
  a board yet, which step 6 sees.
- 2026-10-30: step 3, option 42 asked for and kept, `inet`'s `ntp`
  request and `inet_ntp`; `Dhcp` and `Config` given named fields on the
  way.
- 2026-10-30: step 4, `ntp`, with `datagram_at` in `proto/inet.l0` to
  read its answer in place, and its `start` line in the Pi 5's
  inittab; host tests only so far: step 5 runs it, step 6 on a board.
  It waits for the answer on the kernel's alarm rather than polling as
  `inet_resolve` does. The boot argument the Done when first named was
  left out: `ntp SERVER` in the inittab does the same.
- 2026-10-30: step 5, the `ntp` e2e case: on QEMU, `rtc clock` went
  from the host's time to the stand-in's, `the clock set to Jan 1
  12:00, from Oct 30  22:01`, and `ntp` said so. Left is step 6, the
  user's: a Pi 5 with no battery, booted with its Ethernet on a network
  with a router to the Internet (or a DHCP server naming an NTP
  server), whose top bar should show the time in UTC a few seconds
  after the link comes up, `dmesg` holding `ntp: the time from ...`
  and `rtc: the clock set to ..., and the RTC to it`; and after
  `reboot`, `rtc`'s first line already the right time.
- 2026-10-30: step 6, done: on a Pi 5 the user reported it works, the
  time set from the network once the link was up. The RTC's write
  through the firmware (`SET_RTC_REG`) has run there with it. Done;
  the demo on QEMU keeps the host's time, as the Open note above
  decided, until 0056.
