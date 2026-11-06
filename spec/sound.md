# Sound

Sound on L0S goes through one server, `audio` (`user/sbin/audio`), which
owns the devices its drivers attach and serves the **audio protocol**
([user/lib/proto/audio.l0](../user/lib/proto/audio.l0)) as `audio` to any
number of clients at once. A driver is a driver: it moves frames between
the server and its hardware, in the hardware's own format, and says what
it has, through the **audio device protocol**
([user/lib/proto/audiodev.l0](../user/lib/proto/audiodev.l0)). Everything
common is the server's: which device is the default in and out, a
client's choice of another, every rate and channel count converted to
the output's or the listener's, the mixing of every stream into each
output, what an input hears fanned out to each listener, the settings
and their reload, the chime, and a device that comes or goes.

```
 play, speak, rec, speech, sound ---- audio (proto/audio.l0) ----+
                                                                 v
                                          audio: devices, defaults, /etc/audio,
                                                 streams mixed, listeners fed,
                                                 the chime
                                              |  audio device protocol (proto/audiodev.l0)
                          +-------------------+-------------------+
                          v                                       v
                 hdmi-audio (dev): hdmi0, out               usb-audio: each USB stream,
                 the Pi 5's HDMI0, a ring of                in and out, over xhci's
                 DMA periods (sound on the Pi 5)            isochronous endpoints (devices.md)
```

The demo starts `audio` and `usb-audio` from `/etc/system`, and the Pi 5
those and `hdmi-audio` ([pi5.md](pi5.md)). On QEMU the output is its
`usb-audio` speaker, with `QEMU_USB=audio`, whose sound the host drops
or writes to a WAV file (`QEMU_AUDIO_WAV`); there is no input unless a
microphone is passed through.

## The audio protocol

| Request | Reply |
|---|---|
| `devices` | a line for each device: `ID in\|out NAME CHANS RATES`, the rates separated by commas, then `default` if it is the default of its kind: `1 out hdmi0 2 32000,44100,48000 default`; nothing if there are none |
| `volume ID [PCT]` | `volume PCT`: device ID's volume, 0 to 100, set first if PCT is given |
| `reload` | `ok`: `/etc/audio` read again, the defaults and volumes as it says; `error: WHY` for a line that is wrong, the old settings kept |
| `watch` | `ok`; then a notice to the reply port, `adv`, the device's id and 1 as a device is attached, or 0 as one is detached |
| `open RATE CHANS [ID]` | `stream N`: a stream of 16-bit frames at RATE, 8000 to 192000, of CHANS channels, 1 or 2, to play on output ID, or on the default output; the client then shares pages with the server (`shm_share`, to the pid that answered) |
| `write N VA FRAMES` | `taken K`: up to FRAMES frames of stream N from the client's pages at VA there, as many as the stream's queue has room for, a quarter second at the output's rate; K may be 0, and the client offers the rest again later |
| `drain N` | `queued K`: the frames of stream N not yet played, 0 once all have |
| `close N` | `ok`: stream N gone; so is every stream of a client that exits |
| `listen RATE CHANS [ID]` | `format RATE CHANS 2`: input ID, or the default input, heard by the reply port, which from then on gets a notice `pcm` and the samples, 16-bit frames at RATE of CHANS, every 10 ms or so, whatever the device's own format; any number of listeners may hear one input |
| `stop` | `ok`: the reply port's listening stopped; a listener gone stops it too |

Each is a request, its words separated by spaces, answered `error: WHY`
when refused. No sample travels in a message but a microphone's, as
they come. A stream or a listener is its client's: the server watches
the client's pid (`proc_watch`) and closes them when it exits.

**Streams and mixing.** A stream's frames are converted as they are
written, from its own rate and channels to the output's, into a queue
of its own in the output's format (`format/pcm.l0`'s `pcm_convert`, below).
When the output's driver says it has room, the server takes as many
frames as the fullest stream on it holds, up to the room, from every
stream, a stream with fewer giving silence past its end, sums them at
the output's volume, clamped (`pcm_mix`), into a buffer of 8 pages it
shares with the driver, and asks the driver to play them. So two
programs playing at once are heard together, and one that runs dry is
heard with gaps while the other plays on. An output is started at its
driver when the first stream opens on it, at the stream's rate if it
takes it, else the smallest multiple of it that it takes, else the
smallest rate above it, else its highest (`dev_rate_for`): a 22,050 Hz
voice plays at 44,100 on HDMI0 and a 16 kHz file at 32,000; and stopped
when the last stream closes. `drain` says a stream's queue and what the
driver has queued, together, so a client that waits for 0 has heard its
last frame.

**Listeners and conversion.** An input is set going at its driver when
the first listener asks, at the listener's rate if the device takes it,
else one it does, and each listener converts what comes for itself: a
Yeti's two channels of 24 bits at 48 kHz reach `speech` as one channel
of 16 bits at 16 kHz and `rec` as 16-bit stereo at 48 kHz, from the
same notices. The input is stopped when the last listener stops or
goes.

