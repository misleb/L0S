# L0S -- build, test, and boot the microkernel and its programs.
#
#   make test        host tests of everything: l0 test on this machine
#   make test-virt   the kernel's tests on QEMU's virt board
#   make e2e         every case of tests/e2e booted under the kernel
#   make all         all three, after type checking
#   make initramfs   build/initramfs.cpio: every program, in /bin, /sbin
#                    and /Applications as make root stages them in
#                    build/root, demo/etc, and the splash screen as
#                    /etc/splash.ppm
#   make demo        boot it to the shell, on this terminal: type help;
#                    the splash shows in QEMU's window, and build/disk.img
#                    is the disk, made once, so what is written to it stays
#   make demo SPLASH=picture.ppm        the same, showing another P6 PPM
#   make demo ROOT_UUID=UUID            the same, booted with root=UUID:
#                    the volume of that partition, if fs mounts it and it
#                    holds L0S, is / (sbin/boot)
#   make sysdisk     build/system.img, a 64 MB disk: System, a copy of
#                    the initramfs, and data; System's UUID in
#                    build/system.uuid
#   make demo-system the demo booted from build/system.img's System,
#                    made anew
#   make boot ETC=tests/e2e/hello/etc   boot every program with that etc
#   make -s doc [Q=...]  the libraries' documentation, as l0 doc gives
#                    L0's: every name, or Q a name, a file's stem, or text
#   make mcp         build/mcp/venv, the Python with the MCP SDK that
#                    .mcp.json runs tools/l0s-mcp in: the MCP server
#                    that boots and drives L0S for agents
#
# Images for the board are linked in Docker, as l0 does when L0_VIRT_LD
# is unset.

L0     ?= l0
BUILD  := build

