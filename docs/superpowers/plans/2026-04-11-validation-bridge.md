# Validation Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a GDScript autoload + TypeScript MCP server that lets AI agents launch the game, interact with it, capture screenshots and state, and validate their own code changes without human intervention.

**Architecture:** A minimal GDScript TCP server (autoload, gated by CLI flag) handles screenshot capture, game state serialization, and input injection. A TypeScript MCP server manages the Godot process lifecycle and exposes all capabilities as MCP tools. Agents call tools like `game_reload`, `game_screenshot`, `game_interact` to validate changes.

**Tech Stack:** GDScript (Godot 4.6), TypeScript (Node.js), `@modelcontextprotocol/sdk`, `zod`

**Spec:** `docs/superpowers/specs/2026-04-11-validation-bridge-design.md`

---

## File Structure

```
addons/validation_bridge/
  validation_bridge.gd        # GDScript autoload: TCP server, screenshot, state, input (~200 lines)

tools/mcp/
  package.json                 # Node.js project config
  tsconfig.json                # TypeScript compiler config
  src/
    bridge-client.ts           # TCP client for GDScript bridge communication
    process-manager.ts         # Godot process lifecycle (launch/stop/reload)
    server.ts                  # MCP server entry point + all tool definitions
```

**Modifications:**
- `project.godot:41` -- add `ValidationBridge` autoload registration
- `.gitignore` -- add `tools/mcp/node_modules/` and `tools/mcp/dist/`

---

### Task 1: GDScript Validation Bridge -- TCP Server Core

**Files:**
- Create: `addons/validation_bridge/validation_bridge.gd`

This task creates the complete GDScript bridge as a single file. It handles TCP listening, JSON-line protocol, command dispatch, screenshot capture, state collection, and input injection. All gated behind a CLI activation flag.

- [ ] **Step 1: Create the bridge script**

Create `addons/validation_bridge/validation_bridge.gd` with the following content:

