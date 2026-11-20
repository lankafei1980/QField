#!/usr/bin/env python3
"""A tiny NTRIP caster used to test QField's NTRIP client without hardware.

It speaks enough of NTRIP 1.0 / 2.0 to be usable by QField:

  * answers ``GET /MOUNTPOINT`` with ``ICY 200 OK`` (v1) or ``HTTP/1.1 200 OK`` (v2)
  * optionally enforces HTTP basic authentication (``--user`` / ``--password``)
  * answers a plain ``GET /`` with a small SOURCETABLE (``AUTO``, ``RTCM32_GGB``)
  * records every GGA sentence received from the client
  * streams dummy RTCM 3.x frames at 1 Hz
  * can drop the connection after N seconds to exercise reconnection logic

Only the framing is real (RTCM 3 with a valid CRC-24Q); the payloads are
placeholders. A real receiver would reject them, but QField only forwards the
bytes, so this is enough to verify the whole chain.

Usage::

    python3 tools/dev/mock_ntrip_caster.py --port 2101 --user demo --password demo

Then in QField: Positioning > device (TCP mock receiver or real device) >
  Enable NTRIP corrections > Host: <your computer IP>, Port: 2101,
  Mount point: AUTO, Username: demo, Password: demo.
"""

import argparse
import base64
import datetime
import socket
import socketserver
import struct
import sys
import threading
import time

# --- RTCM 3 framing -------------------------------------------------------

CRC24Q_TABLE = []


def _build_crc_table():
    for i in range(256):
        crc = i << 16
        for _ in range(8):
            crc <<= 1
            if crc & 0x1000000:
                crc ^= 0x1864CFB
        CRC24Q_TABLE.append(crc & 0xFFFFFF)


_build_crc_table()


def crc24q(data):
    crc = 0
    for byte in data:
        crc = ((crc << 8) & 0xFFFFFF) ^ CRC24Q_TABLE[((crc >> 16) ^ byte) & 0xFF]
    return crc


def rtcm_frame(message_number, payload):
    body = bytes([(message_number >> 4) & 0xFF, ((message_number & 0x0F) << 4) | 0x00]) + payload
    length = len(body)
    framed = bytes([0xD3, (length >> 8) & 0x03, length & 0xFF]) + body
    crc = crc24q(framed)
    return framed + bytes([(crc >> 16) & 0xFF, (crc >> 8) & 0xFF, crc & 0xFF])


def rtcm_1005():
    # station id 1, ITRF-ish placeholder coordinates
    body = struct.pack(">HBBi", 1, 0, 0, 0) + bytes(19)
    return rtcm_frame(1005, body)


def rtcm_msm(message_number, cell_mask_len=12):
    # header (12 bytes) + satellite data + signal data, all zeroed
    body = bytes(1) + struct.pack(">HB", 1, 0) + bytes(8) + bytes(cell_mask_len) + bytes(40)
    return rtcm_frame(message_number, body)


RTCM_STREAM = [
    rtcm_1005(),
    rtcm_msm(1074),
    rtcm_msm(1084),
    rtcm_msm(1094),
    rtcm_msm(1124),
    rtcm_frame(1230, bytes(2)),
]

SOURCETABLE = "\r\n".join(
    [
        "SOURCETABLE 200 OK",
        "Server: mock-ntrip/1.0",
        "Content-Type: text/plain",
        "Content-Length: 0",
        "",
        "STR;AUTO;AUTO;RTCM 3.3;1005(1),1074(1),1084(1),1094(1),1124(1),1230(1);0;GPS;GB;CHN;0.00;0.00;0.00;0;0;mock;none;N;N;4096;",
        "STR;RTCM32_GGB;RTCM32_GGB;RTCM 3.2;1005(1),1074(1),1084(1),1124(1);0;GPS;GB;CHN;0.00;0.00;0.00;0;0;mock;none;N;N;4096;",
        "ENDSOURCETABLE",
        "",
    ]
).encode()

STATE = {"gga": 0, "clients": 0, "frames_sent": 0, "last_gga": "", "errors": []}
LOCK = threading.Lock()


