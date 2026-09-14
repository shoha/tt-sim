import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { ProcessManager } from "./process-manager.js";
import type { BridgeResponse } from "./bridge-client.js";

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
// Helper: timeouts for commands that block the bridge for a known length of time
// ---------------------------------------------------------------------------

/** Project default for physics_ticks_per_second; only used to turn frames into a wall-clock bound. */
const PHYSICS_TICKS_PER_SECOND = 60;

/** Matches BridgeTimeControl.MAX_STEP_FRAMES, the bridge's own cap on a single step. */
const MAX_STEP_FRAMES = 6000;

/** Matches ValidationBridge.STEP_UNTIL_DEFAULT_MAX_FRAMES, applied when the caller omits maxFrames. */
const DEFAULT_STEP_UNTIL_MAX_FRAMES = 300;

/** Never wait less than this, so a short step still tolerates a slow frame or a loaded host. */
const STEP_TIMEOUT_FLOOR_MS = 30_000;

/** Slack on top of the frames' own duration, for scene work the step triggers on its way through. */
const STEP_TIMEOUT_OVERHEAD_MS = 15_000;

/**
 * Wall-clock budget for a `step` or `step_until` that may run up to `frames` physics frames.
 *
 * A step holds the bridge's socket for roughly its own game-time duration, and the bridge's cap is
 * 6000 frames -- about 100 real seconds at 60 Hz -- comfortably past the client's 30s default. The
 * global default is deliberately NOT raised to cover that: a 115-second timeout on every command
 * would turn a genuinely hung bridge into a two-minute stall on a `state` query. Only the two
 * commands whose duration is known up front get the longer budget, derived from that duration.
 */
function stepTimeoutMs(frames: number | undefined, seconds: number | undefined): number {
  const requested =
    frames !== undefined && frames > 0
      ? frames
      : seconds !== undefined && seconds > 0
        ? seconds * PHYSICS_TICKS_PER_SECOND
        : 0;
  const bounded = Math.min(Math.max(requested, 0), MAX_STEP_FRAMES);
  const durationMs = (bounded / PHYSICS_TICKS_PER_SECOND) * 1000;
  return Math.max(STEP_TIMEOUT_FLOOR_MS, durationMs + STEP_TIMEOUT_OVERHEAD_MS);
}

/** As stepTimeoutMs, for step_until, whose bound is maxFrames and whose default is 300 frames. */
function stepUntilTimeoutMs(maxFrames: number | undefined): number {
  return stepTimeoutMs(
    maxFrames !== undefined && maxFrames > 0 ? maxFrames : DEFAULT_STEP_UNTIL_MAX_FRAMES,
    undefined
  );
}

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
      const msg = e instanceof Error ? e.message : String(e);
      return {
        content: [{ type: "text" as const, text: `Launch failed: ${msg}` }],
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
      const msg = e instanceof Error ? e.message : String(e);
      return {
        content: [{ type: "text" as const, text: `Reload failed: ${msg}` }],
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
  "Query current game state: app state, tokens, UI panels, camera, scene tree, console errors, " +
    "and the clock ('frozen' and 'time_scale'). Check 'frozen' first when nothing seems to move: " +
    "a frozen game is indistinguishable from a hung one until you look at it.",
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
// Deterministic time control
// ---------------------------------------------------------------------------

server.tool(
  "game_time",
  "Control game time deterministically. 'freeze' stops the clock (physics stops, process delta " +
    "becomes 0, rendering and this bridge keep running). 'step' advances an exact slice of game " +
    "time. 'step_until' advances until a GDScript expression is truthy. 'resume' restores normal " +
    "time. Prefer freeze + step + step_until over game_wait: waits race the game, steps do not.",
  {
    action: z
      .enum(["freeze", "resume", "step", "step_until"])
      .describe("Which time operation to perform"),
    seconds: z
      .number()
      .optional()
      .describe("For 'step': game time to advance. Converted to whole physics frames."),
    frames: z
      .number()
      .int()
      .optional()
      .describe("For 'step': exact physics frames to advance. Takes precedence over seconds."),
    expression: z
      .string()
      .optional()
      .describe(
        "For 'step_until': GDScript expression evaluated against the current scene each frame."
      ),
    maxFrames: z
      .number()
      .int()
      .optional()
      .describe("For 'step_until': frames to advance before giving up. Defaults to 300."),
  },
  async ({ action, seconds, frames, expression, maxFrames }) => {
    const err = requireBridge();
    if (err) return { content: [{ type: "text" as const, text: err }], isError: true };

    let result: BridgeResponse;
    switch (action) {
      case "freeze":
        result = await pm.bridge.send({ cmd: "freeze" });
        break;
      case "resume":
        result = await pm.bridge.send({ cmd: "resume" });
        break;
      case "step":
        result = await pm.bridge.send(
          { cmd: "step", seconds, frames },
          stepTimeoutMs(frames, seconds)
        );
        break;
      case "step_until":
        result = await pm.bridge.send(
          {
            cmd: "step_until",
            expression,
            max_frames: maxFrames,
          },
          stepUntilTimeoutMs(maxFrames)
        );
        break;
    }

    return {
      content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }],
      isError: !result.ok,
    };
  }
);

