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
editing as a substitute — those only cover files touched in the current task.

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
