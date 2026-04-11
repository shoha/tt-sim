# Validation Bridge: Agent Self-Evaluation System

**Date:** 2026-04-11
**Status:** Approved design

## Problem

AI agents editing tt-sim code cannot evaluate the impact of their changes without human
intervention. Breakage is typically subtle -- wrong behavior, visual regressions, interaction
bugs -- not obvious crashes. The agent needs to run the game, interact with it, see the
result, and iterate autonomously.

## Solution

A lightweight, custom-built validation system with three layers:

1. **Validation Bridge** -- a GDScript editor plugin (~150-200 lines) that runs inside Godot,
   accepting commands over TCP
2. **MCP Server** -- a TypeScript process (~500 lines) that manages Godot's lifecycle and
   exposes validation tools via the Model Context Protocol
3. **Agent Loop** -- the agent uses MCP tools to reload the game, interact with it, capture
   screenshots and state, evaluate correctness, and iterate

## Architecture

```
Agent (Claude Code / orchestrator)
  |  MCP protocol (stdio)
  v
MCP Server (TypeScript)
  |  TCP localhost:7777
  v
Validation Bridge (GDScript autoload inside Godot)
```

## Layer 1: GDScript Validation Bridge

An editor plugin at `addons/validation_bridge/` that activates only when Godot is launched
with a `--validation-bridge` CLI flag (or equivalent environment variable). It never loads
during normal gameplay, editor use, or release builds.

### TCP Server

- Listens on `127.0.0.1:7777`
- JSON-line protocol: one JSON object per request, one JSON object per response
- No external dependencies

### Commands

| Command | Input | Output |
|---|---|---|
| `screenshot` | (none) | Base64-encoded PNG of current viewport |
| `state` | (none) | JSON snapshot of game state (see below) |
| `input` | Event descriptor | Acknowledgment after event is processed |
| `wait` | Seconds or signal name | Acknowledgment when complete |

### State Snapshot Contents

- Current app state from Root's state stack (TITLE_SCREEN, PLAYING, PAUSED, etc.)
- Token list with positions, names, visibility
- Active UI panels (which drawers/menus are open)
- Camera position and zoom level
- Scene tree summary (node names + types, not full properties)
- Godot debug log errors accumulated since last snapshot

### Input Injection

- `click(x, y)` -- InputEventMouseButton at viewport coordinates
- `drag(x1, y1, x2, y2)` -- press, move, release sequence
- `key(keycode)` -- InputEventKey (M for measure, Home for camera reset, etc.)
- `scroll(x, y, direction)` -- mouse wheel for zoom

### Loading Strategy

The bridge is registered as a project autoload but gates all behavior behind an activation
check. On `_ready()`, it checks `OS.get_cmdline_user_args()` for `--validation-bridge` (args
after `--` in the Godot command line, e.g., `godot --path . -- --validation-bridge`). If the
flag is absent, the autoload does nothing -- no TCP server, no processing overhead.

This approach was chosen because:
- It requires no environment variable setup
- It cannot accidentally activate in editor play, release builds, or Steam launches
- `OS.get_cmdline_user_args()` is the Godot-standard way to pass custom flags

## Layer 2: MCP Server (TypeScript)

A stdio-transport MCP server at `tools/mcp/` that bridges agent tool calls to the validation
bridge running inside Godot.

### Dependencies

- `@modelcontextprotocol/sdk` (official MCP TypeScript SDK)
- No other external dependencies

### MCP Tools

| Tool | Description |
|---|---|
| `game_launch` | Starts Godot with the validation bridge flag. Options: scene path, window size |
| `game_stop` | Kills the Godot process |
| `game_reload` | Stops and relaunches (for after code changes) |
| `game_screenshot` | Captures viewport, returns base64 PNG |
| `game_state` | Returns the JSON state snapshot |
| `game_click(x, y)` | Click at viewport coordinates |
| `game_drag(x1, y1, x2, y2)` | Drag gesture |
| `game_key(key)` | Keypress |
| `game_scroll(x, y, delta)` | Mouse wheel at position |
| `game_wait(seconds)` | Wait for animations/transitions to settle |
| `game_interact(steps)` | Batch: execute a sequence of inputs with waits, return final screenshot + state |