**Conversion** (`pcm_convert`, `PcmConv`): from 48 kHz down to 16 kHz
goes through a low-pass filter of 63 taps, a sinc cut off at 7 kHz
under a Hamming window, flat to 6 kHz and 31 dB down at 8 kHz, so that
nothing above 8 kHz folds down into what Whistle hears (`pcm_down`);
every other ratio is linear interpolation, each output frame between
the two input frames it falls on, the last input frame kept for the
next piece so that nothing is lost between pieces. Channels are mixed
by the mean for one, the one sample for both from one, and a sample of
2 to 4 bytes read as its top 16 bits.

## The settings

`/etc/audio`, a line each, `#` starting a comment, read as the server
starts and again on `reload` (`sound reload`), which a program that
changes it sends:

| Line | Means |
|---|---|
| `output NAME` | the default output, by the name its driver gave it (`hdmi0`, `usb-046d:0acf-speaker`); the first output attached if none, or if it is not there |
| `input NAME` | the default input, the same way |
| `volume NAME PCT` | a device's volume, 0 to 100; 100 if none |
| `chime off` | no chime as the first output comes; `on` is the default, and so is the boot argument `chime=off` |

A key not known is passed over, so another program's lines may share
the file; a line of a key known that is wrong fails the whole, and
`reload` answers why. Without the file every default is the first
device of its kind, at 100.

**The top bar's volume** is a client's too: `wm`'s status menu
([desktop.md](desktop.md)) asks `watch`, `devices` and the default
output's `volume` on a port of its own, and its slider sets that
output's volume with `volume ID PCT`, in the server alone: nothing
writes `/etc/audio`, so a reload or a new boot puts the volume back as
the file says.

## The audio device protocol

A driver finds the server by its name, waits up to a minute for it, and
with no server says so and exits 0, as with no device. Each device is
attached by asking the server:

| Request | Reply |
|---|---|
| `attach PORT NAME in\|out CHANS RATES LEAD` | `attached ID`: a device the server reaches at the driver's PORT, named NAME, taking sound in or out, of CHANS channels at the RATES, separated by commas; LEAD ms the server holds the first sound back; ID the server's number for it, never given again |
| `detach ID` | `ok`: the device gone, its streams and listeners with it; so is every device of a driver that exits |

and the driver serves the server on that port:

| Request | Reply |
|---|---|
| `start ID RATE` | `audio RATE QUEUED ROOM`: output ID playing at RATE, one of its own; the frames queued and not yet played, and how many more it would take now |
| `play ID VA FRAMES` | `played N`: up to FRAMES frames of 16-bit samples, a sample a channel, from the server's pages shared with the driver at VA there, as many as there was room for |
| `stop ID` | `ok`: output ID playing out, or input ID stopped |
| `listen ID RATE` | `format RATE CHANS SIZE`: input ID going, at RATE if it takes it or else at one it does, each sample SIZE bytes; then what it hears to the server's port |

and tells the server, as notices to the `audio` port: `aro`, the output's
id, its room and what is queued, as each period ends while the output
is started; and `ain`, the input's id and the samples it heard, in the
format `listen` said. While a driver waits for the answer to `attach`
or `detach`, it goes on answering the server's requests: the server
may ask before it answers, as when the device just attached is the
default output and the chime starts on it, and a driver that waits
only for its answer is never answered. usb-audio, which attaches a
device's streams one after another, waits so. The server names a device in the log as it comes,
`device 1: hdmi0, out, 2 channels at 32000,44100,48000`, and as it goes.

**The chime.** The server reads `/etc/chime.wav` as it starts, unless
the settings or `chime=off` say none, and when the default output
attaches, holds it back the output's LEAD ms, then plays it once as a
stream of its own, at the file's rate, converted like any other: the
log says `playing the chime, /etc/chime.wav, 2500 ms at 48000 Hz` as it
starts. On the Pi 5 the chime is a soft piano G major chord, G3, B3,
D4 and G4 rolled 30 ms apart, 2.5 s of mono at 48 kHz, its loudest
sample a quarter of full scale, which
[tools/mkchime](../tools/mkchime/mkchime.l0) synthesizes at the build
into `build/chime.wav`, staged as the Pi's `/etc/chime.wav`; HDMI0's
lead is 3 s, since a monitor takes a second or more to lock onto a new
mode and unmute: played at once, the chime ended unheard, and after 2 s
it was heard on one boot of three. A missing file is no chime, said at
debug level; one that cannot be played is warned of.

## Sound on the Raspberry Pi 5

On the Pi 5, sound goes out on HDMI0, to the monitor's speakers, through
`hdmi-audio` (`user/sbin/hdmi-audio/`), which attaches HDMI0 to the server
as `hdmi0`, an output of two channels at 32, 44.1 or 48 kHz, and plays
what the server feeds it. It is written from Linux's vc4, and has played
`play /etc/chime.wav` on a 4K monitor's speakers at 48 kHz, with HDMI0
at 3840×2160 and 60 Hz. On QEMU there is no channel, and it says so and
exits 0.

