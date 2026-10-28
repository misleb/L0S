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
#                    build/root, demo/etc, and the splash screen as
#                    /etc/splash.ppm
#   make demo        boot it to the shell, on this terminal: type help;
#                    the splash shows in QEMU's window, and build/disk.img
#                    is the disk, made once, so what is written to it stays;
#                    build/sd.img, blank until Disks formats it, the SD card;
#                    the keyboard and mouse are USB's, on a qemu-xhci, and
#                    the mouse moves relatively, so a click in QEMU's
#                    window grabs the host's pointer, and Ctrl-Alt-G
#                    (Ctrl-Option-G on macOS) lets it go
#   make demo SPLASH=picture.ppm        the same, showing another P6 PPM
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
#   make pi5-netboot [PI5_BOOT=DIR] [PI5_TFTP_PREFIX=SERIAL]
#                    build/pi5-tftp: the same, with the Pi 5's device
#                    trees, fetched once and checked, or from DIR, as a
#                    TFTP root it network boots from
#   make pi5-shell   pi5-netboot without hvs, then picocom on the Pi's
#                    serial line to type to its shell (tools/pi5-boot)
#   make -s doc [Q=...]  the libraries' documentation, as l0 doc gives
#                    L0's: every name, or Q a name, a file's stem or the
#                    end of its path, or text, in the programs' too
#   make doc-prune   take the forms documented since off DOC_GAPS, which
#                    make check holds every undocumented form to
#   make mcp         build/mcp/venv, the Python with the MCP SDK that
#                    .mcp.json runs tools/l0s-mcp in: the MCP server
#                    that boots and drives L0S for agents
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
# are rebuilt when l0 is updated, and take its runtime's changes.
L0LIB     := $(dir $(shell $(L0) spec --path))
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

# The splash screen the gpu driver shows, and where QEMU shows it: cocoa
# is macOS's window; sdl elsewhere (gtk is scaled on Wayland), none for no
# window.
SPLASH       ?= $(BUILD)/splash.ppm
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
# more than one, the kernel runs on CPU 0 and processes on the rest (spec
# 6.18). It is 1, since on QEMU more are no faster, and a boot that
# writes a disk a little slower (probes/smp/REQUEST-idle-cpus.md); make
# demo CPUS=4 for four. make test-virt boots each test on one CPU and
# then on VIRT_CPUS.
CPUS         ?= 1
VIRT_CPUS    ?= 4
export QEMU_CPUS ?= $(CPUS)
# make boot gives an etc both inputs: virtio's keyboard and tablet, and a
# qemu-xhci with a USB keyboard and mouse, as the demo's inittab drives.
DEVICES      := -smp $(CPUS) -device virtio-gpu-device$(if $(GPU_OPTS),$(comma)$(GPU_OPTS)) -device virtio-keyboard-device -device virtio-tablet-device \
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
          kernel/sched.l0 kernel/cpus.l0 kernel/pids.l0 kernel/syscall.l0 kernel/process.l0 kernel/kernel.l0 common/rp1.l0
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
# Sound: the audio protocol, its server's side, and WAV files.
AUDIOLIB := user/lib/proto/audio.l0
AUDIO_SERVER := $(AUDIOLIB) user/lib/proto/audio_server.l0
WAV     := user/lib/format/wav.l0
FSLIB   := user/lib/proto/fs.l0
APPLIB  := user/lib/proto/app.l0
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

# USB: its descriptors and requests, and the usb protocol, which the
# host controller's driver serves to the class drivers, over them; and
# the pci protocol, which the PCIe bus's server answers drivers with.
USBDESC := user/lib/format/usbdesc.l0
USBLIB  := $(USBDESC) user/lib/proto/usb.l0
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

# The toolkit, user/lib/ui: its look, widgets, and the desktop's drawing
# commands, which need only render.l0, and the font service's protocol
# and strikes, which its text is drawn from; and its client windows,
# which need the compositor's protocol too.
UI_CORE   := $(STRIKE) $(FONTLIB) user/lib/ui/theme.l0 user/lib/ui/icons.l0 user/lib/ui/face.l0 user/lib/ui/paint.l0 user/lib/ui/widget.l0 \
             user/lib/ui/grid.l0 user/lib/ui/panes.l0 user/lib/ui/entry.l0 user/lib/ui/draw_cmd.l0 \
             user/lib/ui/nav.l0 user/lib/ui/icon_view.l0 user/lib/ui/menu.l0
