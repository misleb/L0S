# L0S -- build, test, and boot the microkernel and its programs.
#
#   make check       l0 check of the kernel, every program and the host
#                    tools, and that every form is documented
#   make test        host tests of everything: l0 test on this machine;
#                    both run only what changed since it passed, JOBS
#                    at once, every CPU unless JOBS=N
#   make test-virt   the kernel's tests on QEMU's virt board
#   make e2e         every case of tests/e2e booted under the kernel
#   make all         all three, after type checking
#   make initramfs   build/initramfs.cpio: every program, in /bin, /sbin
#                    and /Applications as make root stages them in
#                    build/root, demo/etc, and the wallpaper as
#                    /etc/wallpaper.qoi
#   make demo        boot it to the shell, on this terminal: type help;
#                    the desktop shows in QEMU's window, and build/disk.img
#                    is the disk, made once, so what is written to it stays;
#                    build/sd.img, blank until Disks formats it, the SD card;
#                    the keyboard, mouse and tablet are USB's, on a
#                    qemu-xhci, and the host's pointer moves the tablet,
#                    which says where it is, so QEMU's window needs no
#                    grab of it
#   make demo QEMU_USB=046d:0acf        the same, with that device of
#                    this host passed through too (tools/qemu-boot.sh)
#   make demo WALLPAPER_SVG=picture.svg the same, another wallpaper
#   make demo NET=user,tftp=DIR         the same, the network's gateway
#                    serving DIR over TFTP, for tftp 10.0.2.2 FILE
#   make demo ROOT_UUID=UUID            the same, booted with root=UUID:
#                    the volume of that partition, if fs mounts it and it
#                    holds L0S, is / (sbin/boot)
#   make sysdisk     build/system.img, a 64 MB disk: System, a copy of
#                    the initramfs, and data; System's UUID in
#                    build/system.uuid
#   make demo-system the demo booted from build/system.img's System,
#                    made anew
#   make boot ETC=tests/e2e/hello/etc   boot every program with that etc
#   make pi5-card    build/pi5-card: the kernel built for the Raspberry
#                    Pi 5, every program with pi5/etc, its device trees,
#                    and what l0 card writes for its SD card's boot
#                    partition. PI5_RAM_GB=N for a board of more than
#                    2 GB, here and for pi5-netboot
#   make pi5-release-card  build/pi5-release-card: the same, but its
#                    initramfs only the first stage, what mounts the
#                    system volume (make pi5-stage1), as the release has
#   make pi5-netboot [PI5_BOOT=DIR] [PI5_TFTP_PREFIX=SERIAL]
#                    build/pi5-tftp: the same, with the Pi 5's device
#                    trees, fetched once and checked, or from DIR, as a
#                    TFTP root it network boots from
#   make pi5-eeprom [EEPROM_ORDER=0xf21]  pi5-netboot with the pinned
#                    bootloader's update in it too, which the board
#                    flashes as it boots (tools/mkeeprom); serve it
#                    with tools/pi5-boot --no-build
#   make pi5-shell   pi5-netboot without hvs, then picocom on the Pi's
#                    serial line to type to its shell (tools/pi5-boot)
#   make -s doc [Q=...]  the libraries' documentation, as l0 doc gives
#                    L0's: every name, or Q a name, a file's stem or the
#                    end of its path, or text, in the programs' too
#   make preview APP=NAME  an app's scenes, its preview.l0, painted on
#                    this machine as the board paints them, into
#                    build/preview/NAME/*.png, in seconds, no board
#   make doc-prune   take the forms documented since off DOC_GAPS, which
#                    make check holds every undocumented form to
#   make mcp         build/mcp/venv, the Python with the MCP SDK that
#                    .mcp.json runs tools/l0s-mcp in: the MCP server
#                    that boots and drives L0S for agents
#   make proxy       build/proxy/venv, the Python with aiohttp that the
#                    API proxy runs in (tools/api-proxy), and
#                    build/proxy/token, the boards' token, made once,
#                    and the strikes and icons its app builder's
#                    sessions preview apps with
#   make proxy-run [PROXY_LISTEN=ADDR:PORT]  the proxy to Anthropic's API
#                    on ADDR:PORT, 127.0.0.1:8765 unless given, with that
#                    token and ANTHROPIC_API_KEY; usage in
#                    build/proxy/usage.jsonl, and releases from
#                    build/release
#   make release     build/release/pi5 and build/release/virt: the
#                    system, with RELEASE_APPS (calc) beside the
#                    initramfs's apps, the Pi 5's boot files with a
#                    first-stage initramfs, the agent's seed,
#                    Whistle's model and the Pi 5's pieeprom.bin, the
#                    last two fetched once into build/fetch, which the
#                    proxy serves to install --net and the Installer
#                    (tools/mkrelease); WHISTLE_MODEL=FILE and
#                    PIEEPROM=FILE use files of your own instead
#   make agent-etc API=HOST:PORT [MODEL=NAME]  build/agent-etc: the
#                    agent's config, naming the proxy, and the token,
#                    which the demo's and the Pi 5's initramfs then take
#                    as /etc/agent
#   make graph       graphify-out/ rebuilt from the code as it is: the L0
#                    sources (tools/graphify-l0), scripts and Python, the
#                    docs' nodes kept; once /graphify has built it
#   make graph-hook  .git/hooks/post-commit runs make graph after each
#                    commit, in the background (graphify-out/rebuild.log)
#
# Images for the board are linked in Docker, as l0 does when L0_VIRT_LD
# is unset.

L0     ?= l0
BUILD  := build

