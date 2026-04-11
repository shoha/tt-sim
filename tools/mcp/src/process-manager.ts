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
