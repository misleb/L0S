# The display

The display layer: the protocol between the display driver and the compositor, `virtio-gpu` on QEMU and `hvs` on the Raspberry Pi 5. The compositor itself is in [desktop.md](desktop.md).

## The display protocol

**The display protocol** ([user/lib/proto/display.l0](../user/lib/proto/display.l0)) is
the whole contract between the compositor and the display hardware's
driver. It says nothing about virtio. A driver for other hardware, a
plain framebuffer say, serves the same requests as `display`, and `wm`
runs on it unchanged. Such a driver would compose the layers by copying
pixels, and draw the pointer as a top layer.

| Request | Does |
|---|---|
| `info` | `display W H cursor scale S`: the screen's size in its own pixels, `cursor` if the driver moves a pointer itself, and the desktop's scale, 1 or 2 (none means 1) |
| `buffer ID W H VA [N [S]]` | a buffer of W×H 4-byte pixels (b, g, r, and unused, or alpha for a cursor), at VA in the driver, shared there with `shm_share`, its rows S pixels apart (W if not given); N its pages, if more than S×H takes. The same pages may be given again under another ID at another size, as `wm` does to resize a window without sharing anything anew, and with the same S each row stays where it was |
| `forget ID` | the buffer dropped, and the driver's mapping of it given up with `shm_unmap` once no other buffer is in its pages; refused while it is on the screen or is the pointer's. A driver that answers a restack before the screen shows it (`hvs`) keeps the pages until no list it may still read names them |
| `layers ID X Y TOP ...` | the screen, bottom first: each buffer at X, Y, its rows read from row TOP on, as a ring. The bottom layer covers the screen. Only the bands of rows whose pixels changed are transferred and flushed; the first `layers` shows the whole screen |
| `damage ID X Y W H ...` | each rectangle of its buffer changed, one or more groups of five: shown wherever they are visible, all together, with boxes that overlap transferred and flushed as one |
| `shape ID TL TR BL BR` | the buffer's corners rounded, top left, top right, bottom left, bottom right, each radius from 0 (square) to half its width and height. virtio-gpu cannot blend, so it narrows the layer's rows within a corner, and `hvs` writes the alpha of the pixels there 0; either way the layer beneath shows there. A buffer is square when shared; if it is on the screen, the screen is rebuilt |
| `cursor ID HX HY` | the pointer's image, a 64×64 buffer, and its hot spot |
| `move X Y` | the pointer's hot spot at X, Y |
| `frames PORT` | from now on, PORT told the display's notices: `frame N` after each frame that showed a change, N counting from 1, and `release ID` once buffer ID is no longer read, having left the stack |

The reply is `ok`, `display W H cursor scale S` for `info`, or
`error: WHY`.

**The notices** are sent from the driver to each port `frames` named,
as notices are, a tag of three bytes and u32s, little-endian
(`l0s.l0`'s `shown_notice` and `release_notice`, read with
`display_frame_of` and `display_release_of`):

| Notice | Bytes | Says |
|---|---|---|
| `frame N` | `frm`, N | the Nth frame that showed a change is on the screen: what every `damage` and `layers` answered before it changed |
| `release ID` | `rel`, ID | buffer ID, which a `layers` took off the stack, is read no more: its pages may be painted again |

Both are sent before the reply to the request that caused them, so a
client that waits for the reply, as `wm` does, finds them waiting on
its port after it. `virtio-gpu` counts a frame for each `damage` and
each `layers`, once its commands are answered: its `RESOURCE_FLUSH`es
in 2D mode, or the flushes after its `SUBMIT_3D` in 3D mode. One whose
change shows nowhere, a window's damage under another window, counts
too, so that a client waiting for a frame is never left waiting for a
change of someone else's. It releases a buffer when the `layers` that
left it out is answered: in 2D mode the screen's backing no longer has
its rows, so no transfer reads it again, and in 3D mode no copy reads
its texture, which only a `damage` would bring up to date from its
pages. The driver counts the screen's own pixels; once `info` has
said the scale, the client side, `display.l0`, counts the desktop's, and
makes every place, rectangle, top row and radius the screen's on the way.
A buffer's ID is from 0 to 1,000,000.