```gdscript
extends Node

## Validation bridge for AI agent self-evaluation.
## Listens on TCP localhost and accepts commands for screenshot capture,
## game state queries, and input injection.
## Only activates when launched with: godot --path . -- --validation-bridge

const PORT: int = 7777
const HOST: String = "127.0.0.1"
const SCENE_TREE_MAX_DEPTH: int = 3
const SCENE_TREE_MAX_CHILDREN: int = 20

var _server: TCPServer = null
var _client: StreamPeerTCP = null
var _buffer: String = ""
var _processing: bool = false
var _active: bool = false


func _ready() -> void:
	if not "--validation-bridge" in OS.get_cmdline_user_args():
		return
	_active = true
	_server = TCPServer.new()
	var err := _server.listen(PORT, HOST)
	if err != OK:
		push_error(
			"ValidationBridge: Failed to listen on %s:%d: %s" % [HOST, PORT, error_string(err)]
		)
		return
	print("ValidationBridge: Listening on %s:%d" % [HOST, PORT])


func _process(_delta: float) -> void:
	if not _active or _processing:
		return
	_poll_server()


# ---------------------------------------------------------------------------
# TCP server
# ---------------------------------------------------------------------------


func _poll_server() -> void:
	if _server.is_connection_available():
		var new_client := _server.take_connection()
		if _client != null:
			_client.disconnect_from_host()
		_client = new_client
		_buffer = ""
		print("ValidationBridge: Client connected")

	if _client == null:
		return

	_client.poll()
	if _client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_client = null
		_buffer = ""
		return

	var available := _client.get_available_bytes()
	if available <= 0:
		return

	var result := _client.get_data(available)
	if result[0] != OK:
		return

	_buffer += (result[1] as PackedByteArray).get_string_from_utf8()
	_try_process_command()


func _try_process_command() -> void:
	var newline_idx := _buffer.find("\n")
	if newline_idx == -1:
		return

	var line := _buffer.substr(0, newline_idx)
	_buffer = _buffer.substr(newline_idx + 1)

	var json := JSON.new()
	if json.parse(line) != OK:
		_send_response({"ok": false, "error": "Invalid JSON: %s" % json.get_error_message()})
		return

	var cmd: Dictionary = json.data
	_processing = true
	_handle_command(cmd)


func _handle_command(cmd: Dictionary) -> void:
	var response: Dictionary
	match cmd.get("cmd", ""):
		"screenshot":
			await RenderingServer.frame_post_draw
			response = _cmd_screenshot()
		"state":
			response = _cmd_state()
		"input":
			response = await _cmd_input(cmd)
		"wait":
			response = await _cmd_wait(cmd)
		_:
			response = {"ok": false, "error": "Unknown command: %s" % cmd.get("cmd", "")}
	_send_response(response)
	_processing = false


func _send_response(response: Dictionary) -> void:
	if _client == null or _client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var json_str := JSON.stringify(response) + "\n"
	_client.put_data(json_str.to_utf8_buffer())


# ---------------------------------------------------------------------------
# Screenshot
# ---------------------------------------------------------------------------


func _cmd_screenshot() -> Dictionary:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return {"ok": false, "error": "Failed to capture viewport"}
	var png_buffer := image.save_png_to_buffer()
	var base64_str := Marshalls.raw_to_base64(png_buffer)
	return {
		"ok": true,
		"width": image.get_width(),
		"height": image.get_height(),
		"png_base64": base64_str,
	}


# ---------------------------------------------------------------------------
# State snapshot
# ---------------------------------------------------------------------------


func _cmd_state() -> Dictionary:
	return {
		"ok": true,
		"app_state": _get_app_state(),
		"tokens": _get_tokens(),
		"ui": _get_ui_state(),
		"camera": _get_camera_state(),
		"scene_tree": _get_scene_tree(get_tree().current_scene, 0, SCENE_TREE_MAX_DEPTH),
	}


func _get_app_state() -> String:
	var root_scene := get_tree().current_scene
	if root_scene == null or not root_scene.has_method("get_current_state"):
		return "UNKNOWN"
	var state_value: int = root_scene.get_current_state()
	var state_names := ["TITLE_SCREEN", "LOBBY_HOST", "LOBBY_CLIENT", "PLAYING", "PAUSED"]
	if state_value >= 0 and state_value < state_names.size():
		return state_names[state_value]
	return "UNKNOWN(%d)" % state_value


func _get_tokens() -> Array:
	var tokens := []
	for network_id: String in GameState.get_all_token_states():
		var ts: TokenState = GameState.get_token_state(network_id)
		if ts == null:
			continue
		tokens.append({
			"network_id": network_id,
			"name": ts.token_name,
			"position": _vec3_to_dict(ts.position),
			"rotation": _vec3_to_dict(ts.rotation),
			"visible": ts.is_visible_to_players,
			"health": ts.current_health,
			"max_health": ts.max_health,
			"alive": ts.is_alive,
		})
	return tokens


func _get_ui_state() -> Dictionary:
	var result := {}
	var root_scene := get_tree().current_scene
	if root_scene == null:
		return result

	# Check known drawer panels
	for drawer in get_tree().get_nodes_in_group(""):
		pass  # Groups not used; find by type instead

	var nodes := _find_nodes_of_class(root_scene, "DrawerContainer")
	for node in nodes:
		if "is_open" in node:
			result[str(node.name)] = {"open": node.is_open}

	# Check PauseOverlay visibility
	var pause_overlay := root_scene.find_child("PauseOverlay", true, false)
	if pause_overlay:
		result["PauseOverlay"] = {"visible": pause_overlay.visible}

	return result


func _get_camera_state() -> Dictionary:
	var root_scene := get_tree().current_scene
	if root_scene == null:
		return {}
	var game_map := root_scene.find_child("GameMap", true, false)
	if game_map == null:
		return {}
	var camera: Camera3D = game_map.get("camera_node")
	var holder: Node3D = game_map.get("cameraholder_node")
	if camera == null:
		return {}
	var pos: Vector3 = holder.global_position if holder else camera.global_position
	return {
		"position": _vec3_to_dict(pos),
		"zoom": camera.size,
	}


func _get_scene_tree(node: Node, depth: int, max_depth: int) -> Dictionary:
	if node == null:
		return {}
	var result := {
		"name": str(node.name),
		"type": node.get_class(),
	}
	if depth < max_depth:
		var children := []
		var child_nodes := node.get_children()
		var limit := mini(child_nodes.size(), SCENE_TREE_MAX_CHILDREN)
		for i in range(limit):
			children.append(_get_scene_tree(child_nodes[i], depth + 1, max_depth))
		if child_nodes.size() > SCENE_TREE_MAX_CHILDREN:
			children.append({
				"name": "... (%d more)" % (child_nodes.size() - SCENE_TREE_MAX_CHILDREN),
				"type": "truncated",
			})
		result["children"] = children
	elif node.get_child_count() > 0:
		result["child_count"] = node.get_child_count()
	return result


func _find_nodes_of_class(root: Node, class_name_str: String) -> Array[Node]:
	var result: Array[Node] = []
	_find_nodes_of_class_recursive(root, class_name_str, result)
	return result


func _find_nodes_of_class_recursive(
	node: Node, class_name_str: String, result: Array[Node]
) -> void:
	if node.get_class() == class_name_str or (node.get_script() and node is DrawerContainer):
		result.append(node)
	for child in node.get_children():
		_find_nodes_of_class_recursive(child, class_name_str, result)


# ---------------------------------------------------------------------------
# Input injection
# ---------------------------------------------------------------------------


func _cmd_input(cmd: Dictionary) -> Dictionary:
	var input_type: String = cmd.get("type", "")
	match input_type:
		"click":
			var button_str: String = cmd.get("button", "left")
			var button := _parse_mouse_button(button_str)
			_inject_click(cmd.get("x", 0.0), cmd.get("y", 0.0), button)
		"drag":
			await _inject_drag(
				cmd.get("x1", 0.0), cmd.get("y1", 0.0),
				cmd.get("x2", 0.0), cmd.get("y2", 0.0),
			)
		"key":
			_inject_key(cmd.get("key", ""))
		"scroll":
			_inject_scroll(cmd.get("x", 0.0), cmd.get("y", 0.0), cmd.get("delta", 1.0))
		_:
			return {"ok": false, "error": "Unknown input type: %s" % input_type}
	# Wait for input to be processed and visuals to update
	await get_tree().process_frame
	await get_tree().process_frame
	return {"ok": true}


func _inject_click(x: float, y: float, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var pos := Vector2(x, y)
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = pos
	press.global_position = pos
	Input.parse_input_event(press)

	var release := InputEventMouseButton.new()
	release.button_index = button
	release.pressed = false
	release.position = pos
	release.global_position = pos
	Input.parse_input_event(release)


func _inject_key(key_string: String) -> void:
	var keycode := OS.find_keycode_from_string(key_string)
	if keycode == KEY_NONE:
		push_warning("ValidationBridge: Unknown key: %s" % key_string)
		return
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)

	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)


func _inject_scroll(x: float, y: float, delta: float) -> void:
	var pos := Vector2(x, y)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if delta > 0.0 else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.position = pos
	event.global_position = pos
	event.factor = absf(delta)
	Input.parse_input_event(event)


func _inject_drag(x1: float, y1: float, x2: float, y2: float) -> void:
	var from := Vector2(x1, y1)
	var to := Vector2(x2, y2)

	# Press at start
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.global_position = from
	Input.parse_input_event(press)

	await get_tree().process_frame

	# Interpolate motion
	var steps := 10
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var pos := from.lerp(to, t)
		var motion := InputEventMouseMotion.new()
		motion.position = pos
		motion.global_position = pos
		motion.relative = (to - from) / float(steps)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		if i < steps:
			await get_tree().process_frame

	# Release at end
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	release.global_position = to
	Input.parse_input_event(release)


func _cmd_wait(cmd: Dictionary) -> Dictionary:
	var seconds: float = cmd.get("seconds", 0.5)
	if seconds > 0.0:
		await get_tree().create_timer(seconds).timeout
	else:
		await get_tree().process_frame
	return {"ok": true}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _vec3_to_dict(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}


func _parse_mouse_button(name: String) -> MouseButton:
	match name:
		"right":
			return MOUSE_BUTTON_RIGHT
		"middle":
			return MOUSE_BUTTON_MIDDLE
		_:
			return MOUSE_BUTTON_LEFT
```