# The installed toolchain's compiler, runtimes and layouts, so that images
# are rebuilt when l0 is updated, and take its runtime's changes. l0 spec
# --path names every file of the specification, the language's first,
# which lies in the library's own directory.
L0LIB     := $(dir $(firstword $(shell $(L0) spec --path)))
L0_VIRTRT := $(L0LIB)l0c $(wildcard $(L0LIB)virt-aarch64/*.bc) $(L0LIB)virt-aarch64/layout.ld
L0_PROCRT := $(L0LIB)l0c $(wildcard $(L0LIB)proc-aarch64/*.bc) $(L0LIB)proc-aarch64/layout.ld
# What every check and host test is built with, the driver among them, so
# that a new l0 checks and tests everything again.
L0_HOSTRT := $(shell command -v $(L0)) $(L0LIB)l0c $(L0LIB)prelude.l0 $(L0LIB)io.l0 $(L0LIB)test.l0 $(L0LIB)l0rt.o $(L0LIB)l0host.o

# How many checks or tests make check and make test run at once: one for
# each CPU, unless JOBS says otherwise.
JOBS ?= $(shell sysctl -n hw.ncpu 2> /dev/null || nproc 2> /dev/null || echo 1)

# The kernel's own heap and stack, in MB, which l0 build and l0 test give
# the board's layout (spec 10.3's --heap-mb and --stack-mb); the rest of
# the RAM below the user range is the frame pool processes are made of,
# about 1,840 MB at -m 2G, against 765 MB with L0's defaults of 1,024 and
# 256. The kernel's heap holds a record of every page it has given, about
# 128 MB once the whole pool is given, and its copy of the initramfs, and
# it refuses pages once 64 MB is left (process.l0's heap_reserve; make
# test-virt-heap shows a 96 MB heap refusing rather than running out); the rest,
# 20.5 MB at the demo's peak with 65 processes, 12.3 MB of it that copy,
# is small. Its stack stayed under 8 KB. So mkinitramfs refuses an
# archive past INITRAMFS_MAX, the heap less 144 MB: 128 for the pool's
# records and 16 for everything else.
KERNEL_HEAP_MB  ?= 192
KERNEL_STACK_MB ?= 16
KERNEL_LAYOUT   := --heap-mb $(KERNEL_HEAP_MB) --stack-mb $(KERNEL_STACK_MB)
export INITRAMFS_MAX := $(shell echo $$(( ($(KERNEL_HEAP_MB) - 144) * 1048576 )))

# Where QEMU shows the screen: cocoa is macOS's window; sdl elsewhere
# (gtk is scaled on Wayland), none for no window.
QEMU_DISPLAY ?= $(if $(filter Darwin,$(shell uname -s)),cocoa,sdl)
# SCREEN, WxH, is the virtio-gpu's mode, QEMU's 1280x800 if not given. A
# screen of 2560x1440 or more is drawn at scale 2: make demo
# SCREEN=3840x2160, with QEMU_DISPLAY=cocoa,full-screen=on,zoom-to-fit=on
# to fill a 4K monitor.
SCREEN       ?= 2560x1440
# GPU, gl or 2d, is the virtio-gpu the demo gives the board: the GL device,
# with GL in QEMU's window, whose virgl the driver composes with on the
# host's GPU, if tools/qemu-gl finds this machine can, else the plain
# one. make demo GPU=2d forces the plain one; the tests always use it.
GPU          ?= $(shell tools/qemu-gl)
comma        := ,
GPU_OPTS     := $(if $(SCREEN),xres=$(word 1,$(subst x, ,$(SCREEN)))$(comma)yres=$(word 2,$(subst x, ,$(SCREEN))))
# CPUS is how many CPUs make boot, demo and e2e give the virt board: with
# more than one, the kernel runs on CPU 0, with the processes that pass
# messages, and hands those that compute to the rest (spec 6.18,
# spec/kernel.md). It is 4: on QEMU four are as fast as one at writing a
# disk, nearly at passing messages, and far faster beside a process that
# computes (roadmap 0002's log; tools/cputimes times them); make demo
# CPUS=1 for one. QEMU_CPUS, which tools/qemu-boot.sh and the e2e and
# screen tests read, follows it; an e2e case whose output depends on
# which program runs first keeps to one with a cpus file. make test-virt
# boots each test on one CPU and then on VIRT_CPUS.
CPUS         ?= 4
VIRT_CPUS    ?= 4
export QEMU_CPUS ?= $(CPUS)
# make boot gives an etc both inputs: virtio's keyboard and tablet, and a
# qemu-xhci with a USB keyboard and mouse, as the demo's inittab drives,
# and its PL031 counting UTC, as tools/qemu-boot.sh's does.
DEVICES      := -smp $(CPUS) -rtc base=utc -device virtio-gpu-device$(if $(GPU_OPTS),$(comma)$(GPU_OPTS)) -device virtio-keyboard-device -device virtio-tablet-device \
                -device qemu-xhci -device usb-kbd -device usb-mouse -device virtio-rng-device
DISK         := $(BUILD)/disk.img
SYSDISK      := $(BUILD)/system.img
SYSUUID      := $(BUILD)/system.uuid
DISK_DEVICE  := -drive file=$(DISK),if=none,format=raw,id=disk0 -device virtio-blk-device,drive=disk0
# The SD card: a blank image of 256 MB, a size QEMU's sd-card takes (a
# power of 2), in a sdhci-pci on PCIe, for pcie and sdhci; made once and
# kept, as the disk is, so a volume made on it stays.
SD           := $(BUILD)/sd.img
SD_DEVICE    := -device sdhci-pci -drive file=$(SD),if=none,format=raw,id=sd0 -device sd-card,drive=sd0
# NET is the network the board's virtio-net is on, as QEMU's -netdev names
# one without its id: user, QEMU's own, 10.0.2.0/24 behind a gateway at
# 10.0.2.2, which inet's defaults are; make demo NET=user,tftp=DIR to
# have the gateway serve DIR over TFTP too.
NET          ?= user
NET_DEVICE   := -netdev $(NET),id=net0 -device virtio-net-device,netdev=net0,mac=52:54:00:12:34:56

# common/: BASE, the ABI and text.l0's lists and strings, is pure and
# linked into everything, host tools too; COMMON adds the initramfs, and
# is in the kernel and every program.
BASE   := common/abi.l0 common/text.l0
COMMON := $(BASE) common/initramfs.l0
KERNEL := $(COMMON) common/queue.l0 common/klog.l0 kernel/log.l0 kernel/memory.l0 kernel/elf.l0 kernel/mounts.l0 kernel/ipc.l0 kernel/inittab.l0 \
          kernel/sched.l0 kernel/usage.l0 kernel/cpus.l0 kernel/pids.l0 kernel/syscall.l0 kernel/process.l0 kernel/kernel.l0 common/rp1.l0
CLI    := user/lib/sys/cli.l0
ULIB   := $(COMMON) common/queue.l0 common/klog.l0 $(CLI) user/lib/sys/l0s.l0 user/lib/sys/server.l0

# A terminal's line editing, for the terminals; the virtio-mmio
# transports and queues, for the virtio drivers; and the US keyboard's
# layout, for the keyboards' drivers; and the Raspberry Pi 5's VideoCore
# mailbox, for the drivers that ask its firmware; and its RP1's window,
# made to answer, for RP1's drivers.
TTY    := user/lib/sys/tty.l0
VIRTIO := user/lib/sys/virtio.l0
KEYMAP := user/lib/sys/keymap.l0
MAILBOX := user/lib/sys/mailbox.l0
RP1     := common/rp1.l0

# The process table as ps and procmon show it.
PROCS  := user/lib/sys/procs.l0

# The files of /, wherever it is, and its programs started by path: over
# the fs protocol, and so its UUIDs.
PATHS  := user/lib/format/uuid.l0 user/lib/proto/fs.l0 user/lib/sys/paths.l0

# Libraries only some programs link, as LIBS_NAME, grouped by what they
# are under user/lib: sys, the kernel's calls and what every program
# needs; proto, the protocols of servers, as their clients speak them;
# format, data as bytes, pure, which host tools link too; gfx, drawing,
# which would otherwise clash with the shell's own commands; and ui, the
# toolkit. The protocols name rectangles with rect.l0's Rect, so DISPLAY
# and WMLIB need RECT, which RENDER holds.
PPM     := user/lib/format/ppm.l0
QOI     := user/lib/format/qoi.l0
RECT    := user/lib/gfx/rect.l0
RENDER  := $(PPM) $(QOI) $(RECT) user/lib/gfx/render.l0
# Outlines to coverage, and SVG read into them: XML, path data, and the
# document, which need RENDER's points; linked by the host tools that
# draw icons at build time.
RASTER  := user/lib/gfx/raster.l0
XML     := user/lib/format/xml.l0
SVG     := $(XML) $(RASTER) user/lib/gfx/svg_path.l0 user/lib/gfx/svg.l0
# TrueType outlines, read as the rasterizer's segments.
TTF     := $(RASTER) user/lib/format/ttf.l0
# A face at a height, its glyphs rasterized, as bytes read in place:
# the layout, which the toolkit reads; and its making, from a TTF.
STRIKE  := user/lib/format/strike.l0
GLYPHS  := $(TTF) $(STRIKE) user/lib/gfx/glyphs.l0
DISPLAY := user/lib/proto/display.l0
DISPLAY_SERVER := user/lib/proto/display_server.l0
WMLIB   := user/lib/proto/wm.l0
CLOCK   := user/lib/proto/clock.l0
DISKLIB := user/lib/proto/disk.l0
# Sound: the audio protocol, its server's side, WAV files, and samples
# between 48 and 16 kHz.
AUDIOLIB := user/lib/proto/audio.l0
WAV     := user/lib/format/wav.l0
PCM     := user/lib/format/pcm.l0
AUDIO_SERVER := $(AUDIOLIB) $(WAV) user/lib/proto/audio_server.l0
FSLIB   := user/lib/proto/fs.l0
APPLIB  := user/lib/proto/app.l0
# A running app launched again: its name, app.EXEC, the open request
# and its answer; pure, for the toolkit, wm and open.
APPOPEN := user/lib/proto/appopen.l0
# The font service's protocol: its faces, and strikes shared with the
# asker.
FONTLIB := user/lib/proto/font.l0
L0FS   := user/lib/format/l0fs.l0
FAT     := $(L0FS) user/lib/format/fat.l0

# The network: nic, the driver's frames and Ethernet's addresses; and
# inet, the stack's datagrams and IPv4's addresses, and its resolver,
# which needs nic, DNS's messages, and randomness for its queries' ids.
# Randomness from the entropy device's driver, for UUIDs, TCP and DNS.
RANDOM  := user/lib/proto/random.l0
NICLIB  := user/lib/proto/nic.l0
DNSLIB  := user/lib/format/dns.l0
INETLIB := $(NICLIB) $(DNSLIB) $(RANDOM) user/lib/proto/inet.l0
# SNTP's messages, the time asked of a server; pure.
NTPLIB  := user/lib/format/ntp.l0
# JSON's values, read and written as bytes; pure, for the board and the
# host tools alike.
JSON    := user/lib/format/json.l0
# Server-sent events, read from a body that comes in pieces; pure.
SSE     := user/lib/format/sse.l0
# HTTP/1.1's messages, a request written and a response read as it
# comes; pure.
HTTPMSG := user/lib/format/http.l0
# The HTTP/1.1 client over inet's TCP: INETLIB, the messages, and it.
HTTP    := $(INETLIB) $(HTTPMSG) user/lib/proto/httpc.l0
# A model's API, Anthropic's Messages API through the host's proxy: its
# configuration, a request's bytes and its streamed events.
MODELLIB := $(HTTP) $(JSON) $(SSE) user/lib/proto/model.l0
# The agent protocol, agentd's, and its client.
AGENTLIB := user/lib/proto/agent.l0
# The agent's home: its parts, the system prompt's part from them, what
# is fixed, and the history of its writes; over the files and the clock.
AGENTHOME := $(PATHS) $(CLOCK) user/lib/sys/agenthome.l0

# USB: its descriptors and requests, and the usb protocol, which the
# host controller's driver serves to the class drivers, over them; and
# the pci protocol, which the PCIe bus's server answers drivers with.
USBDESC := user/lib/format/usbdesc.l0
USBLIB  := $(USBDESC) user/lib/proto/usb.l0
UAC     := user/lib/format/uac.l0
CACT    := user/lib/format/cact.l0
MEL     := user/lib/speech/mel.l0
NN      := user/lib/speech/nn.l0
WHISTLE := $(CACT) $(MEL) $(NN) user/lib/speech/whistle.l0
ENCODER := $(WHISTLE) user/lib/speech/encoder.l0
DECODER := $(ENCODER) user/lib/speech/decoder.l0
TRANSCRIBE := $(WAV) $(DECODER) user/lib/speech/transcribe.l0
# A Piper voice (roadmap 0062): an ONNX model's weights read in place,
# and the voice's JSON config.
ONNX    := user/lib/format/onnx.l0
VOICE   := $(JSON) user/lib/speech/voice.l0
# English text to the voice's phonemes and IDs, through CMUdict.
PHONEMES := $(VOICE) user/lib/speech/phonemes.l0
# VITS's arithmetic over channel-last tensors, and the voice's model:
# phoneme IDs to samples.
VITS    := $(MEL) user/lib/speech/vits.l0
PIPER   := $(ONNX) $(VOICE) $(VITS) user/lib/speech/piper.l0
MICLIB  := user/lib/proto/mic.l0
# The speech protocol, the speech service's, and its client.
SPEECHLIB := user/lib/proto/speech.l0
PCILIB  := user/lib/proto/pci.l0

# The partition tables, GPT, and the UUIDs and CRC-32 it needs, and
# MBR's, read only.
UUIDLIB := user/lib/format/uuid.l0
CRC32   := user/lib/format/crc32.l0
GPTLIB  := user/lib/format/gpt.l0
MBRLIB  := user/lib/format/mbr.l0
PARTS   := $(UUIDLIB) $(CRC32) $(GPTLIB) $(MBRLIB)

# SHA-256, which the Pi 5's bootloader checks its updates by.
SHA256  := user/lib/format/sha256.l0

# Installing L0S from a release the host's proxy serves (roadmap 0027):
# the manifest, the plan, each file fetched and checked, over the
# proxy's HTTP, SHA-256, the files and the agent's home.
RELEASE := $(MODELLIB) $(SHA256) $(AGENTHOME) user/lib/sys/release.l0

# The Pi 5's bootloader: its image, pieeprom.bin (pure, over SHA256), and
# its firmware's command line, an update's time and files, and the boot
# order (over the mailbox and CLOCK), for eeprom and the installer.
PIEEPROMLIB := user/lib/format/pieeprom.l0
BOOTLOADER  := $(MAILBOX) $(PIEEPROMLIB) user/lib/sys/bootloader.l0

# The toolkit, user/lib/ui: its look, widgets, and the desktop's drawing
# commands, which need only render.l0, and the font service's protocol
# and strikes, which its text is drawn from; and its client windows,
# which need the compositor's protocol too, and an app's many windows on
# one port, uiapp.l0, which every window is opened through, and the loop
# they take their messages and time their steps by, uiloop.l0.
UI_CORE   := $(STRIKE) $(FONTLIB) user/lib/ui/theme.l0 user/lib/ui/icons.l0 user/lib/ui/face.l0 user/lib/ui/metrics.l0 user/lib/ui/paint.l0 user/lib/ui/widget.l0 \
             user/lib/ui/grid.l0 user/lib/ui/panes.l0 user/lib/ui/entry.l0 user/lib/ui/draw_cmd.l0 \
             user/lib/ui/nav.l0 user/lib/ui/icon_view.l0 user/lib/ui/menu.l0 user/lib/ui/lines.l0 user/lib/ui/page.l0 \
             user/lib/ui/controls.l0 user/lib/ui/list.l0
UI_WINDOW := user/lib/ui/window.l0 user/lib/ui/uiapp.l0 user/lib/ui/uiloop.l0 user/lib/ui/run.l0 $(APPOPEN)
UI_TESTS  := theme icons face paint widget grid panes entry draw_cmd nav icon_view menu lines page controls list
# What a test asks of a view laid out, linked into the toolkit's tests
# and those of every program that links the toolkit, never a program.
UI_TESTING := user/lib/ui/testing.l0
# PNG images, written, and an app's views painted on the host as PNGs
# with the build's strikes and icons (roadmap 0065): linked by an app's
# preview.l0, make preview and l0s-app-preview, never by an app.
PNG        := user/lib/format/png.l0
UI_PREVIEW := $(CRC32) $(PNG) user/lib/ui/preview.l0
# PNG images, read: zlib's inflate, and PNGs of 8-bit gray, RGB, palette
# and alpha decoded into the toolkit's ARGB words and fitted to a box.
INFLATE    := user/lib/format/inflate.l0
PNGREAD    := $(INFLATE) user/lib/format/png_read.l0
BASE64     := user/lib/format/base64.l0

LIBS_virtio-gpu := $(VIRTIO) $(RENDER) $(DISPLAY_SERVER)
LIBS_hvs        := $(VIRTIO) $(RENDER) $(DISPLAY_SERVER) $(MAILBOX)
LIBS_virtio-input := $(VIRTIO) $(KEYMAP)
LIBS_pcie       := $(PCILIB)
LIBS_xhci       := $(USBLIB) $(PCILIB) $(RP1)
LIBS_usb-hid    := $(USBLIB) $(KEYMAP)
LIBS_usb-audio  := $(USBLIB) $(UAC) $(MICLIB) $(PCM)
LIBS_lsusb      := $(USBLIB)
LIBS_sdhci      := $(PCILIB) $(DISKLIB) $(UUIDLIB) $(FSLIB)
LIBS_virtio-blk := $(VIRTIO) $(DISKLIB) $(UUIDLIB) $(FSLIB)
LIBS_virtio-net := $(VIRTIO) $(NICLIB)
LIBS_gem        := $(NICLIB) $(MAILBOX) $(RP1)
LIBS_virtio-rng := $(VIRTIO) $(RANDOM)
LIBS_inet       := $(INETLIB) $(CLOCK)
LIBS_net        := $(INETLIB)
LIBS_tftp       := $(INETLIB)
LIBS_http       := $(HTTP) $(JSON) $(SSE)
LIBS_ntp        := $(INETLIB) $(CLOCK) $(NTPLIB)
LIBS_ask        := $(MODELLIB)
LIBS_agent      := $(AGENTLIB) $(MODELLIB) $(AGENTHOME)
LIBS_agentd     := $(MODELLIB) $(AGENTLIB) $(AGENTHOME) $(RENDER) $(WMLIB) $(SVG) $(BASE64)
LIBS_uart       := $(TTY)
LIBS_rtc        := $(CLOCK) $(MAILBOX)
LIBS_eeprom     := $(CLOCK) $(SHA256) $(BOOTLOADER)
LIBS_hdmi-audio := $(AUDIO_SERVER) $(MAILBOX)
LIBS_play       := $(AUDIOLIB) $(WAV) $(PCM)
LIBS_rec        := $(MICLIB) $(WAV)
LIBS_listen     := $(TRANSCRIBE)
LIBS_speak      := $(AUDIOLIB) $(WAV) $(PIPER) user/lib/speech/phonemes.l0
LIBS_speech     := $(TRANSCRIBE) $(MICLIB) $(AGENTLIB) $(SPEECHLIB) $(RECT) $(WMLIB)
LIBS_wm         := $(RENDER) $(DISPLAY) $(UI_CORE) $(CLOCK) $(PATHS) $(APPLIB) $(APPOPEN)
LIBS_vt         := $(TTY) $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) $(PATHS)
LIBS_init       := $(PATHS)
LIBS_boot       := $(PATHS)
LIBS_install    := $(RELEASE) $(BOOTLOADER)
LIBS_draw       := $(RENDER) $(WMLIB) $(UI_CORE)
LIBS_windows    := $(RECT) $(WMLIB)
LIBS_open       := $(RECT) $(WMLIB)
LIBS_widgets    := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW)
LIBS_todo       := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW)
LIBS_calc       := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW)
LIBS_chat       := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) $(AGENTLIB) $(SPEECHLIB) $(PATHS) $(PNGREAD)
LIBS_about      := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW)
LIBS_installer  := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) $(RELEASE) $(BOOTLOADER)
LIBS_fontview   := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW)
LIBS_procmon    := $(PROCS) $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW)
LIBS_disk       := $(DISKLIB)
LIBS_random     := $(RANDOM)
LIBS_font       := $(RENDER) $(GLYPHS) $(FONTLIB)
LIBS_fonts      := $(FONTLIB)
LIBS_fs         := $(DISKLIB) $(PARTS) $(FAT) $(FSLIB) $(CLOCK) $(RANDOM)
LIBS_sh         := $(PROCS) $(PATHS) $(APPLIB)
LIBS_disks      := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) $(DISKLIB) $(PARTS) $(FAT) $(FSLIB)
LIBS_files      := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) $(PATHS) $(APPLIB)

# The programs, found by where their directories are, which is where
# each goes in the initramfs: user/bin/NAME, a command, in /bin;
# user/sbin/NAME, a driver or a service, in /sbin; and user/apps/NAME,
# an app, in a bundle, /Applications/APP.app, whose source is the
# directory user/apps/NAME/APP.app, holding its manifest and its icon:
# icon.svg, the app's own GNOME icon, or icon.draw, drawing commands,
# which tools/mkicon draws as its icon.ppm. BUNDLE_NAME is the bundle's
# name, and ICON_NAME its icon's source.
BIN      := $(notdir $(wildcard user/bin/*))
SBIN     := $(notdir $(wildcard user/sbin/*))
APPS     := $(notdir $(wildcard user/apps/*))
PROGRAMS := $(BIN) $(SBIN) $(APPS)
# The apps a release has and the initramfs does not: built, checked and
# tested as every app is, but staged by release-apps, not root, so they
# reach a system only as install --net and the Installer put a release
# on its volume.
RELEASE_APPS := calc
$(foreach p,$(BIN),$(eval DIR_$(p) := user/bin/$(p)))
$(foreach p,$(SBIN),$(eval DIR_$(p) := user/sbin/$(p)))
$(foreach p,$(APPS),$(eval DIR_$(p) := user/apps/$(p)))
$(foreach p,$(APPS),$(eval BUNDLE_$(p) := $(notdir $(wildcard user/apps/$(p)/*.app))))
$(foreach p,$(APPS),$(eval ICON_$(p) := $(firstword $(wildcard user/apps/$(p)/$(BUNDLE_$(p))/icon.svg) user/apps/$(p)/$(BUNDLE_$(p))/icon.draw)))

# A program's own sources, SRCS_NAME: every .l0 in its directory but its
# main.l0, an app's preview.l0 (its scenes for make preview, a main of
# its own) and its tests, NAME.l0 first; and its tests, TESTS_NAME, each
# run with all of them.
$(foreach p,$(PROGRAMS),$(eval SRCS_$(p) := $(DIR_$(p))/$(p).l0 \
    $(filter-out $(DIR_$(p))/$(p).l0 $(DIR_$(p))/main.l0 $(DIR_$(p))/preview.l0 %_test.l0,$(wildcard $(DIR_$(p))/*.l0))))
# The apps with scenes to preview.
PREVIEW_APPS := $(foreach p,$(APPS),$(if $(wildcard $(DIR_$(p))/preview.l0),$(p)))
$(foreach p,$(PROGRAMS),$(eval TESTS_$(p) := $(wildcard $(DIR_$(p))/*_test.l0)))

L0SDOC   := $(BASE) $(CLI) tools/l0sdoc/l0sdoc.l0
MKFS     := $(COMMON) $(CLI) $(PARTS) $(FAT) tools/mkfs/mkfs.l0
MKEEPROM := $(ULIB) $(CLOCK) $(SHA256) $(BOOTLOADER) tools/mkeeprom/mkeeprom.l0
MKICON   := $(ULIB) $(RENDER) $(UI_CORE) $(SVG) tools/mkicon/mkicon.l0
MKICONS  := $(ULIB) $(RENDER) $(UI_CORE) $(SVG) tools/mkicons/mkicons.l0
MKWALLPAPER := $(ULIB) $(RENDER) $(SVG) tools/mkwallpaper/mkwallpaper.l0
MKCHIME  := $(ULIB) $(WAV) tools/mkchime/mkchime.l0
MKFONT   := $(ULIB) $(RENDER) $(UI_CORE) $(RASTER) tools/mkfont/shape.l0 tools/mkfont/mkfont.l0
MKSTRIKE := $(ULIB) $(RENDER) $(GLYPHS) tools/mkstrike/mkstrike.l0
MKMETRICS := $(ULIB) $(RENDER) $(TTF) tools/mkmetrics/mkmetrics.l0
IMAGES   := $(PROGRAMS:%=$(BUILD)/bin/%.img)
ICONS    := $(APPS:%=$(BUILD)/icons/%.ppm)
ICONS2X  := $(APPS:%=$(BUILD)/icons/%2x.ppm)
ROOT     := $(BUILD)/root

# Every library, which make doc reads the documentation of: common's, the
# kernel's parts, and everything under user/lib.
LIB_SRCS := $(wildcard user/lib/*/*.l0)
DOC_SRCS := $(filter-out %_test.l0,$(wildcard common/*.l0)) $(filter-out $(COMMON) common/queue.l0 common/klog.l0 common/rp1.l0,$(KERNEL)) \
            $(filter-out %_test.l0,$(LIB_SRCS))
# Every program's own sources, and the host tools' and the kernel's board
# tests' assembler: make doc Q=... finds names there too, after the
# libraries', though no other program can link them.
PROG_DOC_SRCS := $(foreach p,$(PROGRAMS),$(SRCS_$(p))) kernel/asm.l0 \
                 $(filter-out %_test.l0 %/main.l0,$(wildcard tools/*/*.l0))
