# 0044: The agent's home: its personality, its history, and a backup

Track: Agent · Status: done · Needs: 0043 · Spec: agent.md, network.md, programs.md, storage.md, testing.md

## Why

The model is stateless: what makes this agent itself is its files.
Kept in Claude Code's own conventions (rules in a `CLAUDE.md`, a
`memory/` of one fact a file with its frontmatter and a `MEMORY.md`
index, `skills/NAME/SKILL.md` each with a description read up front and
a body read when used), the personality can be read and changed on the
host from its card, backed up to git, and loaded into Claude Code to
compare how it behaves there.

An agent that rewrites its own memory and rules drifts, so every change
it makes has to be seen and undone.

## Done when

- The home's layout is fixed in `/Volumes/data/agent` (0043's), on a
  data volume so that it outlives a reinstall of the system volume,
  and `agentd` reads it in at
  the start of every conversation: rules and the memory index whole,
  skills by their descriptions, the rest on demand.
- A part of it the agent cannot change (its constitution, and the rules
  about its rules), which `agentd` refuses to write.
- Every write of the agent's to its home is kept in a history: what
  changed, when, and in which conversation, and any change can be
  undone from a shell.
- A backup of the home is copied to the host and back, and the host's
  copy opens in Claude Code as it is.

## Steps