- [ ] **Step 2: Format the file**

Run: `gdformat addons/validation_bridge/validation_bridge.gd`

Expected: file reformatted (or no changes if already compliant)

- [ ] **Step 3: Syntax check**

Run: `godot --headless --path . --quit-after 1`

Expected: No errors referencing `validation_bridge.gd`. (The autoload registration happens in Task 2.)

- [ ] **Step 4: Commit**

```
git add addons/validation_bridge/validation_bridge.gd
git commit -m "feat: add GDScript validation bridge for agent self-evaluation

TCP server autoload (port 7777) gated by --validation-bridge CLI flag.
Supports screenshot capture, game state queries, and input injection."
```

---

### Task 2: Register Bridge Autoload and Update .gitignore

**Files:**
- Modify: `project.godot:41` -- add autoload entry
- Modify: `.gitignore` -- add MCP server build artifacts

- [ ] **Step 1: Add autoload to project.godot**

Add after the last autoload entry (line 41, after `AssetManager`):

```
ValidationBridge="*res://addons/validation_bridge/validation_bridge.gd"
```

The `[autoload]` section should end with:

```ini
EventBus="*res://autoloads/event_bus.gd"
AssetManager="*res://autoloads/asset_manager.gd"
ValidationBridge="*res://addons/validation_bridge/validation_bridge.gd"
```