**The first frame is the wallpaper.** As soon as its mode is set, a
driver registers `display`, so that a client finds it at once and its
first request waits on the port, and reads the wallpaper (`render.l0`'s
`wallpaper_load`: `/etc/wallpaper.qoi`, or at scale 2
`/etc/wallpaper2x.qoi`), draws it into pages of its own the screen's
size, centered and cut to fit on its corner's color, as `wm` draws its
desktop, and shows that buffer, ID 1,000,001, as the only layer. Every
`layers` puts it under the client's, so what they leave uncovered is
wallpaper, until a client's layer covers the whole screen, square: then
it leaves the stack for good, and its pages are given up. `wm`'s first
`layers` has its desktop, the same image, so the screen goes from the
driver's wallpaper to the desktop with nothing black between. A missing
or unreadable wallpaper is said once on standard error, and the first
frame is black. Neither waits for sound, nor sound for it
([Sound](sound.md)).

## virtio-gpu

**What virtio-gpu's 2D mode does for us.** Without virgl, virtio-gpu
neither blends nor blits. `virtio-gpu` uses the three things it does do,
so that the guest copies no pixels at all:

1. **The host composes the screen**, through scatter-gather backing. The
   screen's resource is backed (`RESOURCE_ATTACH_BACKING`) by a list of
   memory runs. The driver builds that list from the layers, row by row:
   each span of a screen row is a run of the pages of the topmost buffer
   covering it, read from its ring's row. Runs that meet in memory are
   merged. `TRANSFER_TO_HOST_2D` then copies straight out of the
   clients' buffers. Raising, moving or scrolling a window rebuilds the
   list, with `DETACH_BACKING` then `ATTACH_BACKING`.
2. **A hardware cursor**, on the cursor queue: `UPDATE_CURSOR` with a
   64×64 resource, then `MOVE_CURSOR` for each move. Moving the pointer
   costs one small command and no screen update.
3. **Damage-only updates**: a transfer and a flush of just the rectangle
   that changed.

So `vt` scrolls by changing its window's `top`, with no copying anywhere,
and draws only the new row.

**Commands in flight, waited for by the interrupt.** `virtio-gpu` binds
its virtio-mmio transport's interrupt (`irq_bind`, 48 plus the
transport) to a port of its own as it starts, and waits on it and
`display` as one set (`port_set`). A request's commands go into the
control queue as it is handled, each a chain of descriptors over its
place in the request pages and a response slot of its own, as many at
once as the ring's 64 descriptors and the 62 request pages have room for
(`flight.l0`): a long request, a backing of thousands of runs, waits for
the commands before it to free the pages it needs. The device is told
of them once the request is handled, or when the driver must wait for
room. The driver then takes the next request; its reply is sent once
every command made before it is answered, so replies keep their
requests' order, and one whose request made no command goes as soon as
those before it have. Each interrupt is acknowledged, the device's
status and then the kernel's, and the used ring read: the commands used
are retired in the order they were made, whatever order the device
used them in, and a command answered with other than it wants makes
its request's reply an error. The cursor queue's commands are put in
flight the same way, 16 at most, a `move`'s reply waiting for its
command to be used; a new cursor image waits for the control queue's
commands, which the cursor's update names, to be answered first. Before
the driver gives up pages of its own, the wallpaper's, every command in
flight is waited for. An interrupt for a command already seen used is
ended like any other, and a command the device never uses leaves the
driver waiting.

**virtio-gpu's 3D mode.** If the device offers `VIRTIO_GPU_F_VIRGL`, as
QEMU's `virtio-gpu-gl-device` does, the driver (`gl.l0`) composes the
screen on the host's GPU instead, with virgl but without a shader:

1. **Each buffer a client shares is a texture** (`RESOURCE_CREATE_3D`),
   backed by the client's own pages and filled by `TRANSFER_TO_HOST_3D`
   when it is shared. The host's copy of it changes only when a `damage`
   says so, so a client must damage what it paints, as every one does;
   `wm` damages the launcher's page once it has painted it.
