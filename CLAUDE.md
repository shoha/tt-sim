# tt-sim Project Instructions

## File Editing Rules

- Always use the `Read` tool before attempting any `Edit` — this is required for Edit to work
  and ensures correct line ending matching on Windows (CRLF files).
- Never write Python, shell, or any other scripts to perform string replacement in source files.
  The `Edit` tool is the correct tool for all source file modifications. No exceptions.

## Godot

- Godot 4.6 executable: `D:/Apps/Godot 4.6/Godot.exe`
- CLI invocation: `godot --headless --path . <args>`
- Syntax check: `godot --headless --path . --quit-after 1`
- Run tests: `godot --headless --path . --script res://addons/gut/gut_cmdln.gd -- -gconfig=tests/.gutconfig.json`

## Testing

- GUT v9.5.0 is vendored at `addons/gut/`
- 2 pre-existing failures in `test_token_placement_serialization` and
  `test_token_state_serialization` — these are known and expected, do not investigate them
