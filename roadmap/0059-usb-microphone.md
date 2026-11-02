# 0059: A USB microphone

Track: Pi 5 · Status: done · Needs: – · Spec: devices.md, sound.md, programs.md, testing.md

## Why

L0S hears nothing. Its USB stack ([devices.md](../spec/devices.md#usb))
drives boot keyboards and mice only, and its sound
([sound.md](../spec/sound.md)) goes one way, out of the Pi 5's HDMI0.
Talking to the agent (0061) needs a microphone, and a USB one is what a
Pi 5 can take with no hat and no driver of a codec: USB Audio Class
devices all speak one protocol, as boot keyboards do. The one at hand is
a Blue Yeti Nano (Logitech 046d:0acf), a microphone and a speaker, so
devices are listed by what they are, in and out.

## Done when

- `xhci` gives a USB Audio Class device's streaming interface to a
  client: its alternate settings chosen, an isochronous IN endpoint
  opened, and its transfers scheduled.
- A driver of its own, `usb-audio` (beside `usb-hid`), lists every
  audio device's streams, in and out, sets a microphone going at a rate
  it offers, and serves what it hears as `mic`.
- `rec FILE SECONDS` writes what it hears as a WAV file, heard back on
  the host.
- Host tests of the descriptors' parsing and the isochronous schedule;
  an e2e case on QEMU; a real microphone heard, the Yeti Nano passed
  through to QEMU and on a Pi 5.

## Steps

- [x] Isochronous endpoints in `xhci`, IN and OUT: CErr 0, three pages
  a pipe, a packet queued in every slot of its buffer, each event the
  oldest slot's, missed packets done with none, an empty ring no
  packet, and a `uin` every 10 packets; OUT packets silence for now.
  Tested in `core_test.l0` (an audio device's 0x82 and 0x01) and
  `ctx_test.l0`.
- [x] USB Audio Class 1.0's descriptors (`format/uac.l0`): terminals and
  units and their links, each streaming setting's endpoint, format and
  rates, what is at a stream's far end; tested on the Yeti Nano's own
  232 bytes, a speaker out and a microphone in.
- [x] `usb-audio`, serving `mic`: `devices`, `listen`, `stop`, and
  `silence`, a test of the path out; the `usbaudio` e2e case, QEMU's
  `usb-audio` speaker listed and sent 500 packets in half a second.
- [x] `rec`: `list`, a recording to a WAV file of the microphone's own
  samples (`wav_header_sized`), and `silence`.
- [x] A real microphone heard: the Yeti Nano passed through to QEMU
  (`QEMU_USB=046d:0acf`, its `/dev/bus/usb` node made writable on the
  host), `rec` of 5 s played back on the host, and any fault of a real
  device's IN packets fixed.
- [x] On a Pi 5: the Yeti on RP1's ports, `rec` there, the WAV heard;
  and `rec FILE 5 16000`, brought down to Whistle's 16 kHz by
  `usb-audio`, played by `play` and read by `listen`.

## Spec changes

- testing.md: the run with the Yeti Nano on a Pi 5.
- devices.md and sound.md: their Limits, once a microphone is heard on
  a Pi 5.

## Log

- 2026-10-31: written, as the user asked, for speech to the agent
  (0061).
- 2026-10-31: steps 1 to 4 done: isochronous endpoints, the UAC
  parser, `usb-audio` and `rec`, all on QEMU, whose `usb-audio` is a
  speaker only, so nothing has come in yet. The Yeti Nano is on the
  host, but QEMU cannot take it until its device node is writable,
  which is the user's to grant.
- 2026-11-01: step 5 done: the Yeti passed through to QEMU, recorded
  (2 channels of 24 bits at 48 kHz) and heard on the host, with no
  fault. On the way, the demo got QEMU's `usb-tablet`, which `usb-hid`
  now drives, so its window needs no grab, and with `QEMU_USB` its
  qemu-xhci 8 USB 2 ports, since past 4 QEMU hid the Yeti behind a hub
  of its own. And for Whistle (0060, 0061), which hears one channel of
  16 bits at 16 kHz that the Yeti does not offer, `usb-audio` brings
  48 kHz down to it when asked `listen 16000` (`format/pcm.l0`), and
  `play` takes 16 kHz files up to 48 kHz: the Pi 5 step checks both.
- 2026-11-01: step 6 done, and the goal, by the user on a Pi 5: the
  Yeti on RP1's USB, `rec FILE 5 16000` of it brought down to 16 kHz by
  `usb-audio`, played by `play` on HDMI0, and heard rightly by `listen`
  (0060). The spec's Limits now say the microphone was heard there.