class Handler(socketserver.StreamRequestHandler):
    def log(self, message):
        print(f"[caster {time.strftime('%H:%M:%S')}] {message}", flush=True)

    def handle(self):
        args = self.server.args
        try:
            request_line = self.rfile.readline(4096).decode("latin-1").strip()
        except OSError:
            return
        if not request_line:
            return

        headers = {}
        while True:
            line = self.rfile.readline(4096).decode("latin-1")
            if not line or line in ("\r\n", "\n"):
                break
            if ":" in line:
                key, value = line.split(":", 1)
                headers[key.strip().lower()] = value.strip()

        self.log(f"request: {request_line!r} headers={headers}")

        parts = request_line.split()
        path = parts[1] if len(parts) > 1 else "/"
        mount = path.lstrip("/")
        version = parts[2] if len(parts) > 2 else "HTTP/1.0"

        if not mount:
            self.wfile.write(SOURCETABLE)
            self.log("sent SOURCETABLE")
            return

        if args.mount and mount.upper() not in [m.upper() for m in args.mount]:
            self.wfile.write(b"SOURCETABLE 200 OK\r\n\r\nENDSOURCETABLE\r\n")
            self.log(f"rejected unknown mount point {mount!r}")
            return

        if args.user:
            expected = "Basic " + base64.b64encode(f"{args.user}:{args.password}".encode()).decode()
            if headers.get("authorization") != expected:
                self.wfile.write(b"HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"ntrip\"\r\n\r\n")
                self.log("rejected: bad credentials")
                with LOCK:
                    STATE["errors"].append("401")
                return

        if version.upper().startswith("HTTP/1.1"):
            self.wfile.write(b"HTTP/1.1 200 OK\r\nNtrip-Version: Ntrip/2.0\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n")
        else:
            self.wfile.write(b"ICY 200 OK\r\n")

        with LOCK:
            STATE["clients"] += 1
        self.log(f"stream started (mount {mount})")

        started = time.time()
        stop = threading.Event()
        connection_stats = {"gga": 0}

        def reader():
            # collect GGA sentences sent back by the client
            while not stop.is_set():
                try:
                    data = self.rfile.readline(1024)
                except OSError:
                    break
                if not data:
                    break
                text = data.decode("latin-1").strip()
                if "GGA" in text:
                    with LOCK:
                        STATE["gga"] += 1
                        STATE["last_gga"] = text
                    connection_stats["gga"] += 1
                    if args.verbose:
                        self.log(f"GGA from client #{STATE['gga']}")
                elif text:
                    if args.verbose:
                        self.log(f"client: {text[:80]}")

        reader_thread = threading.Thread(target=reader, daemon=True)
        reader_thread.start()

        try:
            while time.time() - started < args.duration:
                for frame in RTCM_STREAM:
                    self.wfile.write(frame)
                    with LOCK:
                        STATE["frames_sent"] += 1
                self.wfile.flush()
                time.sleep(args.interval)
                if args.drop_after and time.time() - started > args.drop_after:
                    self.log("dropping connection on purpose")
                    break
        except (BrokenPipeError, ConnectionResetError):
            self.log("client went away")
        finally:
            stop.set()
            with LOCK:
                STATE["clients"] -= 1
            self.log(f"stream ended (GGA received: {connection_stats['gga']})")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=2101)
    parser.add_argument("--user", default=None, help="require this username (HTTP basic auth)")
    parser.add_argument("--password", default=None)
    parser.add_argument("--mount", nargs="*", default=None, help="accepted mount points (default: any)")
    parser.add_argument("--interval", type=float, default=1.0, help="seconds between RTCM epochs")
    parser.add_argument("--duration", type=float, default=3600.0, help="max seconds per stream")
    parser.add_argument("--drop-after", type=float, default=0.0, help="drop the stream after N seconds (0 = never)")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    server = Server((args.host, args.port), Handler)
    server.args = args
    print(f"mock NTRIP caster listening on {args.host}:{args.port}", flush=True)
    print("mount points: " + (", ".join(args.mount) if args.mount else "any"), flush=True)
    if args.user:
        print(f"credentials: {args.user} / {args.password}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("bye")
        with LOCK:
            print(
                "stats: clients=%d gga=%d rtcm_frames=%d last_gga=%r"
                % (STATE["clients"], STATE["gga"], STATE["frames_sent"], STATE["last_gga"]),
                flush=True,
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())
