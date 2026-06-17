#!/usr/bin/env python3
"""bmp-collector: the observer's BMP monitoring station (M4 increment 2).

BMP is a router-to-station protocol (RFC 7854): the observer's FRR connects out
to this node and streams its RIB. We parse route-monitoring messages, the BMP
framing down to the embedded BGP UPDATE, into the lab's event envelope with the
BMP per-peer timestamp (exact timing, not the scorer's poll diff), and append
them as JSON lines where the scorer reads them (`--source bmp`). The scorer adds
the RPKI annotation and scores; this node is just the BMP/BGP parser, sited on
the network where a station belongs.

Listens on 0.0.0.0:$BMP_PORT, writes events to $BMP_OUT, and (for parser
iteration) appends the raw wire bytes to $BMP_RAW.
"""
import datetime
import ipaddress
import json
import os
import socket
import struct
import sys

PORT = int(os.environ.get("BMP_PORT", "1790"))
OUT = os.environ.get("BMP_OUT", "/out/events.jsonl")
RAW = os.environ.get("BMP_RAW", "/out/raw.bmp")

# BMP message types (RFC 7854 s4.1)
BMP_ROUTE_MONITORING = 0
# BMP per-peer flags (s4.2): V=IPv6, L=post-policy, A=2-byte AS_PATH
F_POST_POLICY = 0x40
F_AS2 = 0x20


def _log(*a):
    print("[bmp]", *a, file=sys.stderr, flush=True)


def _recv(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("peer closed")
        buf += chunk
    return buf


def parse_nlri(data):
    """A run of BGP NLRI (length-prefixed prefixes), IPv4."""
    out, off = [], 0
    while off < len(data):
        plen = data[off]
        off += 1
        nbytes = (plen + 7) // 8
        raw = data[off:off + nbytes] + b"\x00" * (4 - nbytes)
        off += nbytes
        out.append(f"{ipaddress.IPv4Address(raw[:4])}/{plen}")
    return out


def parse_aspath(data, as2):
    asns, off, size = [], 0, (2 if as2 else 4)
    while off + 2 <= len(data):
        seg_len = data[off + 1]
        off += 2
        for _ in range(seg_len):
            if size == 2:
                asns.append(struct.unpack("!H", data[off:off + 2])[0])
            else:
                asns.append(struct.unpack("!I", data[off:off + 4])[0])
            off += size
    return asns


def parse_attrs(data, as2):
    aspath, origin, off = [], None, 0
    while off + 2 <= len(data):
        flags, atype = data[off], data[off + 1]
        off += 2
        if flags & 0x10:  # extended length
            alen = struct.unpack("!H", data[off:off + 2])[0]
            off += 2
        else:
            alen = data[off]
            off += 1
        val = data[off:off + alen]
        off += alen
        if atype == 2:      # AS_PATH
            aspath = parse_aspath(val, as2)
        elif atype == 1:    # ORIGIN
            origin = val[0] if val else None
    return aspath, origin


def parse_update(msg, ts, peer_as, as2, policy):
    """One BGP UPDATE (full message with header) -> announce/withdraw events."""
    if len(msg) < 19 or msg[18] != 2:   # type 2 = UPDATE
        return []
    blen = struct.unpack("!H", msg[16:18])[0]
    body = msg[19:blen]
    off = 0
    wlen = struct.unpack("!H", body[off:off + 2])[0]; off += 2
    withdrawn = parse_nlri(body[off:off + wlen]); off += wlen
    palen = struct.unpack("!H", body[off:off + 2])[0]; off += 2
    attrs = body[off:off + palen]; off += palen
    nlri = parse_nlri(body[off:])
    aspath, _ = parse_attrs(attrs, as2)
    origin_as = aspath[-1] if aspath else None
    events = []
    for pfx in nlri:
        events.append({"ts": ts, "type": "announce", "prefix": pfx,
                       "origin_as": origin_as, "as_path": aspath,
                       "peer_as": peer_as, "policy": policy})
    for pfx in withdrawn:
        events.append({"ts": ts, "type": "withdraw", "prefix": pfx,
                       "origin_as": None, "as_path": [],
                       "peer_as": peer_as, "policy": policy})
    return events


def parse_route_monitoring(body):
    """Per-peer header (42 bytes) + a BGP UPDATE (RFC 7854 s4.6)."""
    flags = body[1]
    peer_as = struct.unpack("!I", body[26:30])[0]
    ts_sec, ts_usec = struct.unpack("!II", body[34:42])
    ts = datetime.datetime.fromtimestamp(
        ts_sec + ts_usec / 1e6, datetime.timezone.utc
    ).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    policy = "post" if (flags & F_POST_POLICY) else "pre"
    return parse_update(body[42:], ts, peer_as, bool(flags & F_AS2), policy)


def serve():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", PORT))
    srv.listen(1)
    _log(f"listening on :{PORT}, events -> {OUT}")
    while True:
        conn, addr = srv.accept()
        _log(f"observer connected from {addr[0]}")
        raw = open(RAW, "ab")
        out = open(OUT, "a")
        try:
            while True:
                hdr = _recv(conn, 6)               # version(1) length(4) type(1)
                length = struct.unpack("!I", hdr[1:5])[0]
                body = _recv(conn, length - 6)
                raw.write(hdr + body); raw.flush()
                if hdr[5] == BMP_ROUTE_MONITORING:
                    # Contain parse errors per message: a malformed or unexpected
                    # message is skipped, never fatal, so the collector keeps
                    # decoding the stream for the whole run.
                    try:
                        for ev in parse_route_monitoring(body):
                            out.write(json.dumps(ev) + "\n"); out.flush()
                    except Exception as e:
                        _log(f"parse error, skipping message: {e}")
        except (ConnectionError, OSError) as e:
            _log(f"connection ended: {e}")
        finally:
            raw.close(); out.close(); conn.close()


if __name__ == "__main__":
    serve()
