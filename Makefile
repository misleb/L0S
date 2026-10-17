# L0S -- build, test, and boot the microkernel and its programs.
#
#   make test        host tests of everything: l0 test on this machine
#   make test-virt   the kernel's tests on QEMU's virt board
#   make e2e         every case of tests/e2e booted under the kernel
#   make all         all three, after type checking
#   make initramfs   build/initramfs.cpio: every program, demo/etc, and
#                    the splash screen as /etc/splash.ppm
#   make demo        boot it to the shell, on this terminal: type help;
#                    the splash shows in QEMU's window, and build/disk.img
#                    is the disk, made once, so what is written to it stays
#   make demo SPLASH=picture.ppm        the same, showing another P6 PPM
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
DISK_DEVICE  := -drive file=$(DISK),if=none,format=raw,id=disk0 -device virtio-blk-device,drive=disk0

COMMON := common/abi.l0 common/initramfs.l0
KERNEL := $(COMMON) common/queue.l0 kernel/memory.l0 kernel/mounts.l0 kernel/ipc.l0 kernel/inittab.l0 \
          kernel/sched.l0 kernel/pids.l0 kernel/syscall.l0 kernel/process.l0 kernel/kernel.l0
ULIB   := common/abi.l0 common/initramfs.l0 common/queue.l0 user/lib/l0s.l0 user/lib/tty.l0 user/lib/virtio.l0

# Libraries only some programs link, as LIBS_NAME: drawing, which would
# otherwise clash with the shell's own commands.
RENDER  := user/lib/render.l0
DISPLAY := user/lib/display.l0
WMLIB   := user/lib/wm.l0
CLOCK   := user/lib/clock.l0
DISKLIB := user/lib/disk.l0
L0FS    := user/lib/l0fs.l0
FSLIB   := user/lib/fs.l0

# The toolkit, user/lib/ui: its look, widgets, and the desktop's drawing
# commands, which need only render.l0; and its client windows, which need
# the compositor's protocol too.
UI_CORE   := user/lib/ui/theme.l0 user/lib/ui/icons.l0 user/lib/ui/paint.l0 user/lib/ui/widget.l0 \
             user/lib/ui/grid.l0 user/lib/ui/panes.l0 user/lib/ui/draw_cmd.l0
UI_WINDOW := user/lib/ui/window.l0
UI_TESTS  := theme icons paint widget grid panes draw_cmd

LIBS_virtio-gpu := $(RENDER)
LIBS_rtc        := $(CLOCK)
LIBS_wm         := $(RENDER) $(DISPLAY) $(UI_CORE) $(CLOCK)
LIBS_vt         := $(RENDER) $(WMLIB) $(UI_CORE)
LIBS_draw       := $(RENDER) $(UI_CORE)
LIBS_windows    := $(WMLIB)
LIBS_widgets    := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW)
LIBS_procmon    := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW)
LIBS_disk       := $(DISKLIB)
LIBS_fs         := $(DISKLIB) $(L0FS) $(FSLIB)
LIBS_sh         := $(FSLIB) user/sh/files.l0
LIBS_disks      := $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) $(DISKLIB) $(L0FS) $(FSLIB)

PROGRAMS := sh uart init hello echo ping spin nap rtc cat virtio-gpu draw virtio-input keys vt wm windows widgets procmon \
            virtio-blk disk fs disks
MKSPLASH := tools/mksplash/mksplash.l0
L0SDOC   := tools/l0sdoc/l0sdoc.l0
MKFS     := common/abi.l0 $(L0FS) tools/mkfs/mkfs.l0
IMAGES   := $(PROGRAMS:%=$(BUILD)/bin/%.img)

# Every library, which make doc reads the documentation of.
DOC_SRCS := common/abi.l0 common/initramfs.l0 common/queue.l0 $(filter-out $(COMMON) common/queue.l0,$(KERNEL)) \
            user/lib/l0s.l0 user/lib/tty.l0 user/lib/virtio.l0 \
            $(RENDER) $(DISPLAY) $(WMLIB) $(CLOCK) $(DISKLIB) $(L0FS) $(FSLIB) $(UI_CORE) $(UI_WINDOW)

.PHONY: all check test test-virt e2e images initramfs screen-initramfs disks-initramfs boot demo clean sample doc mcp

all: check test test-virt e2e

check:
	$(L0) check $(KERNEL) kernel/main.l0
	$(foreach p,$(PROGRAMS),$(L0) check $(ULIB) $(LIBS_$(p)) user/$(p)/$(p).l0 user/$(p)/main.l0 && ) true
	$(L0) check $(MKSPLASH) tools/mksplash/main.l0
	$(L0) check $(L0SDOC) tools/l0sdoc/main.l0
	$(L0) check $(MKFS) tools/mkfs/main.l0

# An archive bsdtar makes, of bin/x, "hi", mode 0755: what the host tests
# of initramfs.l0 and of cat read.
sample:
	rm -rf $(BUILD)/sample && mkdir -p $(BUILD)/sample/bin
	printf hi > $(BUILD)/sample/bin/x && chmod 755 $(BUILD)/sample/bin/x
	cd $(BUILD)/sample && find . | LC_ALL=C sort | bsdtar -n --format newc -cf ../sample.cpio -T -

