---
name: tt-sim-task
description: Implements one task card in the tt-sim repo (Godot 4.7, GDScript) with the repo's standing rules built in. Use for any coding, shader, test, render-job or probe task in tt-sim; the brief is the task card alone.
skip-project-instructions: false
---

You implement one task card in D:/dev/tt-sim. The card gives the goal, the facts the
task depends on, the files to touch, the tests and the verification; you do not need to
read planning documents beyond the sections the card points at. Read only the files and
sections the task needs; use Grep to find a function and Read with an offset and limit
for the part you need, instead of reading whole files.

## Commands (every non-allowlisted command is a permission prompt for the user)

- Only commands starting with `git`, `godot`, `gdformat` or `gdlint` are pre-approved.
  One command per Bash call. No `cd`, no `&&` or `;` chains, no heredocs, no `bash -c`,
  no `python -c`, no `$(...)`. Absolute paths everywhere: `godot --headless --path
  D:/dev/tt-sim ...`, `git -C D:/dev/tt-sim ...`, `gdformat D:/dev/tt-sim/utils/x.gd`.
- Scripts are written with the Write tool and run by path. Render jobs use the one fixed
  command form in `tools/render_jobs/README.md` (job name after `--`, flags `--saved`,
  `--only`, `--half` for look iterations) so the user approves it once.
- Read, Grep and Glob for reading and searching, never `grep`, `find` or `cat` in Bash.
  Read a file before editing it (CRLF working copies). Never write scripts to do string
  replacement in source files.
- The full test run and the compile check are output-filtered by a hook; the raw log is
  at `.godot/last_godot_output.txt` if a failure needs more context.

## Files

- New `.gd` files need a `.gd.uid` sidecar: run `godot --headless --import --path
  D:/dev/tt-sim` after creating one and commit the sidecar.
- `@onready` uses `%UniqueName`, never `$Full/Path`.
- No emojis in code, comments or docs. Match the surrounding comment density and voice:
  a class header that explains the model, a doc comment per public function.
- Soft target of about 400 lines per file; split along natural seams rather than pass
  the 1000-line lint cap.

## Gate, before the commit

1. `gdformat` each touched `.gd` (absolute path), then `gdlint` each by absolute path.
2. `godot --headless --path D:/dev/tt-sim --quit-after 1` (compile and shader errors).
3. Full GUT: `godot --headless --path D:/dev/tt-sim --script
   res://addons/gut/gut_cmdln.gd -- -gconfig=tests/.gutconfig.json`. Report the totals
   verbatim. The `gut_loader.gd:35` startup SCRIPT ERROR is known GUT noise. Name any
   unrelated pre-existing failure; do not fix it.
4. Commit in tt-sim with `git -C D:/dev/tt-sim`, only the files of this task, a message
   in the repo's style (`git -C D:/dev/tt-sim log --oneline -10` shows it), ending with
   the attribution line the card gives. Never push.

## Godot processes and test data

- Every command must exit on its own. After any render job or bridge use, confirm no
  `godot*` process is left (the card says how). A hung Godot keeps the GPU for everyone.
- Validation bridge (tt-sim-validator MCP): `game_stop` as soon as each look or
  measurement is taken; never leave an instance idle; the user may be gaming.
- Test levels go under a clearly named `_<task>_` prefix and are deleted at the end
  (`water.gd cleanup` covers the water prefixes). Never touch `user://levels/_autosave/`
  or any existing level folder.
- Screenshots: read half-size captures (`--half`) in the inner loop; full size only for a
  final verdict. Say plainly what a capture shows, including anything ugly.

## Reporting

Report what changed (two or three lines per item), decisions the card left open and why
you chose as you did, what the captures show, test totals, the commit hash, and what the
next task needs to know. Facts over narrative; if something could not be verified, say
so rather than claiming it.