# The forms of all of them that had no documentation when make check began
# to ask for it: the only ones that may still lack it, as make check says.
DOC_GAPS := tools/l0sdoc/undocumented.txt

.PHONY: FORCE all check fmt test check-each test-each test-virt test-virt-heap e2e app-libs images root release-apps initramfs screen-initramfs usb-initramfs vt-initramfs disks-initramfs launcher-install-initramfs installer-initramfs agent-screen-initramfs boot demo demo-system sysdisk clean sample doc doc-prune metrics mcp proxy proxy-run release agent-etc icon-sheet graph graph-hook preview

all: check test test-virt e2e

# Each check and each host test is a target of its own, build/check/FILE.ok
# or build/test/FILE.ok, FILE the last file it names: made once it passes,
# its output kept beside it in FILE.log. So make check and make test run
# only what changed since it last passed, JOBS at once, and say nothing of
# what passes; what fails is shown whole, and every failure is shown, since
# the rest go on (-k).
#
# $(call logged,COMMAND,WHAT) runs COMMAND, its output in the target's
# log, and touches the target if it passes, or else removes it, shows
# the log and names WHAT as failing.
logged = if $(1) > $(@:.ok=.log) 2>&1; then touch $@; else rm -f $@; cat $(@:.ok=.log); echo "make: $(2) failed"; exit 1; fi

# $(call l0_check,FILES): l0 check of FILES, the last a main.l0.
define L0_CHECK
$(BUILD)/check/$(lastword $(1)).ok: $(1) $(L0_HOSTRT)
	@mkdir -p $$(@D)
	@$$(call logged,$(L0) check $(1),l0 check of $(lastword $(1)))
CHECKS += $(BUILD)/check/$(lastword $(1)).ok
endef
l0_check = $(eval $(call L0_CHECK,$(1)))