- [ ] **Step 2: Add .gitignore entries for MCP server**

Add at the end of `.gitignore`:

```
# Validation bridge MCP server (build artifacts + deps)
tools/mcp/node_modules/
tools/mcp/dist/
```

- [ ] **Step 3: Verify bridge does NOT activate without the flag**

Run: `godot --headless --path . --quit-after 1`

Expected: Output should NOT contain "ValidationBridge: Listening". The autoload loads but `_ready()` exits early because `--validation-bridge` is not in the user args.

- [ ] **Step 4: Verify bridge DOES activate with the flag**

Run: `godot --path . -- --validation-bridge`

Expected: Output contains `ValidationBridge: Listening on 127.0.0.1:7777`. Close Godot manually after verifying (Ctrl+C or close window).

- [ ] **Step 5: Commit**

```
git add project.godot .gitignore
git commit -m "chore: register validation bridge autoload, update gitignore"
```

---

### Task 3: TypeScript MCP Server -- Project Scaffolding

**Files:**
- Create: `tools/mcp/package.json`
- Create: `tools/mcp/tsconfig.json`

- [ ] **Step 1: Create package.json**

Create `tools/mcp/package.json`:

```json
{
  "name": "tt-sim-validator",
  "version": "0.1.0",
  "description": "MCP server for AI agent validation of tt-sim Godot project",
  "type": "module",
  "main": "dist/server.js",
  "scripts": {
    "build": "tsc",
    "start": "node dist/server.js"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.12.0",
    "zod": "^3.24.0"
  },
  "devDependencies": {
    "@types/node": "^22.0.0",
    "typescript": "^5.7.0"
  }
}
```

- [ ] **Step 2: Create tsconfig.json**

Create `tools/mcp/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "declaration": true
  },
  "include": ["src"]
}
```

- [ ] **Step 3: Install dependencies**

Run: `cd tools/mcp && npm install`

Expected: `node_modules/` created with `@modelcontextprotocol/sdk`, `zod`, `typescript`, `@types/node`.

- [ ] **Step 4: Commit**

```
git add tools/mcp/package.json tools/mcp/package-lock.json tools/mcp/tsconfig.json
git commit -m "chore: scaffold TypeScript MCP server project"
```

---

### Task 4: TypeScript MCP Server -- Bridge TCP Client

**Files:**
- Create: `tools/mcp/src/bridge-client.ts`

The bridge client handles TCP communication with the GDScript validation bridge using the JSON-line protocol.

- [ ] **Step 1: Create bridge-client.ts**

Create `tools/mcp/src/bridge-client.ts`:

```typescript
import { Socket } from "node:net";

export interface BridgeResponse {
  ok: boolean;
  error?: string;
  [key: string]: unknown;
}

export class BridgeClient {
  private socket: Socket | null = null;
  private buffer = "";
  private pending: {
    resolve: (value: BridgeResponse) => void;
    reject: (reason: Error) => void;
    timer: ReturnType<typeof setTimeout>;
  } | null = null;

  get connected(): boolean {
    return this.socket !== null && !this.socket.destroyed;
  }

  async connect(port = 7777, host = "127.0.0.1", timeoutMs = 10_000): Promise<void> {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.socket?.destroy();
        reject(new Error(`Connection to bridge timed out after ${timeoutMs}ms`));
      }, timeoutMs);

      this.socket = new Socket();

      this.socket.connect(port, host, () => {
        clearTimeout(timer);
        resolve();
      });

      this.socket.on("error", (err) => {
        clearTimeout(timer);
        reject(err);
      });

      this.socket.on("data", (data: Buffer) => this.onData(data));

      this.socket.on("close", () => {
        if (this.pending) {
          clearTimeout(this.pending.timer);
          this.pending.reject(new Error("Bridge connection closed"));
          this.pending = null;
        }
        this.socket = null;
      });
    });
  }

  async send(cmd: Record<string, unknown>, timeoutMs = 30_000): Promise<BridgeResponse> {
    if (!this.socket || this.socket.destroyed) {
      throw new Error("Not connected to bridge");
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending = null;
        reject(new Error(`Bridge command timed out after ${timeoutMs}ms`));
      }, timeoutMs);

      this.pending = { resolve, reject, timer };
      this.socket!.write(JSON.stringify(cmd) + "\n");
    });
  }

  disconnect(): void {
    if (this.pending) {
      clearTimeout(this.pending.timer);
      this.pending.reject(new Error("Disconnected"));
      this.pending = null;
    }
    this.socket?.destroy();
    this.socket = null;
  }

  private onData(data: Buffer): void {
    this.buffer += data.toString("utf-8");
    let newlineIdx: number;
    while ((newlineIdx = this.buffer.indexOf("\n")) !== -1) {
      const line = this.buffer.slice(0, newlineIdx);
      this.buffer = this.buffer.slice(newlineIdx + 1);
      if (line.trim() === "") continue;
      try {
        const parsed = JSON.parse(line) as BridgeResponse;
        if (this.pending) {
          clearTimeout(this.pending.timer);
          const p = this.pending;
          this.pending = null;
          p.resolve(parsed);
        }
      } catch {
        if (this.pending) {
          clearTimeout(this.pending.timer);
          const p = this.pending;
          this.pending = null;
          p.reject(new Error(`Invalid JSON from bridge: ${line}`));
        }
      }
    }
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd tools/mcp && npx tsc --noEmit`

