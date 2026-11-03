# 0063: A card boot as whole as a network boot: the splash, 4K and HDMI audio

Track: Pi 5 · Status: done · Needs: – · Spec: pi5.md, display.md, sound.md, network.md

## Why

Goal [0027](0027-installer.md) installs L0S onto a Pi 5's card, and the
card boots. But a card boot is not what a network boot is, with the
same files and the same bootloader (2026-05-26's):

- The firmware shows no splash, and leaves HDMI0's clock, M2MC, off.
  `hvs` then says "keeping the firmware's mode on HDMI0: no HDMI0
  regions, M2MC is off" and runs at the firmware's 1920x1080, where a
  network boot gets 3840x2160 at scale 2 (display.md's mode setting
  needs M2MC as the firmware left it).
- `hdmi-audio` says "M2MC is off, so HDMI0 is not up: no sound", as
  seen on a card boot's log of 2026-11-02 (the user saw no sound too).
- The Ethernet PHY was held in reset, which `gem` now lets go
  (network.md); whether RP1's Ethernet clocks are on after a card boot
  was not seen, as no log of one with that change was kept.

The board's own log of a card boot, beside a network boot's, should
say what the firmware does differently: the `config.txt` it reads is
the same file.

## Done when

- Booted from the card, the splash shows as it does over the network,
  `hvs` runs at the monitor's preferred mode (4K at 60 Hz on the user's
  monitor), `hdmi-audio` plays the chime, and `inet` takes a lease:
  each seen in a card boot's serial log.
- spec/pi5.md says what a card boot needs that a network boot does not,
  and how L0S gives it.

## Steps

1. [x] The firmware's own log: `make pi5-card PI5_CONFIG=uart_2ndstage=1`
   adds the line to `config.txt` (any `PI5_CONFIG` word is a line), so
   the firmware says on the debug UART what it does with HDMI.
2. [x] Board runs under 2026-05-26's bootloader: a network boot and a
   card boot of the same build with it and `PI5_ARGS=debug`. Both were
   whole: the splash showed, the firmware brought HDMI0 up, `hvs` set
   4K, the chime played, `gem` let the PHY go on the card boot and
   `inet` took a lease.
3. [x] A card boot under 2026-10-30's bootloader (0064's run 3): the
   display and sound whole there too. Neither bootloader leaves M2MC
   off on a card boot of this build, so `hvs` and `hdmi-audio` are left
   asking the firmware, as before.
4. [x] pi5.md (a card boot as whole as a network boot, and what it
   needs) and network.md (the PHY's reset line, confirmed). display.md
   and sound.md unchanged: what `hvs` and `hdmi-audio` do with M2MC
   off stands, and was not met again.

## Spec changes

- pi5.md: a card boot's display, sound and network, as a network
  boot's.
- display.md, sound.md: `hvs` and `hdmi-audio` with HDMI0 left off.
- network.md: the card boot's link and frames confirmed.

## Log

- 2026-11-02: written as 0027 closed, from the user's card boots after
  the install.
- 2026-11-02: steps written, with 0064, whose board runs these share;
  step 1, `PI5_CONFIG`, in. Not yet run on the board.
- 2026-11-02: run 1, a network boot with `uart_2ndstage=1` and `debug`
  under 2026-05-26's bootloader (`build/pi5-net-0526.log`). The
  firmware says `Select resolution HDMI0/2 hotplug 1 max_mode 2` and
  `FB0 disp 0 max-fb 1 1920x1080`, before it loads `l0.img`; `hvs` finds
  DISP on at 648 MHz, sets 3840x2160 at 60 Hz itself and serves at scale
  2; `hdmi-audio` plays the chime; `gem` links at 1000 Mb/s. The card
  boot of the same build is next, to diff against this.
- 2026-11-02: run 2, the same build installed onto the card from the
  release (`make release PI5_ARGS=debug PI5_CONFIG=uart_2ndstage=1`, the
  Installer) and booted from it under 2026-05-26's bootloader
  (`build/pi5-card-0526.log`, `Boot mode: SD (01) order f2`). It was
  whole: the firmware said the same `hotplug 1` and `FB0 … 1920x1080`
  lines as on the network, `hvs` set 3840x2160 at 60 Hz, `hdmi-audio`
  played the chime, `gem` said `the PHY answered once its reset line
  was let go` and linked at 1000 Mb/s, and `inet` took a lease. So a
  card boot under 2026-05-26's bootloader is not what the Why saw; the
  card boots it describes ran under 2026-10-30's, which the Installer
  had flashed then (0027's log). Run 3, a card boot under 2026-10-30's,
  checks that, with 0064's. The user saw the splash on it too.
- 2026-11-02: run 3, a card boot under 2026-10-30's
  (`build/pi5-card-1030.log`): the display and sound were whole there
  too, the firmware's `hotplug 1` and `FB0` lines, `hvs` at 3840x2160
  and the chime; only RP1's DMA failed (0064). So neither bootloader
  leaves M2MC off on a card boot of this build, and what the Why saw is
  not reproduced: three boots, network and card, each bootloader.
- 2026-11-02: done. Run 2 met each Done when (the user saw the splash),
  and runs 3 and 4 (0064's) kept display and sound whole under
  2026-10-30's. What left M2MC off on the earlier card boots was not
  found; their `config.txt` and serial logs were not kept. Should it
  come back, a card boot with `PI5_CONFIG=uart_2ndstage=1` gives the
  firmware's own account to compare with run 2's
  (`build/pi5-card-0526.log`). pi5.md and network.md updated.
