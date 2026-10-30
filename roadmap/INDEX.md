# L0S roadmap

The [spec](../spec/README.md) says what L0S is. A goal here says what will
change, and changes the spec as its steps land. Goals in different tracks
move independently, so several can be active at once.

## How it works

- **A goal** is one file, `NNNN-slug.md`, numbered in the order written:
  Why, Done when, Steps (a checklist), Spec changes, Log. The template is
  at the end of this page.
- **Status**: `idea` (no steps yet), `ready` (has steps, Needs all met),
  `active` (being worked on), `blocked` (a Need is not met), `done`,
  `dropped`.
- **Progress** is ticked steps over all steps. An `idea` shows `–`.
- **Needs**: other goals by number, `L0 NNNN` (an item in L0's roadmap),
  or an open `probes/…/REQUEST-*.md`. Whatever a goal needs comes first.
- **Spec**: the pages it changes. A step that lands moves its part of
  Spec changes into those pages, in the same change, and ticks the step
  here and in the goal.
- **Picking what's next**: choose from Ready. An `idea` becomes `ready`
  once it has steps.

## Goals

| Goal | Track | Status | Progress | Needs | Spec |
|---|---|---|---|---|---|
| [0007](0007-viewports-subsurfaces.md) Source viewports and subsurfaces | Display | idea | – | – | display.md, desktop.md |
| [0008](0008-cursor-shapes.md) A cursor set and cursor shapes | Display | idea | – | – | display.md, desktop.md, toolkit.md |
| [0009](0009-alpha-layers.md) Alpha layers: shadows and smooth corners | Display | idea | – | – | display.md, desktop.md |
| [0010](0010-output-events.md) Output events for mode changes | Display | idea | – | – | display.md, desktop.md |
| [0013](0013-entry-editing.md) Entries that scroll, select, copy and paste | Toolkit | idea | – | 0012 | toolkit.md |
| [0018](0018-pi5-tftp-large.md) `tftp` fetches a file of megabytes on the Pi 5 | Network | idea | – | – | network.md |
| [0027](0027-installer.md) Installing L0S, a process of its own, with a GUI | Storage | idea | – | – | boot.md, pi5.md, programs.md, storage.md, testing.md |
| [0029](0029-settings-app.md) Settings, an app for the system's configuration | Desktop | idea | – | 0028, 0008, 0020 | programs.md, desktop.md, toolkit.md, network.md, boot.md, pi5.md, testing.md |
| [0030](0030-cpu-usage.md) How the CPUs are used, and what each process serves, in `ps` and System Monitor | Kernel | active | 5/6 | – | kernel.md, syscalls.md, programs.md, demo.md, testing.md |
| [0035](0035-apps-ask-not-wait.md) Disks and Files ask every server as a reply, not a wait | Toolkit | idea | – | 0033 | programs.md, toolkit.md |
| [0036](0036-files-copy-paste.md) Files copies, cuts and pastes | Desktop | idea | – | – | desktop.md, programs.md |
| [0037](0037-fs-serves-during-disk.md) `fs` serves other requests while a disk request is out | Storage | idea | – | – | storage.md |
| [0039](0039-paced-drawing-areas.md) Drawing areas paced too, and a resize that overlaps the restack | Toolkit | idea | – | – | toolkit.md, desktop.md |
| [0040](0040-paint-at-scale-2.md) Painting at scale 2 as fast as at scale 1 | Toolkit | idea | – | – | toolkit.md |
| [0041](0041-http-client-json-sse.md) An HTTP/1.1 client library, with JSON and server-sent events | Agent | idea | – | – | network.md, programs.md |
| [0042](0042-api-through-host-proxy.md) A model's API reached through a proxy on the host | Agent | idea | – | 0041 | network.md, testing.md |
| [0043](0043-agent-loop.md) `agentd`, an agent's loop and its tools on L0S | Agent | idea | – | 0042 | agent.md (new), programs.md, demo.md |
| [0044](0044-agent-home.md) The agent's home: its personality, its history, and a backup | Agent | idea | – | 0043 | agent.md, storage.md |
| [0045](0045-agent-builder-mcp.md) The agent builds programs for itself, through an MCP server on the host | Agent | idea | – | 0043 | agent.md, programs.md, testing.md |
| [0046](0046-agent-self-knowledge.md) The agent learns how it and L0S work | Agent | idea | – | 0045 | agent.md |
| [0047](0047-pi5-random.md) Randomness on the Pi 5 | Pi 5 | idea | – | – | devices.md, pi5.md |
| [0048](0048-tls-client.md) A TLS 1.3 client in L0 | Network | idea | – | 0041, 0047 | network.md, programs.md |
| [0049](0049-agent-chat-app.md) Talking to the agent from the desktop | Agent | idea | – | 0043 | agent.md, programs.md, desktop.md, testing.md |
| [0050](0050-hvs-crowded-lines.md) `hvs` at 4K: crowded lines and a whole-screen flash | Display | idea | – | 0038 | display.md |
| [0051](0051-wm-input-port.md) `wm` takes input on a port of its own, ahead of requests | Desktop | idea | – | – | desktop.md, programs.md |

## Ready

- [0030](0030-cpu-usage.md) How the CPUs are used, active: the
  kernel's counts, `cpu_usage` and `name_list`, `ps`, `names`, `uptime`
  and System Monitor's columns and bars done on QEMU; step 6 is the
  Pi 5's board run, `ps` and `uptime` there.

Every other goal left is an `idea`, without steps. On the display,
[0050](0050-hvs-crowded-lines.md) (crowded lines and the whole-screen
flash at 4K), [0039](0039-paced-drawing-areas.md) and
[0040](0040-paint-at-scale-2.md) follow from 0038's runs.

## Dependencies

```mermaid
graph LR
  0005[0005 HVS frame interrupts] --> 0006[0006 paced display queue]
  0038[0038 hvs at 4K] --> 0050[0050 crowded lines]
  0012[0012 key modifiers] --> 0013[0013 entry editing]
  0019[0019 font service] --> 0020[0020 proportional text]
  0023[0023 file data shared] --> 0024[0024 fs fair serving]
  0028[0028 chime and wallpaper] --> 0029[0029 Settings app]
  0008[0008 cursor shapes] --> 0029
  0020 --> 0029
  0021[0021 many windows] --> 0032[0032 apps launched one way]
  0032 --> 0033[0033 responsive app loop]
  0033 --> 0035[0035 apps ask, not wait]
  0031[0031 many ports] --> 0033
  0021 --> 0033
  0041[0041 HTTP, JSON, SSE] --> 0042[0042 API through a proxy]
  0042 --> 0043[0043 agentd]
  0043 --> 0044[0044 agent's home]
  0043 --> 0045[0045 builder MCP]
  0045 --> 0046[0046 self-knowledge]
  0043 --> 0049[0049 agent chat app]
  0041 --> 0048[0048 TLS client]
  0047[0047 Pi 5 random] --> 0048
```

## Done

| Goal | Track | Done |
|---|---|---|
| [0001](0001-pi5-stable.md) The Pi 5 boots reliably | Pi 5 | 2026-10-26 |
| [0002](0002-faster-with-more-cpus.md) More CPUs make L0S faster | Kernel | 2026-10-28 |
| [0003](0003-pi5-cpus.md) All four of the Pi 5's CPUs | Pi 5 | 2026-10-28 |
| [0004](0004-pi5-devices.md) USB and the SD card on the Pi 5 | Pi 5 | 2026-10-27 |
| [0005](0005-hvs-frame-interrupts.md) The HVS's end-of-frame interrupts | Display | 2026-10-29 |
| [0006](0006-paced-display-queue.md) A paced, pipelined display queue | Display | 2026-10-29 |
| [0011](0011-csd-complete.md) Client-side decorations: maximize and resize | Desktop | 2026-10-27 |
| [0012](0012-key-modifiers.md) Modifier state in `KeyEvent` | Desktop | 2026-10-28 |
| [0014](0014-wheel-across.md) Scrolling by the wheel across | Toolkit | 2026-10-29 |
| [0015](0015-proc-image-got.md) Proc images without `.bss`'s zeros | Tooling | 2026-10-26 |
| [0016](0016-pi5-eeprom-config.md) The Pi 5's boot config, read and changed from L0S | Pi 5 | 2026-10-27 |
| [0017](0017-paths-without-walking.md) Find programs and apps without walking the whole of `/` | Storage | 2026-10-29 |
| [0019](0019-font-service.md) A font service that caches rasterized glyphs | Toolkit | 2026-10-27 |
| [0020](0020-proportional-text.md) Proportional text where GNOME's is | Toolkit | 2026-10-28 |
| [0021](0021-many-windows.md) An app with many windows, its events told by window | Desktop | 2026-10-28 |
| [0022](0022-pi5-card-complete.md) `install --boot` writes all a Pi 5's card needs | Pi 5 | 2026-10-28 |
| [0023](0023-file-data-shared.md) File data through shared memory, in runs of 64 KB | Storage | 2026-10-27 |
| [0024](0024-fs-fair-serving.md) `fs` serves its clients fairly, small requests first | Storage | 2026-10-28 |
| [0025](0025-vt-scrollback-resize-tabs.md) Terminal keeps its scrollback, resizes, and has tabs | Desktop | 2026-10-27 |
| [0026](0026-font-service-limits.md) The font service lets strikes go, and knows who holds them | Toolkit | 2026-10-29 |
| [0028](0028-boot-chime-wallpaper.md) The chime as sound starts, the wallpaper as the screen does | Desktop | 2026-10-28 |
| [0031](0031-many-ports.md) A process waits on several ports, and lets a name go | Kernel | 2026-10-28 |
| [0032](0032-app-launch.md) Apps launched one way: a running app is asked, not started again | Desktop | 2026-10-28 |
| [0033](0033-responsive-app-loop.md) An app's loop that keeps its window answering | Toolkit | 2026-10-28 |
| [0034](0034-servers-wait-not-poll.md) Servers that wait for their time and their ports, not poll | Kernel | 2026-10-29 |
| [0038](0038-hvs-4k-wide-layers.md) `hvs` at 4K: wide windows, a pointer that keeps moving, and no stalls | Display | 2026-10-29 |

## Template

```markdown
# NNNN: Title

Track: … · Status: … · Needs: … · Spec: page.md, …

## Why

The problem, linking the spec's Limit it lifts if it lifts one.

## Done when

- Checkable outcomes, including the tests that show them.

## Steps

- [ ] One change each, that leaves `make check` and `make test` passing.

## Spec changes

What the spec will say once this is done, page by page. Each moves into
spec/ with the step that makes it true.

## Log

- YYYY-MM-DD: what happened.
```