# The installed toolchain's compiler and runtimes, so that images are
# rebuilt when l0 is updated, and take its runtime's changes.
L0LIB     := $(dir $(shell $(L0) spec --path))
L0_VIRTRT := $(L0LIB)l0c $(wildcard $(L0LIB)virt/*.bc)
L0_PROCRT := $(L0LIB)l0c $(wildcard $(L0LIB)proc/*.bc)

# The splash screen the gpu driver shows, and where QEMU shows it: cocoa
# is macOS's window; gtk or sdl elsewhere, none for no window.
SPLASH       ?= $(BUILD)/splash.ppm
QEMU_DISPLAY ?= cocoa
DEVICES      := -device virtio-gpu-device -device virtio-keyboard-device -device virtio-tablet-device
DISK         := $(BUILD)/disk.img
SYSDISK      := $(BUILD)/system.img
SYSUUID      := $(BUILD)/system.uuid
DISK_DEVICE  := -drive file=$(DISK),if=none,format=raw,id=disk0 -device virtio-blk-device,drive=disk0

# common/: BASE, the ABI and text.l0's lists and strings, is pure and
# linked into everything, host tools too; COMMON adds the initramfs, and
# is in the kernel and every program.
BASE   := common/abi.l0 common/text.l0
COMMON := $(BASE) common/initramfs.l0
KERNEL := $(COMMON) common/queue.l0 kernel/memory.l0 kernel/mounts.l0 kernel/ipc.l0 kernel/inittab.l0 \
          kernel/sched.l0 kernel/pids.l0 kernel/syscall.l0 kernel/process.l0 kernel/kernel.l0
CLI    := user/lib/sys/cli.l0
ULIB   := $(COMMON) common/queue.l0 $(CLI) user/lib/sys/l0s.l0 user/lib/sys/server.l0

# A terminal's line editing, for the terminals; and the virtio-mmio
# transports and queues, for the virtio drivers.
TTY    := user/lib/sys/tty.l0
VIRTIO := user/lib/sys/virtio.l0

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
RECT    := user/lib/gfx/rect.l0
RENDER  := $(PPM) $(RECT) user/lib/gfx/render.l0
DISPLAY := user/lib/proto/display.l0
WMLIB   := user/lib/proto/wm.l0
CLOCK   := user/lib/proto/clock.l0
DISKLIB := user/lib/proto/disk.l0
FSLIB   := user/lib/proto/fs.l0
APPLIB  := user/lib/proto/app.l0
L0FS    := user/lib/format/l0fs.l0

# The partition table, GPT, and the UUIDs and CRC-32 it needs.
UUIDLIB := user/lib/format/uuid.l0
CRC32   := user/lib/format/crc32.l0
GPTLIB  := user/lib/format/gpt.l0
PARTS   := $(UUIDLIB) $(CRC32) $(GPTLIB)

# The toolkit, user/lib/ui: its look, widgets, and the desktop's drawing
# commands, which need only render.l0; and its client windows, which need
# the compositor's protocol too.
UI_CORE   := user/lib/ui/theme.l0 user/lib/ui/icons.l0 user/lib/ui/paint.l0 user/lib/ui/widget.l0 \
             user/lib/ui/grid.l0 user/lib/ui/panes.l0 user/lib/ui/entry.l0 user/lib/ui/draw_cmd.l0
UI_WINDOW := user/lib/ui/window.l0
UI_TESTS  := theme icons paint widget grid panes entry draw_cmd

LIBS_virtio-gpu := $(VIRTIO) $(RENDER)
LIBS_virtio-input := $(VIRTIO)
LIBS_virtio-blk := $(VIRTIO)
LIBS_uart       := $(TTY)
LIBS_rtc        := $(CLOCK)
LIBS_wm         := $(RENDER) $(DISPLAY) $(UI_CORE) $(CLOCK) $(PATHS) $(APPLIB)
LIBS_vt         := $(TTY) $(RENDER) $(WMLIB) $(UI_CORE) $(PATHS)
LIBS_init       := $(PATHS)
LIBS_boot       := $(PATHS)
LIBS_install    := $(PATHS)
LIBS_draw       := $(RENDER) $(WMLIB) $(UI_CORE)
LIBS_windows    := $(RECT) $(WMLIB)
LIBS_widgets    := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW)
LIBS_procmon    := $(PROCS) $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW)
LIBS_disk       := $(DISKLIB)
LIBS_fs         := $(DISKLIB) $(PARTS) $(L0FS) $(FSLIB) $(CLOCK)
LIBS_sh         := $(PROCS) $(PATHS) $(APPLIB)
LIBS_disks      := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) $(DISKLIB) $(PARTS) $(L0FS) $(FSLIB)

# The programs, found by where their directories are, which is where
# each goes in the initramfs: user/bin/NAME, a command, in /bin;
# user/sbin/NAME, a driver or a service, in /sbin; and user/apps/NAME,
# an app, in a bundle, /Applications/APP.app, whose source is the
# directory user/apps/NAME/APP.app, holding its manifest and its
# icon.draw, which tools/mkicon draws as its icon.ppm. BUNDLE_NAME is the
# bundle's name.
BIN      := $(notdir $(wildcard user/bin/*))
SBIN     := $(notdir $(wildcard user/sbin/*))
APPS     := $(notdir $(wildcard user/apps/*))
PROGRAMS := $(BIN) $(SBIN) $(APPS)
$(foreach p,$(BIN),$(eval DIR_$(p) := user/bin/$(p)))
$(foreach p,$(SBIN),$(eval DIR_$(p) := user/sbin/$(p)))
$(foreach p,$(APPS),$(eval DIR_$(p) := user/apps/$(p)))
$(foreach p,$(APPS),$(eval BUNDLE_$(p) := $(notdir $(wildcard user/apps/$(p)/*.app))))

# A program's own sources, SRCS_NAME: every .l0 in its directory but its
# main.l0 and its tests, NAME.l0 first; and its tests, TESTS_NAME, each
# run with all of them.
$(foreach p,$(PROGRAMS),$(eval SRCS_$(p) := $(DIR_$(p))/$(p).l0 \
    $(filter-out $(DIR_$(p))/$(p).l0 $(DIR_$(p))/main.l0 %_test.l0,$(wildcard $(DIR_$(p))/*.l0))))
$(foreach p,$(PROGRAMS),$(eval TESTS_$(p) := $(wildcard $(DIR_$(p))/*_test.l0)))

MKSPLASH := $(BASE) $(CLI) $(PPM) tools/mksplash/mksplash.l0
L0SDOC   := $(BASE) $(CLI) tools/l0sdoc/l0sdoc.l0
MKFS     := $(COMMON) $(CLI) $(PARTS) $(L0FS) tools/mkfs/mkfs.l0
MKICON   := $(ULIB) $(RENDER) $(UI_CORE) tools/mkicon/mkicon.l0
IMAGES   := $(PROGRAMS:%=$(BUILD)/bin/%.img)
ICONS    := $(APPS:%=$(BUILD)/icons/%.ppm)
ROOT     := $(BUILD)/root

# Every library, which make doc reads the documentation of: common's, the
# kernel's parts, and everything under user/lib.
LIB_SRCS := $(wildcard user/lib/*/*.l0)
DOC_SRCS := $(filter-out %_test.l0,$(wildcard common/*.l0)) $(filter-out $(COMMON) common/queue.l0,$(KERNEL)) \
            $(filter-out %_test.l0,$(LIB_SRCS))

.PHONY: all check test test-virt e2e images root initramfs screen-initramfs disks-initramfs boot demo demo-system sysdisk clean sample doc mcp

all: check test test-virt e2e

check:
	$(L0) check $(KERNEL) kernel/main.l0
	$(foreach p,$(PROGRAMS),$(L0) check $(ULIB) $(LIBS_$(p)) $(SRCS_$(p)) $(DIR_$(p))/main.l0 && ) true
	$(L0) check $(MKSPLASH) tools/mksplash/main.l0
	$(L0) check $(L0SDOC) tools/l0sdoc/main.l0
	$(L0) check $(MKFS) tools/mkfs/main.l0
	$(L0) check $(MKICON) tools/mkicon/main.l0

# An archive bsdtar makes, of bin/x, "hi", mode 0755: what the host tests
# of initramfs.l0 and of cat read.
sample:
	rm -rf $(BUILD)/sample && mkdir -p $(BUILD)/sample/bin
	printf hi > $(BUILD)/sample/bin/x && chmod 755 $(BUILD)/sample/bin/x
	cd $(BUILD)/sample && find . | LC_ALL=C sort | bsdtar -n --format newc -cf ../sample.cpio -T -

test: sample
	$(L0) test $(BASE) common/abi_test.l0
	$(L0) test $(BASE) common/text_test.l0
	$(L0) test $(COMMON) common/initramfs_test.l0
	$(L0) test $(BASE) common/queue.l0 common/queue_test.l0
	$(L0) test $(BASE) kernel/memory.l0 kernel/memory_test.l0
	$(L0) test $(BASE) kernel/mounts.l0 kernel/mounts_test.l0
	$(L0) test $(BASE) common/queue.l0 kernel/mounts.l0 kernel/ipc.l0 kernel/ipc_test.l0
	$(L0) test $(COMMON) kernel/inittab.l0 kernel/inittab_test.l0
	$(L0) test $(BASE) kernel/sched.l0 kernel/sched_test.l0
	$(L0) test $(BASE) kernel/pids.l0 kernel/pids_test.l0
	$(L0) test $(BASE) kernel/syscall.l0 kernel/syscall_test.l0
	$(L0) test $(KERNEL) kernel/asm.l0 kernel/kernel_test.l0
	$(L0) test $(BASE) $(CLI) user/lib/sys/cli_test.l0
	$(L0) test $(ULIB) user/lib/sys/l0s_test.l0
	$(L0) test $(ULIB) user/lib/sys/server_test.l0
	$(L0) test $(ULIB) $(PROCS) user/lib/sys/procs_test.l0
	$(L0) test $(ULIB) $(PATHS) user/lib/sys/paths_test.l0
	$(L0) test $(ULIB) $(VIRTIO) user/lib/sys/virtio_test.l0
	$(L0) test $(ULIB) $(TTY) user/lib/sys/tty_test.l0
	$(L0) test $(ULIB) $(RECT) user/lib/gfx/rect_test.l0
	$(L0) test $(ULIB) $(RENDER) user/lib/gfx/render_test.l0
	$(L0) test $(ULIB) $(CLOCK) user/lib/proto/clock_test.l0
	$(L0) test $(ULIB) $(DISKLIB) user/lib/proto/disk_test.l0
	$(L0) test $(ULIB) $(UUIDLIB) $(FSLIB) user/lib/proto/fs_test.l0
	$(L0) test $(ULIB) $(PATHS) $(APPLIB) user/lib/proto/app_test.l0
	$(L0) test $(BASE) $(L0FS) user/lib/format/l0fs_test.l0
	$(L0) test $(BASE) $(UUIDLIB) user/lib/format/uuid_test.l0
	$(L0) test $(BASE) $(CRC32) user/lib/format/crc32_test.l0
	$(L0) test $(BASE) $(PARTS) user/lib/format/gpt_test.l0
	$(L0) test $(BASE) $(PPM) user/lib/format/ppm_test.l0
	$(foreach t,$(UI_TESTS),$(L0) test $(ULIB) $(RENDER) $(UI_CORE) user/lib/ui/$(t)_test.l0 && ) true
	$(L0) test $(ULIB) $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) user/lib/ui/window_test.l0
	$(foreach p,$(PROGRAMS),$(foreach t,$(TESTS_$(p)),$(L0) test $(ULIB) $(LIBS_$(p)) $(SRCS_$(p)) $(t) && )) true
	$(L0) test $(MKSPLASH) tools/mksplash/mksplash_test.l0
	$(L0) test $(L0SDOC) tools/l0sdoc/l0sdoc_test.l0
	$(L0) test $(MKFS) tools/mkfs/mkfs_test.l0
	$(L0) test $(MKICON) tools/mkicon/mkicon_test.l0
	python3 tools/l0s-mcp/test_board.py

test-virt:
	$(L0) test --target virt $(KERNEL) kernel/asm.l0 kernel/kernel_virt_test.l0

$(BUILD) $(BUILD)/bin $(BUILD)/icons:
	mkdir -p $@

$(BUILD)/kernel.img: $(KERNEL) kernel/main.l0 $(L0_VIRTRT) | $(BUILD)
	$(L0) build --target virt $(KERNEL) kernel/main.l0 -o $@

define PROGRAM_RULE
$(BUILD)/bin/$(1).img: $(SRCS_$(1)) $(DIR_$(1))/main.l0 $(ULIB) $(LIBS_$(1)) $(L0_PROCRT) | $(BUILD)/bin
	$(L0) build --target proc $(ULIB) $(LIBS_$(1)) $(SRCS_$(1)) $(DIR_$(1))/main.l0 -o $$@
endef
$(foreach p,$(PROGRAMS),$(eval $(call PROGRAM_RULE,$(p))))

images: $(BUILD)/kernel.img $(IMAGES)

$(BUILD)/splash.ppm: $(MKSPLASH) tools/mksplash/main.l0 | $(BUILD)
	$(L0) run $(MKSPLASH) tools/mksplash/main.l0 > $@.tmp && mv $@.tmp $@

$(BUILD)/l0sdoc: $(L0SDOC) tools/l0sdoc/main.l0 | $(BUILD)
	$(L0) build $(L0SDOC) tools/l0sdoc/main.l0 -o $@

# What tools/mkdisk partitions and formats a disk image with.
$(BUILD)/mkfs: $(MKFS) tools/mkfs/main.l0 | $(BUILD)
	$(L0) build $(MKFS) tools/mkfs/main.l0 -o $@

$(BUILD)/mkicon: $(MKICON) tools/mkicon/main.l0 | $(BUILD)
	$(L0) build $(MKICON) tools/mkicon/main.l0 -o $@

# Each app's icon, drawn from its bundle's icon.draw. mkicon draws on the
# theme's colors, so an icon is drawn again when they change.
define ICON_RULE
$(BUILD)/icons/$(1).ppm: $(DIR_$(1))/$(BUNDLE_$(1))/icon.draw $(BUILD)/mkicon | $(BUILD)/icons
	$(BUILD)/mkicon $$< > $$@.tmp && mv $$@.tmp $$@
endef
$(foreach p,$(APPS),$(eval $(call ICON_RULE,$(p))))

# The initramfs's programs, staged in build/root as the archive holds
# them: /bin, /sbin, and each app's bundle, its program, manifest and
# icon. Made anew each time, so that a program that moves leaves nothing
# where it was.
define STAGE_APP
mkdir -p $(ROOT)/Applications/$(BUNDLE_$(1)) && \
install -m 755 $(BUILD)/bin/$(1).img $(ROOT)/Applications/$(BUNDLE_$(1))/$(1) && \
install -m 644 $(DIR_$(1))/$(BUNDLE_$(1))/manifest $(ROOT)/Applications/$(BUNDLE_$(1))/manifest && \
install -m 644 $(BUILD)/icons/$(1).ppm $(ROOT)/Applications/$(BUNDLE_$(1))/icon.ppm
endef

root: $(IMAGES) $(ICONS)
	rm -rf $(ROOT) && mkdir -p $(ROOT)/bin $(ROOT)/sbin $(ROOT)/Applications
	$(foreach p,$(BIN),install -m 755 $(BUILD)/bin/$(p).img $(ROOT)/bin/$(p) && ) true
	$(foreach p,$(SBIN),install -m 755 $(BUILD)/bin/$(p).img $(ROOT)/sbin/$(p) && ) true
	$(foreach p,$(APPS),$(call STAGE_APP,$(p)) && ) true

doc: $(BUILD)/l0sdoc
	@$(BUILD)/l0sdoc "$(Q)" $(DOC_SRCS)

# The MCP server's Python, with the SDK its requirements name.
MCP_VENV := $(BUILD)/mcp/venv
$(MCP_VENV)/.installed: tools/l0s-mcp/requirements.txt
	python3 -m venv $(MCP_VENV)
	$(MCP_VENV)/bin/pip install -q -r tools/l0s-mcp/requirements.txt
	touch $@

mcp: $(MCP_VENV)/.installed

# demo/etc, the splash, and the console font, staged together as the
# archive's /etc.
FONT := fonts/l0s-8x16.txt

initramfs: images root $(SPLASH) $(FONT)
	rm -rf $(BUILD)/etc && cp -R demo/etc $(BUILD)/etc && cp $(SPLASH) $(BUILD)/etc/splash.ppm
	cp $(FONT) $(BUILD)/etc/font.txt
	tools/mkinitramfs $(BUILD)/initramfs.cpio $(BUILD)/etc $(ROOT)

# What the screen and keyboard tests boot: tests/screen/etc, with the
# splash and font as the demo has them, but no vt.
screen-initramfs: images root $(SPLASH) $(FONT)
	rm -rf $(BUILD)/screen-etc && cp -R tests/screen/etc $(BUILD)/screen-etc
	cp $(SPLASH) $(BUILD)/screen-etc/splash.ppm && cp $(FONT) $(BUILD)/screen-etc/font.txt
	tools/mkinitramfs $(BUILD)/screen.cpio $(BUILD)/screen-etc $(ROOT)

# What tests/disks.sh boots: tests/disks/etc, the screen tests' with the
# disk's driver and file server, with the splash and font.
disks-initramfs: images root $(SPLASH) $(FONT)
	rm -rf $(BUILD)/disks-etc && cp -R tests/disks/etc $(BUILD)/disks-etc
	cp $(SPLASH) $(BUILD)/disks-etc/splash.ppm && cp $(FONT) $(BUILD)/disks-etc/font.txt
	tools/mkinitramfs $(BUILD)/disks.cpio $(BUILD)/disks-etc $(ROOT)

e2e: images root initramfs screen-initramfs disks-initramfs
	tests/e2e.sh
	tests/gpu-screen.sh
	tests/keyboard.sh
	tests/vt.sh
	tests/widgets.sh
	tests/procmon.sh
	tests/disks.sh
	tests/disks-create.sh
	tests/partitions.sh
	tests/launcher.sh

boot: images root $(DISK)
	tools/mkinitramfs $(BUILD)/boot.cpio $(ETC) $(ROOT)
	L0_QEMU_ARGS="$(DEVICES) $(DISK_DEVICE)" $(L0) boot $(BUILD)/kernel.img < $(BUILD)/boot.cpio

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

demo: initramfs $(DISK)
	@echo "Booting L0S. Type help; exit stops the system, Ctrl-A x quits QEMU."
	@QEMU_DISPLAY=$(QEMU_DISPLAY) QEMU_DISK=$(DISK) QEMU_APPEND="$(if $(ROOT_UUID),root=$(ROOT_UUID))" \
	  tools/qemu-boot.sh $(BUILD)/initramfs.cpio; echo "L0S stopped, status $$?"

# The demo booted from the system disk, its System volume /: made anew
# from the initramfs as it is now, so what was written to it goes.
demo-system: sysdisk
	@echo "Booting L0S from System, $$(cat $(SYSUUID)). Type help; exit stops the system, Ctrl-A x quits QEMU."
	@QEMU_DISPLAY=$(QEMU_DISPLAY) QEMU_DISK=$(SYSDISK) QEMU_APPEND="root=$$(cat $(SYSUUID))" \
	  tools/qemu-boot.sh $(BUILD)/initramfs.cpio; echo "L0S stopped, status $$?"

clean:
	rm -rf $(BUILD)