2. **The screen is composed from copies** (`compose.l0`): the planner turns
   the layers, bottom first, into `RESOURCE_COPY_REGION` commands, which a
   `SUBMIT_3D` carries to the GPU, 128 to a request. A ring's wrap is two
   copies; a corner a layer cuts is rows copied shorter, so what it looks
   like is what 2D mode shows, pixel for pixel. What no layer covers is
   copied from a black texture of 64 rows. `layers` composes all of the
   screen, a `damage` only the boxes it shows in, and each box is flushed.
3. **The cursor is as in 2D mode.**

A restack of a window drag takes about 8 ms there, against about 20 ms in
2D mode, both under `egl-headless`. If the device offers no virgl, or gives
no context, the driver is the 2D one. Nothing is blended or drawn by the
GPU: it only copies.

## The display layer

Two Wayland-style changes to the display layer (`user/lib/proto/display.l0`,
`user/sbin/virtio-gpu/virtio-gpu.l0`) came with the toolkit:

- **Shaped layers** (`shape ID TL TR BL BR`), like an opaque region. The
  driver narrows a layer's runs on its corner rows, so a window's 12 px
  corners show what's beneath with no blending. `wm` shapes every window,
  and its hit test (`render.l0`'s `corner_cut`, as the driver cuts) lets a press in
  a cut corner fall through.
- **Batched damage and minimal restacks.** One `damage` takes many rects,
  like `wl_surface.commit`, in the display protocol and the compositor's.
  A `layers` change flushes only the bands of rows that changed, and the
  driver builds again only the rows of the layers that changed.
  `ui_present` sends its boxes in one request.

Since then: **client-side decorations**, `wm`'s `csd` request and its
`move ID` (`xdg_toplevel.move`), so a program draws its own header bars
(`ui_open_csd`, `UiCsdBar`), as Files does; such a window has no chrome
of `wm`'s, so it costs no layer or region of its own beyond its content.

## The display on the Raspberry Pi 5

On the Pi 5 the display protocol is served by `hvs` (`user/sbin/hvs/`), a
first draft that has shown the desktop on HDMI0 at 1920×1080, and at
3840×2160 and 60 Hz at scale 2 on a 4K monitor, the mode set by `hvs`
itself, steady with five windows (below). L0 gives the HVS
(0x107C580000), `iommu4` and `iommuc` as regions there (L0 roadmap 0105).
On QEMU it gets none, and says "no HVS on the board" and exits 0.
`pi5/etc/inittab` starts it, with `dev /sbin/hvs`. Before the guard,
the clocks and the IOMMU's setup below, loading it crashed the board, so
`make pi5-shell` still leaves it out (`PI5_SHELL_NO`).

The board's checks found what the driver must guard against:

- **The HVS answers only after a boot with a monitor on HDMI0.** With no
  monitor it is unclocked, and its first read hangs the board silently,
  with no fault and no reset. So before any HVS read, `hvs` asks the
  firmware how many displays it brought up (`GET_NUM_DISPLAYS`, in
  `fw.l0`). If there are none it says "no monitor on HDMI0 at boot; the
  HVS is unclocked" and exits 0.
- **The board's HVS is a D0**: `SCALER6_VERSION` reads 0x00002454.
- **Its clocks are the firmware's.** After it tells the firmware the
  display is its own (`NOTIFY_DISPLAY_DONE`), `hvs` makes sure the
  firmware's CORE (4) and DISP (16) clocks are on, and sets either to
  its highest rate if it reads 0, as Linux's `vc4_hvs_bind` does with
  `clk_prepare_enable`.

It is brought up a stage at a time, by its argument (`start /sbin/hvs
STAGE` in the inittab). Each stage does all of the one before it, then
exits:

| Stage | What it does |
|---|---|
| `hvs mode` | an experiment beside the others: asks the firmware for the monitor's preferred mode (below) and says what the firmware and channel 0's `CTRL0` say after, then exits |
| `hvs hdmi` | beside the others: M2MC made sure of, then reads only HDMI0's regions: the HDMI core's, DVP's, PHY's, rate manager's and CSC's registers, the HD block's, pixel valve 0's and DDC0's, and says the mode the core and the pixel valve give |
| `hvs eof` | beside the others, writing no HVS register, so it runs while `hvs` serves (`run hvs eof`): if the firmware brought a display up, opens the display's interrupt controller and binds its interrupt, 129 (below), saying if the board gives neither; masks and clears every line, unmasks channel 0's, counts its ends of frame for two seconds, clearing the line before each `irq_ack`, and puts the mask back. It says the count, the rate and channel 0's `STATUS` frame count before and after |
| `hvs probe` | reads only: the firmware's displays, the monitor's EDID (and its bytes) and both clocks; the HVS's version and channel 0's `CTRL0`, `CTRL1`, `BGND`, `LPTRS`, `STATUS` and `DL`; the firmware's list, from `DL.LACT` to its end; and `iommu4`'s and `iommuc`'s registers; and what the firmware's display tags answer (`FRAMEBUFFER_GET_*`, `GET_DISPLAY_SETTINGS`, `GET_DISPLAY_TIMING`, `GET_DISPLAY_CFG`), raw. Then it releases the display and reads the clocks again, touching the HVS no more |
| `hvs list` | releases the display, makes sure of the clocks, sets the background to black, and moves channel 0 to an empty list of its own. Then it says the channel's status and list |
| `hvs iommu` | then sets up `iommu4` as `bcm2712_iommu_init` does, and says its registers |
| `hvs` | all that, then serves `display` |

Every step that could hang says so (`hvs: writing iommu4 CTRL off, ...`)
before it runs. The kernel writes that line to the UART before the call
returns, so the last line before a hang names the access. In the full
driver those lines are debug, kept for `dmesg` but not printed.

It is virtio-gpu's 2D mode done by the BCM2712's HVS, the Hardware Video
Scaler (SCALER6), so no pixel is copied:

1. **The mode is the monitor's.** The firmware brings HDMI0 up, always
   at 1920×1080, whatever the monitor and `config.txt` say, and leaves
   the HVS scanning channel 0. `hvs` reads the monitor's EDID from the
   firmware (`GET_EDID_BLOCK_DISPLAY` for display 2, HDMI0, in
   `edid.l0`) and says its name, preferred mode, whether it offers
   3840×2160 and at what rates, and its fastest TMDS. Then it sets HDMI0
   to the preferred mode itself, through the regions L0 gives for
   HDMI0's controller, PHY, pixel valve and DDC (L0 roadmap 0120, asked
   for in [probes/display](../probes/display/REQUEST-pi5-hdmi-mode.md)),
   in Linux `vc4`'s order but changing only what the mode decides
   (`modeset.l0`): the pixel valve stopped, the HVS channel's size, the
   PHY's PLL for the TMDS rate, the HDMI core's and the pixel valve's
   timings, the pixel valve started and the HDMI FIFO recentred; past
   340 MHz, the monitor told over DDC (SCDC, I2C address 0x54) to expect
   scrambling and the core's scrambler on. The rest stays as the
   firmware left it, as `hvs hdmi` read it: the pixel valve at two
   pixels a clock, the CSC, and the clocks, M2MC at 648 MHz and
   PIXEL_BVB at 324 MHz, past what 4K at 60 Hz needs. The boot
   argument `hdmi=boot` keeps the firmware's mode, and `hdmi=30` asks
   for the preferred size at 30 Hz, if the EDID has a timing of it.
   Without HDMI0's regions, as under an older L0, `hvs` keeps the
   firmware's mode unless `hdmi=` asks, and then asks the firmware with
   firmware KMS's `SET_TIMING`, which it never marks answered but obeys;
   but the firmware then keeps the channel (item 3), so past a few
   windows the pointer flickers. `hvs` never resets the HVS, and only
   sets the channel's background to black.
