# tt-sim Claude Code Instructions

## Start Here

`AGENTS.md` is the authoritative quick reference for conventions, key APIs, architecture and
"where to add things". It is over 50k characters, so never read it whole: read only the
section your task needs, found with this index or Grep.

| `AGENTS.md` section | What it holds |
|---------------------|---------------|
| Essential Reading | the table of docs (architecture, UI, assets, the asset pipeline contract, map authoring, system docs, networking, conventions) |
| Key Conventions | one rule or pointer per system: EventBus, state stack, autoloads, map and GLB loading, signal cleanup, environment, settings, measure and grid tools |
| Adding Features | recipes: a new state, shader, autoload, UI panel, drawer, RPC, preset, level field, live-synced property, authoring tool |
| Documentation | which doc to update after which kind of change |
| Testing | GUT, the named subsets, the import step, what headless runs cannot verify |
| Validation Bridge (MCP) | the bridge tools, `game_interact`, `game_state`, troubleshooting |
| CI/CD | the pipeline, what a release contains, versioning, cutting a release |
| File Layout | the top-level folders |

A system's map and model live in its doc under `docs/systems/` (index:
`docs/systems/README.md`); the in-game authoring hub is `docs/MAP_AUTHORING.md`.
Supplementary detail is in `.cursor/rules/` and `docs/`.

## File Editing Rules

- Always use the `Read` tool before any `Edit` — required for correct line-ending matching on
  Windows (project has CRLF files on disk; git normalizes to LF on commit).
- Never write Python, shell, or other scripts to perform string replacement in source files.
  The `Edit` tool is correct for all source file modifications. No exceptions.
- `@onready` references use the unique-name form (`%NodeName`, with `unique_name_in_owner`
  set on the node in the `.tscn`), not `$Full/Path`. Every existing scene does this.
- New `.gd` files need a `.gd.uid` sidecar, which Godot generates lazily. Run
  `godot --headless --import --path D:/dev/tt-sim` and `git add` the new `.uid` before
  committing; they are tracked. A subagent that creates a script and never re-imports leaves its
  `.uid` untracked, so check `git status` for stray `.gd.uid` entries after any batch of
  new-file work.
- Plan and design documents (`docs/plans/`, `docs/superpowers/plans/`, `docs/superpowers/specs/`)
  and the `.superpowers/` scratch workspace are gitignored on purpose. Write them to disk, never
  commit them.
- User-provided screenshots are in `cursor_hints/` (gitignored). Look there first; never search
  under the home directory for them.

## Environment

- Godot installs live one per subfolder under `D:/Apps/Godot/` (newest:
  `Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe`). `godot` on PATH is a
  wrapper that picks the newest (`~/.local/bin/godot` for bash, `~/scoop/shims/godot.cmd`
  for PowerShell); the validator MCP server gets an explicit path through `GODOT_PATH` in
  `.mcp.json` (both this repo's and `D:/dev`'s pin 4.7.1). Always pass `--headless` for CLI
  and agent use unless real pixels are needed.
- Commands use absolute paths (`--path D:/dev/tt-sim`, `git -C D:/dev/tt-sim`), because
  sessions usually start in `D:/dev`. The allowlist (`git`, `godot`, `gdformat`, `gdlint`)
  matches a command by its first word, so a `cd`-prefixed command does not match.
  The full command rules are in the `tt-sim-task` agent and `D:/dev/docs/coordinating.md`.
- For tt-sim work spawn the `tt-sim-task` agent (and `tt-sim-gate` for the gate and a named
  commit): it carries the command rules, the gate and the file rules. A general-purpose agent
  needs those rules in its card.

## Formatting

A hook runs `gdformat` on every `.gd` file after each Edit or Write, so there is no manual
formatting step. Lint the files you touched by absolute path: `gdlint D:/dev/tt-sim/utils/x.gd`.

## Pre-Push Gate (REQUIRED)

CI (`.github/workflows/build.yml`) treats `gdlint` as a hard, build-blocking gate — the whole
release pipeline (export/sign/notarize/release/Steam deploy) is skipped if it fails. Before pushing
to `main` or pushing any tag, always run the full CI-equivalent check against the **whole tree**,
not just files touched in the current change — a lint regression can live in an untouched file from
an earlier session and will still fail CI and block a release:

```
gdlint autoloads/ scenes/ utils/ resources/ tests/unit/
godot --headless --path D:/dev/tt-sim --quit-after 1
godot --headless --path D:/dev/tt-sim --script res://addons/gut/gut_cmdln.gd -- -gconfig=tests/.gutconfig.json
```

