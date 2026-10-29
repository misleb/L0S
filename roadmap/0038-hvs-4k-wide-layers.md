# 0038: `hvs` at 4K: wide windows, a pointer that keeps moving, and no stalls

Track: Display · Status: active · Needs: – · Spec: display.md, kernel.md, syscalls.md, desktop.md, toolkit.md, pi5.md

## Why

Seen on a Pi 5 at 3840×2160, scale 2, during 0005's step 5, which went
clean at 1920×1080:

- **Every list refused once the layers are too wide.** System Monitor
  widened to 1516×520 (3032 pixels) beside overlapping windows: `hvs:
  refused: the screen's layers are too wide for the HVS's line memory`,
  3,152 times. Every list after it was refused too, the pointer's moves
  among them, so the pointer drawn stayed put while `wm`'s moved on: a
  detached cursor until the window was closed (`kill`). The refusal is
  from `screen_planes` (`pieces.l0`'s UPM budget, since the 4K mode,
  `c074150`).
- **The channel seems to stall while windows are resized.** 0005's gap
  lines: `no end of frame taken for 1087 ms, frames 19224 to 19267`,
  `714 ms, frames 19310 to 19311`, and more, all during resizes. In the
  714 ms STATUS's frame count moved one frame where 60 Hz is about 43,
  so the HVS itself made no frames, not the driver missing them; more
  than 63 frames in one gap also leaves `hvs`'s count short, by 64 in an
  earlier run.

## Done when

- A list too wide for the line memory never stops the pointer: the
  pointer's moves are shown, and the screen with the widest layers is
  still shown in some form, said once, not refused for good.
- On a Pi 5 at 3840×2160, scale 2, five windows opened, dragged and
  resized for five minutes bring no gap over two frames in 0005's gap
  line, and `hvs watch` sees no frame over 25 ms.
- `make check` and `make test` pass, with the watch's and any new
  layout's rules tested on the host.

## Steps

- [x] `hvs watch [SECONDS]`, a stage beside the serving driver, reading
  only: channel 0's STATUS and DL as fast as it can, and for each frame
  over 25 ms, less the longest time between two of its samples, one
  line: when it began, how long it took, the lines STATUS's YLINE went
  through, the modes it was in, and the registers before and after.
  Its record of samples pure and tested on the host.
