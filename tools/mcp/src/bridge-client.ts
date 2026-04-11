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
