#!/usr/bin/env python3
"""Filter and sample a RouteViews/RIS MRT RIB dump into a lab seed dump.

The lab seeds its backbone with a real route dump so the global table is
plausibly large. This is not table stuffing: GoBGP
replays the output of this script as real eBGP UPDATEs (gobgp mrt inject). The
job here is to turn a raw, full-table TABLE_DUMP_V2 file into a clean, sampled
one that:

  * carries one entry per prefix, not one-per-collector-peer. Raw RouteViews
    records hold ~20 entries per prefix (one per peer of the collector), and
    `gobgp mrt inject ... <count>` counts entries, so feeding the raw file would
    make a count of 10000 select a few hundred prefixes with huge duplication.
    Re-emitting one entry per prefix makes the count a prefix-count dial.
  * is a representative random sample across the whole table, not the first N.
    MRT RIB dumps are prefix-ordered, so the first N would be a contiguous
    low-address block, narrow in prefix length and origin. Reservoir sampling
    spreads the slice across the table; the emitted records are then shuffled so
    `gobgp mrt inject ... <count>` taking the first <count> still gets a
    representative subset.
  * cannot touch the experimental prefixes. Bogons, special-use space and the
    lab's own blocks are dropped, and any route whose AS_PATH carries a lab ASN
    is dropped, so the seed can never shadow the victim/attacker prefixes or
    claim a lab origin. (The transits also carry an inbound prefix-list as a
    second layer; see configs/transit-*.conf.)

The real AS_PATH is preserved byte-for-byte in value, so origins stay real
(needed for the later RPKI/IRR zone). The seed-to-first-hop adjacency is
fictional from the topology's vantage; that is a named, deliberate boundary
(see seeds/mrt/README.md and the design notes).
"""

import argparse
import ipaddress
import random
import struct
import sys

from mrtparse import Reader

# Networks the seed must never carry: standard bogons / special-use space plus
# the lab's own blocks (the three TEST-NET ranges, the infra 10/8 and the
# 100.64/10 access LAN). A candidate prefix overlapping any of these is dropped.
DENY_NETS = [ipaddress.ip_network(n) for n in (
    "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8",
    "169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24", "192.0.2.0/24",
    "192.88.99.0/24", "192.168.0.0/16", "198.18.0.0/15", "198.51.100.0/24",
    "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4",
)]

# AS numbers that may not appear anywhere in a background path: the lab's
# private range (the fabric lives in 65000-65020), the wider private ranges,
# plus AS0 and AS_TRANS (23456).
def _is_lab_asn(asn):
    return (asn == 0 or asn == 23456
            or 64512 <= asn <= 65534
            or 4200000000 <= asn <= 4294967294)

# MRT / TABLE_DUMP_V2 constants (RFC 6396).
MRT_TABLE_DUMP_V2 = 13
ST_PEER_INDEX_TABLE = 1
ST_RIB_IPV4_UNICAST = 2

SEED_BGP_ID = "10.0.0.26"   # the seed node's router-id / placeholder next-hop
SEED_ASN = 65003


def _aspath_asns(attr_value):
    """Flatten an mrtparse AS_PATH attribute value to a list of ints."""
    asns = []
    for seg in attr_value:
        for a in seg["value"]:
            asns.append(int(a))
    return asns


def _origin_code(attr_value):
    return int(next(iter(attr_value)))


def read_routes(path):
    """Yield (prefix_str, prefix_len, [asns], origin_code) for usable routes."""
    for i, m in enumerate(Reader(path)):
        if getattr(m, "err", None):
            continue
        d = m.data
        st = next(iter(d["subtype"]))
        if st != ST_RIB_IPV4_UNICAST:
            continue
        plen = d["length"]            # mrtparse stores the prefix length here
        if plen == 0 or plen > 24:    # skip default and odd long more-specifics
            continue
        try:
            net = ipaddress.ip_network(f"{d['prefix']}/{plen}")
        except ValueError:
            continue
        if any(net.overlaps(dn) for dn in DENY_NETS):
            continue
        entry = d["rib_entries"][0]
        asns = origin = None
        for attr in entry["path_attributes"]:
            ty = next(iter(attr["type"]))
            if ty == 2:               # AS_PATH
                asns = _aspath_asns(attr["value"])
            elif ty == 1:             # ORIGIN
                origin = _origin_code(attr["value"])
        if not asns:
            continue
        if any(_is_lab_asn(a) for a in asns):
            continue
        yield (d["prefix"], plen, asns, origin if origin is not None else 0)