- [x] **The home's layout, and what is read in.** A library,
  [sys/agenthome.l0](../user/lib/sys/agenthome.l0) (`AGENTHOME`,
  linked into `agentd` and `agent`), names the home's parts, in
  Claude Code's conventions so that a copy opens there as it is:
  `CLAUDE.md`, the rules (0043's); `CONSTITUTION.md`, the fixed part;
  `memory/MEMORY.md`, the memory's index, and `memory/NAME.md`, a fact
  each with its frontmatter; `.claude/skills/NAME/SKILL.md`, a skill
  each, its frontmatter's `name` and `description`; and `.history/`.
  At its start `agentd` makes what is missing of these (`memory/` with
  an index that says it is empty, `.claude/skills/`, `.history/`) and
  writes `CONSTITUTION.md` from `/etc/agent/CONSTITUTION.md` whenever
  the two differ, so the home's copy is always L0S's. The constitution
  L0S ships (`demo/etc/agent/`, `pi5/etc/agent/`) holds the rules about
  the rules: what the agent may change (its rules, memory and skills,
  through its file tools, so that each change is kept), what it may
  not (the constitution and the history), and how the memory and
  skills are kept. The default `CLAUDE.md` begins with
  `@CONSTITUTION.md` and `@memory/MEMORY.md`, Claude Code's imports.
  Each conversation's system prompt (`home_prompt`, pure) is the
  built-in part, then the constitution, the rules, the memory's index,
  each whole, then a line for each skill, its name and description and
  where its body is, read when it is used; the rest of the home is
  read on demand. Tests: the prompt of a home's parts compared as
  text; a skill's description from its frontmatter, and from a file
  with none; the setup's files made under `build/` on this host.
- [x] **The fixed part.** `home_fixed home path`, pure: the
  constitution, and `.history` and all in it. `write_file` and
  `make_dir` refuse such a path, saying it is fixed, before touching
  anything. Tests: each fixed path, its relative and `..` spellings, a
  path beside them that is not fixed, and the tools' refusals.
- [x] **The history.** Every write of the agent's file tools inside
  its home (`write_file`, `make_dir`; a path outside the home is not
  the home's) is a line in `.history/log`, `N TIME CONV KIND PATH`:
  N from 1, one more than the log's lines; TIME the clock's seconds
  (`rtc clock`'s, 0 with no clock); CONV the conversation, `S.ID`, S
  the time `agentd` started and ID its conversation; KIND `new` (no
  file was there), `changed` (the file before kept whole as
  `.history/N`), `removed` (the same, the file gone), `dir` (a
  directory made) or `rmdir`. A write whose file is not written leaves
  no line. The log is read and written whole, in a few dozen bytes a
  line. Tests: lines made and read back, N counted, each KIND's
  record of a write under `build/`, and a failed write leaving none.
- [x] **Undone from a shell.** `run agent history [PATH]` lists the
  log, the newest last, as `N DATE TIME CONV KIND PATH`, only PATH's
  if given; `run agent undo N` undoes entry N by its inverse, itself
  recorded (CONV `undo:N`), so an undo is undone in turn: `new` by
  removing the file, `changed` and `removed` by writing `.history/N`
  back, `dir` by removing the directory if it is empty, `rmdir` by
  making it again. Its result is said, as `undid 3: wrote
  /Volumes/data/agent/CLAUDE.md as it was`. An N not in the log, or a
  directory not empty, fails, saying so. Tests: each KIND undone under
  `build/`, and the undo of an undo.
- [x] **A backup to the host and back.** The proxy also serves `PUT
  /backup` and `GET /backup`, behind the same token, with `--backup
  DIR` (`build/proxy/backup` by default): a PUT's body is the home as
  a cpio archive (newc), unpacked into `DIR/home`, which it replaces
  whole, the archive kept as `DIR/archive/STAMP.cpio`; an entry whose
  name is absolute or holds `..` refuses it all, 400. A GET answers
  `DIR/home` packed the same way, so what the host's copy holds,
  edited in Claude Code or not, is what goes back; 404 if there is
  none. `tools/api-proxy/cpio.py`, pure, packs and unpacks.
  `run agent backup` packs the home, every directory and file of it,
  `.history` with them, and PUTs it to the proxy `/etc/agent/config`
  names, saying how many files and bytes; `run agent restore` GETs it
  and writes it into the home: `.history` first, as it is, then every
  other file through the history (CONV `restore`), so a restore is
  undone file by file; a file in the home that the backup has not is
  left as it is, and said. Tests: `cpio.py`'s round trip and its
  refusals; the proxy's PUT, GET, 401 and 404 against a directory
  under a temporary one (`test_proxy.py`); `agent`'s archive of a list
  of files as bytes, read back by `parse_initramfs`.
- [x] **The e2e case, and a Pi 5.** The case `agent_home`, as 0043's
  `agent` case is: the stand-in's script writes `CLAUDE.md` anew,
  writes a memory and its index, and tries to write `CONSTITUTION.md`,
  which fails; the checks see the constitution, rules and index in the
  next request's system prompt. Then, outside the conversation: `run
  agent history`, `run agent undo` of the rules' change, `cat` of
  `CLAUDE.md` as it was, `run agent backup`, a file removed, `run
  agent restore`, and the file back. `e2e_serve.py` gives its proxy
  a backup directory under `build/e2e`, whose `home/CLAUDE.md` the
  case checks. Then on a Pi 5 (the user): a conversation that changes
  its rules and remembers a fact; `run agent history`; `run agent
  backup`, and the host's `build/proxy/backup/home` opened in Claude
  Code; a reinstall of `System` and the home found as it was.

## Spec changes

- agent.md: the home, its layout, what is fixed and its history; the
  system prompt's parts; `agent history`, `undo`, `backup` and
  `restore`.
- network.md: the proxy's `/backup`.
- programs.md: `agent`'s row, `sys/agenthome.l0`'s.
- storage.md: the home on the `data` volume, apart from the system's,
  which a reinstall leaves as it was.
- testing.md: the `agent_home` case; the proxy's backup tests.

## Log

- 2026-10-29: written, with 0041 to 0043 and 0045 to 0049.
- 2026-10-29: the home's place settled in 0043: `/Volumes/data/agent`,
  a data volume, so the agent's files outlive a reinstall; its rules
  are the home's `CLAUDE.md` from 0043 on, which this goal grows.
- 2026-10-30: steps written, the open questions settled with the user:
  the history keeps whole files, a log line for each write and the
  file before it, since an undo is then a copy back, and the host
  reads it as it is; the backup goes over HTTP to the host's proxy,
  behind the board's token, and comes back the same way, so that it
  needs neither 0045 nor a card pulled. Skills are under
  `.claude/skills/`, not the `skills/` this goal first named, as that
  is where Claude Code finds a project's. Active though 0043's
  reinstall check is not done: nothing here waits on it.
- 2026-10-30: steps 1 to 5 done, and step 6's e2e case. Beyond the
  plan: `agentd`'s own keys of `/etc/agent/config` (`home_conf`) and
  the home's place (`home_of`) moved from `tools.l0` into the library,
  since `agent` needs them too; the history's log lines and undo are
  written once, there, for both. `agent history`'s CONV with no clock
  is `0.ID`, as on QEMU's e2e board, which has no `rtc`; the time is
  the board's clock's, local time, as `fs`'s UUIDs take it. A restore
  says which of the home's files the backup has not, but not the
  history's own, which the restore adds to. The stand-in's checks gain
  `results_failed` (a result that must fail, holding a text), a list
  for `system_contains`, and `system_contains_at`, the Nth request's;
  `e2e_serve.py` gives its proxy `build/e2e/NAME.backup`. In the case,
  as run: the rules' change, the memory and its index kept as entries
  1 to 3, the constitution refused, the second conversation's prompt
  holding the new rules and index, `undo 1`, `undo 2` and `undo 5`
  (the undo of an undo), a backup of 9 files and 4 directories, 6.0 kB,
  and a restore of the one file changed behind the history's back.
  The `agent` case's `ls` of the home shows the new parts. Left: step
  6's run on a Pi 5, the user's:

      make proxy-run PROXY_LISTEN=192.168.254.200:8765   # restarted, for /backup
      make agent-etc API=192.168.254.200:8765
      make pi5-netboot && tools/pi5-boot --console
      # at a shell (the serial console, or a vt):
      #   run agent
      #   > from now on, answer in one line; and remember that my name is NAME
      #   > /exit
      #   run agent history                 the rules' change and the memory, entries
      #   run agent backup
      # on the host: build/proxy/backup/home, opened in Claude Code
      # then a reinstall of System from the netboot (0043's Log), and:
      #   ls /Volumes/data/agent            as it was
      #   run agent                         its prompt with the new rules and the memory
- 2026-10-30: step 6 done, on a Pi 5 by the user, through the proxy on
  192.168.254.200:8765 restarted for `/backup`. In two conversations
  the agent remembered a name for itself and the person's name: its
  history, as backed up, is four entries, `memory/agent-name.md` and
  `memory/user-name.md` new and `memory/MEMORY.md` changed twice, the
  file before each change kept as `.history/2` and `.history/4`. The
  first conversation's tag is `101101.1`, its times 1793424170: agentd
  started while the Pi's clock still counted from 1970 (no battery;
  0055's `ntp` set it later), so S, the start, is the clock's then, and
  the tag still tells that start's conversations apart. `run agent
  backup` put the home on the host, 5380 bytes as
  `build/proxy/backup/archive/20261031T054515Z.cpio`, and
  `build/proxy/backup/home` opened in Claude Code; `System` reinstalled
  from a netboot, the home was found as it was. `proxy.py --day`, the
  day's whole, both boards and every run: 29 answers, input 107, output
  4941, cache written 36710, cache read 138740.