# The files host tests read beside their sources: fonts, the apps'
# bundles, and the sample archive.
TEST_DATA := $(wildcard fonts/*) $(wildcard user/apps/*/*.app/*)

# $(call l0_test,FILES): l0 test of FILES, the last a test file.
define L0_TEST
$(BUILD)/test/$(lastword $(1)).ok: $(1) $(L0_HOSTRT) $(TEST_DATA) $(BUILD)/sample.cpio
	@mkdir -p $$(@D)
	@$$(call logged,$(L0) test $(1),l0 test of $(lastword $(1)))
TESTS += $(BUILD)/test/$(lastword $(1)).ok
endef
l0_test = $(eval $(call L0_TEST,$(1)))

$(call l0_check,$(KERNEL) kernel/main.l0)
$(foreach p,$(PROGRAMS),$(call l0_check,$(ULIB) $(LIBS_$(p)) $(SRCS_$(p)) $(DIR_$(p))/main.l0))
$(foreach p,$(PREVIEW_APPS),$(call l0_check,$(ULIB) $(LIBS_$(p)) $(SRCS_$(p)) $(UI_PREVIEW) $(DIR_$(p))/preview.l0))
$(call l0_check,$(L0SDOC) tools/l0sdoc/main.l0)
$(call l0_check,$(MKFS) tools/mkfs/main.l0)
$(call l0_check,$(MKEEPROM) tools/mkeeprom/main.l0)
$(call l0_check,$(MKICON) tools/mkicon/main.l0)
$(call l0_check,$(MKFONT) tools/mkfont/main.l0)
$(call l0_check,$(MKSTRIKE) tools/mkstrike/main.l0)
$(call l0_check,$(MKMETRICS) tools/mkmetrics/main.l0)
$(call l0_check,$(MKICONS) tools/mkicons/main.l0)
$(call l0_check,$(MKWALLPAPER) tools/mkwallpaper/main.l0)
$(call l0_check,$(MKCHIME) tools/mkchime/main.l0)

# That every form is documented, but those DOC_GAPS lists.
$(BUILD)/check/doc.ok: $(BUILD)/l0sdoc $(DOC_GAPS) $(DOC_SRCS) $(PROG_DOC_SRCS)
	@mkdir -p $(@D)
	@$(call logged,$(BUILD)/l0sdoc --check $(DOC_GAPS) $(DOC_SRCS) $(PROG_DOC_SRCS),the documentation check)
CHECKS += $(BUILD)/check/doc.ok

# That every .l0 file git knows is as l0 fmt would leave it: its closers
# where its indentation says. make fmt writes them so.
L0_FILES := $(shell git ls-files '*.l0' 2> /dev/null)
$(BUILD)/check/fmt.ok: $(L0_FILES) $(L0_HOSTRT)
	@mkdir -p $(@D)
	@$(call logged,$(L0) fmt --check $(L0_FILES),the format check (make fmt rewrites))
CHECKS += $(BUILD)/check/fmt.ok

fmt:
	$(L0) fmt $(L0_FILES)

# That the toolkit's metrics, user/lib/ui/metrics.l0, are what mkmetrics
# writes from the fonts now; make metrics writes them again.
METRICS := user/lib/ui/metrics.l0
METRICS_FACES := code=fonts/SourceCodePro-Regular.ttf code-bold=fonts/SourceCodePro-Bold.ttf \
                 sans=fonts/SourceSans3-Regular.ttf sans-bold=fonts/SourceSans3-Bold.ttf
$(BUILD)/check/metrics.ok: $(BUILD)/mkmetrics $(METRICS) $(wildcard fonts/*.ttf)
	@mkdir -p $(@D)
	@$(call logged,sh -c '$(BUILD)/mkmetrics $(METRICS_FACES) $(BUILD)/metrics.l0 && cmp $(BUILD)/metrics.l0 $(METRICS)',the metrics check (make metrics writes them))
CHECKS += $(BUILD)/check/metrics.ok

metrics: $(BUILD)/mkmetrics
	$(BUILD)/mkmetrics $(METRICS_FACES) $(METRICS)

# Every check, and then every warning they gave, passing ones' too, from
# their logs: l0 check's warnings never fail it, and each is a whole copy
# of a map, array or record that a loop pays for every time.
check:
	@$(MAKE) -s -k -j$(JOBS) check-each; st=$$?; \
	w=$$(cat $(CHECKS:.ok=.log) 2> /dev/null | grep 'warning:' | sort -u); \
	if [ -n "$$w" ]; then echo "$$w"; echo "make check: $$(echo "$$w" | wc -l) warnings"; fi; exit $$st

check-each: $(CHECKS)

# An archive bsdtar makes, of bin/x, "hi", mode 0755: what the host tests
# of initramfs.l0 and of cat read.
sample: $(BUILD)/sample.cpio

$(BUILD)/sample.cpio: | $(BUILD)
	rm -rf $(BUILD)/sample && mkdir -p $(BUILD)/sample/bin
	printf hi > $(BUILD)/sample/bin/x && chmod 755 $(BUILD)/sample/bin/x
	cd $(BUILD)/sample && find . | LC_ALL=C sort | bsdtar -n --format newc -cf ../sample.cpio -T -

$(call l0_test,$(BASE) common/abi_test.l0)
$(call l0_test,$(BASE) common/text_test.l0)
$(call l0_test,$(COMMON) common/initramfs_test.l0)
$(call l0_test,$(BASE) common/queue.l0 common/queue_test.l0)
$(call l0_test,$(BASE) common/klog.l0 common/klog_test.l0)
$(call l0_test,$(BASE) common/queue.l0 common/klog.l0 kernel/log.l0 kernel/log_test.l0)
$(call l0_test,$(BASE) common/queue.l0 kernel/memory.l0 kernel/memory_test.l0)
$(call l0_test,$(BASE) kernel/mounts.l0 kernel/mounts_test.l0)
$(call l0_test,$(BASE) common/queue.l0 kernel/mounts.l0 kernel/ipc.l0 kernel/ipc_test.l0)
$(call l0_test,$(COMMON) kernel/inittab.l0 kernel/inittab_test.l0)
$(call l0_test,$(BASE) kernel/sched.l0 kernel/sched_test.l0)
$(call l0_test,$(BASE) kernel/usage.l0 kernel/usage_test.l0)
$(call l0_test,$(BASE) kernel/usage.l0 kernel/cpus.l0 kernel/cpus_test.l0)
$(call l0_test,$(BASE) kernel/pids.l0 kernel/pids_test.l0)
$(call l0_test,$(BASE) kernel/syscall.l0 kernel/syscall_test.l0)
$(call l0_test,$(KERNEL) kernel/asm.l0 kernel/kernel_test.l0)
$(call l0_test,$(KERNEL) kernel/asm.l0 kernel/elf_test.l0)
$(call l0_test,$(BASE) $(CLI) user/lib/sys/cli_test.l0)
$(call l0_test,$(ULIB) user/lib/sys/l0s_test.l0)
$(call l0_test,$(ULIB) user/lib/sys/server_test.l0)
$(call l0_test,$(ULIB) $(PROCS) user/lib/sys/procs_test.l0)
$(call l0_test,$(ULIB) $(PATHS) user/lib/sys/paths_test.l0)
$(call l0_test,$(ULIB) $(VIRTIO) user/lib/sys/virtio_test.l0)
$(call l0_test,$(ULIB) $(TTY) user/lib/sys/tty_test.l0)
$(call l0_test,$(ULIB) $(KEYMAP) user/lib/sys/keymap_test.l0)
$(call l0_test,$(ULIB) $(MAILBOX) user/lib/sys/mailbox_test.l0)
$(call l0_test,$(BASE) $(RP1) common/rp1_test.l0)
$(call l0_test,$(ULIB) $(RECT) user/lib/gfx/rect_test.l0)
$(call l0_test,$(ULIB) $(RENDER) user/lib/gfx/render_test.l0)
$(call l0_test,$(ULIB) $(CLOCK) user/lib/proto/clock_test.l0)
$(call l0_test,$(ULIB) $(RECT) $(DISPLAY) user/lib/proto/display_test.l0)
$(call l0_test,$(ULIB) $(RECT) $(DISPLAY_SERVER) user/lib/proto/display_server_test.l0)
$(call l0_test,$(ULIB) $(RECT) $(WMLIB) user/lib/proto/wm_test.l0)
$(call l0_test,$(ULIB) $(DISKLIB) user/lib/proto/disk_test.l0)
$(call l0_test,$(ULIB) $(FONTLIB) user/lib/proto/font_test.l0)
$(call l0_test,$(ULIB) $(AUDIOLIB) user/lib/proto/audio_test.l0)
$(call l0_test,$(ULIB) $(AUDIO_SERVER) user/lib/proto/audio_server_test.l0)
$(call l0_test,$(ULIB) $(UUIDLIB) $(FSLIB) user/lib/proto/fs_test.l0)
$(call l0_test,$(ULIB) $(NICLIB) user/lib/proto/nic_test.l0)
$(call l0_test,$(ULIB) $(INETLIB) user/lib/proto/inet_test.l0)
$(call l0_test,$(ULIB) $(HTTP) user/lib/proto/httpc_test.l0)
$(call l0_test,$(ULIB) $(MODELLIB) user/lib/proto/model_test.l0)
$(call l0_test,$(ULIB) $(AGENTLIB) user/lib/proto/agent_test.l0)
$(call l0_test,$(ULIB) $(SPEECHLIB) user/lib/proto/speech_test.l0)
$(call l0_test,$(ULIB) $(AGENTHOME) user/lib/sys/agenthome_test.l0)
# agenthome's tests write a home's files and history under build/, as
# this host has no fs to make its directories.
$(BUILD)/test/user/lib/sys/agenthome_test.l0.ok: $(BUILD)/agenthome_test/.history
$(BUILD)/agenthome_test/.history:
	@mkdir -p $@
$(call l0_test,$(ULIB) $(RANDOM) user/lib/proto/random_test.l0)
$(call l0_test,$(ULIB) $(USBLIB) user/lib/proto/usb_test.l0)
$(call l0_test,$(ULIB) $(PCILIB) user/lib/proto/pci_test.l0)
$(call l0_test,$(ULIB) $(PATHS) $(APPLIB) user/lib/proto/app_test.l0)
$(call l0_test,$(ULIB) $(APPOPEN) user/lib/proto/appopen_test.l0)
$(call l0_test,$(BASE) $(L0FS) user/lib/format/l0fs_test.l0)
$(call l0_test,$(BASE) $(FAT) user/lib/format/fat_test.l0)
$(call l0_test,$(BASE) $(PARTS) user/lib/format/mbr_test.l0)
$(call l0_test,$(BASE) $(UUIDLIB) user/lib/format/uuid_test.l0)
$(call l0_test,$(BASE) $(DNSLIB) user/lib/format/dns_test.l0)
$(call l0_test,$(BASE) $(USBDESC) user/lib/format/usbdesc_test.l0)
$(call l0_test,$(BASE) $(USBDESC) $(UAC) user/lib/format/uac_test.l0)
$(call l0_test,$(BASE) $(CACT) user/lib/format/cact_test.l0)
$(call l0_test,$(BASE) $(CLI) $(WAV) $(MEL) user/lib/speech/mel_test.l0)
$(call l0_test,$(BASE) $(CACT) $(MEL) $(NN) user/lib/speech/nn_test.l0)
$(call l0_test,$(BASE) $(WHISTLE) user/lib/speech/whistle_test.l0)
$(call l0_test,$(BASE) $(ENCODER) user/lib/speech/encoder_test.l0)
$(call l0_test,$(BASE) $(DECODER) user/lib/speech/decoder_test.l0)
$(call l0_test,$(BASE) $(CLI) $(TRANSCRIBE) user/lib/speech/transcribe_test.l0)
$(call l0_test,$(BASE) $(ONNX) user/lib/format/onnx_test.l0)
$(call l0_test,$(BASE) $(VOICE) user/lib/speech/voice_test.l0)
$(call l0_test,$(BASE) $(PHONEMES) user/lib/speech/phonemes_test.l0)
$(call l0_test,$(BASE) $(VITS) user/lib/speech/vits_test.l0)
$(call l0_test,$(BASE) $(PIPER) user/lib/speech/piper_test.l0)
$(call l0_test,$(BASE) $(CRC32) user/lib/format/crc32_test.l0)
$(call l0_test,$(BASE) $(CRC32) $(PNG) user/lib/format/png_test.l0)
$(call l0_test,$(BASE) $(CRC32) $(PNG) $(INFLATE) user/lib/format/inflate_test.l0)
$(call l0_test,$(BASE) $(CRC32) $(PNG) $(PNGREAD) user/lib/format/png_read_test.l0)
$(call l0_test,$(BASE64) user/lib/format/base64_test.l0)
$(call l0_test,$(BASE) $(SHA256) user/lib/format/sha256_test.l0)
$(call l0_test,$(ULIB) $(RELEASE) user/lib/sys/release_test.l0)
$(call l0_test,$(BASE) $(SHA256) $(PIEEPROMLIB) user/lib/format/pieeprom_test.l0)
$(call l0_test,$(ULIB) $(CLOCK) $(SHA256) $(BOOTLOADER) user/lib/sys/bootloader_test.l0)
$(call l0_test,$(BASE) $(PARTS) user/lib/format/gpt_test.l0)
$(call l0_test,$(BASE) $(PPM) user/lib/format/ppm_test.l0)
$(call l0_test,$(BASE) $(PPM) $(QOI) user/lib/format/qoi_test.l0)
$(call l0_test,$(BASE) $(WAV) user/lib/format/wav_test.l0)
$(call l0_test,$(BASE) $(PCM) user/lib/format/pcm_test.l0)
$(call l0_test,$(BASE) $(XML) user/lib/format/xml_test.l0)
$(call l0_test,$(BASE) $(JSON) user/lib/format/json_test.l0)
$(call l0_test,$(BASE) $(NTPLIB) user/lib/format/ntp_test.l0)
$(call l0_test,$(BASE) $(SSE) user/lib/format/sse_test.l0)
$(call l0_test,$(BASE) $(HTTPMSG) user/lib/format/http_test.l0)
$(foreach t,$(UI_TESTS),$(call l0_test,$(ULIB) $(RENDER) $(UI_CORE) $(UI_TESTING) user/lib/ui/$(t)_test.l0))
$(call l0_test,$(ULIB) $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) user/lib/ui/window_test.l0)
$(call l0_test,$(ULIB) $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) user/lib/ui/uiapp_test.l0)
$(call l0_test,$(ULIB) $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) user/lib/ui/uiloop_test.l0)
$(call l0_test,$(ULIB) $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) user/lib/ui/run_test.l0)
$(call l0_test,$(ULIB) $(RENDER) $(UI_CORE) $(UI_PREVIEW) user/lib/ui/preview_test.l0)
$(foreach p,$(PROGRAMS),$(foreach t,$(TESTS_$(p)),$(call l0_test,$(ULIB) $(LIBS_$(p)) $(if $(filter user/lib/ui/widget.l0,$(LIBS_$(p))),$(UI_TESTING)) $(SRCS_$(p)) $(t))))
$(call l0_test,$(L0SDOC) tools/l0sdoc/l0sdoc_test.l0)
$(call l0_test,$(MKFS) tools/mkfs/mkfs_test.l0)
$(call l0_test,$(MKEEPROM) tools/mkeeprom/mkeeprom_test.l0)
$(call l0_test,$(MKICON) tools/mkicon/mkicon_test.l0)
$(call l0_test,$(MKICONS) tools/mkicons/mkicons_test.l0)
$(call l0_test,$(MKWALLPAPER) tools/mkwallpaper/mkwallpaper_test.l0)
$(call l0_test,$(MKCHIME) tools/mkchime/mkchime_test.l0)
$(foreach t,shape mkfont,$(call l0_test,$(MKFONT) tools/mkfont/$(t)_test.l0))
$(call l0_test,$(MKSTRIKE) tools/mkstrike/mkstrike_test.l0)
$(call l0_test,$(MKMETRICS) tools/mkmetrics/mkmetrics_test.l0)
$(call l0_test,$(ULIB) $(RENDER) $(TTF) user/lib/format/ttf_test.l0)
$(call l0_test,$(ULIB) $(RENDER) $(GLYPHS) user/lib/format/strike_test.l0)
$(call l0_test,$(ULIB) $(RENDER) $(RASTER) user/lib/gfx/raster_test.l0)
$(call l0_test,$(ULIB) $(RENDER) $(SVG) user/lib/gfx/svg_path_test.l0)
$(call l0_test,$(ULIB) $(RENDER) $(SVG) user/lib/gfx/svg_test.l0)

# The MCP server's tests, of its pure parts.
$(BUILD)/test/l0s-mcp.ok: $(wildcard tools/l0s-mcp/*.py)
	@mkdir -p $(@D)
	@$(call logged,python3 tools/l0s-mcp/test_board.py,tools/l0s-mcp/test_board.py)

# The tests of the graph's L0 parser and of graph-usage.
$(BUILD)/test/graphify-l0.ok: $(wildcard tools/graphify-l0/*.py) tools/graphify-l0/graph-usage
	@mkdir -p $(@D)
	@$(call logged,{ python3 tools/graphify-l0/test_l0_graph.py && python3 tools/graphify-l0/test_graph_usage.py; },tools/graphify-l0's tests)

# The API proxy's tests, against its stand-in, with the venv's Python,
# which has aiohttp: the first after a clean needs the network, for pip.
PROXY_VENV := $(BUILD)/proxy/venv
$(BUILD)/test/api-proxy.ok: $(wildcard tools/api-proxy/*.py) $(wildcard tools/api-proxy/bin/*) tools/l0s-app-new $(PROXY_VENV)/.installed
	@mkdir -p $(@D)
	@$(call logged,$(PROXY_VENV)/bin/python tools/api-proxy/test_proxy.py,tools/api-proxy/test_proxy.py)

# Every host test, and then how many passed in all, those run before
# among them. A failure is shown as it happens, and the count still given.
test:
	@$(MAKE) -s -k -j$(JOBS) test-each; st=$$?; \
	cat $(TESTS:.ok=.log) 2> /dev/null | awk '/^# [0-9]+ passed, [0-9]+ failed$$/ { p += $$2; f += $$4 } \
	  END { print "make test: " p " passed, " f " failed, of $(words $(TESTS)) files" }'; exit $$st

test-each: $(TESTS) $(BUILD)/test/l0s-mcp.ok $(BUILD)/test/graphify-l0.ok $(BUILD)/test/api-proxy.ok

test-virt: test-virt-heap
	L0_QEMU_ARGS="-smp 1" $(L0) test --target virt $(KERNEL_LAYOUT) $(KERNEL) kernel/asm.l0 kernel/kernel_virt_test.l0
	L0_QEMU_ARGS="-smp $(VIRT_CPUS)" $(L0) test --target virt $(KERNEL_LAYOUT) $(KERNEL) kernel/asm.l0 kernel/kernel_virt_test.l0

# test_heap_runs_low on a kernel heap of 96 MB, too small to record every
# page of the pool: the kernel refuses pages once its heap is down to its
# reserve (process.l0's heap_has_room), rather than stopping with heap
# exhausted.
test-virt-heap:
	L0_QEMU_ARGS="-smp 1" $(L0) test --target virt --heap-mb 96 --stack-mb $(KERNEL_STACK_MB) --match heap_runs_low $(KERNEL) kernel/asm.l0 kernel/kernel_virt_test.l0

$(BUILD) $(BUILD)/bin $(BUILD)/icons $(BUILD)/images:
	mkdir -p $@

# The kernel's layout options as last built, rewritten only when they
# change, so that a new KERNEL_HEAP_MB or KERNEL_STACK_MB rebuilds it.
$(BUILD)/kernel.layout: FORCE | $(BUILD)
	@echo '$(KERNEL_LAYOUT)' | cmp -s - $@ || echo '$(KERNEL_LAYOUT)' > $@

FORCE:

$(BUILD)/kernel.img: $(KERNEL) kernel/main.l0 $(L0_VIRTRT) $(BUILD)/kernel.layout | $(BUILD)
	$(L0) build --target virt $(KERNEL_LAYOUT) $(KERNEL) kernel/main.l0 -o $@

define PROGRAM_RULE
$(BUILD)/bin/$(1).img: $(SRCS_$(1)) $(DIR_$(1))/main.l0 $(ULIB) $(LIBS_$(1)) $(L0_PROCRT) | $(BUILD)/bin
	$(L0) build --target proc $(ULIB) $(LIBS_$(1)) $(SRCS_$(1)) $(DIR_$(1))/main.l0 -o $$@
endef
$(foreach p,$(PROGRAMS),$(eval $(call PROGRAM_RULE,$(p))))

images: $(BUILD)/kernel.img $(IMAGES)

$(BUILD)/l0sdoc: $(L0SDOC) tools/l0sdoc/main.l0 | $(BUILD)
	$(L0) build $(L0SDOC) tools/l0sdoc/main.l0 -o $@

# What tools/mkdisk partitions and formats a disk image with.
$(BUILD)/mkfs: $(MKFS) tools/mkfs/main.l0 | $(BUILD)
	$(L0) build $(MKFS) tools/mkfs/main.l0 -o $@

$(BUILD)/mkeeprom: $(MKEEPROM) tools/mkeeprom/main.l0 | $(BUILD)
	$(L0) build $(MKEEPROM) tools/mkeeprom/main.l0 -o $@

$(BUILD)/mkicon: $(MKICON) tools/mkicon/main.l0 | $(BUILD)
	$(L0) build $(MKICON) tools/mkicon/main.l0 -o $@

# The wallpaper, branding/wallpaper-dark.svg drawn as QOI by
# tools/mkwallpaper at 1920 by 1080, and at 3840 by 2160 for a 4K
# screen: /etc/wallpaper.qoi and /etc/wallpaper2x.qoi, which the
# display drivers show first and wm draws its desktop on. make demo
# WALLPAPER_SVG=picture.svg draws another.
WALLPAPER_SVG ?= branding/wallpaper-dark.svg
WALLPAPERS := $(BUILD)/wallpaper.qoi $(BUILD)/wallpaper2x.qoi

$(BUILD)/mkwallpaper: $(MKWALLPAPER) tools/mkwallpaper/main.l0 | $(BUILD)
	$(L0) build $(MKWALLPAPER) tools/mkwallpaper/main.l0 -o $@

$(BUILD)/wallpaper.qoi: $(WALLPAPER_SVG) $(BUILD)/mkwallpaper
	$(BUILD)/mkwallpaper $< 1920 1080 $@.tmp && mv $@.tmp $@

$(BUILD)/wallpaper2x.qoi: $(WALLPAPER_SVG) $(BUILD)/mkwallpaper
	$(BUILD)/mkwallpaper $< 3840 2160 $@.tmp && mv $@.tmp $@

# The chime a sound driver plays as it starts, /etc/chime.wav on the
# Pi 5, the only board with one: a soft piano G major chord, which
# tools/mkchime synthesizes.
CHIME := $(BUILD)/chime.wav

$(BUILD)/mkchime: $(MKCHIME) tools/mkchime/main.l0 | $(BUILD)
	$(L0) build $(MKCHIME) tools/mkchime/main.l0 -o $@

$(CHIME): $(BUILD)/mkchime
	$(BUILD)/mkchime $@.tmp && mv $@.tmp $@

# The face the desktop draws the pointer with, /etc/face:
# fonts/cursors.paths, rasterized.
FACE := $(BUILD)/face
# The fonts the font service reads, /etc/fonts: Source Code Pro's and
# Source Sans 3's, regular and bold.
ETC_FONTS := fonts/SourceCodePro-Regular.ttf fonts/SourceCodePro-Bold.ttf \
             fonts/SourceSans3-Regular.ttf fonts/SourceSans3-Bold.ttf

$(BUILD)/mkfont: $(MKFONT) tools/mkfont/main.l0 | $(BUILD)
	$(L0) build $(MKFONT) tools/mkfont/main.l0 -o $@

$(FACE): $(BUILD)/mkfont fonts/cursors.paths
	$(BUILD)/mkfont fonts/cursors.paths $@.tmp && mv $@.tmp $@

# The strikes the desktop draws its text from at scales 1 and 2, Source
# Code Pro's and Source Sans 3's regular and bold at 16, 32 and 64,
# which the font service keeps as it starts, staged with the fonts in
# /etc/fonts.
STRIKES := $(foreach h,16 32 64,$(foreach f,code code-bold sans sans-bold,$(BUILD)/strikes/$(f)-$(h).strike))

$(BUILD)/mkstrike: $(MKSTRIKE) tools/mkstrike/main.l0 | $(BUILD)
	$(L0) build $(MKSTRIKE) tools/mkstrike/main.l0 -o $@

$(BUILD)/mkmetrics: $(MKMETRICS) tools/mkmetrics/main.l0 | $(BUILD)
	$(L0) build $(MKMETRICS) tools/mkmetrics/main.l0 -o $@

$(BUILD)/strikes/code-bold-%.strike: $(BUILD)/mkstrike fonts/SourceCodePro-Bold.ttf
	@mkdir -p $(@D)
	$(BUILD)/mkstrike fonts/SourceCodePro-Bold.ttf $* $@.tmp && mv $@.tmp $@

$(BUILD)/strikes/code-%.strike: $(BUILD)/mkstrike fonts/SourceCodePro-Regular.ttf
	@mkdir -p $(@D)
	$(BUILD)/mkstrike fonts/SourceCodePro-Regular.ttf $* $@.tmp && mv $@.tmp $@

$(BUILD)/strikes/sans-bold-%.strike: $(BUILD)/mkstrike fonts/SourceSans3-Bold.ttf
	@mkdir -p $(@D)
	$(BUILD)/mkstrike fonts/SourceSans3-Bold.ttf $* $@.tmp && mv $@.tmp $@

$(BUILD)/strikes/sans-%.strike: $(BUILD)/mkstrike fonts/SourceSans3-Regular.ttf
	@mkdir -p $(@D)
	$(BUILD)/mkstrike fonts/SourceSans3-Regular.ttf $* $@.tmp && mv $@.tmp $@

# The toolkit's symbolic icons, /etc/icons, at every scale: GNOME's SVGs
# under icons/, rasterized by mkicons. make icon-sheet draws them all
# into build/icon-sheet.ppm, to look at.
ICON_FACE := $(BUILD)/icons.face
SYMBOLIC  := $(sort $(wildcard icons/*/symbolic/*-symbolic.svg))

$(BUILD)/mkicons: $(MKICONS) tools/mkicons/main.l0 | $(BUILD)
	$(L0) build $(MKICONS) tools/mkicons/main.l0 -o $@

$(ICON_FACE): $(BUILD)/mkicons $(SYMBOLIC)
	$(BUILD)/mkicons $@.tmp $(SYMBOLIC) && mv $@.tmp $@

icon-sheet: $(BUILD)/mkicons $(SYMBOLIC)
	$(BUILD)/mkicons --sheet $(BUILD)/icon-sheet.ppm $(SYMBOLIC)

# An app's scenes, its preview.l0, painted on the host as the board
# would paint them, with these strikes and icons, into
# build/preview/APP/NAME.png (roadmap 0065): make preview APP=NAME. The
# preview's own test paints with them too.
PREVIEW_DIR = $(BUILD)/preview/$(APP)
preview: $(STRIKES) $(ICON_FACE)
	@if [ -z "$(APP)" ] || [ ! -f "user/apps/$(APP)/preview.l0" ]; then \
	  echo "make preview APP=NAME, NAME an app with a preview.l0: $(PREVIEW_APPS)"; exit 2; fi
	@mkdir -p $(PREVIEW_DIR)
	@$(L0) build $(ULIB) $(LIBS_$(APP)) $(SRCS_$(APP)) $(UI_PREVIEW) user/apps/$(APP)/preview.l0 -o $(PREVIEW_DIR)/preview
	@$(PREVIEW_DIR)/preview $(PREVIEW_DIR) $(BUILD)

$(BUILD)/test/user/lib/ui/preview_test.l0.ok: $(STRIKES) $(ICON_FACE)

# The full-color icons Files and Disks show things with, /etc/images:
# Adwaita's SVGs under icons/adwaita/scalable, each drawn by mkicon
# --image into NAME.face, its images at every size, with their alpha.
COLOR_SVGS  := $(sort $(wildcard icons/adwaita/scalable/*.svg))
IMAGE_FACES := $(COLOR_SVGS:icons/adwaita/scalable/%.svg=$(BUILD)/images/%.face)

$(BUILD)/images/%.face: icons/adwaita/scalable/%.svg $(BUILD)/mkicon | $(BUILD)/images
	$(BUILD)/mkicon --image $< $@.tmp && mv $@.tmp $@

# Each app's icon, drawn from its bundle's icon.svg or icon.draw, and
# an icon.svg's images for Files, icon.face. mkicon draws on the
# theme's colors, so an icon is drawn again when they change.
define ICON_RULE
$(BUILD)/icons/$(1).ppm: $(ICON_$(1)) $(BUILD)/mkicon $(ICON_FACE) | $(BUILD)/icons
	$(BUILD)/mkicon $$< $(ICON_FACE) > $$@.tmp && mv $$@.tmp $$@

$(BUILD)/icons/$(1)2x.ppm: $(ICON_$(1)) $(BUILD)/mkicon $(ICON_FACE) $(FACE) | $(BUILD)/icons
	$(BUILD)/mkicon $$< $(ICON_FACE) $(FACE) > $$@.tmp && mv $$@.tmp $$@

$(BUILD)/icons/$(1).face: $(ICON_$(1)) $(BUILD)/mkicon | $(BUILD)/icons
	$(BUILD)/mkicon --image $$< $$@.tmp && mv $$@.tmp $$@
endef
$(foreach p,$(APPS),$(eval $(call ICON_RULE,$(p))))
SVG_APPS := $(foreach p,$(APPS),$(if $(filter %.svg,$(ICON_$(p))),$(p)))
IMAGES_FACE := $(SVG_APPS:%=$(BUILD)/icons/%.face)

# The initramfs's programs, staged in build/root as the archive holds
# them: /bin, /sbin, and each app's bundle, its program, manifest and
# icon, at both scales, and as what Files paints on any ground: an
# icon.svg's images, icon.face, or the drawing commands of an icon.draw.
# Made anew each time, so that a program that moves leaves nothing
# where it was.
# STAGE_APP NAME DIR: the app NAME's bundle staged under DIR.
define STAGE_APP
mkdir -p $(2)/Applications/$(BUNDLE_$(1)) && \
install -m 755 $(BUILD)/bin/$(1).img $(2)/Applications/$(BUNDLE_$(1))/$(1) && \
install -m 644 $(DIR_$(1))/$(BUNDLE_$(1))/manifest $(2)/Applications/$(BUNDLE_$(1))/manifest && \
install -m 644 $(BUILD)/icons/$(1).ppm $(2)/Applications/$(BUNDLE_$(1))/icon.ppm && \
install -m 644 $(BUILD)/icons/$(1)2x.ppm $(2)/Applications/$(BUNDLE_$(1))/icon2x.ppm && \
$(if $(filter %.svg,$(ICON_$(1))),install -m 644 $(BUILD)/icons/$(1).face $(2)/Applications/$(BUNDLE_$(1))/icon.face,install -m 644 $(ICON_$(1)) $(2)/Applications/$(BUNDLE_$(1))/icon.draw)
endef

root: $(IMAGES) $(ICONS) $(ICONS2X) $(IMAGES_FACE)
	rm -rf $(ROOT) && mkdir -p $(ROOT)/bin $(ROOT)/sbin $(ROOT)/Applications
	$(foreach p,$(BIN),install -m 755 $(BUILD)/bin/$(p).img $(ROOT)/bin/$(p) && ) true
	$(foreach p,$(SBIN),install -m 755 $(BUILD)/bin/$(p).img $(ROOT)/sbin/$(p) && ) true
	$(foreach p,$(filter-out $(RELEASE_APPS),$(APPS)),$(call STAGE_APP,$(p),$(ROOT)) && ) true

# RELEASE_APPS' bundles, staged as root stages the rest, in a tree of
# their own, which mkrelease adds to a release's system.
RELEASE_APPS_ROOT := $(BUILD)/release-apps
release-apps: $(IMAGES) $(ICONS) $(ICONS2X) $(IMAGES_FACE)
	rm -rf $(RELEASE_APPS_ROOT) && mkdir -p $(RELEASE_APPS_ROOT)/Applications
	$(foreach p,$(RELEASE_APPS),$(call STAGE_APP,$(p),$(RELEASE_APPS_ROOT)) && ) true

doc: $(BUILD)/l0sdoc
	@$(BUILD)/l0sdoc "$(Q)" $(DOC_SRCS) -- $(PROG_DOC_SRCS)

# The libraries an app the agent has built links (roadmap 0045,
# tools/api-proxy/bin/l0s-app-build): every program's, a window's, and
# those of each variable APP_LIBS names, as paths from here.
app-libs:
	@echo $(ULIB) $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) $(foreach v,$(APP_LIBS),$($(v)))

# DOC_GAPS without the forms documented since, or gone: it only shrinks.
doc-prune: $(BUILD)/l0sdoc
	$(BUILD)/l0sdoc --prune $(DOC_GAPS) $(DOC_SRCS) $(PROG_DOC_SRCS) > $(BUILD)/undocumented.txt
	mv $(BUILD)/undocumented.txt $(DOC_GAPS)

# The MCP server's Python, with the SDK its requirements name.
MCP_VENV := $(BUILD)/mcp/venv
$(MCP_VENV)/.installed: tools/l0s-mcp/requirements.txt
	python3 -m venv $(MCP_VENV)
	$(MCP_VENV)/bin/pip install -q -r tools/l0s-mcp/requirements.txt
	touch $@

mcp: $(MCP_VENV)/.installed

# The API proxy's Python, with aiohttp, as the MCP server's; the token a
# board gives it, 32 random hex digits made once, readable by no one
# else; and the proxy run with them, on PROXY_LISTEN. PROXY_VENV is
# set above, where its tests are.
$(PROXY_VENV)/.installed: tools/api-proxy/requirements.txt
	python3 -m venv $(PROXY_VENV)
	$(PROXY_VENV)/bin/pip install -q --disable-pip-version-check -r tools/api-proxy/requirements.txt
	touch $@

$(BUILD)/proxy/token:
	@mkdir -p $(@D)
	@umask 077 && python3 -I -c 'import secrets; print(secrets.token_hex(16))' > $@.new && mv $@.new $@
	@echo "make proxy: a new token in $@"

# The strikes and icons too, which the builder's sessions preview apps
# with (l0s-app-preview).
proxy: $(PROXY_VENV)/.installed $(BUILD)/proxy/token $(STRIKES) $(ICON_FACE)

# The agent's etc for a board: build/agent-etc/config, naming the proxy
# at API, HOST:PORT, and the model if MODEL names one, and the boards'
# token beside it. While it is there, the demo's initramfs and the
# Pi 5's take it as /etc/agent (stage_agent), and install carries it
# onto a system volume with the rest of /etc. rm -rf build/agent-etc
# leaves it out again.
AGENT_ETC := $(BUILD)/agent-etc
agent-etc: $(BUILD)/proxy/token
	@test -n "$(API)" || { echo 'make agent-etc: API=HOST:PORT names the proxy, such as API=10.0.2.2:8765'; exit 1; }
	@rm -rf $(AGENT_ETC) && mkdir -p $(AGENT_ETC)
	@{ echo '# made by make agent-etc: the proxy, and the model'; echo 'api $(API)'; \
	   if [ -n '$(MODEL)' ]; then echo 'model $(MODEL)'; fi; } > $(AGENT_ETC)/config
	@cp $(BUILD)/proxy/token $(AGENT_ETC)/token
	@echo "make agent-etc: $(AGENT_ETC), api $(API)$(if $(MODEL), and model $(MODEL)); make initramfs or pi5-initramfs takes it as /etc/agent"
stage_agent = if [ -d $(AGENT_ETC) ]; then mkdir -p $(1)/agent && cp $(AGENT_ETC)/config $(AGENT_ETC)/token $(1)/agent/; fi

PROXY_LISTEN ?= 127.0.0.1:8765
proxy-run: proxy
	$(PROXY_VENV)/bin/python -I tools/api-proxy/proxy.py --listen $(PROXY_LISTEN) --token-file $(BUILD)/proxy/token --usage $(BUILD)/proxy/usage.jsonl --release $(BUILD)/release

# The releases the proxy serves (roadmap 0027): each board's system, as
# its initramfs holds it with /etc and the agent's etc, the Pi 5's boot
# files as pi5-release-card writes them, whose initramfs is only the
# first stage, the rest started from the system, the agent's seed, Whistle's speech
# model for both, and the Pi 5's bootloader image, pieeprom.bin. The
# model and the image are fetched once into build/fetch, each from a
# pinned commit and kept only if its SHA-256 is the one below, so every
# release has the same ones; a new pin changes both. WHISTLE_MODEL and
# PIEEPROM name files of your own instead, and nothing is fetched. The
# bootloader is 2026-10-30's, rpi-eeprom's newest, on which L0S has run
# since rp1_up sets the inbound window RP1's DMA uses, which it leaves
# 8 MB wide (roadmap 0064); 2026-05-26's ran before that. Its file is
# named for its version, so that a new pin is fetched, not an old one's
# file kept.
WHISTLE_COMMIT := 741118687e1f008f06d1351a402a731274789790
WHISTLE_URL    := https://huggingface.co/Cactus-Compute/whistle/resolve/$(WHISTLE_COMMIT)/whistle.cact
WHISTLE_SHA256 := b6e02f048568ac5d01a2042556c658061e699acbc0aa2a1439f52f3d461dffeb
PIEEPROM_COMMIT  := d5b79502fd59b5af411c6268652b5b1b6db74afb
PIEEPROM_VERSION := 2026-10-30
PIEEPROM_URL     := https://raw.githubusercontent.com/raspberrypi/rpi-eeprom/$(PIEEPROM_COMMIT)/firmware-2712/default/pieeprom-$(PIEEPROM_VERSION).bin
PIEEPROM_SHA256  := 251a27b235571c2f6ba0de254aff32f5fe0d6d5ed1af7429faee11d1f396c566
WHISTLE_MODEL ?= $(BUILD)/fetch/whistle.cact
PIEEPROM      ?= $(BUILD)/fetch/pieeprom-$(PIEEPROM_VERSION).bin

# fetch_pinned URL SHA256: the target fetched with curl, kept only if
# its SHA-256 is SHA256.
fetch_pinned = @mkdir -p $(@D) \
  && { command -v curl > /dev/null 2>&1 || { echo "fetch: curl is needed to fetch $(@F), once" >&2; exit 1; }; } \
  && echo "fetch: $(1)" && curl -fsSL -o $@.part $(1) \
  && { echo "$(2)  $@.part" | sha256sum -c --quiet - \
       || { rm -f $@.part; echo "fetch: $(@F) from $(1) is not the one pinned" >&2; exit 1; }; } \
  && mv $@.part $@

$(BUILD)/fetch/whistle.cact:
	$(call fetch_pinned,$(WHISTLE_URL),$(WHISTLE_SHA256))

$(BUILD)/fetch/pieeprom-$(PIEEPROM_VERSION).bin:
	$(call fetch_pinned,$(PIEEPROM_URL),$(PIEEPROM_SHA256))

# The voice speak speaks with (roadmap 0062): Piper's en_US-ljspeech-medium
# (LJSpeech, public domain), its config and model card, and CMUdict
# (BSD 2-clause), each at a pinned commit and kept only if its SHA-256 is
# the one below; probes/piper/README.md says what each is. PIPER_VOICE
# and CMUDICT name files of your own instead (the config is the voice's
# name with .json added), and nothing is fetched.
PIPER_COMMIT   := e7229f7d33a10e145e109b886d661984201ac3c4
PIPER_BASE     := https://huggingface.co/rhasspy/piper-voices/resolve/$(PIPER_COMMIT)/en/en_US/ljspeech/medium
PIPER_SHA256   := 6f52a751e2349abe7a76735eb09dc1875298c77ea2342ffd2fef79ff81b87f22
PIPER_JSON_SHA256 := 141d612cc0a95ed7efc1ca936b845c2364967f2e9217c5dbfcf69fc4d6c65860
PIPER_CARD_SHA256 := fbee1529c89d36b3fe76d7e9f3f832dce17f44900a52d76a9bda735654766b4d
CMUDICT_COMMIT := 74790861f652b15e4ac49015a90074ad62a27690
CMUDICT_BASE   := https://raw.githubusercontent.com/cmusphinx/cmudict/$(CMUDICT_COMMIT)
CMUDICT_SHA256 := 81917843c7f44ce2b094ac63873c2c7a4cf802040792c455ba3ca406891c3d22
CMUDICT_LICENSE_SHA256 := bd4ce8e44170a5f9f481310ca85c51de3c4f851a65e679b40e603b143bd3542a
PIPER_VOICE ?= $(BUILD)/fetch/en_US-ljspeech-medium.onnx
CMUDICT     ?= $(BUILD)/fetch/cmudict.dict

$(BUILD)/fetch/en_US-ljspeech-medium.onnx:
	$(call fetch_pinned,$(PIPER_BASE)/en_US-ljspeech-medium.onnx,$(PIPER_SHA256))

$(BUILD)/fetch/en_US-ljspeech-medium.onnx.json:
	$(call fetch_pinned,$(PIPER_BASE)/en_US-ljspeech-medium.onnx.json,$(PIPER_JSON_SHA256))

$(BUILD)/fetch/MODEL_CARD:
	$(call fetch_pinned,$(PIPER_BASE)/MODEL_CARD,$(PIPER_CARD_SHA256))

$(BUILD)/fetch/cmudict.dict:
	$(call fetch_pinned,$(CMUDICT_BASE)/cmudict.dict,$(CMUDICT_SHA256))

$(BUILD)/fetch/cmudict.LICENSE:
	$(call fetch_pinned,$(CMUDICT_BASE)/LICENSE,$(CMUDICT_LICENSE_SHA256))

# piper-fetch: the voice and the dictionary, for speak and its tests.
.PHONY: piper-fetch
piper-fetch: $(PIPER_VOICE) $(CMUDICT) $(BUILD)/fetch/en_US-ljspeech-medium.onnx.json $(BUILD)/fetch/MODEL_CARD $(BUILD)/fetch/cmudict.LICENSE

release: initramfs pi5-release-card release-apps $(WHISTLE_MODEL) $(PIEEPROM) $(PIPER_VOICE) $(PIPER_VOICE).json $(CMUDICT)
	APPS=$(RELEASE_APPS_ROOT) WHISTLE_MODEL=$(WHISTLE_MODEL) PIPER_VOICE=$(PIPER_VOICE) CMUDICT=$(CMUDICT) tools/mkrelease $(BUILD)/release/virt $(ROOT) $(BUILD)/etc demo/etc/agent
	APPS=$(RELEASE_APPS_ROOT) WHISTLE_MODEL=$(WHISTLE_MODEL) PIPER_VOICE=$(PIPER_VOICE) CMUDICT=$(CMUDICT) PIEEPROM=$(PIEEPROM) tools/mkrelease $(BUILD)/release/pi5 $(BUILD)/pi5-root $(BUILD)/pi5-etc pi5/etc/agent $(BUILD)/pi5-release-card

# The knowledge graph, which /graphify built first: graphify's own Python,
# as it wrote it down, rebuilds it with the L0 sources it cannot read.
GRAPHIFY_PY = $(shell cat graphify-out/.graphify_python 2> /dev/null)
graph:
	@test -n "$(GRAPHIFY_PY)" || { echo 'make graph: no graphify-out/; run /graphify once first'; exit 1; }
	PYTHONHASHSEED=0 $(GRAPHIFY_PY) tools/graphify-l0/rebuild.py .

graph-hook:
	tools/graphify-l0/install-hook

# demo/etc, the wallpaper at both scales, the face, the icons and the
# fonts, staged together as the archive's /etc.
ETC_DEPS := $(WALLPAPERS) $(FACE) $(ICON_FACE) $(IMAGE_FACES) $(ETC_FONTS) $(STRIKES)
stage_etc = cp $(WALLPAPERS) $(1)/ && cp $(FACE) $(1)/face && cp $(ICON_FACE) $(1)/icons \
            && mkdir -p $(1)/fonts && cp $(ETC_FONTS) $(STRIKES) $(1)/fonts/ \
            && mkdir -p $(1)/images && cp $(IMAGE_FACES) $(1)/images/

initramfs: images root $(ETC_DEPS)
	rm -rf $(BUILD)/etc && cp -R demo/etc $(BUILD)/etc
	$(call stage_etc,$(BUILD)/etc)
	@$(call stage_agent,$(BUILD)/etc)
	tools/mkinitramfs $(BUILD)/initramfs.cpio $(BUILD)/etc $(ROOT)

# What the screen and keyboard tests boot: tests/screen/etc, with the
# wallpaper, fonts and face as the demo has them, but no vt.
screen-initramfs: images root $(ETC_DEPS)
	rm -rf $(BUILD)/screen-etc && cp -R tests/screen/etc $(BUILD)/screen-etc
	$(call stage_etc,$(BUILD)/screen-etc)
	tools/mkinitramfs $(BUILD)/screen.cpio $(BUILD)/screen-etc $(ROOT)

# The same desktop on USB's keyboard and mouse, for tests/usb.sh, booted
# with QEMU_INPUT=usb.
usb-initramfs: images root $(ETC_DEPS)
	rm -rf $(BUILD)/usb-etc && cp -R tests/usb/etc $(BUILD)/usb-etc
	$(call stage_etc,$(BUILD)/usb-etc)
	tools/mkinitramfs $(BUILD)/usb.cpio $(BUILD)/usb-etc $(ROOT)

# What tests/vt.sh boots: the demo's etc, with tests/vt/etc/system over
# its own, so that two terminals run whatever the demo starts.
vt-initramfs: images root $(ETC_DEPS)
	rm -rf $(BUILD)/vt-etc && cp -R demo/etc $(BUILD)/vt-etc && cp tests/vt/etc/system $(BUILD)/vt-etc/system
	$(call stage_etc,$(BUILD)/vt-etc)
	tools/mkinitramfs $(BUILD)/vt.cpio $(BUILD)/vt-etc $(ROOT)

# What tests/disks.sh and tests/files.sh boot: tests/disks/etc, the
# screen tests' with the disk's driver and file server, with the
# wallpaper, fonts and face.
disks-initramfs: images root $(ETC_DEPS)
	rm -rf $(BUILD)/disks-etc && cp -R tests/disks/etc $(BUILD)/disks-etc
	$(call stage_etc,$(BUILD)/disks-etc)
	tools/mkinitramfs $(BUILD)/disks.cpio $(BUILD)/disks-etc $(ROOT)

# What tests/installer.sh boots, once it has made @PORT@ in its
# agent/config the proxy's: tests/installer/etc, the disks test's with
# the network, staged as the screen tests' are.
installer-initramfs: images root $(ETC_DEPS)
	rm -rf $(BUILD)/installer-etc && cp -R tests/installer/etc $(BUILD)/installer-etc
	$(call stage_etc,$(BUILD)/installer-etc)

# What tests/agent.sh boots, once it has named its proxy's port in
# agent/config: tests/agent-screen/etc, the desktop with the disk, the
# network and agentd, staged as the screen tests' are.
agent-screen-initramfs: images root $(ETC_DEPS)
	rm -rf $(BUILD)/agent-screen-etc && cp -R tests/agent-screen/etc $(BUILD)/agent-screen-etc
	$(call stage_etc,$(BUILD)/agent-screen-etc)

# What tests/launcher-install.sh boots, and copies onto its disk's System
# volume to boot from: tests/launcher-install/etc, boot and the disk's
# driver and file server beside the compositor.
launcher-install-initramfs: images root $(ETC_DEPS)
	rm -rf $(BUILD)/launcher-install-etc && cp -R tests/launcher-install/etc $(BUILD)/launcher-install-etc
	$(call stage_etc,$(BUILD)/launcher-install-etc)
	tools/mkinitramfs $(BUILD)/launcher-install.cpio $(BUILD)/launcher-install-etc $(ROOT)

# The boot cases, then the screen tests, each E2E_JOBS at once (half
# this machine's CPUs unless set; E2E_JOBS=1 runs one at a time). mkfs
# is built first, as the tests that make disks would each build it. The
# screen tests are listed longest first, so the last to start are short.
SCREEN_TESTS := vt files launch responsive disks-create resize logo-menu procmon disks launcher launcher-install \
                installer agent fontview partitions usb fat hidpi widgets keyboard gpu-screen todo

e2e: images root initramfs screen-initramfs usb-initramfs vt-initramfs disks-initramfs launcher-install-initramfs installer-initramfs agent-screen-initramfs $(BUILD)/mkfs $(PROXY_VENV)/.installed
	tests/e2e.sh
	tests/screens.sh $(SCREEN_TESTS)

boot: images root $(DISK) $(SD)
	tools/mkinitramfs $(BUILD)/boot.cpio $(ETC) $(ROOT)
	L0_QEMU_ARGS="$(DEVICES) $(DISK_DEVICE) $(SD_DEVICE) $(NET_DEVICE)" $(L0) boot $(BUILD)/kernel.img < $(BUILD)/boot.cpio

# The SD card's image, blank, a sparse file: made once, and kept.
$(SD): | $(BUILD)
	dd if=/dev/zero of=$@ bs=1048576 count=0 seek=256 2> /dev/null

# The disk: made once, and never again while it is there, so that what is
# written to it stays from one boot to the next. make clean resets it. A
# disk made before L0FS's version 2, which has directories, is older than
# the stamp, and is made again, once.
$(BUILD)/disk-l0fs-2: | $(BUILD)
	touch $@

$(DISK): $(BUILD)/disk-l0fs-2
	tools/mkdisk $@

# The system disk: 64 MB, with System, the initramfs copied onto it, and
# data, empty; its System's UUID, which root= names, in system.uuid. Made
# anew every time, from the initramfs as it is now.
sysdisk: initramfs $(BUILD)/mkfs
	tools/mkdisk $(SYSDISK) 131072 System:40:110000:$(BUILD)/initramfs.cpio data:110040:20998 > $(BUILD)/system.vols
	awk '$$1 == "System" { print $$2 }' $(BUILD)/system.vols > $(SYSUUID)
	@echo "System is $$(cat $(SYSUUID)): make demo-system boots from it"

demo: initramfs $(DISK) $(SD)
	@echo "Booting L0S. Type help; exit stops the system, Ctrl-A x quits QEMU."
	@GPU=$(GPU) QEMU_INPUT=usb QEMU_USB="tablet $(QEMU_USB)" QEMU_DISPLAY=$(QEMU_DISPLAY) QEMU_GPU=$(GPU_OPTS) QEMU_DISK=$(DISK) QEMU_SD=$(SD) QEMU_NET=$(NET) QEMU_APPEND="$(if $(ROOT_UUID),root=$(ROOT_UUID))" \
	  tools/qemu-boot.sh $(BUILD)/initramfs.cpio; echo "L0S stopped, status $$?"

# The Pi 5 as demo is QEMU: build its TFTP root without the display
# driver and the sound driver after it (PI5_SHELL_NO), check that dnsmasq serves it, and open
# /dev/ttyUSB0 (PI5_SERIAL) in picocom to type to the shell once the
# board is power-cycled; Ctrl-A Ctrl-X quits. PI5_ARGS=debug as for
# tools/pi5-boot.
.PHONY: pi5-shell
PI5_SHELL_NO ?= /sbin/hvs /sbin/hdmi-audio
pi5-shell:
	@PI5_NO="$(PI5_SHELL_NO)" tools/pi5-boot --console

# The demo booted from the system disk, its System volume /: made anew
# from the initramfs as it is now, so what was written to it goes.
demo-system: sysdisk
	@echo "Booting L0S from System, $$(cat $(SYSUUID)). Type help; exit stops the system, Ctrl-A x quits QEMU."
	@GPU=$(GPU) QEMU_INPUT=usb QEMU_USB="tablet $(QEMU_USB)" QEMU_DISPLAY=$(QEMU_DISPLAY) QEMU_GPU=$(GPU_OPTS) QEMU_DISK=$(SYSDISK) QEMU_NET=$(NET) QEMU_APPEND="root=$$(cat $(SYSUUID))" \
	  tools/qemu-boot.sh $(BUILD)/initramfs.cpio; echo "L0S stopped, status $$?"

# The Raspberry Pi 5, which nothing here can boot: the kernel built for
# it, its initramfs, every program with pi5/etc, and the files its SD
# card's boot partition needs, in build/pi5-card: the board's device
# trees (below), and what l0 card writes, the image, config.txt,
# cmdline.txt (the boot arguments PI5_ARGS, as debug or root=UUID) and the
# initramfs. The firmware itself is in the Pi 5's EEPROM, so copied onto
# a FAT32 partition, they are all a card needs. The programs are the same
# images as on QEMU.
#
# The kernel's heap keeps a record of every page it gives, about 285
# bytes a page, 72 MB for each GB, and every page past its heap and stack
# is the frame pool processes are made of, so the heap is sized to the
# board: PI5_RAM_GB, 2 by default, the least a Pi 5 has, gets 64 MB (as
# QEMU's, the initramfs's copy and the rest) and 72 for each GB, at most
# the 1,008 the layout's 1,024 MB has beside the stack (spec 10.3). A 2
# GB board gets 208 MB, leaving about 1.8 GB to processes; a 16 GB one
# 1,008, records for about 13 GB given at once. A kernel built for less
# RAM than the board has runs out of heap once processes take more.
.PHONY: pi5-initramfs pi5-card pi5-stage1 pi5-release-card

PI5_ARGS            ?=
# Lines added to config.txt after l0 card's, as PI5_CONFIG=uart_2ndstage=1,
# the firmware's own log on the debug UART.
PI5_CONFIG          ?=
# Programs of pi5/etc/inittab's start lines left out of this build, as
# PI5_NO="/sbin/hvs /sbin/gem".
PI5_NO              ?=
PI5_RAM_GB          ?= 2
PI5_KERNEL_HEAP_MB  ?= $(shell r=$$(( 64 + 72 * $(PI5_RAM_GB) )); [ $$r -gt 1008 ] && r=1008; echo $$r)
PI5_KERNEL_STACK_MB ?= 16
PI5_KERNEL_LAYOUT   := --heap-mb $(PI5_KERNEL_HEAP_MB) --stack-mb $(PI5_KERNEL_STACK_MB)
L0_PI5RT := $(L0LIB)l0c $(wildcard $(L0LIB)pi5-aarch64/*.bc) $(L0LIB)pi5-aarch64/layout.ld

# The Pi kernel's layout options as last built, as kernel.layout is
# QEMU's, so that a new PI5_RAM_GB rebuilds it.
$(BUILD)/kernel-pi5.layout: FORCE | $(BUILD)
	@echo '$(PI5_KERNEL_LAYOUT)' | cmp -s - $@ || echo '$(PI5_KERNEL_LAYOUT)' > $@

$(BUILD)/kernel-pi5.img: $(KERNEL) kernel/main.l0 $(L0_PI5RT) $(BUILD)/kernel-pi5.layout | $(BUILD)
	$(L0) build --target pi5 $(PI5_KERNEL_LAYOUT) $(KERNEL) kernel/main.l0 -o $@

# The board's device trees, bcm2712-rpi-5-b.dtb for the C1 stepping and
# bcm2712d0-rpi-5-b.dtb for D0, which its firmware loads from the card or
# the TFTP root: fetched once into build/pi5-dtb from
# raspberrypi/firmware's boot/ at PI5_DTB_COMMIT, its stable branch on
# 2026-06-01 (kernel 6.18.33), the same bytes the board has booted with.
# Each is kept only if its SHA-256 is pi5/dtb.sha256's, so every build
# has the same ones; a new pin changes both. They are built from Linux's
# device tree sources, GPL-2.0 (boot/COPYING.linux beside them there),
# and go onto the board as they are. PI5_BOOT names another directory
# holding both, Raspberry Pi OS's boot partition or
# raspberrypi/firmware's boot/, and nothing is fetched.
PI5_BOOT       ?=
PI5_DTB_COMMIT := 12eeaa12865869b07db760f4bbb7507ec6f1976c
PI5_DTB_URL    := https://raw.githubusercontent.com/raspberrypi/firmware/$(PI5_DTB_COMMIT)/boot
PI5_DTB_NAMES  := bcm2712-rpi-5-b.dtb bcm2712d0-rpi-5-b.dtb
PI5_DTB_DIR    := $(if $(PI5_BOOT),$(PI5_BOOT),$(BUILD)/pi5-dtb)
PI5_DTBS       := $(addprefix $(PI5_DTB_DIR)/,$(PI5_DTB_NAMES))

$(BUILD)/pi5-dtb/%.dtb: pi5/dtb.sha256 | $(BUILD)
	@mkdir -p $(@D)
	@command -v curl > /dev/null 2>&1 || { echo "pi5-dtb: curl is needed to fetch $*.dtb, once" >&2; exit 1; }
	curl -fsSL -o $@.part $(PI5_DTB_URL)/$*.dtb
	@echo "$$(grep ' $*.dtb$$' pi5/dtb.sha256 | cut -d' ' -f1)  $@.part" | sha256sum -c --quiet - \
	  || { rm -f $@.part; echo "pi5-dtb: $*.dtb from $(PI5_DTB_URL) is not the one pi5/dtb.sha256 names" >&2; exit 1; }
	mv $@.part $@

# Given PI5_BOOT, its own device trees, and nothing fetched.
ifneq ($(PI5_BOOT),)
$(PI5_DTBS):
	@test -f $@ || { echo "pi5: no $(notdir $@) in $(PI5_BOOT)" >&2; exit 1; }
endif

# The Pi's initramfs holds its own boot files too, in /boot: the image,
# config.txt and cmdline.txt, as l0 card writes them, and the device
# trees, for install --boot to make a card's boot partition of, input.bin
# and all, from the system running. config.txt names input.bin and no
# size, so any will do; l0 card is given a byte of one, since with none
# it names none. The device trees go in first, so that l0 card finds
# them there and does not say the card lacks them.
pi5-initramfs: images root $(ETC_DEPS) $(CHIME) $(BUILD)/kernel-pi5.img $(PI5_DTBS)
	rm -rf $(BUILD)/pi5-etc && cp -R pi5/etc $(BUILD)/pi5-etc && cp $(CHIME) $(BUILD)/pi5-etc/chime.wav
	@for p in $(PI5_NO); do for f in inittab system; do grep -v "^start $$p\( \|$$\)" $(BUILD)/pi5-etc/$$f > $(BUILD)/pi5-etc/$$f.new; mv $(BUILD)/pi5-etc/$$f.new $(BUILD)/pi5-etc/$$f; done; echo "pi5-initramfs: not starting $$p"; done
	$(call stage_etc,$(BUILD)/pi5-etc)
	@$(call stage_agent,$(BUILD)/pi5-etc)
	rm -rf $(BUILD)/pi5-root && mkdir -p $(BUILD)/pi5-root/boot && cp -Rp $(ROOT)/. $(BUILD)/pi5-root/
	cp $(PI5_DTBS) $(BUILD)/pi5-root/boot/
	printf x | $(L0) card $(BUILD)/kernel-pi5.img $(BUILD)/pi5-root/boot
	rm -f $(BUILD)/pi5-root/boot/input.bin && chmod 644 $(BUILD)/pi5-root/boot/*
	tools/mkinitramfs $(BUILD)/pi5.cpio $(BUILD)/pi5-etc $(BUILD)/pi5-root

pi5-card: $(BUILD)/kernel-pi5.img pi5-initramfs $(PI5_DTBS)
	rm -rf $(BUILD)/pi5-card && mkdir -p $(BUILD)/pi5-card
	cp $(PI5_DTBS) $(BUILD)/pi5-card/
	$(L0) card $(BUILD)/kernel-pi5.img $(BUILD)/pi5-card $(PI5_ARGS) < $(BUILD)/pi5.cpio
	@for c in $(PI5_CONFIG); do echo "$$c" >> $(BUILD)/pi5-card/config.txt; echo "pi5-card: config.txt says $$c"; done
	@echo "build/pi5-card: copy its files onto a FAT32 partition of an SD card for a Pi 5"

# The release's initramfs, the first stage alone: boot, and what mounts
# the system volume, uart, xhci, sdhci and fs, and usb-hid, as
# pi5/etc/inittab starts them, with /bin/sh for a rescue shell, and of
# /etc only the inittab,
# board, motd and pi5/stage1/system, which starts that shell if no volume
# is made /. Everything else, the other drivers among them, boot starts
# from the system volume's /etc/system, which the release's system/
# holds (make release). pi5-card keeps the whole system in its
# initramfs, for a board booted over the network with no card.
PI5_STAGE1      := /sbin/boot /sbin/uart /sbin/xhci /sbin/usb-hid /sbin/sdhci /sbin/fs /bin/sh
PI5_STAGE1_ETC  := inittab board motd

pi5-stage1: pi5-initramfs
	rm -rf $(BUILD)/pi5-stage1-root $(BUILD)/pi5-stage1-etc
	mkdir -p $(BUILD)/pi5-stage1-root/bin $(BUILD)/pi5-stage1-root/sbin $(BUILD)/pi5-stage1-etc
	$(foreach p,$(PI5_STAGE1),cp -p $(ROOT)$(p) $(BUILD)/pi5-stage1-root$(p) && ) true
	$(foreach f,$(PI5_STAGE1_ETC),cp $(BUILD)/pi5-etc/$(f) $(BUILD)/pi5-stage1-etc/ && ) cp pi5/stage1/system $(BUILD)/pi5-stage1-etc/
	tools/mkinitramfs $(BUILD)/pi5-stage1.cpio $(BUILD)/pi5-stage1-etc $(BUILD)/pi5-stage1-root

# The release's boot partition: as pi5-card's, but with the first
# stage's initramfs as input.bin.
pi5-release-card: $(BUILD)/kernel-pi5.img pi5-stage1 $(PI5_DTBS)
	rm -rf $(BUILD)/pi5-release-card && mkdir -p $(BUILD)/pi5-release-card
	cp $(PI5_DTBS) $(BUILD)/pi5-release-card/
	$(L0) card $(BUILD)/kernel-pi5.img $(BUILD)/pi5-release-card $(PI5_ARGS) < $(BUILD)/pi5-stage1.cpio
	@for c in $(PI5_CONFIG); do echo "$$c" >> $(BUILD)/pi5-release-card/config.txt; echo "pi5-release-card: config.txt says $$c"; done

# The same booted over the network: build/pi5-tftp, a TFTP server's root,
# holding what the Pi 5's bootloader fetches by TFTP once DHCP names the
# server: the card's files and the board's device tree. The Pi 5's
# firmware is in its EEPROM, so nothing else is fetched; its BOOT_ORDER
# must try the network (a 2 in it, as 0xf21 does). The bootloader looks
# in a directory named for the board's serial number unless its EEPROM
# says TFTP_PREFIX=1 with an empty TFTP_PREFIX_STR: PI5_TFTP_PREFIX is
# that directory, the 8 hex digits, or empty for the root. The device
# trees are the card's, as above.
.PHONY: pi5-netboot
PI5_TFTP_PREFIX ?=
PI5_TFTP        := $(BUILD)/pi5-tftp$(if $(PI5_TFTP_PREFIX),/$(PI5_TFTP_PREFIX))

pi5-netboot: pi5-card
	rm -rf $(BUILD)/pi5-tftp && mkdir -p $(PI5_TFTP)
	cp $(BUILD)/pi5-card/* $(PI5_TFTP)/
	@echo "$(PI5_TFTP): serve $(BUILD)/pi5-tftp as a TFTP root, with DHCP naming it (option 66), to a Pi 5 whose BOOT_ORDER tries the network"

# The netboot's root with the pinned bootloader's update in it too,
# pieeprom.upd and pieeprom.sig (tools/mkeeprom), its own configuration
# with BOOT_ORDER=EEPROM_ORDER, timed now: a board that boots from it
# flashes that bootloader, as one whose bootloader L0S cannot drive
# needs. make pi5-netboot, which tools/pi5-boot runs, leaves them out
# again, so it is flashed once; tools/pi5-boot --no-build serves them.
.PHONY: pi5-eeprom
EEPROM_ORDER ?= 0xf21
pi5-eeprom: pi5-netboot $(BUILD)/mkeeprom $(PIEEPROM)
	$(BUILD)/mkeeprom $(PIEEPROM) $(PI5_TFTP) $$(date +%s) $(EEPROM_ORDER)
	@echo "$(PI5_TFTP): serve it with tools/pi5-boot --no-build; the board flashes the $(PIEEPROM_VERSION) bootloader as it boots"

clean:
	rm -rf $(BUILD)
