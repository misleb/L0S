# 0017: Find programs and apps without walking the whole of `/`

Track: Storage · Status: done · Needs: – · Spec: boot.md, programs.md, testing.md

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

- [x] `program_paths` in `paths.l0`: on a system volume, a listing of
  `/bin`, `/sbin`, `/Applications` and each bundle in it, a level each;
  the initramfs's `entry_paths` while `/` is it. `program_found` finds
  a program by a path outside them by asking `fs` (`path_elsewhere`).
  The shell's `run` and unknown words, and `init`, look among
  `program_paths`; `app_program_path` finds an app's program the same
  way.
- [x] Nothing else that looks walks: `app_bundles` is a listing of
  `/Applications` (`app_dirs_now`); the shell no longer lists `/` as it
  starts, and a file command takes `/`'s paths only for `ls` with no
  path, or while `/` is the initramfs (`file_names`).
- [x] A test: `tests/e2e/rootboot_full`, a System holding 24,000 other
  files (a new `filler` file of `tests/e2e.sh`), on which twenty
  commands are all answered before a background `nap 10000` ends. With
  the walk each took about 2 s, and `nap`'s line came after the fifth.

## Spec changes

None left: boot.md says what `program_paths` lists and that only `ls`
with no path and `install` walk `/`; programs.md's `paths.l0` row names
`program_paths`; testing.md has `filler` and `rootboot_full`.

## Log

- 2026-10-27: written while paging `list`, from the Pi 5's card, whose
  `overlays/` hung Files: Files no longer lists every folder in the
  place it shows to count it, but `root_paths` still walks `/`.
- 2026-10-29: done. Timed on the board, a walk of a System of 24,686
  paths took 1.8 to 2.2 s; `rootboot_full` with the old shell took 40 s
  and put `nap`'s line in the middle of its commands, and with
  `program_paths` 18 s, every command answered first. `ls` with no path
  still lists every file of `/`, a walk by what it asks, and `install`
  copies them all.
