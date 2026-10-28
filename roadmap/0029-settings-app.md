# 0029: Settings, an app for the system's configuration

Track: Desktop · Status: idea · Needs: 0028, 0008, 0020 · Spec: programs.md, desktop.md, toolkit.md, network.md, boot.md, pi5.md, testing.md

## Why

Everything about L0S's configuration is fixed when it is built, or
changed by hand in a file or at the shell:

- The desktop's wallpaper is `wm`'s `/etc/splash.ppm`, which 0028 makes
  the wallpaper's image. Nothing chooses another.
- The look is fixed. `ui_style` is `UiDark` in `theme.l0`, "the one
  place a light/dark setting will be read", but no setting exists. The
  fonts are the ones built in (0019's font service, 0020's proportional
  text), and the cursor set is the one `fonts/cursors.paths` holds
  (0008).
- Boot options are `cmdline.txt`'s words on a Pi 5's card (`root=`,
  which `install --boot --root` writes) and `inittab`/`/etc/system`
  lines, edited by hand.
- The Pi 5's bootloader settings are read and changed with `eeprom`
  at the shell ([pi5.md](../spec/pi5.md)), and only an expert knows
  what `BOOT_ORDER=0xf21` means.
- The network is whatever `inet`'s arguments in the inittab say, `dhcp`
  or a fixed address ([network.md](../spec/network.md)), set only by
  editing that line and booting again.

GNOME's answer is Settings: one app, a sidebar of panels, each panel
changing one thing and saying what it changed.

## Done when

- To be written. What it will at least hold:
  - A Settings app in the launcher, GNOME's layout (a sidebar of
    panels, each a page of rows), with these panels:
    - **Appearance:** the desktop's wallpaper, chosen from images on
      the system (the boot splash, 0028's driver frame, stays fixed);
      dark or light style; the default fonts; the cursor set.
    - **Network:** DHCP or a fixed address, netmask, gateway and name
      server, what `inet info` and `dns` say now, applied without
      booting again where `inet` can take it.
    - **Boot:** the boot volume's `cmdline.txt` words (the root, and
      others), and what `/etc/system` starts.
    - **Raspberry Pi** (only on a Pi 5): the bootloader's settings
      `eeprom` changes, `BOOT_ORDER` above all, named in words ("SD
      card, then network"), with the update and its reboot said before
      they happen.
  - Settings kept in files on the system volume, read by the programs
    that use them, so a setting holds across boots and is the same
    whether the app or a shell wrote it.
  - Each change seen at once by the programs it concerns where it can
    be (`wm`'s wallpaper, every window's style), else said to need a
    restart.

## To decide

- Where settings live and in what form: one file per area under
  `/etc` (`/etc/settings/appearance`...), or one store. Who writes it:
  the app itself, or a settings service that programs ask and that
  tells them of a change (a `settings` protocol, as `font` is served).
- How a running window learns of a style change. `ui_style` is a
  constant; it would become a value the toolkit is told and repaints
  every window for.
- What `wm` accepts as a wallpaper: only PPMs `tools/` made, or
  anything `svg.l0` draws, rendered on the board (slow: seconds for a
  full screen).
- Whether the network panel needs `inet` to take new settings while
  running, a new request, or restarts it.
- Whether boot options and `/etc/system` edits are this app's job or
  0027's installer's, which writes `cmdline.txt` first.
- Settings with no GUI: a `settings` shell command, so e2e cases can
  set and read them.

## Steps

None yet: an `idea` until Done when is written.

## Spec changes

To be written with the steps.

## Log

- 2026-10-28: written. It needs 0028 for the wallpaper as an image,
  0008 for a cursor set to choose from, and 0020 for fonts to choose
  among; the Network and Raspberry Pi panels need none of these and
  could come first.