Expected: No errors.

- [ ] **Step 3: Commit**

```
git add tools/mcp/src/bridge-client.ts
git commit -m "feat: add bridge TCP client for validation MCP server"
```

---

### Task 5: TypeScript MCP Server -- Process Manager

**Files:**
- Create: `tools/mcp/src/process-manager.ts`

Manages the Godot process lifecycle: launch with the validation bridge flag, capture stdout/stderr, connect to the bridge, stop, and reload.

- [ ] **Step 1: Create process-manager.ts**

Create `tools/mcp/src/process-manager.ts`:

```typescript
import { ChildProcess, spawn } from "node:child_process";
import { BridgeClient } from "./bridge-client.js";

export interface LaunchOptions {
  scene?: string;
}

export class ProcessManager {
  private process: ChildProcess | null = null;
  private _stdout = "";
  private _stderr = "";
  private readonly godotPath: string;
  private readonly projectPath: string;
  private readonly bridgePort: number;
  readonly bridge: BridgeClient;

  constructor() {
    this.godotPath = process.env.GODOT_PATH ?? "godot";
    this.projectPath = process.env.GODOT_PROJECT_PATH ?? process.cwd();
    this.bridgePort = parseInt(process.env.VALIDATION_BRIDGE_PORT ?? "7777", 10);
    this.bridge = new BridgeClient();
  }

  get isRunning(): boolean {
    return this.process !== null && this.process.exitCode === null;
  }

  get stdout(): string {
    return this._stdout;
  }

  get stderr(): string {
    return this._stderr;
  }

  async launch(options: LaunchOptions = {}): Promise<string> {
    if (this.isRunning) {
      return "Game is already running. Use game_reload to restart.";
    }

    const args = ["--path", this.projectPath, "--windowed"];

    if (options.scene) {
      args.push(options.scene);
    }

    args.push("--", "--validation-bridge");

    this._stdout = "";
    this._stderr = "";

    this.process = spawn(this.godotPath, args, {
      stdio: ["ignore", "pipe", "pipe"],
    });

    this.process.stdout?.on("data", (d: Buffer) => {
      this._stdout += d.toString();
    });
    this.process.stderr?.on("data", (d: Buffer) => {
      this._stderr += d.toString();
    });

    this.process.on("exit", () => {
      this.bridge.disconnect();
      this.process = null;
    });

    // Retry connecting to the bridge until it's ready
    const maxRetries = 20;
    const retryDelayMs = 500;
    for (let i = 0; i < maxRetries; i++) {
      await sleep(retryDelayMs);

      if (!this.isRunning) {
        throw new Error(
          `Godot exited during startup.\nstdout:\n${this._stdout}\nstderr:\n${this._stderr}`
        );
      }

      try {
        await this.bridge.connect(this.bridgePort);
        return "Game launched and bridge connected.";
      } catch {
        // Bridge not ready yet, retry
      }
    }

    // Timed out -- kill the process and report
    this.process?.kill();
    throw new Error(
      `Bridge did not connect within ${(maxRetries * retryDelayMs) / 1000}s.\n` +
        `stdout:\n${this._stdout}\nstderr:\n${this._stderr}`
    );
  }

  async stop(): Promise<string> {
    if (!this.isRunning) {
      return "Game is not running.";
    }

    this.bridge.disconnect();

    const exitPromise = new Promise<void>((resolve) => {
      if (this.process) {
        this.process.on("exit", () => resolve());
      } else {
        resolve();
      }
    });

    this.process!.kill();
    await exitPromise;
    this.process = null;
    return "Game stopped.";
  }

  async reload(options: LaunchOptions = {}): Promise<string> {
    await this.stop();
    await sleep(500); // Brief pause for port to free
    return this.launch(options);
  }

  getErrors(): string[] {
    const lines = (this._stdout + "\n" + this._stderr).split("\n");
    return lines.filter(
      (l) =>
        l.includes("ERROR") ||
        l.includes("SCRIPT ERROR") ||
        l.includes("Parse Error") ||
        l.includes("Invalid") ||
        (l.includes("push_error") && !l.includes("ValidationBridge"))
    );
  }

  clearOutput(): void {
    this._stdout = "";
    this._stderr = "";
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd tools/mcp && npx tsc --noEmit`

