# tt-sim Claude Code Instructions

## Start Here

Read `AGENTS.md` before making any changes. It is the authoritative quick-reference for
conventions, key APIs, architecture, and "where to add things". Supplementary detail is in
`.cursor/rules/` and `docs/`.

## File Editing Rules

- Always use the `Read` tool before any `Edit` — required for correct line-ending matching on
  Windows (project has CRLF files on disk; git normalizes to LF on commit).
- Never write Python, shell, or other scripts to perform string replacement in source files.
  The `Edit` tool is correct for all source file modifications. No exceptions.
- `@onready` references use the unique-name form (`%NodeName`, with `unique_name_in_owner`
  set on the node in the `.tscn`), not `$Full/Path`. Every existing scene does this.
- New `.gd` files need a `.gd.uid` sidecar, which Godot generates lazily. Run
  `godot --headless --import --path .` and `git add` the new `.uid` before committing; they are
  tracked. A subagent that creates a script and never re-imports leaves its `.uid` untracked, so
  check `git status` for stray `.gd.uid` entries after any batch of new-file work.
- Plan and design documents (`docs/plans/`, `docs/superpowers/plans/`, `docs/superpowers/specs/`)
  and the `.superpowers/` scratch workspace are gitignored on purpose. Write them to disk, never
  commit them.
- User-provided screenshots are in `cursor_hints/` (gitignored). Look there first; never search
  under the home directory for them.

## Environment

- Godot 4.7 is installed at `D:/Apps/Godot/Godot.exe`. `godot` on PATH is a wrapper
  (`~/.local/bin/godot` for bash, `~/scoop/shims/godot.cmd` for PowerShell). Always pass
  `--headless` for CLI and agent use unless real pixels are needed.
- Permission allowlist: `Bash(git *)`, `Bash(godot *)`, `Bash(gdformat *)`, `Bash(gdlint *)`
  match commands that *start* with that word. `cd dir && git ...` starts with `cd` and prompts;
  use `git -C /d/dev/tt-sim ...` instead. Avoid `bash -c "..."` wrappers and `$(cat <<'EOF' ...)`
  command substitution in commit messages, which trigger a prompt even when `git` is allowed.
- Subagents that touch files need the general-purpose type (Read/Edit/Write); a Bash-only agent
  fails mid-task on any edit. In subagent prompts, name the Grep/Glob/Read tools rather than
  writing `grep -r`/`find`/`cat` commands, which prompt for permission.

## Post-Edit: Formatting

After editing any `.gd` file, run the formatter before committing:

```
gdformat path/to/file.gd
```

Lint (optional, single file): `gdlint path/to/file.gd`

## Pre-Push Gate (REQUIRED)

CI (`.github/workflows/build.yml`) treats `gdlint` as a hard, build-blocking gate — the whole
release pipeline (export/sign/notarize/release/Steam deploy) is skipped if it fails. Before pushing
to `main` or pushing any tag, always run the full CI-equivalent check against the **whole tree**,
not just files touched in the current change — a lint regression can live in an untouched file from
an earlier session and will still fail CI and block a release:

```
gdlint autoloads/ scenes/ utils/ resources/ tests/unit/
godot --headless --path . --quit-after 1
godot --headless --path . --script res://addons/gut/gut_cmdln.gd -- -gconfig=tests/.gutconfig.json
```

All three must be clean before pushing. Do not rely on per-file `gdformat`/`gdlint` runs during
editing as a substitute — those only cover files touched in the current task. This gate exists
because the `v0.1.16` tag build failed at lint on a `static var` ordering violation in a file no
one in that session had touched; it had silently broken CI for three pushes, and the tag had to be
moved and the release pipeline re-run. The release steps are in `AGENTS.md` "Cutting a release".

## Godot CLI

```
# Syntax check (prints all compile errors, exits)
godot --headless --path . --quit-after 1

# Run all unit tests
godot --headless --path . --script res://addons/gut/gut_cmdln.gd -- -gconfig=tests/.gutconfig.json

# After fresh clone or new class_name scripts
godot --headless --import --path .
```

After any batch of file renames/deletions (e.g. a multi-step refactor), re-run the import step
before the user reopens the editor. See AGENTS.md's "Running tests from the CLI" section for why
(stale `.godot/` cache -> spurious `Unrecognized UID`/`Cannot load shader` errors) and the fix.

## Testing Notes

- GUT v9.5.0 vendored at `addons/gut/`

## Validation Bridge

After making code changes, use the `tt-sim-validator` MCP tools to verify your work:

```
game_reload  → restart game with new code
game_state   → check for console errors
game_interact → exercise the feature (click, drag, key, screenshot, state in one batch)
```

See `AGENTS.md` "Validation Bridge (MCP)" section for full tool reference, examples, and
troubleshooting. Always smoke-test (`game_reload` + `game_state`) after edits that affect
runtime behavior.

Rules that apply every time the bridge is used:

- **Stop the game (`game_stop`) as soon as each test or measurement is done**, not at the end of
  the task. An idle instance burns the user's CPU and GPU, and sustained GPU load throttles the
  clocks: a 1.48x uniform slowdown was measured across a long session of back-to-back runs, so
  a running instance also corrupts the next measurement. Restore any harness state you changed at
  the same time (delete `override.cfg`, restore `user://settings.cfg`).
- **The bridge is repo source, not infrastructure.** When it misbehaves, open
  `addons/validation_bridge/validation_bridge.gd` and find the failure path before declaring a
  check impossible. "Escape hangs the bridge" was one line (`PROCESS_MODE_ALWAYS`); "drags never
  register" was a stale cursor read in the DragAndDrop3D addon. State the real symptom, not a
  capability claim. Declaring something untestable quietly drops verification coverage.
- **If the MCP server reports `CONNECTION_CLOSED` at session start**, `node` is not on the PATH
  Claude Code launches servers with (fnm only sets it in the PowerShell profile). The committed
  `tools/mcp/run-server.cmd` resolves the newest fnm node itself; the user-scope registration in
  `~/.claude.json` must point its `command` at that file with no `args`. See the AGENTS.md
  troubleshooting list for the no-MCP fallback over TCP.

## Performance Is a First-Class Constraint

This is a real-time 3D game with a fixed isometric camera and heavy foliage and shadow load.
Never claim a change is performance-neutral from code reading; measure it. The procedure that
produces valid numbers (pinned viewport, vsync off, in-run A/B, drift checks) is in
`docs/PERFORMANCE.md` "How to measure without fooling yourself". Read it before any rendering
work. When exposing a shadow-softness or light-count control to users, sanity-check the top of
its range, not just the default.
