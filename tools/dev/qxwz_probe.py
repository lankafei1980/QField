#!/usr/bin/env python3
"""Probe the Qianxun (FindCM) NTRIP caster without a valid account.

Useful to tell "the caster is unreachable from this network" apart from
"the credentials are wrong": a reachable caster answers with an HTTP status
line (401 for bad credentials), an unreachable one times out.

  Qianxun FindCM endpoint: rtk.ntrip.qxwz.com
    port 8001 -> ITRF2008, epoch 2016.0
    port 8002 -> WGS84,   epoch 2005.0
    port 8003 -> CGCS2000, epoch 2000.0
    mount point AUTO lets the caster pick the closest station

Usage::

    python3 tools/dev/qxwz_probe.py                    # all three ports, no credentials
    python3 tools/dev/qxwz_probe.py --user U --password P --port 8003
"""

import argparse
import base64
import socket
import sys

DEFAULT_HOST = "rtk.ntrip.qxwz.com"
PORTS = (8001, 8002, 8003)


def probe(host, port, mount, user=None, password=None, timeout=8.0, revision="1.0"):
    payload = f"GET /{mount} HTTP/{revision}\r\nUser-Agent: NTRIP qfield-probe/1.0\r\n"
    if revision.startswith("1.1"):
        payload += "Ntrip-Version: Ntrip/2.0\r\n"
    if user is not None:
        token = base64.b64encode(f"{user}:{password}".encode()).decode()
        payload += f"Authorization: Basic {token}\r\n"
    payload += "\r\n"

    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            sock.sendall(payload.encode())
            head = sock.recv(512)
    except socket.timeout:
        return "TIMEOUT (no answer within %.0f s)" % timeout
    except OSError as error:
        return f"UNREACHABLE ({error})"

    text = head.decode("latin-1", "replace").splitlines()
    status = text[0] if text else "<empty>"
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, action="append", help="repeatable, default: 8001 8002 8003")
    parser.add_argument("--mount", default="AUTO")
    parser.add_argument("--user", default=None)
    parser.add_argument("--password", default=None)
    parser.add_argument("--revision", default="1.0", help="HTTP revision sent in the request line (1.0 or 1.1)")
    parser.add_argument("--timeout", type=float, default=8.0)
    args = parser.parse_args()

    ports = args.port or list(PORTS)
    failures = 0
    for port in ports:
        status = probe(args.host, port, args.mount, args.user, args.password, args.timeout, args.revision)
        print(f"{args.host}:{port} mount={args.mount} -> {status}", flush=True)
        if not status.startswith(("ICY", "HTTP", "SOURCETABLE")):
            failures += 1

    if failures:
        print("\nSome ports did not answer like an NTRIP caster; check the network (mobile data, VPN, firewall).")
    else:
        print("\nCaster reachable. A 401 simply means the credentials were rejected, the request format itself was understood.")
        print("Proxy environment with REQUESTS_CA_BUNDLE / https_proxy? NTRIP is plain TCP, use the real network to test.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
