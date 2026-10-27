# 0017: Find programs and apps without walking the whole of `/`

Track: Storage · Status: idea · Needs: – · Spec: boot.md, programs.md

## Why

When `/` is a system volume, `root_paths` (`user/lib/sys/paths.l0`)
lists every directory of it, a `list` each, to give every path there
is ([boot.md, Limits](../spec/boot.md#limits)). The shell asks it as it
starts and again for each file command, each `run` and each unknown
word; `init` asks it to start its jobs, and the app list
(`app_bundles`) to find the bundles. That costs a walk of the whole
volume each time, which grows with everything on it: a volume holding a
user's files, or a card's, makes every command slower. Listing a
directory is one level only, a page of entries a message, since `list`
gained FROM; this is about the callers that walk.

## Done when

- Finding a program or the apps lists only the directories that can
  hold them (`/bin`, `/sbin`, `/Applications` and a bundle's own), not
  the whole of `/`, and a test with a system volume full of other files
  shows the shell's commands no slower for them.

## Steps

## Spec changes

- boot.md: `root_paths` no longer said to list every directory of a
  system volume.

## Log

- 2026-10-27: written while paging `list`, from the Pi 5's card, whose
  `overlays/` hung Files: Files no longer lists every folder in the
  place it shows to count it, but `root_paths` still walks `/`.
