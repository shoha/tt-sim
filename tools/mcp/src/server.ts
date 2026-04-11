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