2. **A list of planes.** Each layer is one plane, fetched unscaled from
   the client's pages (`plane.l0`). A ring read from a row other than
   its first is two planes, one each side of the wrap, and a layer
   hidden whole by those above is none. A plane partly off the screen is
   cut, and the cut moves into its address (`pieces.l0`).
3. **Two lists.** A list is written into the half of the list memory
   the channel isn't fetching (words 32 to 2063, or 2064 to 4095), and
   the channel's `LPTRS` pointed at it, which the channel takes from its
   next frame, as `DL` then shows (`frames.l0`): `hvs` binds channel 0's
   end of frame (below) to a port of its own as it starts serving, waits
   on it and its `display` port as one set, and counts each frame.
   **A restack is answered at once** (`pending.l0`): `layers`, `move`,
   `shape`, `cursor`, and a `buffer` given again under an id the screen
   shows, are planned as they come (their planes, their line memory,
   their corners; a screen that cannot be one list is refused then), and
   their list is written and pointed at now if the last list pointed at
   has been taken (`DL` names it, read as the request comes). If it has
   not, the screen asked is kept, over any kept before, and written at
   the end of frame that shows that one taken, after which `DL` is read,
   polling 2 ms more. So a list is never written into a half the channel
   fetches or may fetch next, at most one list a frame is pointed at,
   requests that come between are coalesced into the latest, and that
   one is the screen shown once frames go by. A list pointed at and not
   taken by an end of frame within 50 ms (an alarm on the same port
   wakes `hvs` for it) is said once and `DL` read once more; if it was
   not taken, the firmware is taken to keep the channel. On a board
   that gives no end-of-frame interrupt, and once the firmware keeps
   the channel, each restack is still written and waited for as it
   comes, its reply sent after: `DL` polled a millisecond apart for up
   to 50 ms, or the firmware's lists written below. After a
   `SET_TIMING`, though, the firmware keeps the channel:
   whatever `LPTRS` is given, from the next frame it is back at one of
   the firmware's two lists, words 32 and 672, between which it flips
   every frame or so, without rewriting them, whether it was told the
   display was the driver's before or after. So once a switch is not
   taken, `hvs` writes each list over the firmware's two instead, the
   one the channel is not fetching first, and the other once the
   firmware has flipped to the first: a list rewritten while the HVS
   reads it shows half of each, and its planes' UPM garbled, as white
   columns. Either way the new list's planes take line memory (UPM)
   beside the list shown's: a plane still there as wide keeps its
   units and handle, and any other takes free ones, out of all 1,024
   units and 32 handles (`pieces.l0`). The list beside it is the one
   the channel will be fetching when the new one is written: the list
   pointed at, if one is, else the list fetched.
   **Forgotten pages wait for the lists.** As a restack's reply no
   longer means the list before it is no longer read, a `forget` (or a
   buffer given again under its id in other pages, or the wallpaper
   leaving the stack) drops the buffer from what `hvs` answers from at
   once, but unmaps its pages from the aperture and gives them up only
   once no list names them that the channel fetches, is pointed at, or
   is wanted next, nor the list it fetched before the one it fetches,
   until that one is shown: at once if none does, else at the end of
   the frame that shows a list leaving them out. A buffer given again
   in those pages meanwhile keeps them.
