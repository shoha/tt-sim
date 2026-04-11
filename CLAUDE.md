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

Lint (optional): `gdlint path/to/file.gd`

## Godot CLI

```
# Syntax check (prints all compile errors, exits)
godot --headless --path . --quit-after 1

# Run all unit tests
godot --headless --path . --script res://addons/gut/gut_cmdln.gd -- -gconfig=tests/.gutconfig.json

# After fresh clone or new class_name scripts
godot --headless --import --path .
```

## Testing Notes

- GUT v9.5.0 vendored at `addons/gut/`
- 2 pre-existing failures in `test_token_placement_serialization` and
  `test_token_state_serialization` — known, do not investigate

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
