---
name: l0s-dev
description: Map of the L0S operating system (a microkernel and user programs written in L0) and checklists for changing it. Where each piece lives, how files are linked together, how to add a program, a library, a server request or a system call, the server/listen/driver patterns, and the pitfalls that cost time. Use before any change to L0S code, the Makefile, an inittab, or a protocol, and whenever you need to find where something is done. Pairs with l0-code (the language), l0s-testing and l0s-ui.
---

# Working on L0S

L0S is a microkernel for QEMU's aarch64 `virt` board and the programs that
run on it, all in L0. Read the `l0-code` skill for the language; this one is
about the system. `README.md` is the full human description: go to it for
detail, but use this skill and `make -s doc` to find things fast.

## Find things before reading files

```bash
make -s doc                    # every documented name in the libraries, one line each
make -s doc Q=port_send        # one name in full: def, data type, or constructor
make -s doc Q=l0s              # one library file in full (its stem: l0s, wm, widget, kernel...)
make -s doc Q=sbin/wm/wm       # any file by the end of its path, a program's too
make -s doc Q=cascade          # a program's own def, when no library has the name
make -s doc Q=damage           # every name or doc line mentioning the text
l0 doc NAME                    # the L0 standard library, which is linked into everything
```

Run both before writing a helper: L0S's libraries already have list, number,
request and drawing helpers that the standard library lacks. Queries look
in the libraries first, then in every program's and tool's own sources (a
name found there is that program's, which no other program can link), so
reach for `make -s doc` before grepping for a name; grep is for where a
name is used. The l0s MCP server's `doc` tool runs the same. The docs are
the `;` comment block directly above each form, so write yours that way
(below).

## What connects to a name: the graph

`make -s doc` says what a name is. For who calls it, what a change to it
reaches, or what a program is built from, ask the knowledge graph in
`graphify-out/` (built by `/graphify`, kept current by `make graph` and
the hook `make graph-hook` installs; see the Makefile's header) instead
of opening file after file:

```bash
graphify explain "request_numbers()"   # a name, its file and line, every caller and callee
graphify affected "request_numbers()"  # what depends on it, two levels out: before changing it
graphify affected Rect                 # a type: everything that names it
graphify explain user_sbin_hvs_hvs_handle   # a name defined in several files, by its node id
```

A def is `NAME()`, a type or constructor is bare `NAME`. A name more than
one file defines (`handle()`, `complain()`, `main()`) prints each match's
node id, which is the file's path with `_` for `/` and `.l0` dropped, then
the name. Each edge gives the file and line it was read at.

What it is and is not:

- Calls, references to a type, constructors' uses, and which file holds
  each form, read from the L0 itself (`tools/graphify-l0`), plus the
  scripts and Python, and concepts from the README, skills, rules and
  probes linked to the files they name.
- **Not run-time messages.** Programs reach each other through ports, so
  `graphify path "usb_hid()" "wm()"` finds nothing: that path is the
  README's table of who talks to whom. `path --undirected` finds one
  through a doc instead, which is no call at all.
- **A name defined in several places is not linked** where a caller could
  mean either, rather than guessed. A missing caller is possible, so
  grep before deleting a name.
- The communities and their names in `GRAPH_REPORT.md` are clustering, a
  rough map, not the design; `graphify query` is a loose search, weaker
  than `explain`.
- Docs change it only through `/graphify --update`. If `graphify-out/`
  is missing, nothing here works: say so and use `make -s doc` and grep.

`tools/graphify-l0/graph-usage [-v] [SESSION...]` says which sessions
asked the graph, and how, from their transcripts.

## Where things are

| Path | What |
|---|---|
| `kernel/` | the kernel, `--target virt`. `kernel.l0` is the state, every call's handler (`do_*`), `dispatch`, traps and the loop; `syscall.l0` decodes registers into a `Call`; `elf.l0` reads and checks a program's ELF (spec 10.3), which `process.l0` maps segment by segment with their flags' perms, bss on first touch (a raw image is refused); `process.l0`, `memory.l0` (a process's `Layout`: where its image lies, its heap, what may be written), `mounts.l0` (the mount table: the initramfs at `/` until `root_switch` makes a volume `/`, volumes at `/Volumes/LABEL` with their UUIDs), `ipc.l0`, `sched.l0`, `pids.l0`, `inittab.l0` are its parts. File calls on a volume go to its server as fs-protocol requests (`ask_fs`, the `AwaitingFs` state). `asm.l0` hand-assembles threads for board tests |
| `common/` | shared by kernel, programs and host tools: `abi.l0` (call numbers `call_*`, error codes, limits, `le16`/`le64` and their readers, `label_ok`, `pages_for`, `array_from`/`array_to_list`), `text.l0` (lists and strings: `nth`, `take`, `drop`, `unwords`, `join_with`, `split_on`, `lines`, `up_to`, padding, `is_number`, `word_number(s)`, `ceil_div`); `initramfs.l0` (the cpio archive) and `queue.l0` for kernel and programs |
| `user/lib/sys/` | in every program (`ULIB`): `l0s.l0` (call wrappers, `request`, `port_ask`, `reply_why`, `shm_region`, `shm_share_to`, `put_bytes`/`get_bytes`, `KeyEvent`, `PointerEvent`, notices, `name_wait`), `server.l0` (`name_register_or_why`, `irq_bind_or_why`, `request_numbers`, `Served`, `served_ok`/`served_error`, `request_answer`, `port_tell`, listeners), `cli.l0` (`complain_as`, `note_as`, `say`, `arg_number`, `read_whole`, `write_whole`, `done_why`; the host tools link it too). Where a `LIBS_` list says: `tty.l0` (`TTY`), `keymap.l0` (`KEYMAP`: the US layout, for `virtio-input` and `usb-hid`), `virtio.l0` (`VIRTIO`: `virtio_open`, `virtio_probe`, `virtq_mem`, `virtq_offer`, `virtq_wait`, `VirtqRun`), `procs.l0` (`PROCS`: the live processes, `state_text`), `mailbox.l0` (`MAILBOX`: the Pi 5's VideoCore mailbox, `mailbox_ask`, for `rtc` and `gem`), `paths.l0` (`PATHS`, with `proto/fs.l0` and `uuid.l0`: `root_paths`, `program_found`, `spawn_path`; a program never uses `entry_paths` or `spawn_entry` to find or start another, since `/` may be a volume) |
| `user/lib/proto/` | the servers' protocols, client side: `display.l0`, `wm.l0`, `clock.l0`, `disk.l0`, `fs.l0`, `app.l0` (apps: a bundle's manifest, the bundles there are, the app a program is, running one by its bundle's name), `nic.l0` (`NICLIB`: the network driver's frames, Ethernet addresses), `inet.l0` (`INETLIB`, with `nic.l0`: the IPv4 stack's requests and notices, IPv4 addresses), `usb.l0` (`USBLIB`, with `format/usbdesc.l0`: the usb protocol `xhci` serves to `usb-hid` and `lsusb`), `pci.l0` (`PCILIB`: what `pcie` found) |
| `user/lib/format/` | data as bytes, pure, linked by host tools too: `uuid.l0` (UUIDs, version 7), `crc32.l0`, `gpt.l0` (the partition table, `gpt_layout`), `mbr.l0` (MBR's table, read only; `PARTS` is these four), `l0fs.l0` (a volume's on-disk format, directories as cluster chains), `fat.l0` (FAT32, `FAT` with `l0fs.l0`, whose result types it shares; fs reaches either through its own `volume.l0`'s `fv_` calls), `ppm.l0` (PPM images, `rgb` and its channels), `usbdesc.l0` (USB's descriptors and setup packets, `USBDESC`) |
| `user/lib/gfx/`, `user/lib/ui/` | `rect.l0` (`RECT`: `Rect`, the one rectangle type, and its operations, for layout, painting, damage and the protocols); `render.l0` (`RENDER` is it with `ppm.l0` and `rect.l0`: the `Canvas`, over a shared region or an array (`canvas_new`), shapes, the font, `corner_cut`, `draw`'s commands); the toolkit (`l0s-ui`) |
| `user/bin/NAME/`, `user/sbin/NAME/`, `user/apps/NAME/` | one program each: `NAME.l0`, `NAME_test.l0`, `main.l0` (only `main`), and any more `.l0` files of its own with their tests (`sh/files.l0`, `wm/launcher.l0`). The directory says where it goes: `bin` a command, `/bin/NAME`; `sbin` a driver or service, `/sbin/NAME`; `apps` an app, with its bundle's source `APP.app/` (`manifest`, `icon.draw`) beside it, `/Applications/APP.app/NAME`. The Makefile finds all three |
| `user/sbin/wm/launcher.l0` | the compositor's launcher, GNOME Shell's grid of apps: its layout, painting and clicks |
| `demo/etc/` | the demo's `inittab` (stage 1: `boot`, the drivers, `fs`), `system` (what `boot` starts: `sh`, `wm`, the `vt`s), `motd`; `tests/screen/etc/` the screen tests' |
| `build/root` | `make root`: every program staged as the initramfs holds it, `bin/`, `sbin/`, `Applications/APP.app/`, which `tools/mkinitramfs OUT ETC ROOT [IMAGE...]` archives with an `etc` |
| `tools/` | `mkicon/` (an L0 tool: an app's `icon.svg` or `icon.draw`, `run draw`'s commands, drawn into its 48×48 `icon.ppm`, and with a face given, its 96×96 `icon2x.ppm`; `--image` an `icon.svg`'s `icon.face` for Files), `mkicons/` (an L0 tool: GNOME's symbolic SVGs under `icons/` rasterized into `/etc/icons`; `make icon-sheet`), `mkfont/` (an L0 tool: TrueType outlines and `fonts/cursors.paths`, rasterized by `user/lib/gfx/raster.l0` into `/etc/face`, the text's glyphs at every scale and the pointers: `ttf.l0`, `shape.l0`), `pi5-boot` (a real Pi 5 over TFTP: builds `build/pi5-tftp`, checks dnsmasq serves it, reads the UART into `build/pi5-serial.log`; `--until`, `--console`), `qemu-boot.sh` (boots with the serial line on a terminal, monitor and QMP sockets, `QEMU_DISK` as a virtio-blk, and `QEMU_GPU` the GPU's options, such as `xres=3840,yres=2160`), `mkinitramfs`, `mkdisk` (a fresh 1 MB disk image, or of any layout, partitioned and formatted by `mkfs/`, an L0 host tool, which fills a volume from a cpio too; `fat32` or `fat32=CPIO` as a volume's archive makes it FAT32, and `mbr` first an MBR in place of the GPT), `deadline` (timeout, macOS has none), `slowtype`, `mksplash/` (an L0 tool), `l0sdoc/` (`make doc`), `l0s-mcp/` (the MCP server that boots and drives L0S, in Python; `make mcp`), `graphify-l0/` (the knowledge graph's L0 parser and its rebuild, in Python; `make graph`, `make graph-hook`) |
| `tests/` | `e2e.sh` and `e2e/CASE/`, the screen tests `gpu-screen.sh`, `keyboard.sh`, `vt.sh`, `widgets.sh`, `resize.sh`, `procmon.sh` |
| `build/` | everything make makes; ignored by git |

Who talks to whom at run time is the table under "The interactive demo" in
the README, and the desktop's diagram under "The desktop".

## Linking: one namespace

L0 has no modules. Every file on the command line is one program, so **two
files defining the same name do not compile**. That's why the Makefile links
the optional libraries only into the programs that need them:

```make
BASE := common/abi.l0 common/text.l0                 # kernel, programs, tools
ULIB := $(BASE) common/initramfs.l0 common/queue.l0 $(CLI) user/lib/sys/l0s.l0 user/lib/sys/server.l0
LIBS_wm := $(RENDER) $(DISPLAY) $(UI_CORE) $(CLOCK) $(APPLIB)
```

- A new name in a library must not clash with **any** program that links it.
  Check with `make check`, which checks every program with its libraries.
  `common/text.l0` and `abi.l0` take their names in the kernel too, and
  `ULIB`'s in every program. Real clashes met so far: `fill_rows`
  (render.l0 vs a driver), `Command` and `parse_command` (render.l0 vs sh),
  `Reply` (display.l0 vs draw), `display_info` (display.l0 vs virtio-gpu),
  and a constructor shadowing a library's, as draw's own `Done` once hid
  `IoDone`'s. Look a name up first: `make -s doc Q=NAME`.
- **Before writing a helper, look for it**: `common/text.l0` has the list
  and string helpers, `cli.l0` failing and files, `server.l0` and `l0s.l0`
  asking and answering, `rect.l0` rectangles, and `render.l0` drawing on
  any canvas, an array's too. A second copy under another prefix is what
  this layout exists to stop.
- The toolkit prefixes every name `ui_` and every type `Ui`; do the same in
  any new library that many programs link. Programs never linked together
  may reuse names (`complain`, `serve`, `requested`).
- A name of yours shadows the L0 standard library's, so a library name is
  never something to work around.

## Adding things: checklists

**A program**
1. `user/bin/NAME/` for a command, `user/sbin/NAME/` for a driver or
   service, `user/apps/NAME/` for an app: `NAME.l0`, `NAME_test.l0`,
   `main.l0`. `main` only calls in: `(def main () int (NAME))`. A name with
   a hyphen gets an underscored function (`virtio-gpu` → `virtio_gpu`).
2. Makefile: nothing, unless it needs more than `ULIB`: then
   `LIBS_NAME := ...`. The Makefile finds the directory, every `.l0` in it
   and its tests, and its check, test, image and initramfs rules follow.
3. **An app** (a program with a window the desktop starts) is a bundle
   too: `user/apps/NAME/APP.app/manifest` (`name`, `exec NAME`, `icon
   icon.ppm`, `summary`; `app.l0`) and its icon: `icon.svg`, its GNOME
   app's icon copied in (its license and source under `icons/PROJECT/`),
   or `icon.draw`, `run draw`'s commands for its 48×48 icon on the
   launcher's ground (a `round 0 0 48 48 10 COLOR` and an `icon 8 8 NAME
   2 COLOR`; a new symbolic icon is an SVG under `icons/` and a name in
   `ui/icons.l0`). The Makefile finds the directory: the program goes in
   `/Applications/APP.app/NAME`, and the launcher shows it. APP is one
   word; add the bundle to `app_test.l0`'s `test_app_sources`.
4. To start it at boot: a driver, or anything a disk needs, a `start
   PATH [ARGS]` line in `demo/etc/inittab`, with `dev PATH` if it maps
   devices or binds interrupts; anything else a `start` line in
   `demo/etc/system`, which `boot` starts, from the system volume when
   `/` is one, and so never with devices. PATH is where step 2 put it
   (`/bin/sh`, `/sbin/wm`, `/Applications/Terminal.app/vt`). Adding a
   `start` line shifts later pids: update the README's pid table and `ps`
   sample, and check `tests/vt.sh`'s pid arithmetic.
5. Its row in the README's programs table, and for an app, the Apps table.

**A library** in `user/lib/GROUP/` (`sys`, `proto`, `format`, `gfx`, `ui`)
1. Its file header `; NAME.l0 -- summary`, a doc block on every def. Its
   stem must be unique across `user/lib` and `common`, for `make doc Q=`.
2. Makefile: a variable for it, added to each `LIBS_` that needs it (or to
   `ULIB`, if every program does); a `$(call l0_test,... user/lib/GROUP/NAME_test.l0)`
   line beside the others. `DOC_SRCS` finds it.
3. Its row in the README's libraries table.

**A request to a server** (the compositor; the display driver is alike)
1. Server: `user/sbin/wm/wm.l0` `requested` takes word arguments (`hello`,
   `windows`, `desktop`, `title`); `requested_window` takes numbers
   (`window`, `damage`, `top`, `close`). Add an `(if (eq op "X") ...)` branch
   returning a `(Served Wm)` through `okay` or `refused` (`server.l0`'s
   `served_ok`, `served_error`). The dispatcher is split to keep nesting
   shallow; split again rather than nest deeper. A server of numbers only
   reads them with `request_numbers` (virtio-gpu, virtio-blk).
2. Client: a wrapper in `user/lib/proto/wm.l0` (`compositor_ask`, `ask_nums`,
   `wm_error`), and its line in that file's header table. Every client asks
   through `l0s.l0`'s `port_ask` and reads errors with `reply_why`.
3. The README's compositor protocol table, and tests on both sides.
   For the display: `user/sbin/virtio-gpu/virtio-gpu.l0` `requested` /
   `requested_pointer`, `user/lib/proto/display.l0`'s header, the README's
   display table.

**A system call** (`shm_revoke`, 282, is a complete example)
1. `common/abi.l0`: `(def call_NAME () int N)` with its contract as a
   trailing comment; numbers from 256 are L0S's own.
2. `kernel/syscall.l0`: a constructor in `Call`, and its line in the right
   `decode_own_*` function; `kernel/syscall_test.l0`: a `decoded` check.
3. `kernel/kernel.l0`: `do_NAME`, and its arm in `dispatch`. Check every
   argument against the kernel's own records before it reaches a builtin
   that can fail: nothing a process passes may crash the kernel.
4. `user/lib/sys/l0s.l0`: the wrapper over `supervisor_call`. If the call can
   fail, it returns a type of its own with a constructor for each answer
   (`(data Kill (Killed) (KillNoProc) (KillDenied))`), read from the
   kernel's word by a pure `X_of` that `l0s_test.l0` tests code by code;
   constructor names are global, so prefix them with the call's.
5. `kernel/kernel_virt_test.l0`: tests through `asm.l0`'s `call_words`, run
   by `make test-virt`; include refusals.
6. The README's table of the kernel's own calls.

## Patterns to copy

- **A call's answer is matched**, every constructor of it: `port_send`
  gives a `Sending`, `name_register` a `Registration`, `spawn_entry` a
  `Spawn`, and so on (the README's table of calls lists them all). Handle
  each arm; for a failure's message use its `X_why` (`sending_why`,
  `registration_why`, `spawn_why`, `irq_binding_why`, `dma_alloc_why`,
  `shm_share_why`). Only a send whose answer truly does not matter is
  dropped, with `server.l0`'s `port_tell`, which says why.
- **A server** (`user/sbin/echo/echo.l0`): `port_new`,
  `name_register_or_why port "name"` (empty, or why not), then a loop on
  `port_receive`. A `(Message from b)` holds the bytes the kernel gave,
  the sender's pid and then the payload (see "Bytes, not lists"). A
  request is `(request REPLY BODY)`: a text server reads the body once
  with `(msg_text_from b 4)`, and answers with `(msg_answer b reply)`,
  which sends nothing if it names no reply port (`request_body` and
  `request_answer` do the same for a payload already a list). Replies are `ok`, `error: WHY`
  (`error_reply`), or the request's own answer; a server's state and its
  answer are a `(Served S)`. Clients find a server with `name_wait NAME ns`
  and ask with `port_ask`.
- **Listening to a driver** (`user/sbin/virtio-input/virtio-input.l0`,
  server side; `input_listen` in `l0s.l0`, whose `Listening` gives the
  driver's pid, client side): a `listen` request adds the reply port to the
  driver's list with `listener_add`, and each event goes to every listener
  with `listeners_tell`, which drops one whose port is gone and keeps one
  whose queue is full, in order (rtc does the same).
- **A driver moving bulk data** (`user/sbin/virtio-blk/virtio-blk.l0` with
  `user/lib/proto/disk.l0`, like `virtio-gpu` with `display.l0`): the
  client makes a buffer once with `shm_region`, `shm_share_to`s it with the
  driver's pid (learned from the `from` of a first reply), and names it in
  its requests by where the driver sees it. The driver gets the device's
  addresses of those pages with `page_addresses`, whose `None` means they
  are not shared with it, and builds descriptors over them, so nothing is
  copied (`virtq_page_runs`, `virtq_push_chain`). A virtio driver finds its
  device with `virtio_probe`, takes its queue's memory with `virtq_mem`,
  offers a request with `virtq_offer`, and waits with `virtq_wait`
  (`user/lib/sys/virtio.l0`). A driver that moves no DMA, as `sdhci`
  does, opens the client's shared pages as a region for the request
  (`dma_open` of its VA) and closes it after.
- **A disk driver** registers each disk with `disk_register`, the first
  `diskN` free, any number on one port; reads each request's disk with
  `disk_asked`, the name its first word; and then tells `fs` with
  `fs_attach_disk`. Clients find disks with `disk_names` and
  `disk_open_named`; `disk_open` waits for `disk0`.
- **Waiting for a message or a time.** A receive cannot time out. Either a
  device interrupt arrives as a message (`irq_bind`), or the loop polls with
  `port_try_receive` and `sleep_ns` (`rtc clock`, `procmon`).
- **Failing.** Each program has
  `(def complain ((why (list int))) int (complain_as "NAME" why))`
  (`cli.l0`). A driver whose device is absent says so with `note_as` and
  exits 0: no device is no failure.
- **A state record** is one `data` with many fields, matched and rebuilt in
  every function (`Wm`, `Drv`, `Win`). Adding a field means updating every
  pattern: the Edit tool's replace-all on the exact pattern text does most
  of them; then `l0 check` names the rest, with their different binding
  names.

## Bytes, not lists

A `(list int)` costs a cons cell per byte, about 16 times what `bytes`
does, and converting either way copies every byte. Data that arrives or
leaves as bytes stays `bytes`: messages, files, sectors, frames, images.
Make a list only to parse text or to build output, and convert once.

- **Read in place**: `bytes_get`, `le_u32`, `le_u16_at`, `be16_at` and
  `be32_at` (inet), `bytes_is_at b i "lit"` for a magic number or a tag,
  and `crc32 b i j`, `crc32_zeroed`, `sum16_bytes` over a range. Never
  `(eq (bytes_range ...) "lit")`, and never `bytes_from_list` a list
  just to read a field from it; a list's own field reads with `nth`.
- **Pass (bytes, start, end) to read; slice only to keep.**
  `(bytes_slice b i j)` copies, it is not a view, so a reader takes the
  whole value and its range: `udp_of src dst b i j`,
  `tcp_of`, `icmp_of`, `decode_args_in`, `ipv4_of b off` and its `Ipv4`,
  which keeps its payload as the frame's bytes and two offsets.
- **Messages**: a `Message`, and an `Asked`, hold the bytes received,
  the pid's 4 bytes first. `msg_len`, `msg_byte`, `msg_u32`, `msg_is`
  and `msg_starts` read the payload in place, and `msg_reply` its reply
  port; `msg_text` and `msg_text_from b i` give it as a list, for text.
  Binary notices (keys, the pointer, `exit_of`, `is_irq_notice`,
  `usb_report_of`, `fs_reply_of`'s word) are read in place. A frame's
  place in a notice is `frame_notice_at`, a send's `nic_frame_at`, a
  write's `tty_is_write`/`tty_written_at`. Tests build one with
  `message_new from payload`.
- **Send a range**: `port_send_bytes port b i j`, `port_forward port b`
  (a message's payload as it came, as `wm` passes keys on and `echo`
  answers); to a device, `put_bytes_range` and `disk_put_range`, the
  frame or the file's bytes copied from the message in place.
- **Join with `bytes_concat`.** A header and a body that must become
  one value: the header made bytes once, then
  `(bytes_concat (cons hdr (cons body (nil bytes))))`, as
  `spawn_image_bytes`, `ask_fs_data`, `fs_reply_data` and inet's udp
  notices do; a piece kept from a value is `bytes_slice` (fs's held
  cluster, a datagram's data). `msg_answer_bytes` and
  `listeners_tell_bytes` send bytes made once. Only a device's memory
  (read a byte at a time) and TCP's reassembly still make lists.

## What a driver says

Everything a program or the kernel reports goes through the kernel's log:
`log_write level text` (call 294) keeps it, stamped with the time and the
pid, in a ring of 64 KiB, and writes the line to the kernel's standard
error, the serial line, at once, unless its level is debug. `dmesg` at a
shell (or the MCP's `dmesg`) reads it back, which is how a desktop with
no serial console sees what booted. In `user/lib/sys/server.l0`:

| Call | Level | Gives | For |
|---|---|---|---|
| `info_as "NAME" TEXT` | info | 0 | what it found or did |
| `warn_as "NAME" TEXT` | warning | 0 | something wrong it goes on through |
| `debug_as "NAME" TEXT` | debug | 0 | per-event chatter; kept, never printed |
| `fail_as "NAME" TEXT` | error | 1 | what ends it: each program's `complain` |

The conventions, so every driver reads alike:

- **One info line for each thing it found, as it starts to serve**, as
  `NAME: WHAT: FACTS`: what the device is, where it is (`virtio_where t`
  for a virtio transport, `pci_bdf_text` and the BAR for PCI, a base
  address and irq for a fixed device), its size or mode, and the name it
  serves, as `sdhci: disk1: an SD card of 268.4 MB, 524288 sectors` and
  `virtio-net: a card 52:54:00:12:34:56, virtio-mmio 30 at 0x0a003c00,
  irq 78, serving nic`. Sizes go through `format_size`, addresses are
  `0x` and `hex_digits`, and a MAC, IP or time goes through the formatter
  its protocol library has (`mac_text`, `ip_text`, `clock_text`).
- **Build the line in a pure function** (`card_line`, `disk_line`,
  `screen_line`) and test its text, as the programs' `_test.l0` do; the
  call that says it is one `info_as`.
- **No device is no failure**: `info_as` "no X on the board" and exit 0.
  A failure is `fail_as`, and the program's exit status is its 1.
- **Say it once the thing is true**, after the name is registered or the
  device is ready, not when it is about to be.
- **Never on standard output**: the e2e cases compare it exactly, and a
  program's stdout is its answer to whoever ran it. Commands in `bin/`
  and apps keep `complain_as` on stderr for their own user; only the
  kernel's servers and drivers use the log.
- **Don't flush**: `log_as` delivers the line itself.
- A library or host tool that must not link `l0s.l0` cannot call these;
  they are in `server.l0`, with the other server helpers.

The kernel logs as `l0s: ...` with pid 0: a board banner (CPU, boot
arguments, pages free, how a process's memory is laid out, limits, the
initramfs), each process it starts (debug), each volume mounted or
unmounted, `/` becoming a volume, kills, deadlock. L0 has no builtin for
the board's RAM, CPUs, timer or interrupt controller, so it says nothing
of them rather than guess.

## Documenting

The first lines of every file: `; FILE.l0 -- summary`, a few lines, a blank
line. Above every def or data, a block of `;` lines with no blank line
between: what it is or does, in plain words. One comment may cover a group
of one-liners directly beneath it. Section dividers are
`; ---------------------------------------------------------------- name`.
`make doc` reads exactly this, so an undocumented def is invisible there.
`make check` enforces it: a form with no block fails it, unless
`tools/l0sdoc/undocumented.txt` lists it from before the check began. Never
add to that list. Documenting a listed form fails the check too, until
`make doc-prune` takes its line off, so the list only shrinks.

## Pitfalls that have cost time

- **Writes are held back.** A process's stdout and stderr reach the terminal
  only when flushed or when it exits, and `wm`, the drivers and servers
  never exit. `(file_flush (IoFile 1))` after a prompt; for a debug line,
  `(let f (file_flush (IoFile 2)) ...)` after the `write_err`. What a
  process the inittab starts writes reaches the kernel's own streams, but
  only its standard error is the serial line's text (QEMU's semihosting
  stderr: in a screen test the `build/NAME.out` file, where the script
  merges both streams; in an e2e case `NAME.err`, never the diffed
  `expected`). To report, use `info_as` and its kind (see "What a driver
  says"), which flushes and keeps the line for `dmesg`.
- **The proc runtime keeps at most 64 regions open at once.** Every
  `ui_buffer`, `shm_region` and `dma_open` is one; close it when done
  (`close_device`, or `ui_buffer_free` / `shm_region_free`, which also
  unmap the pages), or the 65th open fails. `wm` opens two per window
  (title bar and frame) and closes them in `give_up`.
- **Ports** hold 32 messages of at most 4096 bytes. A message must carry
  numbers, never pixels: pixels go through shared pages (`shm_alloc`,
  `shm_share`).
- **A list round trip passes every test and costs every byte.** A
  `bytes_to_list` then `bytes_from_list`, or a whole payload turned
  into a list to read four bytes of it, gives the right answer. It just
  copies each message, frame or file chunk byte by byte, once for every
  hop it takes. See "Bytes, not lists".
- **Docker must be running**: board images (`--target virt` and `proc`) are
  linked in l0's container. Homebrew's `ld.lld` is blocked on this machine.
- **The kernel's heap is 192 MB and its stack 16 MB** (`KERNEL_HEAP_MB`,
  `KERNEL_STACK_MB`, passed as `--heap-mb` and `--stack-mb` to both
  `l0 build` and `l0 test --target virt`): every other page below the user
  range is frames. Build the kernel by hand without them and it gets L0's
  1,024 and 256, and a pool of 765 MB. The heap holds a record of every
  page given (about 128 MB for the whole pool; at 96 MB
  `test_frames_run_out` exhausts it) and the whole initramfs, so
  `mkinitramfs` refuses one past `INITRAMFS_MAX`, 48 MB. Shrinking the heap
  grows the pool, and so the records it must hold: never go below what a
  full pool needs. Anything the kernel keeps per process, port, message or
  mapping must stay bounded, or a process can exhaust that heap; ports and
  a region shared into many processes are not yet.
  `kernel_virt_test.l0`'s `in_frame_pool` and `test_mem_info_total` pin
  the windows these sizes give, so they change with them.
- **QEMU's Unix sockets** must have paths under 104 bytes: put them in
  `build/` and use relative paths, as the tests do. A scratch directory's
  path is too long.
- **`main` cannot be tested**: keep it to one call.
- **Edit source with the editor tools**, not sed, awk or scripts: a shell
  rewrite with a stale line number once overwrote the top of a file.
- **The README's tables** (programs, libraries, protocols, calls, pids,
  tests) are relied on by people and agents; update them in the same change.

## Done

`make check` and `make test` pass. For anything that boots, draws or takes
input, `make e2e` too (see `l0s-testing`). Never say L0 code works without
having run them.