Expected: No errors.

- [ ] **Step 3: Commit**

```
git add tools/mcp/src/process-manager.ts
git commit -m "feat: add Godot process manager for validation MCP server"
```

---

### Task 6: TypeScript MCP Server -- Tool Definitions

**Files:**
- Create: `tools/mcp/src/server.ts`

The main MCP server with all tool definitions: lifecycle (launch/stop/reload), query (screenshot/state), interaction (click/drag/key/scroll/wait), and batch (interact).

- [ ] **Step 1: Create server.ts**

Create `tools/mcp/src/server.ts`:

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { ProcessManager } from "./process-manager.js";

const pm = new ProcessManager();

const server = new McpServer({
  name: "tt-sim-validator",
  version: "0.1.0",
});

// ---------------------------------------------------------------------------
// Helper: check bridge is connected before sending commands
// ---------------------------------------------------------------------------

function requireBridge(): string | null {
  if (!pm.bridge.connected) {
    return "Game is not running. Call game_launch first.";
  }
  return null;
}

type ContentItem =
  | { type: "text"; text: string }
  | { type: "image"; data: string; mimeType: string };

// ---------------------------------------------------------------------------
// Lifecycle tools
// ---------------------------------------------------------------------------

server.tool(
  "game_launch",
  "Launch Godot with the validation bridge. Must be called before other game_ tools.",
  {
    scene: z
      .string()
      .optional()
      .describe("Scene path (e.g. res://scenes/root.tscn). Defaults to main scene."),
  },
  async ({ scene }) => {
    try {
      const msg = await pm.launch({ scene });
      return { content: [{ type: "text" as const, text: msg }] };
    } catch (e) {
      return {
        content: [{ type: "text" as const, text: `Launch failed: ${(e as Error).message}` }],
        isError: true,
      };
    }
  }
);

server.tool("game_stop", "Stop the running Godot instance.", {}, async () => {
  const msg = await pm.stop();
  return { content: [{ type: "text" as const, text: msg }] };
});

server.tool(
  "game_reload",
  "Stop and relaunch Godot. Use after making code changes.",
  {
    scene: z.string().optional().describe("Scene path. Defaults to main scene."),
  },
  async ({ scene }) => {
    try {
      const msg = await pm.reload({ scene });
      return { content: [{ type: "text" as const, text: msg }] };
    } catch (e) {
      return {
        content: [{ type: "text" as const, text: `Reload failed: ${(e as Error).message}` }],
        isError: true,
      };
    }
  }
);

// ---------------------------------------------------------------------------
// Query tools
// ---------------------------------------------------------------------------

server.tool(
  "game_screenshot",
  "Capture a screenshot of the current game viewport. Returns the image.",
  {},
  async () => {
    const err = requireBridge();
    if (err) return { content: [{ type: "text" as const, text: err }], isError: true };

    const result = await pm.bridge.send({ cmd: "screenshot" });
    if (!result.ok) {
      return {
        content: [{ type: "text" as const, text: `Screenshot failed: ${result.error}` }],
        isError: true,
      };
    }

    const content: ContentItem[] = [
      { type: "image", data: result.png_base64 as string, mimeType: "image/png" },
    ];
    const errors = pm.getErrors();
    if (errors.length > 0) {
      content.push({ type: "text", text: `Console errors:\n${errors.join("\n")}` });
    }
    return { content };
  }
);

server.tool(
  "game_state",
  "Query current game state: app state, tokens, UI panels, camera, scene tree, and console errors.",
  {},
  async () => {
    const err = requireBridge();
    if (err) return { content: [{ type: "text" as const, text: err }], isError: true };

    const result = await pm.bridge.send({ cmd: "state" });
    if (!result.ok) {
      return {
        content: [{ type: "text" as const, text: `State query failed: ${result.error}` }],
        isError: true,
      };
    }

    const errors = pm.getErrors();
    const state = { ...result, console_errors: errors };
    return { content: [{ type: "text", text: JSON.stringify(state, null, 2) }] };
  }
);