Every output driver keeps a ring of periods its device reads cyclically,
as frame counts (`audiodev.l0`'s `AudioRing`: where to write next, the
room, what is queued, the periods that ended and the one to silence),
writes the server's frames into the periods ahead of the one playing,
and silence into each that ends, so the device plays silence when no one
plays. HDMI's part:

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
   into each period that ended, for its next turn, cleans the ring for
   the channel, and, while the server has the output started, tells it
   the room.
4. **The server's frames** are written into the periods ahead of the one
   playing, as IEC958 subframes, as many as there is room for, and the
   reply says how many. A `start` at another rate stops the channel,
   sets the MAI up again and starts the ring anew, silent.

It starts once `display` is served, since `hvs` sets HDMI0's mode and
its M2MC clock, without which a read of HDMI0's registers stalls the
CPU, turning it on if the firmware left it off, and asks the firmware
that M2MC runs all the same. It plays only if `SCHEDULER_CONTROL` says
HDMI0 sends HDMI, not DVI. `hdmi-audio probe` reads the channel's
registers and, once M2MC runs, the MAI's, the audio packets', the clock
regeneration's and the PHY's, and the HVS's version, writing none. On
the board it read back every word as written, the channel on another
block at each read, and `MAI_CTL` 0x3028 after the chime: no `DLATE` or
`ERRORE`, so the FIFO never ran dry.

## USB devices

A USB audio device's streams, in and out, are the server's through
`usb-audio` ([devices.md](devices.md#isochronous-endpoints)), which
attaches each stream of each device as a device of the server's, named
`usb-VID:PID-KIND` by the terminal at the stream's far end,
`usb-046d:0acf-microphone` and `usb-046d:0acf-speaker` for a Blue Yeti
Nano's two, `usb-46f4:0002-speaker` for QEMU's `usb-audio`, of its own
channels and rates (a second of the same name gets `-2`).

**A stream in** is set going at the rate the server asks, or the
nearest it takes, and each isochronous packet is passed on as it comes,
in the device's own format, which the server converts for each
listener. A Blue Yeti Nano's microphone is two channels of 24 bits, in
3 bytes, at 44.1 or 48 kHz, 288 bytes a millisecond at 48 kHz
(`uac_test.l0` reads its descriptors).

**A stream out** is set going at the rate the server starts it at, and
fed from a ring `usb-audio` shares with `xhci` (`usb.l0`'s `feed`): a
quarter second of the device's frames and a page more, after a header
of two counts, the bytes written and the bytes read. The server's
16-bit frames are written into it as the server plays them, each
sample widened to the device's, and `xhci` fills each isochronous
packet from it as it queues the packet's slot, its share of the rate's
frames (48 a packet at 48 kHz, 44 or 45 at 44.1), silence where the
ring holds less; every 10 packets gone, `usb-audio` reads the counts
and tells the server the room. On QEMU the chime and a 16 kHz chirp,
brought up to 48 kHz by the server, were heard this way in the WAV
QEMU's speaker wrote (`tests/e2e/usbaudio`, [testing.md](testing.md)).

**`rec`** ([user/bin/rec](../user/bin/rec/rec.l0)) is a client: `rec list`
writes the devices; `rec FILE SECONDS [RATE [CHANS [ID]]]` records
SECONDS of the default input, or device ID, at RATE (48000) of CHANS
channels (2) into a WAV file of 16-bit samples, saying `recorded S s at
RATE Hz, CH channels of 16 bits, to FILE`, or how much came if the
microphone sent less within SECONDS and 3 more; `rec FILE S 16000 1`
records what Whistle ([speech.md](speech.md)) hears, which `listen
FILE.wav` reads and `play` plays. `speech` listens the same way, for its
key.

## Limits

- **The outputs that have played are QEMU's speaker, through the
  server, and the Pi 5's HDMI0, through `hdmi-audio` before the
  server**: the server's path to HDMI0, and a USB speaker on a board,
  the Yeti's, are the goal's last step (roadmap 0069). A stream is
  16-bit samples, 1 or 2 channels; a WAV of 24 bits is refused. A USB
  stream out is fed its largest packet's share only on a full-speed
  endpoint, a packet a millisecond.
- **One microphone has been heard, the Yeti Nano**, through the drivers
  before the server: on a Pi 5, on RP1's USB, and on QEMU, passed
  through; the server's path from it, and two listeners at once, have
  run on no board yet. QEMU's own `usb-audio` is a speaker.
- **The mix is a sum at the device's volume**: a stream has no volume
  of its own, and nothing ducks one for another. The queue is a quarter
  second: a client that writes less often than that is heard with gaps.
  Conversion between rates that are not 48 to 16 kHz is linear, so a
  file brought up to 48 kHz images above its own band, faintly, and
  one brought down below 48 kHz from a rate above it folds what lies
  above half the new rate.
- **The chime is one file, played whole** on the default output as it
  attaches, held in memory while it plays (240 KB on the Pi 5); an
  output attached later, or made the default by a reload, plays none.
  How long to hold it back is the driver's guess, the same for every
  monitor.
