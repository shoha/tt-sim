"""Collect the GDScript analyzer warnings the editor shows, headless.

The analyzer sends its warnings to an attached debugger only (nothing reaches stdout), so
this script is a minimal debugger: it listens on a TCP port, starts Godot with
--remote-debug against it, runs tools/gdscript_warnings/probe.tscn (which recompiles every
project script), keeps the game running past the debugger's pauses, decodes the "error"
messages and prints counts by code and by file.

    python tools/gdscript_warnings/collect.py [--project D:/dev/tabletop/tt-sim]
        [--godot godot] [--port 6010] [--out warnings.tsv] [--scene res://...] [--frames N]

--out gets one line per warning: file:line, code, message. With --scene and --frames the
given scene runs for that many frames instead (a startup check of what the running game
reports). Exit code 1 when any warning or script error was seen.
"""

import argparse
import collections
import shutil
import socket
import struct
import subprocess
import threading
import time


def _decode(buf, off):
    head = struct.unpack_from("<I", buf, off)[0]
    off += 4
    kind, flags = head & 0xFF, head >> 16
    if kind == 0:
        return None, off
    if kind == 1:
        return bool(struct.unpack_from("<I", buf, off)[0]), off + 4
    if kind == 2:
        if flags & 1:
            return struct.unpack_from("<q", buf, off)[0], off + 8
        return struct.unpack_from("<i", buf, off)[0], off + 4
    if kind == 3:
        if flags & 1:
            return struct.unpack_from("<d", buf, off)[0], off + 8
        return struct.unpack_from("<f", buf, off)[0], off + 4
    if kind == 4:
        size = struct.unpack_from("<I", buf, off)[0]
        off += 4
        text = buf[off:off + size].decode("utf8", "replace")
        return text, off + ((size + 3) & ~3)
    if kind == 28:
        count = struct.unpack_from("<I", buf, off)[0] & 0x7FFFFFFF
        off += 4
        items = []
        for _ in range(count):
            item, off = _decode(buf, off)
            items.append(item)
        return items, off
    raise ValueError("variant type %d" % kind)


def _messages(raw):
    off, out = 0, []
    while off + 4 <= len(raw):
        size = struct.unpack_from("<I", raw, off)[0]
        off += 4
        try:
            out.append(_decode(raw, off)[0])
        except (ValueError, struct.error):
            pass  # a stack dump or other message the decoder does not know
        off += size
    return out


def _continue_message():
    def string(text):
        data = text.encode()
        return struct.pack("<II", 4, len(data)) + data + b"\0" * (-len(data) % 4)

    body = (
        struct.pack("<II", 28, 3)
        + string("continue")
        + struct.pack("<II", 2, 1)
        + struct.pack("<II", 28, 0)
    )
    return struct.pack("<I", len(body)) + body


def _listen(port, sink):
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(1)
    server.settimeout(300)
    conn, _ = server.accept()
    conn.settimeout(5)
    stop = threading.Event()

    def keep_running():
        # A script error pauses the game at the debugger; answer every pause with continue.
        while not stop.is_set():
            try:
                conn.sendall(_continue_message())
            except OSError:
                return
            time.sleep(0.3)

    threading.Thread(target=keep_running, daemon=True).start()
    idle = 0
    while idle < 4:
        try:
            chunk = conn.recv(65536)
            if not chunk:
                break
            sink.extend(chunk)
            idle = 0
        except socket.timeout:
            idle += 1
        except OSError:
            break
    stop.set()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="D:/dev/tabletop/tt-sim")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--port", type=int, default=6010)
    parser.add_argument("--out", default="")
    parser.add_argument("--scene", default="res://tools/gdscript_warnings/probe.tscn")
    parser.add_argument("--frames", type=int, default=0)
    args = parser.parse_args()

    raw = bytearray()
    listener = threading.Thread(target=_listen, args=(args.port, raw))
    listener.start()
    time.sleep(1)
    command = [shutil.which(args.godot) or args.godot, "--headless", "--path", args.project]
    command += ["--remote-debug", "tcp://127.0.0.1:%d" % args.port]
    if args.frames:
        command += ["--quit-after", str(args.frames)]
    else:
        command.append(args.scene)
    try:
        subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    finally:
        try:  # wakes the listener if Godot never connected
            socket.create_connection(("127.0.0.1", args.port), timeout=2).close()
        except OSError:
            pass
    listener.join()

    seen = {}
    for msg in _messages(bytes(raw)):
        if isinstance(msg, list) and msg and msg[0] == "error":
            data = msg[2]
            seen[(data[4], data[6], data[7], data[8])] = True
    by_code = collections.Counter(key[2] for key in seen)
    by_file = collections.Counter(key[0] for key in seen)
    print("%d reports" % len(seen))
    for code, count in by_code.most_common():
        print("  %5d  %s" % (count, code))
    print("top files:")
    for path, count in by_file.most_common(15):
        print("  %5d  %s" % (count, path))
    if args.out:
        with open(args.out, "w", encoding="utf8") as handle:
            for key in sorted(seen):
                handle.write("%s:%s\t%s\t%s\n" % (key[0], key[1], key[2], key[3]))
    raise SystemExit(1 if seen else 0)


if __name__ == "__main__":
    main()
