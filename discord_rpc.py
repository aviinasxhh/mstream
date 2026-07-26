#!/usr/bin/env python3

import socket
import struct
import json
import os
import sys
import time
import uuid
import signal

CONFIG_DIR = os.path.expanduser("~/.mstream")
CLIENT_ID_FILE = os.path.join(CONFIG_DIR, "discord_client_id")
NOW_FILE = os.path.join(CONFIG_DIR, "now_playing")
POS_FILE = os.path.join(CONFIG_DIR, "pos")
DURATION_FILE = os.path.join(CONFIG_DIR, "duration")
ARTWORK_FILE = os.path.join(CONFIG_DIR, "artwork_url")
PAUSED_FILE = os.path.join(CONFIG_DIR, "paused")
PID_FILE = os.path.join(CONFIG_DIR, "mpv.pid")
QUEUE_FILE = os.path.join(CONFIG_DIR, "queue.txt")


def find_ipc_socket():
    candidates = []

    for env_var in ("XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"):
        d = os.environ.get(env_var)
        if d:
            candidates.append(d)
    candidates.append("/tmp")

    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    if runtime:
        candidates.append(os.path.join(runtime, "snap.discord"))
        candidates.append(
            os.path.join(runtime, "app", "com.discordapp.Discord")
        )

    for base in candidates:
        for i in range(10):
            path = os.path.join(base, f"discord-ipc-{i}")
            if os.path.exists(path):
                return path
    return None


def read_file(path):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except (FileNotFoundError, IOError, PermissionError):
        return ""


class DiscordRPC:

    def __init__(self, client_id):
        self.client_id = client_id
        self.sock = None

    def connect(self):
        path = find_ipc_socket()
        if not path:
            return False
        try:
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.settimeout(5)
            self.sock.connect(path)
            self._send(0, {"v": 1, "client_id": self.client_id})
            resp = self._recv()
            if resp and resp.get("cmd") == "DISPATCH" and resp.get("evt") == "READY":
                return True
            if resp and "code" not in resp.get("data", {}):
                return True
            self.close()
            return False
        except (socket.error, OSError):
            self.close()
            return False

    def _send(self, opcode, payload):
        data = json.dumps(payload).encode("utf-8")
        header = struct.pack("<II", opcode, len(data))
        self.sock.sendall(header + data)

    def _recv(self):
        try:
            header = b""
            while len(header) < 8:
                chunk = self.sock.recv(8 - len(header))
                if not chunk:
                    return None
                header += chunk
            _opcode, length = struct.unpack("<II", header)
            data = b""
            while len(data) < length:
                chunk = self.sock.recv(length - len(data))
                if not chunk:
                    break
                data += chunk
            return json.loads(data.decode("utf-8"))
        except (socket.timeout, socket.error, OSError):
            return None

    def set_activity(self, activity=None):
        payload = {
            "cmd": "SET_ACTIVITY",
            "args": {"pid": os.getpid(), "activity": activity},
            "nonce": str(uuid.uuid4()),
        }
        try:
            self._send(1, payload)
            self._recv()
        except (socket.error, OSError, BrokenPipeError):
            raise ConnectionError("Discord disconnected")

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None


def build_activity(title, artist, artwork, pos_str, dur_str, is_paused):
    activity = {
        "type": 2, 
        "details": title,
        "state": f"by {artist}",
        "assets": {},
    }

    if artwork:
        activity["assets"]["large_image"] = artwork

    if not is_paused and pos_str and dur_str:
        try:
            pos = float(pos_str)
            dur = float(dur_str)
            if dur > 0:
                now = int(time.time())
                start = now - int(pos)
                end = start + int(dur)
                activity["timestamps"] = {"start": start, "end": end}
        except (ValueError, TypeError):
            pass

    return activity


def main():
    client_id = read_file(CLIENT_ID_FILE)
    if not client_id:
        sys.exit(1)

    def signal_handler(_sig, _frame):
        sys.exit(0)

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    rpc = DiscordRPC(client_id)

    last_state = None
    idle_count = 0

    try:
        while True:
            try:
                if not rpc.sock:
                    if not rpc.connect():
                        time.sleep(15)
                        continue

                now_playing = read_file(NOW_FILE)

                if not now_playing:
                    current_state = "idle"
                    if last_state != current_state:
                        try:
                            rpc.set_activity(None)
                        except ConnectionError:
                            rpc.close()
                            last_state = None
                            continue
                        last_state = current_state

                    idle_count += 1
                    if idle_count > 12 and not os.path.exists(QUEUE_FILE):
                        break

                    time.sleep(5)
                    continue

                idle_count = 0

                parts = now_playing.split("|")
                if len(parts) < 3:
                    time.sleep(5)
                    continue

                _vid, title, artist = parts[0], parts[1], parts[2]

                is_paused = os.path.exists(PAUSED_FILE)
                pos_str = read_file(POS_FILE)
                dur_str = read_file(DURATION_FILE)
                artwork = read_file(ARTWORK_FILE)

                current_state = f"{now_playing}|{is_paused}|{bool(dur_str)}"

                if current_state != last_state:
                    if is_paused:
                        activity = None
                    else:
                        activity = build_activity(
                            title, artist, artwork, pos_str, dur_str, is_paused
                        )
                    try:
                        rpc.set_activity(activity)
                        last_state = current_state
                    except ConnectionError:
                        rpc.close()
                        last_state = None
                        continue

            except ConnectionError:
                rpc.close()
                last_state = None
                time.sleep(15)
                continue
            except Exception:
                time.sleep(15)
                continue

            time.sleep(5)

    finally:
        if rpc.sock:
            try:
                rpc.set_activity(None)
            except Exception:
                pass
            rpc.close()


if __name__ == "__main__":
    main()
