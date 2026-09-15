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

  /**
   * How many responses to earlier, timed-out commands are still owed by the bridge.
   *
   * The wire protocol carries no request id, so a response is matched to a request purely by
   * arrival order. A command that times out does NOT cancel anything on the bridge -- it is a
   * single-threaded loop that finishes the command and answers it eventually -- so without this
   * counter the late reply would resolve whatever request happened to be pending when it landed.
   * That is a silent wrong answer: a `state` issued after a timed-out `step` would report the
   * step's `{"ok": true}` as its own. Counting the owed replies and discarding exactly that many
   * incoming lines keeps the stream aligned without inventing a protocol change.
   *
   * This is sound because the bridge serializes commands and answers each exactly once. If the
   * bridge is genuinely dead rather than slow the counter only grows and every later command times
   * out too -- loud and self-consistent, never a wrong answer. Correlation ids in the protocol
   * itself remain the real fix; this is the cheap half of it on the client side only.
   */
  private orphanedResponses = 0;

  get connected(): boolean {
    return this.socket !== null && !this.socket.destroyed;
  }

  async connect(port = 7777, host = "127.0.0.1", timeoutMs = 10_000): Promise<void> {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.socket?.destroy();
        reject(new Error(`Connection to bridge timed out after ${timeoutMs}ms`));
      }, timeoutMs);

      // A fresh socket is a fresh stream: nothing from the previous connection can still arrive.
      this.buffer = "";
      this.orphanedResponses = 0;
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
    const socket = this.socket;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending = null;
        // The bridge still owes a reply to this command; skip it when it arrives.
        this.orphanedResponses += 1;
        reject(
          new Error(
            `Bridge command timed out after ${timeoutMs}ms. Its late reply will be discarded; ` +
              `subsequent commands stay correctly matched.`
          )
        );
      }, timeoutMs);

      this.pending = { resolve, reject, timer };
      socket.write(JSON.stringify(cmd) + "\n");
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
    this.buffer = "";
    this.orphanedResponses = 0;
  }

  private onData(data: Buffer): void {
    this.buffer += data.toString("utf-8");
    let newlineIdx: number;
    while ((newlineIdx = this.buffer.indexOf("\n")) !== -1) {
      const line = this.buffer.slice(0, newlineIdx);
      this.buffer = this.buffer.slice(newlineIdx + 1);
      if (line.trim() === "") continue;
      if (this.orphanedResponses > 0) {
        this.orphanedResponses -= 1;
        continue;
      }
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
