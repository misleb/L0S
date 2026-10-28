# Sound on the Raspberry Pi 5

On the Pi 5, sound goes out on HDMI0, to the monitor's speakers, through
`hdmi-audio` (`user/sbin/hdmi-audio/`), which serves the **audio
protocol** ([user/lib/proto/audio.l0](../user/lib/proto/audio.l0)) as
`audio`. It is written from Linux's vc4, and has played `play
/etc/chime.wav` on a 4K monitor's speakers at 48 kHz, with HDMI0 at
3840×2160 and 60 Hz.
On QEMU there is no channel, and it says so and exits 0.

| Request | Reply |
|---|---|
| `info` | `audio RATE QUEUED ROOM`: the rate played, the frames queued and not played, and how many more it would take now |
| `start RATE` | `ok` once it plays at `RATE`, 32000, 44100 or 48000; what was queued at another rate is dropped |
| `play VA FRAMES CHANS` | `played N`: up to `FRAMES` frames of 16-bit samples, `CHANS` a frame, 1 or 2, from the client's pages shared with the driver at `VA` there; `N` may be 0 when the ring is full, and the client offers the rest again once some have played |

As with the disk, no sample travels in a message. What every sound
driver keeps alike, the requests, the ring's counts and the chime, is
[audio_server.l0](../user/lib/proto/audio_server.l0); the rest is HDMI's.

**The chime.** A sound driver plays `/etc/chime.wav` once, as soon as it
serves `audio` and its ring runs, as a client would play it: at the
file's rate, set first if the driver plays another, its frames written
ahead of the period playing as far as there is room, and more as each
period ends, until all are (`audio_chime_load`, `audio_chime_feed`;
WAV read by `wav.l0`, as `play` reads one). It waits for nothing else:
not for the screen, which shows its wallpaper as soon as its own mode is
set ([The display](display.md#the-display-protocol)), nor the screen for
it. A client's `start` or `play` meanwhile is answered as always, and
ends the chime there: what it already wrote plays out ahead of the
client's frames, or, for a `start` at another rate, is dropped with the
rest of the ring. The boot argument `chime=off` plays none. A missing
or unplayable file is said once on standard error, `no chime:` and why,
and the driver serves all the same; one that plays is said as it starts,
at info, as `playing the chime, /etc/chime.wav, 2500 ms at 48000 Hz`
(`audio_chime_said`), so the log shows it was played. On the Pi 5 the
chime is a soft piano G major chord, G3, B3, D4 and G4 rolled 30 ms
apart, 2.5 s of mono at 48 kHz, its loudest sample a quarter of full
scale, which [tools/mkchime](../tools/mkchime/mkchime.l0) synthesizes
at the build into `build/chime.wav`, staged as the Pi's
`/etc/chime.wav`. `hdmi-audio` starts once `hvs` serves `display`,
which is when HDMI0's audio exists, and holds the chime back 3 s from
then (`chime_lead_ms`, `audio_chime_after`), its ring playing silence,
since a monitor takes a second or more to lock onto the new mode and
unmute: played at once, the chime ended unheard, and after 2 s it was
heard on one boot of three. The `playing the chime` line comes as it
starts.

HDMI's part:

1. **The MAI** is HDMI0's audio FIFO, in the HD block, and it takes
   IEC958 subframes, a 32-bit word a sample with its preamble, the
   channel status a bit a frame over blocks of 192, and parity, as
   alsa-lib's iec958 plugin builds them for Linux (`iec958.l0`). Its
   divider is set from a fixed 108 MHz audio clock, whose gate in
   `DVP_MISC_CONFIG` the driver opens, and its thresholds as Linux sets
   them on the D0 (`mai.l0`).
2. **The packets**: the audio packets' config, N for the clock's
   regeneration with the hardware making CTS (CTS written too, from the
   TMDS rate the PHY's PLL is set to), and the audio infoframe in packet
   RAM's slot 4, all as `vc4_hdmi_audio_prepare` writes them.
3. **The DMA.** L0 gives channel 6 of the BCM2712's 40-bit DMA
   controller, `dma40`, as a region with its interrupt, 118 (L0 roadmap
   0122, asked for in [probes/audio](../probes/audio/REQUEST-pi5-dma40.md)).
   It plays a ring of 12 periods, a DMA page each, 512 frames, 10.7 ms
   at 48 kHz, 128 ms in all, cyclically into `MAI_DATA`, one control
   block a period, each raising the interrupt as it ends (`dma40.l0`).
   The MAI asks for data on DREQ 12 on the D0, this board's stepping,
   as `bcm2712d0-rpi-5-b.dts` says, and 10 on the C0: with 10 on the
   D0 the channel moved 512 bytes and waited for good, the FIFO empty.
   On it, the driver reads which block the channel is on, writes silence
   into each period that ended, for its next turn, and cleans the ring
   for the channel, so silence plays when no client does.
4. **A client's frames** are written into the periods ahead of the one
   playing, as IEC958 subframes, as many as there is room for, and the
   reply says how many.

It starts once `display` is served, since `hvs` sets HDMI0's mode and
its M2MC clock, without which a read of HDMI0's registers stalls the
CPU, and asks the firmware that M2MC runs all the same. It plays only if
`SCHEDULER_CONTROL` says HDMI0 sends HDMI, not DVI. `hdmi-audio probe`
reads the channel's registers and, once M2MC runs, the MAI's, the audio
packets', the clock regeneration's and the PHY's, and the HVS's version,
writing none. On the board it read back every word as written, the
channel on another block at each read, and `MAI_CTL` 0x3028 after the
chime: no `DLATE` or `ERRORE`, so the FIFO never ran dry.

## Limits

- **Sound is the Pi 5's HDMI0 alone, and new** (see
  [Sound on the Raspberry Pi 5](#sound-on-the-raspberry-pi-5)): 16-bit
  PCM, two channels, at 32, 44.1 or 48 kHz, through `dma40`'s channel 6,
  the one L0 gives. It plays silence whenever no client does, so its
  interrupt comes 94 times a second at 48 kHz even then. One client at
  a time: two would interleave. QEMU has no sound device L0S drives.
- **The chime is one file, played whole at boot** unless `chime=off`:
  held in the driver's memory while it plays (240 KB on the Pi 5), and
  at a rate the driver plays, or not at all. How long to hold it back
  for the monitor is a guess, the same for every monitor: the old chime
  was heard on one boot of three after 2 s; the chord, after 3 s, is
  heard on every boot on an LG 4K monitor. So on the Pi 5 it comes at
  about the time `wm`'s desktop does, not with the wallpaper, the
  first frame: the monitor takes that long to play sound after a mode
  is set, and nothing HDMI0 sees says when it is ready.