// ---------------------------------------------------------------------------
// Interaction tools
// ---------------------------------------------------------------------------

server.tool(
  "game_click",
  "Click at viewport coordinates.",
  {
    x: z.number().describe("X coordinate in viewport pixels"),
    y: z.number().describe("Y coordinate in viewport pixels"),
    button: z
      .enum(["left", "right", "middle"])
      .default("left")
      .describe("Mouse button"),
  },
  async ({ x, y, button }) => {
    const err = requireBridge();
    if (err) return { content: [{ type: "text" as const, text: err }], isError: true };

    const result = await pm.bridge.send({ cmd: "input", type: "click", x, y, button });
    return {
      content: [{ type: "text" as const, text: result.ok ? "Clicked." : `Error: ${result.error}` }],
    };
  }
);

server.tool(
  "game_drag",
  "Drag from one viewport position to another.",
  {
    x1: z.number().describe("Start X"),
    y1: z.number().describe("Start Y"),
    x2: z.number().describe("End X"),
    y2: z.number().describe("End Y"),
  },
  async ({ x1, y1, x2, y2 }) => {
    const err = requireBridge();
    if (err) return { content: [{ type: "text" as const, text: err }], isError: true };

    const result = await pm.bridge.send({ cmd: "input", type: "drag", x1, y1, x2, y2 });
    return {
      content: [{ type: "text" as const, text: result.ok ? "Dragged." : `Error: ${result.error}` }],
    };
  }
);

server.tool(
  "game_key",
  "Press and release a key.",
  {
    key: z.string().describe("Key name (e.g. 'M', 'Escape', 'Home', 'Space')"),
  },
  async ({ key }) => {
    const err = requireBridge();
    if (err) return { content: [{ type: "text" as const, text: err }], isError: true };

    const result = await pm.bridge.send({ cmd: "input", type: "key", key });
    return {
      content: [
        { type: "text" as const, text: result.ok ? `Key '${key}' pressed.` : `Error: ${result.error}` },
      ],
    };
  }
);

server.tool(
  "game_scroll",
  "Scroll the mouse wheel at a viewport position.",
  {
    x: z.number().describe("X coordinate"),
    y: z.number().describe("Y coordinate"),
    delta: z.number().describe("Scroll amount (positive = zoom in, negative = zoom out)"),
  },
  async ({ x, y, delta }) => {
    const err = requireBridge();
    if (err) return { content: [{ type: "text" as const, text: err }], isError: true };

    const result = await pm.bridge.send({ cmd: "input", type: "scroll", x, y, delta });
    return {
      content: [{ type: "text" as const, text: result.ok ? "Scrolled." : `Error: ${result.error}` }],
    };
  }
);

server.tool(
  "game_wait",
  "Wait for a duration (for animations/transitions to settle).",
  {
    seconds: z.number().default(0.5).describe("Seconds to wait"),
  },
  async ({ seconds }) => {
    const err = requireBridge();
    if (err) return { content: [{ type: "text" as const, text: err }], isError: true };

    const result = await pm.bridge.send({ cmd: "wait", seconds });
    return {
      content: [
        { type: "text" as const, text: result.ok ? `Waited ${seconds}s.` : `Error: ${result.error}` },
      ],
    };
  }
);

// ---------------------------------------------------------------------------
// Batch tool
// ---------------------------------------------------------------------------

const StepSchema = z.discriminatedUnion("action", [
  z.object({ action: z.literal("click"), x: z.number(), y: z.number(), button: z.enum(["left", "right", "middle"]).default("left") }),
  z.object({ action: z.literal("drag"), x1: z.number(), y1: z.number(), x2: z.number(), y2: z.number() }),
  z.object({ action: z.literal("key"), key: z.string() }),
  z.object({ action: z.literal("scroll"), x: z.number(), y: z.number(), delta: z.number() }),
  z.object({ action: z.literal("wait"), seconds: z.number() }),
  z.object({ action: z.literal("screenshot") }),
  z.object({ action: z.literal("state") }),
]);