4. **The IOMMU.** A plane reads one run of addresses, and a client's
   pages are scattered. So each buffer's pages are mapped one after
   another in a 512 MB aperture of `iommu4` at 40 GB (`iommu.l0`).
   Memory below the aperture passes through as it is. The tables are 129
   of the driver's DMA pages, cleaned with `dma_sync` before the IOMMU
   reads them, and a 130th, zeroed, is the default page `ILLEGAL_ADR`
   sends unmapped addresses to. The registers are written in
   `bcm2712_iommu_init`'s order: `CTRL` off with its sticky bits and TLB
   cleared, `MISC` two-level, `ADDR_CAP`, `BYPASS_START` 0,
   `BYPASS_END`, `PT_PA_BASE`, `ILLEGAL_ADR`, the cache flushed, then
   `CTRL` on. The channel is on the driver's own empty list by then, so
   no plane is fetched while the IOMMU changes. A buffer given again in
   the same pages, as a window resized in its room is, keeps its place.
5. **Damage is a cache clean.** The HVS reads every pixel every frame, but
   the Pi's DMA does not see the CPU's caches. So `damage` only cleans the
   pages of the damaged rows, and `buffer` cleans all of a new buffer's.
6. **The pointer is a plane on top** with its pixels' own alpha. A move
   writes the list again. A new image, which `wm` paints into the same
   buffer, has its pages cleaned when `cursor` names it; before, the HVS
   showed it torn, old rows beside new, until the caches wrote back.

