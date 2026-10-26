# Feature request: the HDMI controller, its PHY and pixel valve, and DDC as regions on the Raspberry Pi 5, so L0S can set HDMI0's mode

Status: landed (L0 roadmap 0120, commit 4e184e1): the four regions as
asked, in the boot map's block 65. On a board (2026-10-26) `hvs` opens
them and sets HDMI0 to 3840×2160 at 60 Hz itself, scrambling over DDC0
included (`user/sbin/hvs/modeset.l0`). `aon_intr` and `bsc_irq` are for
their own request.
Project: L0S, a microkernel in L0, booting on a Raspberry Pi 5 (2 GB,
serial 1b08af2e, EEPROM 2026/05/26) by TFTP

L0S's display driver `hvs` (`user/sbin/hvs/`) shows the desktop on
HDMI0 through the HVS and `iommu4`, which L0 gives as regions (roadmap
0105). It takes the mode the firmware leaves, and the firmware always
leaves 1920×1080. On a 4K monitor that wastes the screen: the monitor's
EDID, which `hvs` now reads from the firmware, prefers 3840×2160 at 60 Hz
(594 MHz) and offers 4K at 24 to 60 Hz. This asks for the regions that
setting the mode takes, so that L0S can do it as Linux's `vc4` does.

## What could not be written

A mode set of L0S's own: the HDMI controller's timings, its PHY's PLL
at the TMDS rate, the pixel valve that feeds it from the HVS, and, above
340 MHz, scrambling turned on in the monitor over DDC. None of those
blocks is one of section 10.3's regions, so `open_device` refuses them.

## The workaround actually used, and why it is not enough

The firmware's mailbox, which is a region, answers firmware KMS's
`SET_TIMING` (0x00048017) on the Pi 5. Given the EDID's timing it
re-times HDMI0 to 3840×2160: it never marks the tag answered, but two
seconds on the HVS channel's `CTRL0` reads the new size. `hvs` does
this when the boot argument `hdmi=preferred` asks.

After it, though, the firmware keeps the HVS channel. Every frame or so
it points the channel's `LPTRS` back at one of its own two display
lists (words 32 and 672 of the list memory), whatever `hvs` wrote, and
whether `NOTIFY_DISPLAY_DONE` came before `SET_TIMING` or after. At
1920×1080, with no `SET_TIMING`, `NOTIFY_DISPLAY_DONE` hands the channel
over and `hvs` double-buffers its own lists cleanly. After `SET_TIMING`,
`hvs` can only write its lists over the firmware's two, the one not on
screen first, and hope the firmware flips as it expects. On the board
that shows the desktop at 4K, steady with a few windows, but the
pointer flickers once there are more, and a list can show stale for a
frame (the launcher drawn low, then right). So 4K stays opt-in, and the
default is the firmware's 1080p. A mode set of L0S's own would never put
the firmware in that state.

## Smallest change that would help

**These regions on the Pi 5,** device memory as the others. The CPU
address is bus address + 0x10_0000_0000 (`soc@107c000000`'s `ranges`).
From `bcm2712.dtsi` (rpi-6.12.y), node `hdmi0: hdmi@7ef00700` and its
neighbours:

| Base | Bytes | What | Linux's name |
| --- | --- | --- | --- |
| 0x107C700000 | 0x4800 | HDMI0's blocks, one run: the DVP clock and reset controller (0x0, `dvp: clock@7c700000`), the CSC (0x100), the DVP (0x1000), the HDMI core (0x1400), the PHY (0x1D00), the rate manager (0x2000), packet RAM (0x3800) and metadata (0x4000) | `dvp`, `hdmi0` reg-names `csc`, `dvp`, `hdmi`, `phy`, `rm`, `packet`, `metadata` |
| 0x107C720000 | 0x100 | the HD block, shared by both HDMIs (`VID_CTL`) | `hdmi0` reg-name `hd` |
| 0x107C410000 | 0x100 | pixel valve 0, which feeds HDMI0 from HVS channel 0 | `pixelvalve0` |
| 0x107D508200 | 0x58 | DDC0, a `brcm,brcmstb-i2c` controller on HDMI0's DDC lines | `ddc0` |

If one run of 0x4800 is too coarse, the separate `hdmi0` ranges are
0x107C701400 (0x300), 0x107C701000 (0x200), 0x107C701D00 (0x300),
0x107C702000 (0x80), 0x107C703800 (0x200), 0x107C704000 (0x800) and
0x107C700100 (0x80), with the DVP controller at 0x107C700000 (0x10).

The clocks are the firmware's, asked over the mailbox as `hvs` already
asks CORE and DISP: M2MC, id 13, the HDMI state machine's (Linux's
`hsm`), at the TMDS rate times 101/100 and never below 120 MHz; and
PIXEL_BVB, id 14, at 300 MHz above 297 MHz of TMDS. There is no pixel
clock to set: on the BCM2712 the PHY's own PLL makes it from a 54 MHz
reference.

## How L0S would use them

`hvs` would take the mode set over from the firmware in Linux's order
(`vc4_crtc_atomic_enable`, `vc4_hdmi_encoder_pre_crtc_configure`,
`vc6_hdmi_phy_init`, `vc5_hdmi_set_timings`, `vc4_crtc_config_pv`,
`vc4_hdmi_encoder_post_crtc_enable`):

1. M2MC on and at its rate before any HDMI register is touched: with it
   at 0, an access stalls the CPU with no fault, as the HVS does
   unclocked.
2. The HVS channel reset and given the new size (it has the HVS).
3. PIXEL_BVB set; the PHY reset, its PLL programmed for the TMDS rate
   (594 MHz: divider 2, VCO 11.88 GHz, `RM_OFFSET` 0x9B800000), powered
   up and its PLL started.
4. The HDMI core's timings (`HORZA`, `HORZB`, `VERTA0/1`, `VERTB0/1`),
   colour depth, and AV mute cleared.
5. The pixel valve's timings, FIFO and format, then enabled.
6. The CSC set to RGB, the HDMI FIFO started and recentred, and the
   channel's video enabled in `VID_CTL`; then HDMI mode on, waiting for
   `HDMI_ACTIVE`.
7. Above 340 MHz of TMDS, scrambling: over DDC0, the monitor's SCDC
   (I2C address 0x54) register 0x20 set to 0x03 (clock ratio 1/40 and
   scrambling), then the core's `SCRAMBLER_CTL` on, and the monitor's
   0x21 read now and then to keep it so, as Linux does every second.

It would start from 1080p, which the firmware leaves, so each step can
be tried a stage at a time as the HVS's were (`hvs probe` and the
rest), with every write said before it is made.

## Later, for its own request

- `aon_intr` at 0x107D510600 (0x30), cascaded to GIC SPI 239: HDMI0's
  hotplug (lines 7 and 8), so a monitor plugged in after boot is seen.
- `bsc_irq` at 0x107D508380 (0x10), cascaded to SPI 242: DDC0's
  interrupt (line 1). Polling the controller is enough at first.

## Which deliberate restriction this breaks

None that we can see. They are devices like the HVS, `iommu4` and the
mailbox, reached only through their registers; the PHY and controller
read no memory.

## Alternatives considered

- **Firmware KMS's `SET_TIMING`**, which `hvs` uses now (above): it
  works, but the firmware then keeps the HVS channel.
- **`config.txt`.** `hdmi_group`, `hdmi_mode`, `hdmi_enable_4kp60`,
  `max_framebuffer_width` and `max_framebuffer_height` were all tried
  and ignored: on the Pi 5 they are the legacy display stack's, and the
  firmware's boot display is 1920×1080 whatever the monitor offers.