server.tool(
  "game_interact",
  "Execute a sequence of interactions and return collected screenshots and state. " +
    "Preferred over individual calls for multi-step validation.",
  {
    steps: z.array(StepSchema).describe("Sequence of actions to perform"),
  },
  async ({ steps }) => {
    const err = requireBridge();
    if (err) return { content: [{ type: "text" as const, text: err }], isError: true };

    const content: ContentItem[] = [];

    for (const step of steps) {
      switch (step.action) {
        case "click":
          await pm.bridge.send({
            cmd: "input", type: "click",
            x: step.x, y: step.y, button: step.button,
          });
          break;
        case "drag":
          await pm.bridge.send({
            cmd: "input", type: "drag",
            x1: step.x1, y1: step.y1, x2: step.x2, y2: step.y2,
          });
          break;
        case "key":
          await pm.bridge.send({ cmd: "input", type: "key", key: step.key });
          break;
        case "scroll":
          await pm.bridge.send({
            cmd: "input", type: "scroll",
            x: step.x, y: step.y, delta: step.delta,
          });
          break;
        case "wait":
          await pm.bridge.send({ cmd: "wait", seconds: step.seconds });
          break;
        case "screenshot": {
          const result = await pm.bridge.send({ cmd: "screenshot" });
          if (result.ok) {
            content.push({
              type: "image",
              data: result.png_base64 as string,
              mimeType: "image/png",
            });
          } else {
            content.push({ type: "text", text: `Screenshot failed: ${result.error}` });
          }
          break;
        }
        case "state": {
          const result = await pm.bridge.send({ cmd: "state" });
          const errors = pm.getErrors();
          const state = { ...result, console_errors: errors };
          content.push({ type: "text", text: JSON.stringify(state, null, 2) });
          break;
        }
      }
    }

    if (content.length === 0) {
      content.push({ type: "text", text: "All steps completed (no screenshot or state requested)." });
    }

    return { content };
  }
);

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err: unknown) => {
  process.stderr.write(`MCP server failed to start: ${err}\n`);
  process.exit(1);
});
```

- [ ] **Step 2: Verify it compiles**

Run: `cd tools/mcp && npx tsc --noEmit`

Expected: No errors.

- [ ] **Step 3: Commit**

```
git add tools/mcp/src/server.ts
git commit -m "feat: add MCP server with all validation tools

Lifecycle: game_launch, game_stop, game_reload
Query: game_screenshot, game_state
Interaction: game_click, game_drag, game_key, game_scroll, game_wait
Batch: game_interact (preferred for multi-step validation)"
```

---

### Task 7: Build and Integration Verification

**Files:**
- No new files (build output goes to `tools/mcp/dist/`, which is gitignored)

- [ ] **Step 1: Build the TypeScript project**

Run: `cd tools/mcp && npx tsc`

Expected: `dist/` directory created with `server.js`, `bridge-client.js`, `process-manager.js`, and their `.d.ts` files. No compilation errors.

- [ ] **Step 2: Verify MCP server starts**

Run: `echo '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}},"id":1}' | node tools/mcp/dist/server.js`

Expected: JSON response containing `"result"` with server capabilities and tool list. This confirms the MCP server can start and respond to the initialize handshake.

- [ ] **Step 3: End-to-end integration test**

This is a manual verification. Run these commands in sequence:

1. Launch Godot with the bridge: `godot --path . -- --validation-bridge`
2. In a separate terminal, test the bridge directly with a TCP connection:

```bash
echo '{"cmd":"state"}' | nc localhost 7777
```

Expected: JSON response with `"ok": true`, `"app_state": "TITLE_SCREEN"`, `"tokens": []`, etc.

3. Test screenshot:

```bash
echo '{"cmd":"screenshot"}' | nc localhost 7777
```

Expected: JSON response with `"ok": true` and a `"png_base64"` field containing a base64-encoded PNG string. The `"width"` and `"height"` fields should match the viewport size (1920x1080 or the window size).

4. Close Godot.

- [ ] **Step 4: Register MCP server with Claude Code**

Run: `claude mcp add tt-sim-validator -- node D:/dev/tt-sim/tools/mcp/dist/server.js`

Expected: MCP server registered. In subsequent Claude Code sessions within the tt-sim project, the `game_launch`, `game_screenshot`, etc. tools will be available.

Note: If the Godot executable is not on PATH as `godot`, set the environment variable when registering:

```bash
claude mcp add tt-sim-validator -e GODOT_PATH="D:/Apps/Godot 4.6/Godot.exe" -- node D:/dev/tt-sim/tools/mcp/dist/server.js
```

- [ ] **Step 5: Verify tools appear in Claude Code**

Start a new Claude Code session in the tt-sim project. The MCP tools should appear in the available tools list. Test with a simple sequence:

1. Agent calls `game_launch` -- game window opens
2. Agent calls `game_screenshot` -- returns an image of the title screen
3. Agent calls `game_state` -- returns JSON with `app_state: "TITLE_SCREEN"`
4. Agent calls `game_stop` -- game window closes

If all four work, the integration is complete.
