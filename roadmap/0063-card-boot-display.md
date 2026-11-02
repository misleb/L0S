# 0063: A card boot as whole as a network boot: the splash, 4K and HDMI audio

Track: Pi 5 · Status: idea · Needs: – · Spec: pi5.md, display.md, sound.md, network.md

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

To be written. Open: whether the firmware skips HDMI on a card boot
for a setting (`config.txt`, `cmdline.txt`, the bootloader's
`bootconf.txt`) or for what it found there, and whether `hvs` should
then bring M2MC and HDMI0 up itself rather than ask the firmware to.

## Spec changes

- pi5.md: a card boot's display, sound and network, as a network
  boot's.
- display.md, sound.md: `hvs` and `hdmi-audio` with HDMI0 left off.
- network.md: the card boot's link and frames confirmed.

## Log

- 2026-11-02: written as 0027 closed, from the user's card boots after
  the install.