UI_WINDOW := user/lib/ui/window.l0
UI_TESTS  := theme icons face paint widget grid panes entry draw_cmd nav icon_view menu

LIBS_virtio-gpu := $(VIRTIO) $(RENDER) $(DISPLAY_SERVER)
LIBS_hvs        := $(VIRTIO) $(RENDER) $(DISPLAY_SERVER) $(MAILBOX)
LIBS_virtio-input := $(VIRTIO) $(KEYMAP)
LIBS_pcie       := $(PCILIB)
LIBS_xhci       := $(USBLIB) $(PCILIB) $(RP1)
LIBS_usb-hid    := $(USBLIB) $(KEYMAP)
LIBS_lsusb      := $(USBLIB)
LIBS_sdhci      := $(PCILIB) $(DISKLIB) $(UUIDLIB) $(FSLIB)
LIBS_virtio-blk := $(VIRTIO) $(DISKLIB) $(UUIDLIB) $(FSLIB)
LIBS_virtio-net := $(VIRTIO) $(NICLIB)
LIBS_gem        := $(NICLIB) $(MAILBOX) $(RP1)
LIBS_virtio-rng := $(VIRTIO) $(RANDOM)
LIBS_inet       := $(INETLIB) $(CLOCK)
LIBS_net        := $(INETLIB)
LIBS_tftp       := $(INETLIB)
LIBS_http       := $(INETLIB)
LIBS_uart       := $(TTY)
LIBS_rtc        := $(CLOCK) $(MAILBOX)
LIBS_eeprom     := $(CLOCK) $(MAILBOX) $(SHA256)
LIBS_hdmi-audio := $(AUDIO_SERVER) $(MAILBOX)
LIBS_play       := $(AUDIOLIB) $(WAV)
LIBS_wm         := $(RENDER) $(DISPLAY) $(UI_CORE) $(CLOCK) $(PATHS) $(APPLIB)
LIBS_vt         := $(TTY) $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) $(PATHS)
LIBS_init       := $(PATHS)
LIBS_boot       := $(PATHS)
LIBS_install    := $(PATHS)
LIBS_draw       := $(RENDER) $(WMLIB) $(UI_CORE)
LIBS_windows    := $(RECT) $(WMLIB)
LIBS_widgets    := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW)
LIBS_about      := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW)
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
$(foreach p,$(BIN),$(eval DIR_$(p) := user/bin/$(p)))
$(foreach p,$(SBIN),$(eval DIR_$(p) := user/sbin/$(p)))
$(foreach p,$(APPS),$(eval DIR_$(p) := user/apps/$(p)))
$(foreach p,$(APPS),$(eval BUNDLE_$(p) := $(notdir $(wildcard user/apps/$(p)/*.app))))
$(foreach p,$(APPS),$(eval ICON_$(p) := $(firstword $(wildcard user/apps/$(p)/$(BUNDLE_$(p))/icon.svg) user/apps/$(p)/$(BUNDLE_$(p))/icon.draw)))

# A program's own sources, SRCS_NAME: every .l0 in its directory but its
# main.l0 and its tests, NAME.l0 first; and its tests, TESTS_NAME, each
# run with all of them.
$(foreach p,$(PROGRAMS),$(eval SRCS_$(p) := $(DIR_$(p))/$(p).l0 \
    $(filter-out $(DIR_$(p))/$(p).l0 $(DIR_$(p))/main.l0 %_test.l0,$(wildcard $(DIR_$(p))/*.l0))))
$(foreach p,$(PROGRAMS),$(eval TESTS_$(p) := $(wildcard $(DIR_$(p))/*_test.l0)))

MKSPLASH := $(BASE) $(CLI) $(PPM) tools/mksplash/mksplash.l0
L0SDOC   := $(BASE) $(CLI) tools/l0sdoc/l0sdoc.l0
MKFS     := $(COMMON) $(CLI) $(PARTS) $(FAT) tools/mkfs/mkfs.l0
MKICON   := $(ULIB) $(RENDER) $(UI_CORE) $(SVG) tools/mkicon/mkicon.l0
MKICONS  := $(ULIB) $(RENDER) $(UI_CORE) $(SVG) tools/mkicons/mkicons.l0
MKWALLPAPER := $(ULIB) $(RENDER) $(SVG) tools/mkwallpaper/mkwallpaper.l0
MKFONT   := $(ULIB) $(RENDER) $(UI_CORE) $(RASTER) tools/mkfont/shape.l0 tools/mkfont/mkfont.l0
MKSTRIKE := $(ULIB) $(RENDER) $(GLYPHS) tools/mkstrike/mkstrike.l0
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

.PHONY: FORCE all check test check-each test-each test-virt test-virt-heap e2e images root initramfs screen-initramfs usb-initramfs vt-initramfs disks-initramfs launcher-install-initramfs boot demo demo-system sysdisk clean sample doc doc-prune mcp icon-sheet graph graph-hook

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
$(call l0_check,$(MKSPLASH) tools/mksplash/main.l0)
$(call l0_check,$(L0SDOC) tools/l0sdoc/main.l0)
$(call l0_check,$(MKFS) tools/mkfs/main.l0)
$(call l0_check,$(MKICON) tools/mkicon/main.l0)
$(call l0_check,$(MKFONT) tools/mkfont/main.l0)
$(call l0_check,$(MKSTRIKE) tools/mkstrike/main.l0)
$(call l0_check,$(MKICONS) tools/mkicons/main.l0)
$(call l0_check,$(MKWALLPAPER) tools/mkwallpaper/main.l0)

# That every form is documented, but those DOC_GAPS lists.
$(BUILD)/check/doc.ok: $(BUILD)/l0sdoc $(DOC_GAPS) $(DOC_SRCS) $(PROG_DOC_SRCS)
	@mkdir -p $(@D)
	@$(call logged,$(BUILD)/l0sdoc --check $(DOC_GAPS) $(DOC_SRCS) $(PROG_DOC_SRCS),the documentation check)
CHECKS += $(BUILD)/check/doc.ok

check:
	@$(MAKE) -s -k -j$(JOBS) check-each

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
$(call l0_test,$(BASE) kernel/cpus.l0 kernel/cpus_test.l0)
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
$(call l0_test,$(BASE) $(KEYMAP) user/lib/sys/keymap_test.l0)
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
$(call l0_test,$(ULIB) $(RANDOM) user/lib/proto/random_test.l0)
$(call l0_test,$(ULIB) $(USBLIB) user/lib/proto/usb_test.l0)
$(call l0_test,$(ULIB) $(PCILIB) user/lib/proto/pci_test.l0)
$(call l0_test,$(ULIB) $(PATHS) $(APPLIB) user/lib/proto/app_test.l0)
$(call l0_test,$(BASE) $(L0FS) user/lib/format/l0fs_test.l0)
$(call l0_test,$(BASE) $(FAT) user/lib/format/fat_test.l0)
$(call l0_test,$(BASE) $(PARTS) user/lib/format/mbr_test.l0)
$(call l0_test,$(BASE) $(UUIDLIB) user/lib/format/uuid_test.l0)
$(call l0_test,$(BASE) $(DNSLIB) user/lib/format/dns_test.l0)
$(call l0_test,$(BASE) $(USBDESC) user/lib/format/usbdesc_test.l0)
$(call l0_test,$(BASE) $(CRC32) user/lib/format/crc32_test.l0)
$(call l0_test,$(BASE) $(SHA256) user/lib/format/sha256_test.l0)
$(call l0_test,$(BASE) $(PARTS) user/lib/format/gpt_test.l0)
$(call l0_test,$(BASE) $(PPM) user/lib/format/ppm_test.l0)
$(call l0_test,$(BASE) $(PPM) $(QOI) user/lib/format/qoi_test.l0)
$(call l0_test,$(BASE) $(WAV) user/lib/format/wav_test.l0)
$(call l0_test,$(BASE) $(XML) user/lib/format/xml_test.l0)
$(foreach t,$(UI_TESTS),$(call l0_test,$(ULIB) $(RENDER) $(UI_CORE) user/lib/ui/$(t)_test.l0))
$(call l0_test,$(ULIB) $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) user/lib/ui/window_test.l0)
$(foreach p,$(PROGRAMS),$(foreach t,$(TESTS_$(p)),$(call l0_test,$(ULIB) $(LIBS_$(p)) $(SRCS_$(p)) $(t))))
$(call l0_test,$(MKSPLASH) tools/mksplash/mksplash_test.l0)
$(call l0_test,$(L0SDOC) tools/l0sdoc/l0sdoc_test.l0)
$(call l0_test,$(MKFS) tools/mkfs/mkfs_test.l0)
$(call l0_test,$(MKICON) tools/mkicon/mkicon_test.l0)
$(call l0_test,$(MKICONS) tools/mkicons/mkicons_test.l0)
$(call l0_test,$(MKWALLPAPER) tools/mkwallpaper/mkwallpaper_test.l0)
$(foreach t,shape mkfont,$(call l0_test,$(MKFONT) tools/mkfont/$(t)_test.l0))
$(call l0_test,$(MKSTRIKE) tools/mkstrike/mkstrike_test.l0)
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

# Every host test, and then how many passed in all, those run before
# among them. A failure is shown as it happens, and the count still given.
test:
	@$(MAKE) -s -k -j$(JOBS) test-each; st=$$?; \
	cat $(TESTS:.ok=.log) 2> /dev/null | awk '/^# [0-9]+ passed, [0-9]+ failed$$/ { p += $$2; f += $$4 } \
	  END { print "make test: " p " passed, " f " failed, of $(words $(TESTS)) files" }'; exit $$st

test-each: $(TESTS) $(BUILD)/test/l0s-mcp.ok $(BUILD)/test/graphify-l0.ok

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

$(BUILD)/splash.ppm: $(MKSPLASH) tools/mksplash/main.l0 | $(BUILD)
	$(L0) run $(MKSPLASH) tools/mksplash/main.l0 > $@.tmp && mv $@.tmp $@

# The same at scale 2, which the desktop shows on a large screen; none
# for a SPLASH of another's, which is shown at scale 2 as it is.
$(BUILD)/splash2x.ppm: $(MKSPLASH) tools/mksplash/main.l0 | $(BUILD)
	$(L0) run $(MKSPLASH) tools/mksplash/main.l0 -- 2 > $@.tmp && mv $@.tmp $@

$(BUILD)/l0sdoc: $(L0SDOC) tools/l0sdoc/main.l0 | $(BUILD)
	$(L0) build $(L0SDOC) tools/l0sdoc/main.l0 -o $@

# What tools/mkdisk partitions and formats a disk image with.
$(BUILD)/mkfs: $(MKFS) tools/mkfs/main.l0 | $(BUILD)
	$(L0) build $(MKFS) tools/mkfs/main.l0 -o $@

$(BUILD)/mkicon: $(MKICON) tools/mkicon/main.l0 | $(BUILD)
	$(L0) build $(MKICON) tools/mkicon/main.l0 -o $@

# The wallpaper, branding/wallpaper-dark.svg drawn as QOI by
# tools/mkwallpaper at 1920 by 1080, and at 3840 by 2160 for a 4K
# screen: /etc/wallpaper.qoi and /etc/wallpaper2x.qoi, which the
# display drivers show first and wm draws its desktop on.
WALLPAPERS := $(BUILD)/wallpaper.qoi $(BUILD)/wallpaper2x.qoi

$(BUILD)/mkwallpaper: $(MKWALLPAPER) tools/mkwallpaper/main.l0 | $(BUILD)
	$(L0) build $(MKWALLPAPER) tools/mkwallpaper/main.l0 -o $@

$(BUILD)/wallpaper.qoi: branding/wallpaper-dark.svg $(BUILD)/mkwallpaper
	$(BUILD)/mkwallpaper $< 1920 1080 $@.tmp && mv $@.tmp $@

$(BUILD)/wallpaper2x.qoi: branding/wallpaper-dark.svg $(BUILD)/mkwallpaper
	$(BUILD)/mkwallpaper $< 3840 2160 $@.tmp && mv $@.tmp $@

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
# Code Pro's regular and bold at 16, 32 and 64, which the font service
# keeps as it starts, staged with the fonts in /etc/fonts.
STRIKES := $(foreach h,16 32 64,$(BUILD)/strikes/code-$(h).strike $(BUILD)/strikes/code-bold-$(h).strike)

$(BUILD)/mkstrike: $(MKSTRIKE) tools/mkstrike/main.l0 | $(BUILD)
	$(L0) build $(MKSTRIKE) tools/mkstrike/main.l0 -o $@

$(BUILD)/strikes/code-bold-%.strike: $(BUILD)/mkstrike fonts/SourceCodePro-Bold.ttf
	@mkdir -p $(@D)
	$(BUILD)/mkstrike fonts/SourceCodePro-Bold.ttf $* $@.tmp && mv $@.tmp $@

$(BUILD)/strikes/code-%.strike: $(BUILD)/mkstrike fonts/SourceCodePro-Regular.ttf
	@mkdir -p $(@D)
	$(BUILD)/mkstrike fonts/SourceCodePro-Regular.ttf $* $@.tmp && mv $@.tmp $@

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
define STAGE_APP
mkdir -p $(ROOT)/Applications/$(BUNDLE_$(1)) && \
install -m 755 $(BUILD)/bin/$(1).img $(ROOT)/Applications/$(BUNDLE_$(1))/$(1) && \
install -m 644 $(DIR_$(1))/$(BUNDLE_$(1))/manifest $(ROOT)/Applications/$(BUNDLE_$(1))/manifest && \
install -m 644 $(BUILD)/icons/$(1).ppm $(ROOT)/Applications/$(BUNDLE_$(1))/icon.ppm && \
install -m 644 $(BUILD)/icons/$(1)2x.ppm $(ROOT)/Applications/$(BUNDLE_$(1))/icon2x.ppm && \
$(if $(filter %.svg,$(ICON_$(1))),install -m 644 $(BUILD)/icons/$(1).face $(ROOT)/Applications/$(BUNDLE_$(1))/icon.face,install -m 644 $(ICON_$(1)) $(ROOT)/Applications/$(BUNDLE_$(1))/icon.draw)
endef

root: $(IMAGES) $(ICONS) $(ICONS2X) $(IMAGES_FACE)
	rm -rf $(ROOT) && mkdir -p $(ROOT)/bin $(ROOT)/sbin $(ROOT)/Applications
	$(foreach p,$(BIN),install -m 755 $(BUILD)/bin/$(p).img $(ROOT)/bin/$(p) && ) true
	$(foreach p,$(SBIN),install -m 755 $(BUILD)/bin/$(p).img $(ROOT)/sbin/$(p) && ) true
	$(foreach p,$(APPS),$(call STAGE_APP,$(p)) && ) true

doc: $(BUILD)/l0sdoc
	@$(BUILD)/l0sdoc "$(Q)" $(DOC_SRCS) -- $(PROG_DOC_SRCS)

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

# The knowledge graph, which /graphify built first: graphify's own Python,
# as it wrote it down, rebuilds it with the L0 sources it cannot read.
GRAPHIFY_PY = $(shell cat graphify-out/.graphify_python 2> /dev/null)
graph:
	@test -n "$(GRAPHIFY_PY)" || { echo 'make graph: no graphify-out/; run /graphify once first'; exit 1; }
	PYTHONHASHSEED=0 $(GRAPHIFY_PY) tools/graphify-l0/rebuild.py .

graph-hook:
	tools/graphify-l0/install-hook

# demo/etc, the splash at both scales, and the face, staged together as
# the archive's /etc.
SPLASH2X := $(if $(filter $(BUILD)/splash.ppm,$(SPLASH)),$(BUILD)/splash2x.ppm)
ETC_DEPS := $(SPLASH) $(SPLASH2X) $(FACE) $(ICON_FACE) $(IMAGE_FACES) $(ETC_FONTS) $(STRIKES)
stage_etc = cp $(SPLASH) $(1)/splash.ppm && cp $(FACE) $(1)/face && cp $(ICON_FACE) $(1)/icons \
            && mkdir -p $(1)/fonts && cp $(ETC_FONTS) $(STRIKES) $(1)/fonts/ \
            && mkdir -p $(1)/images && cp $(IMAGE_FACES) $(1)/images/ \
            $(if $(SPLASH2X),&& cp $(SPLASH2X) $(1)/splash2x.ppm) \
            && cp $(WALLPAPERS) $(1)/
ETC_DEPS += $(WALLPAPERS)

initramfs: images root $(ETC_DEPS)
	rm -rf $(BUILD)/etc && cp -R demo/etc $(BUILD)/etc
	$(call stage_etc,$(BUILD)/etc)
	tools/mkinitramfs $(BUILD)/initramfs.cpio $(BUILD)/etc $(ROOT)

# What the screen and keyboard tests boot: tests/screen/etc, with the
# splash, font and face as the demo has them, but no vt.
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
# screen tests' with the disk's driver and file server, with the splash,
# font and face.
disks-initramfs: images root $(ETC_DEPS)
	rm -rf $(BUILD)/disks-etc && cp -R tests/disks/etc $(BUILD)/disks-etc
	$(call stage_etc,$(BUILD)/disks-etc)
	tools/mkinitramfs $(BUILD)/disks.cpio $(BUILD)/disks-etc $(ROOT)

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
SCREEN_TESTS := vt files disks-create resize logo-menu procmon disks launcher launcher-install \
                partitions usb fat hidpi widgets keyboard gpu-screen

e2e: images root initramfs screen-initramfs usb-initramfs vt-initramfs disks-initramfs launcher-install-initramfs $(BUILD)/mkfs
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
	@GPU=$(GPU) QEMU_INPUT=usb QEMU_DISPLAY=$(QEMU_DISPLAY) QEMU_GPU=$(GPU_OPTS) QEMU_DISK=$(DISK) QEMU_SD=$(SD) QEMU_NET=$(NET) QEMU_APPEND="$(if $(ROOT_UUID),root=$(ROOT_UUID))" \
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
	@GPU=$(GPU) QEMU_INPUT=usb QEMU_DISPLAY=$(QEMU_DISPLAY) QEMU_GPU=$(GPU_OPTS) QEMU_DISK=$(SYSDISK) QEMU_NET=$(NET) QEMU_APPEND="root=$$(cat $(SYSUUID))" \
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
.PHONY: pi5-initramfs pi5-card

PI5_ARGS            ?=
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
pi5-initramfs: images root $(ETC_DEPS) $(BUILD)/kernel-pi5.img $(PI5_DTBS)
	rm -rf $(BUILD)/pi5-etc && cp -R pi5/etc $(BUILD)/pi5-etc
	@for p in $(PI5_NO); do grep -v "^start $$p\( \|$$\)" $(BUILD)/pi5-etc/inittab > $(BUILD)/pi5-etc/inittab.new; mv $(BUILD)/pi5-etc/inittab.new $(BUILD)/pi5-etc/inittab; echo "pi5-initramfs: not starting $$p"; done
	$(call stage_etc,$(BUILD)/pi5-etc)
	rm -rf $(BUILD)/pi5-root && mkdir -p $(BUILD)/pi5-root/boot && cp -Rp $(ROOT)/. $(BUILD)/pi5-root/
	cp $(PI5_DTBS) $(BUILD)/pi5-root/boot/
	printf x | $(L0) card $(BUILD)/kernel-pi5.img $(BUILD)/pi5-root/boot
	rm -f $(BUILD)/pi5-root/boot/input.bin && chmod 644 $(BUILD)/pi5-root/boot/*
	tools/mkinitramfs $(BUILD)/pi5.cpio $(BUILD)/pi5-etc $(BUILD)/pi5-root

pi5-card: $(BUILD)/kernel-pi5.img pi5-initramfs $(PI5_DTBS)
	rm -rf $(BUILD)/pi5-card && mkdir -p $(BUILD)/pi5-card
	cp $(PI5_DTBS) $(BUILD)/pi5-card/
	$(L0) card $(BUILD)/kernel-pi5.img $(BUILD)/pi5-card $(PI5_ARGS) < $(BUILD)/pi5.cpio
	@echo "build/pi5-card: copy its files onto a FAT32 partition of an SD card for a Pi 5"

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

clean:
	rm -rf $(BUILD)
