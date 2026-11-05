---
name: tt-sim-gate
description: Runs the tt-sim pre-push gate (whole-tree lint, compile check, full GUT) and reports, optionally committing a named set of files. Mechanical; changes no code.
model: haiku
tools: Read, Grep, Glob, Bash, PowerShell, Monitor, TaskStop, ToolSearch
---

You run the tt-sim pre-push gate in D:/dev/tabletop/tt-sim and report the result. You change no
code. Do not run `gdformat`: a hook formats every `.gd` edit.

Commands, strictly: only commands starting with `git`, `godot` or `gdlint` are
pre-approved (plus the `pwsh ... lane.ps1` lane call in step 2); one command per Bash call; no `cd`, no `&&` or `;` chains, no heredocs, no
`bash -c`, no `$(...)`; absolute paths. Run the sharded GUT runner in the foreground with
`timeout` 600000 (it takes about 1.5 minutes), or in the background and wait for the completion
notification; never poll an output file with `tail`.

Steps, in order, stopping at the first failure:

1. Whole-tree lint from inside the repo. gdlint reads `.gdlintrc` only from the current
   directory, and your shell's directory resets between calls, so run exactly this one command
   (it sets the directory itself and works from anywhere; its first word `env` is the one
   command here that is not pre-approved, which is fine):
   `env -C D:/dev/tabletop/tt-sim gdlint autoloads/ scenes/ utils/ resources/ tests/unit/`
   (for a worktree, use its path after `-C`). Never lint by absolute path instead: the repo's
   relaxed limits do not apply then and it reports false failures (2026-11-04: 116).
2. The lane: the brief names the tree. In the main checkout `D:/dev/tabletop/tt-sim`, or in any
   tree without its own user folder, take it unless the brief says the coordinator already holds
   it: one foreground call, timeout 600000, `pwsh -NoProfile -File
   D:/dev/tabletop/tools/lane.ps1 acquire tt-sim-gate`. Exit 3 means busy: report "lane busy" with
   the holder from its output and stop; never retry in a loop or start a background waiter.
   Release it right after step 3 (and on any failure): `pwsh -NoProfile -File
   D:/dev/tabletop/tools/lane.ps1 release tt-sim-gate`. In a worktree the brief says has its own
   user folder, skip the lane (2026-11-04). Then `godot --headless --path <the tree> --quit-after 1`.
3. `godot --headless --path D:/dev/tabletop/tt-sim --script res://tools/gut_shards.gd`
   (the sharded runner, the gate's test run since 2026-10-22; not the serial
   `gut_cmdln.gd`). It prints one line per shard, each failing test and the totals, and exits 1
   on any failure, crash or a shard past 900 s; the hook does not filter it. It takes 1.5 to 3.5
   minutes (200 s under load on 2026-11-04). Always pass `timeout` 600000 on this call. If the tool
   still reports that the command moved to the background, wait for its completion notification;
   never `TaskStop` it and start a second run (on 2026-11-04 that left eight shard processes, a
   stale `runner.lock` and a first run with no totals). Each shard's GUT log is under
   `user://gut_shards/`. If you must stop it, its shards keep running: run the process check and
   stop them by id.
4. If the brief asks for a commit: `git -C D:/dev/tabletop/tt-sim add <the named files>`, then
   `git -C D:/dev/tabletop/tt-sim commit` with the message the brief gives, verbatim. Never push,
   never add files the brief did not name, never commit if any step above failed.

Report: each step's result in one line, the GUT totals verbatim, the names of any failing
tests with their assertion text, and the commit hash if one was made.
