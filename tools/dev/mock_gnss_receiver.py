#!/usr/bin/env python3
"""A mock GNSS receiver that speaks NMEA over TCP, mimicking a SparkFun RTK.

SparkFun RTK devices stream NMEA (GGA, GSA, GST, GSV, RMC) over Bluetooth SPP at
2-4 Hz and accept RTCM 3 corrections on the same serial link. A Bluetooth link
is not scriptable from CI, so this tool exposes the very same byte protocol over
TCP: QField connects to it as a "TCP (NMEA)" positioning device, therefore
exercising NMEA parsing, the RTK fixed/float display and NTRIP correction
write-back without any hardware.

Incoming bytes are parsed as RTCM 3 frames and their message numbers reported,
which proves that QField forwards the corrections it receives from the caster.

Usage::

    python3 tools/dev/mock_gnss_receiver.py --port 2102 --lat 39.9087 --lon 116.3975

Then in QField: Positioning device > TCP (NMEA) > Host: <computer IP>, Port: 2102.
"""

import argparse
import datetime
import math
import socket
import socketserver
import sys
import threading
import time

STATE = {"frames": 0, "bytes": 0, "messages": {}}
LOCK = threading.Lock()


def nmea(sentence):
    checksum = 0
    for char in sentence:
        checksum ^= ord(char)
    return f"${sentence}*{checksum:02X}\r\n"


def dm(value, is_latitude):
    """Decimal degrees -> NMEA ddmm.mmmmm / dddmm.mmmmm."""
    hemisphere = ("N" if value >= 0 else "S") if is_latitude else ("E" if value >= 0 else "W")
    value = abs(value)
    degrees = int(value)
    minutes = (value - degrees) * 60.0
    degrees_width = 2 if is_latitude else 3
    return f"{degrees:0{degrees_width}d}{minutes:09.6f}", hemisphere


def build_sentences(lat, lon, altitude, quality, satellites, hdop, speed, heading):
    now = datetime.datetime.now(datetime.timezone.utc)
    utc = now.strftime("%H%M%S") + ".00"
    date = now.strftime("%d%m%y")
    lat_dm, lat_ns = dm(lat, True)
    lon_dm, lon_ew = dm(lon, False)

    out = [
        nmea(f"GPGGA,{utc},{lat_dm},{lat_ns},{lon_dm},{lon_ew},{quality},{satellites:02d},{hdop:.1f},{altitude:.3f},M,0.000,M,,"),
        nmea(f"GPGST,{utc},0.5,0.3,0.2,{heading:.1f},0.02,0.02,0.03"),
        nmea(f"GPGSA,A,3,01,02,03,05,06,07,08,09,10,11,12,13,0.9,0.8,0.5"),
        nmea("GPGSV,3,1,12,01,45,090,42,02,40,120,41,03,35,150,40,04,30,180,39"),
        nmea(f"GPRMC,{utc},A,{lat_dm},{lat_ns},{lon_dm},{lon_ew},{speed:.2f},{heading:.1f},{date},,A"),
    ]
    return out


class Handler(socketserver.StreamRequestHandler):
    def log(self, message):
        print(f"[gnss {time.strftime('%H:%M:%S')}] {message}", flush=True)

    def handle(self):
        args = self.server.args
        peer = self.client_address
        self.log(f"client connected from {peer[0]}:{peer[1]}")

        stop = threading.Event()

        def reader():
            buffer = b""
            while not stop.is_set():
                try:
                    data = self.rfile.read1(4096) if hasattr(self.rfile, "read1") else self.rfile.read(4096)
                except OSError:
                    break
                if not data:
                    break
                with LOCK:
                    STATE["bytes"] += len(data)
                buffer += data
                while True:
                    start = buffer.find(b"\xd3")
                    if start < 0:
                        buffer = b""
                        break
                    if start > 0:
                        buffer = buffer[start:]
                    if len(buffer) < 6:
                        break
                    length = ((buffer[1] & 0x03) << 8) | buffer[2]
                    total = 3 + length + 3
                    if len(buffer) < total:
                        break
                    frame, buffer = buffer[:total], buffer[total:]
                    message_number = (frame[3] << 4) | (frame[4] >> 4)
                    with LOCK:
                        STATE["frames"] += 1
                        STATE["messages"][message_number] = STATE["messages"].get(message_number, 0) + 1
                    if args.verbose:
                        self.log(f"RTCM {message_number} ({total} bytes)")

        reader_thread = threading.Thread(target=reader, daemon=True)
        reader_thread.start()

        steps = 0
        try:
            while not stop.is_set():
                # slowly move the position so that the map marker is alive
                t = steps * args.interval
                lat = args.lat + 0.00002 * math.sin(t)
                lon = args.lon + 0.00002 * math.cos(t)
                for sentence in build_sentences(
                    lat, lon, args.altitude, args.quality, args.satellites, args.hdop, args.speed, args.heading
                ):
                    self.wfile.write(sentence.encode())
                self.wfile.flush()
                steps += 1
                if args.duration and steps * args.interval > args.duration:
                    break
                time.sleep(args.interval)
        except (BrokenPipeError, ConnectionResetError):
            self.log("client went away")
        finally:
            stop.set()
            with LOCK:
                self.log(
                    "stats: rtcm_frames=%d rtcm_bytes=%d messages=%s"
                    % (STATE["frames"], STATE["bytes"], dict(sorted(STATE["messages"].items())))
                )


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=2102)
    parser.add_argument("--lat", type=float, default=39.9087)
    parser.add_argument("--lon", type=float, default=116.3975)
    parser.add_argument("--altitude", type=float, default=45.0)
    parser.add_argument("--quality", type=int, default=4, help="GGA fix quality (4 = RTK fixed)")
    parser.add_argument("--satellites", type=int, default=14)
    parser.add_argument("--hdop", type=float, default=0.7)
    parser.add_argument("--speed", type=float, default=0.0)
    parser.add_argument("--heading", type=float, default=0.0)
    parser.add_argument("--interval", type=float, default=0.25, help="seconds between NMEA epochs (4 Hz)")
    parser.add_argument("--duration", type=float, default=0.0, help="stop after N seconds (0 = forever)")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    server = Server((args.host, args.port), Handler)
    server.args = args
    print(f"mock GNSS receiver streaming NMEA on {args.host}:{args.port}", flush=True)
    print(f"position: {args.lat}, {args.lon} fix quality {args.quality} @ {1.0 / args.interval:.1f} Hz", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("bye", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