### `game_interact` (Batch Tool)

The primary tool for validation. Accepts a sequence of steps and executes them in order,
returning collected screenshots and final state in one response. This minimizes round-trips
and token usage.

```json
{
  "steps": [
    {"action": "click", "x": 500, "y": 300},
    {"action": "wait", "seconds": 0.5},
    {"action": "click", "x": 600, "y": 400},
    {"action": "wait", "seconds": 0.3},
    {"action": "screenshot"},
    {"action": "state"}
  ]
}
```

### Process Management

- Spawns Godot as a child process
- Captures stdout/stderr for error detection (GDScript errors, crashes)
- Waits for the bridge TCP connection before reporting "ready"
- On `game_reload`: kills process, waits for port to free, relaunches
- Timeout: if bridge doesn't connect within 10 seconds, returns launch failure with captured
  console output
- Godot console errors are included in every `game_state` response under an `errors` field
- If Godot crashes, the next tool call returns the crash output

## Layer 3: Agent Validation Loop

The agent improvises test sequences based on what it changed. No pre-authored test scenarios.

### Flow

```
1. Agent edits .gd file(s)
2. game_reload()          -- restart with new code
3. game_state()           -- check for startup errors
4. If errors -> fix code, go to 1
5. game_interact(steps)   -- exercise the changed feature
6. game_screenshot()      -- capture result
7. Evaluate:
   a. State check: does game_state match expectations?
   b. Error check: any new errors in console?
   c. Vision check: does screenshot look correct?
8. If problems -> diagnose, fix code, go to 1
9. Done
```

### Validation Levels

1. **Smoke test (always):** Reload and check for errors. Free, catches regressions.
2. **Targeted interaction (from context):** The agent reasons about what it changed and
   exercises that specific feature. Edit the measure tool -> place tokens and measure. Edit
   the context menu -> right-click a token.
3. **Acceptance criteria (from prompt):** If the task specifies expected behavior ("the glow
   should be orange"), the agent uses vision to verify.

### What the Agent Can vs. Cannot Catch

**Can catch:**
- Crashes and errors on load
- Missing/broken UI elements
- Wrong colors (bold changes)
- Features that don't respond to input
- State corruption (via game_state)
- Layout obviously wrong

**Probably cannot catch:**
- Subtle animation timing
- 1px alignment issues
- Slight color shade differences
- Performance regressions
- "Feel" of drag interactions
- Edge cases the agent doesn't think to test

The vision model is a sanity check, not a pixel-perfect comparator. The real power is the
combination: state queries for precision, screenshots for "does this look broken," error
capture for regressions.

## Project Integration

### File Layout

```
D:\dev\tt-sim\
  addons/
    validation_bridge/
      validation_bridge.gd    # TCP server + commands (~200 lines, registered as autoload)
  tools/
    mcp/
      package.json            # TypeScript MCP server
      tsconfig.json
      src/
        server.ts             # MCP tool definitions + process management
        bridge-client.ts      # TCP client for talking to Godot
```

### MCP Registration

```bash
claude mcp add tt-sim-validator -- node D:/dev/tt-sim/tools/mcp/dist/server.js
```

### Git

Both `addons/validation_bridge/` and `tools/mcp/` are committed as dev tooling (same as GUT).
No .gitignore additions needed.

### CI

No CI changes. The validation bridge is for local agent workflows. Unit tests (GUT) remain
the CI-appropriate validation layer.

### Orchestrator Compatibility

- Stdio transport: standard for Claude Code, Cursor, and most orchestration frameworks
- Any MCP-compatible agent framework can use the tools
- Tools are stateless from the MCP perspective (server holds process state internally)

## Non-Goals

- Visual regression baselines / golden image storage
- Pixel-perfect image comparison
- Performance benchmarking
- Headless CI integration (requires a GPU/window on Windows)
- Pre-authored reusable test scenarios