7. **Rounded corners are alpha.** Cutting them a row at a time would
   cost a plane per row of each corner, and the HVS has 32 handles (see
   [Limits](#limits)), so a layer whose buffer `shape` rounded is a
   plane with its pixels' own alpha, as the pointer is. The toolkit
   writes every pixel opaque, its fourth byte 0xff (`render.l0`'s
   `canvas_opaque`), and the driver writes that byte 0 in the pixels its
   corners cut, the same ones virtio-gpu leaves out (`corner_cut`;
   `corners.l0`): again after a `damage` that drew over them, before the
   rows are cleaned, and back to 0xff where a new `TOP` or shape no
   longer cuts. A rounded layer still hides what is under it between its
   corners, and is still cut to what shows of it.
8. **The first frame is the wallpaper**, as in the protocol above: once
   the channel is on the driver's list and the IOMMU is on, `hvs`
   registers `display`, draws the wallpaper into `shm_alloc`'s pages of
   its own, the screen's size (8 MB at 1920×1080, 33 MB at 3840×2160),
   through a region it closes at once, so that it keeps none of the 64
   open, and maps them in the aperture as a client's buffer is, cleaned
   out of the caches. That buffer is one plane, under every client's
   layers, over the black background, until a client's layer covers
   the screen. Then it leaves the stack, and its pages are given up as a
   forgotten buffer's are (item 3): once the list without it is shown,
   its place in the aperture cleared and its pages unmapped. Seen on a
   Pi 5, before the desktop.

**The end of frame.** `hvs` takes channel 0's to point the channel at
the next list (above, Two lists). What is known of it, from Raspberry Pi's Linux
(rpi-6.12.y: `bcm2712.dtsi`, `vc4_hvs.c`, `irq-brcmstb-l2.c`) and,
where it says so, the board:

- The SCALER6 HVS has no interrupt enable or status of its own for a
  channel's end of frame: `vc4_hvs.c` enables and disables the line at
  the display's interrupt controller, `disp_intr`
  (`interrupt-controller@7c502000`, 0x30 bytes, `brcm,bcm2711-l2-intc`,
  on a page of its own beside `mop` and `moplet`).
- Channel 0's end of frame is that controller's line 2 (`ch0-eof`),
  channel 1's line 9, channel 2's line 16. Its registers, level
  triggered: the lines raised at 0x00, a write of 1s clearing them at
  0x08, the mask at 0x0C, a write of 1s masking at 0x10 and one of 1s
  unmasking at 0x14.
- The controller raises GIC SPI 97, the GIC's ID 129, at the GIC-400.
- L0 gives both since its roadmap 0127
  ([probes/display/REQUEST-pi5-hvs-eof.md](../probes/display/REQUEST-pi5-hvs-eof.md)),
  the controller as a region and 129 as a level interrupt, setting
  neither up.
- **Seen** on a Pi 5 at 3840×2160 at 60 Hz, the desktop up (`run hvs
  eof`): the firmware leaves every line unmasked (mask 0). Two seconds
  took 121 interrupts, 120 of them with line 2 raised, 59.9 Hz, and
  `STATUS`'s 6-bit frame count went from 14 to 6, 120 frames on.
- **Seen** with `hvs` serving on it: the wallpaper, and windows opened
  and stacked, every switch taken by an end of frame, none said to have
  waited 50 ms.
- A process that enabled 129 and left a line unmasked as it exited hung
  a Pi 5: the stage now masks every line as it ends, and the kernel
  holds an interrupt nobody binds taken (syscalls.md).

**Which frame showed what** (`shown.l0`). `hvs` counts every frame:
at each end of frame it reads channel 0's `STATUS` and carries its
count on by the 6-bit frame count's step, so the frames that pass while
it serves a request, its interrupt taken and not yet acked, count too
(up to 63 at once). Each change is noted with a number and the frame it
is shown by: a list switched, once `DL` shows it taken, at the end of
the frame after the count then (`STATUS`'s, as the request comes, so
an end of frame not yet taken counts); a `damage`'s clean, a frame later still, as the
frame being fetched may have read some rows before. At each end of
frame the changes due are marked shown, and `hvs` keeps the latest
shown. Every 600th frame it says the count and the changes at the debug
level (`hvs: frame 1200: changes shown to 189 of 189, 0 pending`),
and any gap of over 100 ms between ends of frame it took (`hvs: no end
of frame taken for 714 ms, frames 19310 to 19311`), as more than 63
frames in one would go uncounted.
**Seen** on a Pi 5 at 3840×2160 at 60 Hz: frames 600, 1200 and 1800
said 10.000 s apart, every change shown, none left pending.

**Frames and releases** (the protocol's `frames`). `hvs` keeps the ports `frames` names (`frames.l0`), and at
each end of frame that shows a change, by the bookkeeping above
(`shown.l0`'s `changes_shown`), tells them first a `release` of each
buffer the lists it shows left out, then `frame N`, N counting the
frames that showed a change from 1. A list seen taken notes the
buffers the list before it showed and it leaves out
(`changes_releasing`), so they are released at the end of the frame
after the one that took it, as the HVS reads every pixel of a buffer
it shows every frame; a screen asked and coalesced away before it was
written releases nothing. A `damage` is a
frame two ends of frame on, as its clean is shown; a pointer's move,
which writes the list again, is one too. Unlike `virtio-gpu`'s, these
notices come after the reply, at the end of the frame. Where the board
gives no end of frame, and `hvs` polls, it tells a frame as each change
is made and a release as its list is taken.
**Seen** on a Pi 5 at 1920×1080 with five windows: each window's
buffer swapped and its frames told (`run windows`), the toolkit's
slowest presents 6.5 to 13 ms, none over 100 ms, nothing torn or
garbled, no fallback; at 3840×2160 the presents as short, the desktop
slowed by the HVS's stalls (Limits) and by painting at scale 2.

**The first runs** go one boot a stage, `probe`, `list`, `iommu` and
then the whole driver, each with `tools/pi5-boot --until 'l0s>'` and its
log kept from `build/pi5-serial.log`. They should check these on the
serial line and `dmesg`, against Linux's view of the same board. None
of them could be confirmed from Linux's source:

- `probe`, **seen**: the release gates no clock. DISP is on at 648 MHz
  before and after it. CORE reads "off" at 500 MHz throughout, and still
  does after `SET_CLOCK_STATE` on, while the HVS answers, so that bit
  says nothing of CORE's gate
- `probe`, **seen**: channel 0 is enabled at 1920×1080 and running
  (`STATUS.MODE` 2), with `BGENB` already set. The firmware's list is at
  word 32: one 4-word plane that reads no memory, then the end.
  `iommu4` is off (`CTRL` 0, `ADDR_CAP` and `BYPASS_END` 0xfff and not
  enabled, `MISC` 0x80003ffc with `SINGLE_TABLE` set), so nothing the
  firmware left fetches through it. `DEBUG_INFO` is 0x20804774, so
  `BYPASS_END` counts in 256 MB units
- the D0 layout `SCALER6_VERSION` picks: **seen** right for channel 0's
  `CTRL0`, `LPTRS`, `STATUS` and `DL`
- `list`, **seen**: `LPTRS.HEADE` is taken, so `DL.LACT` comes to word
  2064, and the screen goes black with the board alive
- `iommu`, **seen**: each write lands as written (`CTRL` 0x04090803,
  `ADDR_CAP` 0x800000a1, `BYPASS_END` 0x800000a0, `MISC` 0x00003ffc,
  `ILLEGAL_ADR` the default page). The TLB clears and the cache flushes
  within their polls, and the channel runs on under it
- the whole driver, **seen**: `wm`'s desktop shows on HDMI0, its planes
  fetched through the aperture in the D0's words, and `gem` and DHCP
  work beside it. Still open: a USB keyboard on `xhci 1`'s port 1 fails
  to be given an address (`address device failed: 4`) in that boot
- `SCALER6_UBM_SIZE` and `CXM_SIZE`: the driver takes 1,024 units of UPM
  (256 KB) and 4,096 words of list memory
- that a plane's UPM can be sized by its width rather than its buffer's
  stride
- the pointer's alpha: not premultiplied, as the toolkit paints it
- that the 9th word of a plane, which CTL0's NEXT counts, is skipped

## Limits

- **The wallpaper is drawn at two sizes**, 1920×1080 and 3840×2160, at
  the build. A screen of another size shows the one its scale picks,
  centered and cut, or on its corner's color where the screen is the
  larger: never scaled. Until it leaves the stack it holds the screen's
  size in pages, 4 MB at 1280×800, 8 MB at 1920×1080, 33 MB at 4K, and
  reading and drawing it delays the answer to the first request: about
  0.1 s of decoding at 1920×1080 on this host's CPU, and some seconds
  on QEMU's at 4K, where `tests/hidpi.sh` sees the desktop after 8 s
  where it saw it after 4.
- **A screen's backing is at most 15,870 runs**, what the virtio-gpu's
  control queue of 64 entries can carry in one request. A 4K desktop
  whose pages are all apart, with a 1280×800 window over it, at scale 2,
  takes 10,500; more windows over pages apart could reach the limit, and
  the driver then says the screen is in too many pieces. Pages given
  together usually lie together, and their runs join.
- **Nothing is drawn by the GPU.** With virgl (the GL device) it copies
  the layers into the screen, and in 2D mode the host composes them
  from the clients' pages, but every pixel in them is painted by the
  guest's CPU, at scale 2 four times as many. Nothing is blended.
- **The Pi 5's display is new** (see
  [The display on the Raspberry Pi 5](#the-display-on-the-raspberry-pi-5)):
  it has shown the desktop on one board, at 1920×1080 and at 3840×2160.
  Every layer is one plane, a scrolled ring two, and a layer hidden
  whole by those above is none. The planes share the HVS's 32 UPM
  handles and 256 KB of line memory (1,024 units) with the list shown:
  a plane still there as wide keeps its own, and any other takes some
  that list does not use, as Linux's `vc6_plane_allocate_upm` does. A
  row 1920 wide takes 61 units and one 3840 wide 121, so a screen holds
  about 16 rows of 1920, or 8 of 3840: at 3840×2160 the desktop and the
  top bar take 242 units, and a window about W/8 for a width of W at
  scale 2, its content and its frame. A screen past either is refused,
  and so is every list after it, the pointer's moves among them, so the
  pointer shown stops while `wm`'s moves on, until a window shrinks or
  closes (seen with one widened to 3032 pixels at 4K). Resizing windows
  at 4K has also brought gaps of up to a second with no end of frame,
  the HVS's own frame count barely moving, as if the channel stalled;
  more than 63 frames in one leave `hvs`'s count short. With five
  windows opened and moved at 4K, stalls of about 117 ms (two or three
  frames where seven were due) came again and again, at multiples of
  about 1.2 s, and the desktop slowed with them. Neither was seen at
  1920×1080.
  A restack is answered before it is shown, and shown by the third end
  of frame after it at the latest, as one list a frame is pointed at:
  only while the channel is the driver's and ends of frame come. Where
  the board gives none, or the firmware keeps the channel, each restack
  is waited for as it comes, up to 50 ms or a frame, and `wm`, which
  waits for each reply, with it.
  On a screen 2560 wide or more a window's frame is fetched only where
  it shows, while that leaves half the handles and line memory free.
  At 3840×2160 and 60 Hz the HVS has shown five windows steady; with
  more the planes it fetches each line may outrun it (black lines,
  seen when the frames were fetched whole). Corners are square there.
- In 2D mode, the display driver attaches a whole new backing, a run list of some
  thousands of entries, for every raise, move or scroll, though it builds
  again only the rows that changed, and finds who shows along them once
  for each run of rows alike. A drag's restack takes about 9 ms with two
  windows on QEMU, about 5 of them building the rows that changed, 3
  joining the run list and attaching it (virtio-gpu's 2D mode has one
  backing for the screen, and replaces it whole), and 1 showing the
  damage, so a drag shows a few dozen positions a second, not every one.
  With virgl a restack is a few commands, and nothing is attached again.