- [x] Run it on the Pi 5 at 4K with five windows dragged and resized,
  and log what a stall is: the channel stopped in its frame (YLINE
  stuck, the HVS's fetch behind), at its end (the pixel valve or HDMI),
  or not running; and what it follows (a resize, a restack, a number of
  planes, the 1.2 s rhythm 0038's Log found). The fix's steps are
  written from that. (Log: System Monitor's refresh, the kernel
  counting every process's pages.)
- [x] The kernel counts a process's own and shared pages as they are
  mapped and unmapped, so `proc_info` and `mem_info` answer without
  walking every page of every process; timed on the board before and
  after, with System Monitor open at 4K, by 0005's gap line and `hvs
  watch`. `make test-virt` with tests of the counts against a walk.
  (Log: System Monitor's read from 71 ms to 4.4 ms, and no frame over
  25 ms.)
- [x] The driver late: a resize's buffer mapped and synced, and any
  other step `hvs` takes over a frame, timed and taken out of the
  frame's way. (Log: `hvs` cleans only a buffer's pixels' pages; the
  kernel's shared-memory calls were the rest, and the kernel keeps a
  pool of zeroed frames for them, made while idle.)
- [x] Layers too wide: the pointer's move shown whatever the windows'
  width, and a screen past the line memory shown, by fetching less of
  it, not refused. (Log: the lowest pieces left out until the rest fit,
  said once; the `forget` storm gone with the refusal.)
- [x] The 4K memory budget: at scale 2 a big window's buffers took
  about 140 MB of the 384 MB of device pages above a process's stack,
  so with two or three big windows a buffer more had no room in `hvs`.
  Every device page, region, DMA and shared, now lies in L0's high user
  range, 0x2000000000 up to 0x4000000000, 128 GB (spec §10.3, L0's
  0128), and the 384 MB above the stack is mapped by nothing; a copy in
  or out of a process stays in one range; the file-window notice's
  address is a u64. Board tests of 1,136 MB of device pages past a
  gigabyte, the same frames read back across it, and a process's
  tables over it given back as it ends. The HVS's background takes the
  wallpaper's corner's color where pieces are left out, and `hvs` says
  the CPU's and RAM's clocks. `dma_limit` and the toolkit's room to grow
  are as they were, and `wm` still trims, which keeps the kernel's page
  records down. (Log: no window unshown at 4K; the CPU at its full 2.4
  GHz.)
- [ ] The fit without flicker: a list must fit beside the one shown, so
  while a big window is dragged off the screen's bottom edge beside
  others, lists alternate frame by frame between most of the screen
  left out and none of it. Leave out first the pieces that need line
  memory the list shown does not give them, the moving window's, not
  the lowest, or hold the list shown a frame more; tested on the host
  with the alternation the board showed.
- [ ] The board run of "Done when", at 4K and at 1920×1080.

## Spec changes

- display.md: the flicker gone from its Limits once step 7 is done.

## Log

- 2026-10-29: written from 0005's step 5 board run.
- 2026-10-29: seen again in 0006's board run at 3840×2160, scale 2,
  with `hvs` answering restacks at once: smooth at first, then sluggish
  as Files, Fonts, Disks, System Monitor and Terminal were opened and
  moved, never a glitch. 41 gaps of 100 to 156 ms between ends of frame
  in nine minutes, from about four minutes in. In 30, STATUS's count
  moved 2 or 3 frames in about 117 ms where 7 were due, so the HVS
  itself made no frames; they came at multiples of about 1.2 s
  (352.75 and 353.96 s, 446.31 and 447.53 s), a rhythm worth matching
  against what runs each second (System Monitor's refresh, the clock).
  In the other 11 the count moved as it should, so the driver was late,
  likely mapping a resized window's buffer.
- 2026-10-29: steps written; step 1, `hvs watch`, built and run on the
  Pi 5 at 3840×2160 with Files, Fonts, Disks, System Monitor and
  Terminal open. Sleeping 1 ms between samples slept 13 to 30 ms, so
  it samples as fast as it can, and counts a frame long only past the
  largest gap between its samples. At rest for 20 s: 1198 frames, 59.9
  Hz, none long. With the user dragging and resizing for four minutes:
  16 frames of 47 to 53 ms, one frame counted in each, YLINE moving
  (400 to 872, 4 to 1079), always running, HANDLE_ERROR 0, DL steady:
  the channel slowed, not stopped, and `hvs`'s own gaps of 100 to 170
  ms every 1.2 to 1.3 s beside them, the watch's own samples held off
  at the same times. Idle, with no one at the board: a gap of about
  101 ms every 1.19 s (STATUS 2 to 6 frames in it), and none in 40 s
  once System Monitor was closed. Step 2: the stall is System Monitor's
  refresh, each second: its `mem_info` makes the kernel walk every page
  every live process maps (`k_used_frames` to `proc_page_counts`, a
  `map_keys` of each process's pages and a lookup of each), and its
  `proc_info` of each process the same again, all on CPU 0, which holds
  every other CPU's calls; at 4K `wm`, `hvs` and each app map every
  window's buffers, twice since 0006, tens of thousands of pages. The
  HVS slowing with it is likely that walk's memory traffic. Also seen:
  `dmesg`'s 64 KiB written to the UART at 115200 baud held `hvs` from
  its ends of frame for 350 to 770 ms at a time, so a stall is timed
  with no `dmesg` running.
- 2026-10-29: step 3. Each process's pages are kept as `Pages`
  (`memory.l0`), the map and how many of them are at its device pages,
  counted as each is put and removed; its shared image pages are
  counted from the image segments it shares (`mem_image_pages`), not
  from its pages. A first version read the map again after putting to
  it, so every put copied the whole map (an L0 map is changed in place
  only when nothing else holds it): the Pi was unusable and
  `test_frames_run_out` did not end in an hour. Counted before the put,
  that test takes 14 s, as before. On the Pi 5 at 3840×2160, scale 2,
  with Files, Fonts, Disks, System Monitor and Terminal open, System
  Monitor's read each second (its `proc_info` rows, then `mem_info`)
  went from 71 and 35 ms to 4.4 and 1.3 ms; `hvs watch 30` at rest:
  1800 frames, none over 25 ms, the longest 16.6 ms, where the 1.19 s
  gap of about 101 ms was before. The user: moving windows and widgets
  responsive; resizing and scrolling large views still a little choppy,
  which steps 4 and 5 and goals 0039 and 0040 are for.
- 2026-10-29: steps 4 and 5, on the Pi 5 at 3840×2160, scale 2, with
  `hvs`'s requests over 4 ms said (`slow_request`) and, for the run,
  each kernel call over 4 ms. A resize's `buffer` took 32 to 41 ms,
  cleaning all 11,664 pages its client shared, room to grow included;
  cleaning only the pixels' 3,310 took it to 7 to 13 ms, 25 ms for a
  window near the screen's size. The gaps left came with no `hvs`
  request in them: the kernel's `shm_alloc`, `shm_unmap` and `shm_share`
  of 8,000 to 13,000 pages, tens of ms each on CPU 0. Timed per page at
  boot over 8,192: `frame_new` 2.75 us (L0's zeroing, about 1.5 GB/s),
  the share counts' map 0.9 us and a rehash of the whole of it each
  time its size crosses a power of two, `pages_put` 0.4 us, `space_map`
  0.05 us. So the kernel keeps a pool of up to 16,384 zeroed frames,
  made 128 at a time while CPU 0 is idle; the screen's buffer's
  `shm_alloc` went from 29 to 11.4 ms, `wm`'s from 37 to 12.6. Asked of
  L0: a faster `frame_new`, a larger user range, `Map` hysteresis, and
  a warning for a map read after a put, which copies it whole (made
  twice here: in `pages_put`, which made mapping quadratic until fixed,
  and in a timing line that held a process during its call).
  Layers too wide were refused, and every list after them, and `wm`
  then asked again and again to forget buffers still on the screen
  shown, each refusal a 6 ms line on the UART, until the pointer froze;
  now the lowest pieces are left out until the rest fit, which shows
  as black where the wallpaper's lower pieces were while windows are
  that wide. Then windows froze after resizes: their next buffer's
  share was refused, silently and retried each present, as the
  compositor had no room: `wm` with 84,000 of its 98,304 device pages
  given, its largest gap 5,592 where 11,387 were asked. `wm` now keeps
  one page of each client buffer, and the toolkit says a refused share
  once; a first version gave up a trimmed buffer's whole range, taking
  other buffers placed in it since, which the e2e's Files maximize
  caught. `hvs`, which must map every buffer to clean it and cut its
  corners, then ran out the same way (83,000 given): step 6.
- 2026-10-29: L0 answered the four requests (its commits 863e263 and
  449124f, installed here with `l0 init`). A high user range,
  0x2000000000 up to 0x4000000000, beside the old one (its 0128),
  tested on QEMU, not on a Pi 5: step 6 rewritten around it, in place
  of shrinking the buffers to fit 384 MB. `frame_new` zeroes with `dc
  zva` now (0129), but the old memset was already 32-byte stores: 2.67
  us a fresh frame of 8,192 against 2.71, since past the caches the
  zeros' writes to DRAM, about 1.5 GB/s, are the cost; the pool stays,
  and the CPU clock the firmware leaves is worth reading. A new frame's
  zeros reach a device that does not see the caches only after
  `(frame_sync f 1)` (spec 6.13), as `hvs` already syncs a buffer it is
  given. `Map` keeps rehashing across a power of two (0130 left
  queued), which keeping a count off the boundary avoids. The hidden
  copy is documented in `l0 doc Map` and the l0-code skill (0131);
  `L0_ARRAY_STATS=1` counts the copies.
- 2026-10-29: step 6 on the Pi 5 at 3840×2160, scale 2: the kernel's
  layout line says device, DMA and shared pages from 0x2000000000, and
  five big windows resized hard left none unshown, no "next buffer is
  not shown", no fault, where before two or three froze. The firmware
  measures the ARM clock at 2400 MHz, its most (set 1500), and SDRAM at
  250 MHz (set 0, at most 400); Raspberry Pi documents no SDRAM clock
  for the Pi 4 on, so zeroing frames past the caches costs what it
  costs and the pool stays. The background register's bits, found by
  writing it on the board: red asked as 10 bits from bit 20 showed
  green, and bits 10 to 19 alone blue, so green, blue, red from the top.
  With a big window dragged off the bottom beside others, the screen
  below the top bar flickered to the background every other frame
  (step 7), and a black band moved with it, lines the HVS could not
  fetch (goal 0050). The vt screen test assumed its vts were pids 17
  and 18; once in seven runs a brief process took 18, so it now reads
  them from `ps`.
