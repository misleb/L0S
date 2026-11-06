# 0069: An audio server: drivers that only move frames, and one place that mixes

Track: Desktop · Status: active · Needs: – · Spec: sound.md, devices.md, programs.md, demo.md, pi5.md, testing.md

## Why

Sound on L0S is two drivers with a protocol each, and the clients know
both ([sound.md](../spec/sound.md)). `hdmi-audio` serves `audio` to one
client at a time, plays the chime itself, and takes 16-bit frames at
three rates, so `play` takes 16 kHz up to 48 kHz itself and `speak`
doubles its voice's 22,050 Hz; `usb-audio` serves `mic` to one listener,
of the first microphone, and brings 48 kHz down to Whistle's 16 kHz
itself; and a USB speaker, the Yeti Nano's or QEMU's, plays nothing. A
second program that wanted sound would wait for the first, and the agent
cannot speak while `play` plays. What every sound system has is missing:
one server that owns the devices, says which is the default in and out,
lets a client pick another, takes any rate and mixes every client into
each output, resamples what comes in for each listener, finds devices as
they are plugged in and lets them go when they are not, reads its
settings and reads them again when told, and plays the chime once, on
the first output. The drivers are then drivers: each moves frames
between the server and its hardware, in the hardware's format, and says
what it has.

## Done when

- `audio` (`user/sbin/audio`) serves the audio protocol to any number of
  clients at once: `devices`, `open RATE CHANS [ID]` for a stream on the
  default output or a named one, `write`, `drain`, `close`; `listen RATE
  CHANS [ID]` of the default input or a named one, any number of
  listeners of one microphone, each given the format it asked; `volume`;
  `watch`; `reload`. Streams are mixed into each output at the output's
  rate, each converted from its own rate, channels and sample size;
  what comes in is converted for each listener.
- `/etc/audio` names the default output and input, each device's volume
  and whether the chime plays; `reload` reads it again, and the defaults
  and volumes change without a restart.
- Drivers attach devices to the server as they find them and detach
  them as they go: `hdmi-audio` its HDMI0, `usb-audio` each stream of
  each USB audio device, in and out, so the Yeti Nano is a microphone
  and a speaker, and QEMU's `usb-audio` a speaker that plays. A driver
  that exits takes its devices with it, and a client that exits its
  streams and listens, by the kernel's exit notices.
- The chime plays from the server, once, on the first output attached,
  held back as long as that device says a listener needs.
- `play` plays a WAV file at any rate, `speak` says its voice at the
  voice's own rate, `rec` records any format through the server, and
  `speech` listens through it; `sound` lists the devices and defaults,
  reloads the settings and sets a volume.
- Host tests of the conversion, the mixing, the settings, the protocols
  and the server's bookkeeping; the `usbaudio` e2e case plays a file
  through the server into QEMU's speaker; the Pi 5 heard, the chime and
  `speak` on HDMI0 and the Yeti both ways (the user's).

## Steps

- [x] `format/pcm.l0`: frames converted a piece at a time from any
  format (rate, channels, bytes a sample) to 16-bit samples at another
  rate and channels (`PcmConv`, `pcm_convert`: 48 to 16 kHz through the
  filter, any other ratio by linear interpolation), and pieces mixed at
  volumes (`pcm_mix`); `pcm_up` gone with `play`'s own resampling.
- [x] The protocols: `proto/audio.l0`, the server's to its clients, and
  `proto/audiodev.l0`, the server's to its drivers (attach and detach,
  start, play, stop and listen, the `aro` and `ain` notices, and the
  ring every output driver keeps); `mic.l0` and `audio_server.l0` gone.
- [x] The server `audio`: devices, defaults, `/etc/audio` and `reload`,
  streams and their queues, listeners, mixing and feeding on the
  drivers' room notices, the chime, `watch`, the kernel's exit notices.
- [x] `hdmi-audio` a driver of it: HDMI0 attached as `hdmi0`, fed by the
  server, its room said after each period, its chime gone.
- [x] `usb-audio` a driver of it: every stream attached as a device,
  inputs listened to for the server, and outputs played through `xhci`,
  whose isochronous OUT packets take their bytes from a ring the class
  driver shares with it in place of silence (`feed`).
- [x] The clients: `play` at any rate, `speak` at the voice's rate, `rec`
  and `speech` through the server, and `sound`; the demo and the Pi 5
  start `audio`; the `usbaudio` e2e case plays into QEMU's speaker.
- [ ] On a Pi 5: the chime, `play`, `speak` and `rec` through the server
  on HDMI0 and the Yeti, and the Yeti unplugged and plugged in again.

## Spec changes

- sound.md, devices.md, programs.md, demo.md, pi5.md and testing.md:
  in. The Pi 5 step changes sound.md's and pi5.md's Limits once the
  server's path has played there: HDMI0 through the server, and the
  Yeti both ways.

## Log

- 2026-11-05: written, as the user asked: the audio subsystem built out
  properly, a driver just a driver, the common work in one server.
- 2026-11-05: steps 1 to 6 done on QEMU. The server mixes at the
  output's rate from each stream's own queue, converted on write, and
  feeds the driver as it says there is room; inputs are converted for
  each listener from the same notices. `xhci` got `feed`, a ring a
  class driver shares with it from which an isochronous OUT endpoint's
  packets are filled, each its share of the rate, so QEMU's `usb-audio`
  speaker is an output: the `usbaudio` case plays the chime and a 16
  kHz chirp through it, and with `QEMU_AUDIO_WAV` the host's WAV held
  the chord decaying and then the chirp at full scale, 1.96 s of it;
  the chime's start was not in the file, as QEMU's writer takes up the
  stream a moment after the first packets. The Pi 5 is the user's:
  HDMI0 through the server, the Yeti as a speaker (24-bit samples
  widened from 16, 44 or 45 frames a packet at 44.1 kHz), and the
  chime 3 s after `hdmi0` attaches.
- 2026-11-05: first boot on a Pi 5: `audio` and `usb-audio` deadlocked
  at boot, and `sound` waited for ever. The Yeti's speaker, attached
  first, became the default output, and the server, its lead 0, asked
  `usb-audio` to start the chime on it while `usb-audio` waited for the
  answer to the microphone's attach. `usb-audio` now answers the
  server's requests while it waits; the `usbaudio_two` e2e case, two
  of QEMU's speakers, hung the same way before and passes now.
