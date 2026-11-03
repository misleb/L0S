# 0066: The agent shows images: a build's previews as it builds

Track: Agent · Status: done · Needs: 0049 (met), 0065 (met) · Spec: agent.md, network.md, toolkit.md, programs.md, testing.md

## Why

`build_app` (0045, 0065) has the host's session preview an app's
scenes as PNGs before it builds, but the person sees only its progress
lines: the pictures stay on the host. The Agent app has an Images pane
beside Tools for them, and the agent protocol a notice to show one,
`agent image PATH`, but `agentd` sends none (agent.md's Limits). The
model cannot show the person an image either.

## Done when

- While a build runs, each scene the session previews reaches the
  board, is written into the home under `previews/NAME/`, and is
  told to every open port as `agent image PATH`, so the Images pane
  shows it as it comes.
- The model can show the person a PNG in the home with a tool.
- A window that opens later is told of the images shown before.
- A test drives a build with the stand-in builder and sees the notices
  and the files.

## Steps

- [x] Reading PNGs on the board: `format/inflate.l0` (zlib and DEFLATE)
  and `format/png_read.l0` (8-bit gray, RGB, palette and alpha, every
  filter, `png_fit` to a box), checked against the host's zlib and
  Pillow.
- [x] The Images pane: the Agent app's side pane toggles between Tools
  and Images; `agent image PATH` adds an image, read a reply at a time
  from its file server and decoded as idle work, shown fitted
  (`UiPicture`), with buttons to the one before and after.
- [x] The builder sends each new preview in its stream: the proxy's
  `POST /build` events gain `preview` (the scene's name and its PNG,
  recompressed and base64), found at the session's next line after it
  is painted; the proxy's tests with the stand-in builder.
- [x] `agentd` writes each into the home, `previews/NAME/SCENE.png`,
  reading its base64 in place (`format/base64.l0`), and tells it as
  `agent image`; the `agent_build` case sees the notice and the file.
- [x] The image notices kept in the conversation, so `open` tells a
  window that opens later of them: `Conv`'s images, its newest 64, in
  the kept file's `images`, kept through compaction, told after the
  turns.
- [x] A `show_image` tool, a path in the home, told as `agent image`;
  `agent_build` shows the preview with it and is refused on the
  program.
- [x] The Agent app's screen test showing one: `tests/agent.sh`.

## Spec changes

All moved into spec/.

## Log

- 2026-11-03: PNG reading and the Images pane in, with the notice in
  the protocol; then a build's previews streamed to the board and told,
  so the pane shows each scene as the session paints it. Then the
  images kept in the conversation and told on open, show_image, and
  tests/agent.sh: done.