// ---------------------------------------------------------------------------
// Inspection
// ---------------------------------------------------------------------------

server.tool(
  "game_eval",
  "Evaluate a GDScript expression against the running game's current scene and return the value. " +
    "Use this to read state that game_state does not report, instead of editing the bridge. " +
    "Expressions cannot declare variables, loop, or assign, but can read properties and call " +
    "methods, e.g. 'find_child(\"GameMap\", true, false).camera_node.size' or " +
    "'get_node(\"/root/GameState\").get_all_token_states().size()'.",
  {
    expression: z.string().describe("GDScript expression, evaluated with the current scene as self"),
  },
  async ({ expression }) => {
    const err = requireBridge();
    if (err) return { content: [{ type: "text" as const, text: err }], isError: true };

    const result = await pm.bridge.send({ cmd: "eval", expression });
    return {
      content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }],
      isError: !result.ok,
    };
  }
);

server.tool(
  "game_controls",
  "List Control nodes in the running game with their viewport-space rect and centre point, up " +
    "to 200. The response carries a 'truncated' flag: when it is true the walk hit the cap, so a " +
    "control you expect but don't see may be past the cap rather than absent from the scene. " +
    "Walks from the window root, so dialogs and overlays parented outside the current scene are " +
    "included (game_state's scene_tree does not see those). Use this to find what to click.",
  {
    visibleOnly: z
      .boolean()
      .default(true)
      .describe("Only report Controls currently visible in the tree"),
  },
  async ({ visibleOnly }) => {
    const err = requireBridge();
    if (err) return { content: [{ type: "text" as const, text: err }], isError: true };

    const result = await pm.bridge.send({ cmd: "controls", visible_only: visibleOnly });
    return {
      content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }],
      isError: !result.ok,
    };
  }
);