Run the `gdlint` line with `D:/dev/tt-sim` as the working directory: gdlint reads `.gdlintrc`
only from the current directory, and run from `D:/dev` it reports false max-public-methods and
max-returns failures that the repo config relaxes. All three must be clean before pushing. Do
not rely on per-file `gdlint` runs during editing as a substitute — those only cover files
touched in the current task. This gate exists because the `v0.1.16` tag build failed at lint on
a `static var` ordering violation in a file no one in that session had touched; it had silently
broken CI for three pushes, and the tag had to be moved and the release pipeline re-run. The
release steps are in `AGENTS.md` "Cutting a release"; cutting a version needs the user's OK.

## Godot CLI

```
# Syntax check (prints all compile errors, exits)
godot --headless --path D:/dev/tt-sim --quit-after 1

# Run all unit tests (about 4 minutes)
godot --headless --path D:/dev/tt-sim --script res://addons/gut/gut_cmdln.gd -- -gconfig=tests/.gutconfig.json

# Named subsets for the inner loop; the full run is still required before a commit
godot --headless --path D:/dev/tt-sim --script res://addons/gut/gut_cmdln.gd -- -gconfig=tests/.gutconfig_avatar.json
godot --headless --path D:/dev/tt-sim --script res://addons/gut/gut_cmdln.gd -- -gconfig=tests/.gutconfig_authoring.json
godot --headless --path D:/dev/tt-sim --script res://addons/gut/gut_cmdln.gd -- -gconfig=tests/.gutconfig_net.json
godot --headless --path D:/dev/tt-sim --script res://addons/gut/gut_cmdln.gd -- -gconfig=tests/.gutconfig_ui.json

# After fresh clone or new class_name scripts
godot --headless --import --path D:/dev/tt-sim
```

The subsets (AGENTS.md "Running tests from the CLI" says what each covers): avatar and tokens
(about 2.5 s), net (under 1 s) and ui (about 10 s) are quick. Authoring takes about 220 s of
the full run's 236 s, because the five landform recipe scripts alone take about 115 s, so narrow
it with `-gselect=<part of a script name>` while iterating. Add a new test script to every
subset it belongs to; `test_gut_subsets.gd` fails if a subset lists a missing script.

After any batch of file renames/deletions (e.g. a multi-step refactor), re-run the import step
before the user reopens the editor. See AGENTS.md's "Running tests from the CLI" section for why
(stale `.godot/` cache -> spurious `Unrecognized UID`/`Cannot load shader` errors) and the fix.

## Testing Notes

- GUT v9.5.0 vendored at `addons/gut/`

## Checking the running game: render jobs first, then the bridge

After edits that affect runtime behaviour or visuals, check them in the running game.

- **Render jobs** (`tools/render_jobs/README.md`) are the default for anything visual or
  repeatable: one fixed `godot` command runs a JSON job in a real window, captures PNGs and
  quits by itself, and a job can save a built map once and re-run only its look captures.
  Captures come out at half size (960x540) unless the run passes `--full`: iterate at the
  default and add `--full` only for verdict captures.
- **The validation bridge** (`tt-sim-validator` MCP) is for interactive checks a job cannot
  script: driving a dialog, probing live state with `game_eval`, reproducing a reported bug.
  `game_launch` or `game_reload`, check `game_state`'s `console_errors`, drive the feature
  (`game_interact` batches clicks, keys, screenshots and state in one call), then
  `game_stop`. Tool reference, examples and troubleshooting: `AGENTS.md` "Validation Bridge
  (MCP)".

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
  `tools/mcp/run-server.cmd` resolves the newest fnm node itself; the registrations in
  `.mcp.json` (this repo's and `D:/dev`'s) point `command` at that file with no `args`, and must
  keep doing so. See the AGENTS.md troubleshooting list for the no-MCP fallback over TCP.

## Performance Is a First-Class Constraint

This is a real-time 3D game with a fixed isometric camera and heavy foliage and shadow load.
Never claim a change is performance-neutral from code reading; measure it. The procedure that
produces valid numbers (pinned viewport, vsync off, in-run A/B, drift checks) is in
`docs/PERFORMANCE.md` "How to measure without fooling yourself". Read it before any rendering
work. When exposing a shadow-softness or light-count control to users, sanity-check the top of
its range, not just the default.