def reservoir(it, k, rng):
    """Reservoir-sample up to k items uniformly from an iterator."""
    sample = []
    for n, item in enumerate(it):
        if len(sample) < k:
            sample.append(item)
        else:
            j = rng.randint(0, n)
            if j < k:
                sample[j] = item
    return sample


# ── minimal TABLE_DUMP_V2 encoder ──────────────────────────────────────────

def _mrt_record(subtype, body):
    # timestamp is cosmetic for an injected RIB; a fixed value keeps the
    # committed sample reproducible.
    hdr = struct.pack("!IHHI", 0, MRT_TABLE_DUMP_V2, subtype, len(body))
    return hdr + body


def _peer_index_table():
    bgp_id = ipaddress.ip_address(SEED_BGP_ID).packed
    body = bgp_id                       # collector_bgp_id
    body += struct.pack("!H", 0)        # view_name_length = 0
    body += struct.pack("!H", 1)        # peer_count = 1
    # one peer: IPv4 peer, 4-byte AS (peer_type bit 1 set = 0x02)
    body += struct.pack("!B", 0x02)
    body += bgp_id                      # peer_bgp_id
    body += ipaddress.ip_address(SEED_BGP_ID).packed   # peer_ip (IPv4)
    body += struct.pack("!I", SEED_ASN)                # peer_as (4-byte)
    return _mrt_record(ST_PEER_INDEX_TABLE, body)


def _attr(flags, type_code, value):
    if len(value) > 255:
        flags |= 0x10                   # extended length
        return struct.pack("!BBH", flags, type_code, len(value)) + value
    return struct.pack("!BBB", flags, type_code, len(value)) + value


def _aspath_attr(asns):
    # An AS_SEQUENCE segment counts its ASNs in one octet, so it holds at most
    # 255. Real dumps carry the odd heavily-prepended path longer than that;
    # split it across multiple AS_SEQUENCE segments, which is valid wire format.
    seg = b""
    for i in range(0, len(asns), 255):
        chunk = asns[i:i + 255]
        seg += struct.pack("!BB", 2, len(chunk))      # AS_SEQUENCE, count
        seg += b"".join(struct.pack("!I", a) for a in chunk)
    return _attr(0x40, 2, seg)


def _rib_record(seq, prefix, plen, asns, origin):
    attrs = _attr(0x40, 1, struct.pack("!B", origin))          # ORIGIN
    attrs += _aspath_attr(asns)                                # AS_PATH
    attrs += _attr(0x40, 3, ipaddress.ip_address(SEED_BGP_ID).packed)  # NEXT_HOP
    pbytes = (plen + 7) // 8
    pfx = ipaddress.ip_address(prefix).packed[:pbytes]
    entry = struct.pack("!H", 0)        # peer_index = 0
    entry += struct.pack("!I", 0)       # originated_time
    entry += struct.pack("!H", len(attrs)) + attrs
    body = struct.pack("!I", seq)
    body += struct.pack("!B", plen) + pfx
    body += struct.pack("!H", 1)        # entry_count = 1
    body += entry
    return _mrt_record(ST_RIB_IPV4_UNICAST, body)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("raw", help="input MRT RIB dump (.bz2/.gz/raw)")
    ap.add_argument("out", help="output filtered/sampled MRT file")
    ap.add_argument("--count", type=int, default=10000,
                    help="max prefixes to emit (default 10000)")
    ap.add_argument("--seed", type=int, default=1,
                    help="RNG seed for reproducible samples (default 1)")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    sys.stderr.write("reading and filtering (one full pass) ...\n")
    sample = reservoir(read_routes(args.raw), args.count, rng)
    rng.shuffle(sample)
    sys.stderr.write(f"emitting {len(sample)} prefixes -> {args.out}\n")

    with open(args.out, "wb") as f:
        f.write(_peer_index_table())
        for seq, (prefix, plen, asns, origin) in enumerate(sample):
            f.write(_rib_record(seq, prefix, plen, asns, origin))


if __name__ == "__main__":
    main()