server.tool(
  "game_click_control",
  "Click a Control by node name, node path, or exact button text. Prefer this over game_click: " +
    "it needs no coordinate conversion, so it cannot miss because of the viewport/window size " +
    "mismatch. Fails loudly when the query matches nothing or is ambiguous. Cannot click items " +
    "inside an open OptionButton popup menu (a Godot PopupMenu is a Window, not a Control) -- " +
    "use game_key with arrow keys and Enter for those.",
  {
    query: z.string().describe("Node name, node path, or exact button/label text"),
    button: z.enum(["left", "right", "middle"]).default("left").describe("Mouse button"),
  },
  async ({ query, button }) => {
    const err = requireBridge();
    if (err) return { content: [{ type: "text" as const, text: err }], isError: true };

    const result = await pm.bridge.send({ cmd: "input", type: "click_control", query, button });
    return {
      content: [{ type: "text" as const, text: JSON.stringify(result, null, 2) }],
      isError: !result.ok,
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
  z.object({ action: z.literal("freeze") }),
  z.object({ action: z.literal("resume") }),
  z.object({ action: z.literal("step"), seconds: z.number().optional(), frames: z.number().int().optional() }),
  z.object({ action: z.literal("step_until"), expression: z.string(), maxFrames: z.number().int().optional() }),
  z.object({ action: z.literal("eval"), expression: z.string() }),
  z.object({ action: z.literal("controls"), visibleOnly: z.boolean().default(true) }),
  z.object({ action: z.literal("click_control"), query: z.string(), button: z.enum(["left", "right", "middle"]).default("left") }),
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
        case "click": {
          const result = await pm.bridge.send({
            cmd: "input", type: "click",
            x: step.x, y: step.y, button: step.button,
          });
          if (!result.ok) {
            content.push({ type: "text", text: `Step failed (click): ${result.error}` });
          }
          break;
        }
        case "drag": {
          const result = await pm.bridge.send({
            cmd: "input", type: "drag",
            x1: step.x1, y1: step.y1, x2: step.x2, y2: step.y2,
          });
          if (!result.ok) {
            content.push({ type: "text", text: `Step failed (drag): ${result.error}` });
          }
          break;
        }
        case "key": {
          const result = await pm.bridge.send({ cmd: "input", type: "key", key: step.key });
          if (!result.ok) {
            content.push({ type: "text", text: `Step failed (key): ${result.error}` });
          }
          break;
        }
        case "scroll": {
          const result = await pm.bridge.send({
            cmd: "input", type: "scroll",
            x: step.x, y: step.y, delta: step.delta,
          });
          if (!result.ok) {
            content.push({ type: "text", text: `Step failed (scroll): ${result.error}` });
          }
          break;
        }
        case "wait": {
          const result = await pm.bridge.send({ cmd: "wait", seconds: step.seconds });
          if (!result.ok) {
            content.push({ type: "text", text: `Step failed (wait): ${result.error}` });
          }
          break;
        }
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
        case "freeze":
        case "resume": {
          const result = await pm.bridge.send({ cmd: step.action });
          if (!result.ok) {
            content.push({ type: "text", text: `Step failed (${step.action}): ${result.error}` });
          }
          break;
        }
        case "step": {
          // Same derived timeout as the standalone game_time tool: this is an independent code
          // path, and leaving it on the 30s default is what lets a long step's late reply be
          // mistaken for the next step's result.
          const result = await pm.bridge.send(
            {
              cmd: "step",
              seconds: step.seconds,
              frames: step.frames,
            },
            stepTimeoutMs(step.frames, step.seconds)
          );
          if (!result.ok) {
            content.push({ type: "text", text: `Step failed (step): ${result.error}` });
          }
          break;
        }
        case "step_until": {
          const result = await pm.bridge.send(
            {
              cmd: "step_until",
              expression: step.expression,
              max_frames: step.maxFrames,
            },
            stepUntilTimeoutMs(step.maxFrames)
          );
          content.push({ type: "text", text: JSON.stringify(result, null, 2) });
          break;
        }
        case "eval": {
          const result = await pm.bridge.send({ cmd: "eval", expression: step.expression });
          content.push({ type: "text", text: JSON.stringify(result, null, 2) });
          break;
        }
        case "controls": {
          const result = await pm.bridge.send({
            cmd: "controls",
            visible_only: step.visibleOnly,
          });
          content.push({ type: "text", text: JSON.stringify(result, null, 2) });
          break;
        }
        case "click_control": {
          const result = await pm.bridge.send({
            cmd: "input",
            type: "click_control",
            query: step.query,
            button: step.button,
          });
          if (!result.ok) {
            content.push({
              type: "text",
              text: `Step failed (click_control): ${JSON.stringify(result)}`,
            });
          }
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