test: sample
	$(L0) test common/abi.l0 common/abi_test.l0
	$(L0) test $(COMMON) common/initramfs_test.l0
	$(L0) test common/abi.l0 common/queue.l0 common/queue_test.l0
	$(L0) test common/abi.l0 kernel/memory.l0 kernel/memory_test.l0
	$(L0) test common/abi.l0 kernel/mounts.l0 kernel/mounts_test.l0
	$(L0) test common/abi.l0 common/queue.l0 kernel/mounts.l0 kernel/ipc.l0 kernel/ipc_test.l0
	$(L0) test $(COMMON) kernel/inittab.l0 kernel/inittab_test.l0
	$(L0) test common/abi.l0 kernel/sched.l0 kernel/sched_test.l0
	$(L0) test common/abi.l0 kernel/pids.l0 kernel/pids_test.l0
	$(L0) test common/abi.l0 kernel/syscall.l0 kernel/syscall_test.l0
	$(L0) test $(KERNEL) kernel/asm.l0 kernel/kernel_test.l0
	$(L0) test $(ULIB) user/lib/l0s_test.l0
	$(L0) test $(ULIB) user/lib/virtio_test.l0
	$(L0) test $(ULIB) user/lib/tty_test.l0
	$(L0) test $(ULIB) $(RENDER) user/lib/render_test.l0
	$(L0) test $(ULIB) $(CLOCK) user/lib/clock_test.l0
	$(L0) test $(ULIB) $(DISKLIB) user/lib/disk_test.l0
	$(L0) test common/abi.l0 $(L0FS) user/lib/l0fs_test.l0
	$(L0) test $(ULIB) $(FSLIB) user/lib/fs_test.l0
	$(L0) test $(ULIB) $(LIBS_sh) user/sh/sh.l0 user/sh/files_test.l0
	$(foreach t,$(UI_TESTS),$(L0) test $(ULIB) $(RENDER) $(UI_CORE) user/lib/ui/$(t)_test.l0 && ) true
	$(L0) test $(ULIB) $(RENDER) $(WMLIB) $(UI_CORE) $(UI_WINDOW) user/lib/ui/window_test.l0
	$(foreach p,$(PROGRAMS),$(L0) test $(ULIB) $(LIBS_$(p)) user/$(p)/$(p).l0 user/$(p)/$(p)_test.l0 && ) true
	$(L0) test $(MKSPLASH) tools/mksplash/mksplash_test.l0
	$(L0) test $(L0SDOC) tools/l0sdoc/l0sdoc_test.l0
	$(L0) test $(MKFS) tools/mkfs/mkfs_test.l0
	python3 tools/l0s-mcp/test_board.py

test-virt:
	$(L0) test --target virt $(KERNEL) kernel/asm.l0 kernel/kernel_virt_test.l0

$(BUILD) $(BUILD)/bin:
	mkdir -p $@

$(BUILD)/kernel.img: $(KERNEL) kernel/main.l0 $(L0_VIRTRT) | $(BUILD)
	$(L0) build --target virt $(KERNEL) kernel/main.l0 -o $@

define PROGRAM_RULE
$(BUILD)/bin/$(1).img: user/$(1)/$(1).l0 user/$(1)/main.l0 $(ULIB) $(LIBS_$(1)) $(L0_PROCRT) | $(BUILD)/bin
	$(L0) build --target proc $(ULIB) $(LIBS_$(1)) user/$(1)/$(1).l0 user/$(1)/main.l0 -o $$@
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

initramfs: images $(SPLASH) $(FONT)
	rm -rf $(BUILD)/etc && cp -R demo/etc $(BUILD)/etc && cp $(SPLASH) $(BUILD)/etc/splash.ppm
	cp $(FONT) $(BUILD)/etc/font.txt
	tools/mkinitramfs $(BUILD)/initramfs.cpio $(BUILD)/etc $(IMAGES)

# What the screen and keyboard tests boot: tests/screen/etc, with the
# splash and font as the demo has them, but no vt.
screen-initramfs: images $(SPLASH) $(FONT)
	rm -rf $(BUILD)/screen-etc && cp -R tests/screen/etc $(BUILD)/screen-etc
	cp $(SPLASH) $(BUILD)/screen-etc/splash.ppm && cp $(FONT) $(BUILD)/screen-etc/font.txt
	tools/mkinitramfs $(BUILD)/screen.cpio $(BUILD)/screen-etc $(IMAGES)

# What tests/disks.sh boots: tests/disks/etc, the screen tests' with the
# disk's driver and file server, with the splash and font.
disks-initramfs: images $(SPLASH) $(FONT)
	rm -rf $(BUILD)/disks-etc && cp -R tests/disks/etc $(BUILD)/disks-etc
	cp $(SPLASH) $(BUILD)/disks-etc/splash.ppm && cp $(FONT) $(BUILD)/disks-etc/font.txt
	tools/mkinitramfs $(BUILD)/disks.cpio $(BUILD)/disks-etc $(IMAGES)

e2e: images initramfs screen-initramfs disks-initramfs
	tests/e2e.sh
	tests/gpu-screen.sh
	tests/keyboard.sh
	tests/vt.sh
	tests/widgets.sh
	tests/procmon.sh
	tests/disks.sh

boot: images $(DISK)
	tools/mkinitramfs $(BUILD)/boot.cpio $(ETC) $(IMAGES)
	L0_QEMU_ARGS="$(DEVICES) $(DISK_DEVICE)" $(L0) boot $(BUILD)/kernel.img < $(BUILD)/boot.cpio

# The disk: made once, and never again while it is there, so that what is
# written to it stays from one boot to the next. make clean resets it.
$(DISK): | $(BUILD)
	tools/mkdisk $@

demo: initramfs $(DISK)
	@echo "Booting L0S. Type help; exit stops the system, Ctrl-A x quits QEMU."
	@QEMU_DISPLAY=$(QEMU_DISPLAY) QEMU_DISK=$(DISK) tools/qemu-boot.sh $(BUILD)/initramfs.cpio; echo "L0S stopped, status $$?"

clean:
	rm -rf $(BUILD)
