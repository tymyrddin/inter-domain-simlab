#!/usr/bin/env python3
"""scorer.py - M4: watch the observer, normalise to events, score, emit the timeline.

The filter.py pattern: a host-side tool, stdlib only, driven by `ctl score`. It
polls the observer's `show ip bgp json`, diffs successive snapshots into one fresh
event envelope, annotates each event with its RPKI validation state (computed from
Routinator's VRPs), evaluates the scenario flag from the structured `target:`
block, prints a live scoreboard, and writes artefacts/<scenario>/timeline.json for
heimdallr. See the design notes.
"""
import argparse
import datetime
import ipaddress
import json
import os
import subprocess
import sys
import time

LAB = "inter-domain"
OBSERVER = f"clab-{LAB}-observer"
RTR = f"clab-{LAB}-registry-rtr"
BMP_EVENTS = os.path.join("access", "bmp", "events.jsonl")  # bmp-collector output


def _utc():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _docker(node, *cmd):
    r = subprocess.run(["docker", "exec", node, *cmd],
                       capture_output=True, text=True)
    return r.stdout


def read_block(scenario, name):
    """Minimal scenario.yaml reader (stdlib only): pull one flat top-level block
    (`name:` ... until the next unindented key) into a dict, inline # comments
    stripped. Used for target:, position: and posture: (see session.py)."""
    path = os.path.join("scenarios", scenario, "scenario.yaml")
    block, inside = {}, False
    with open(path) as f:
        for line in f:
            if line.startswith(name + ":"):
                inside = True
                continue
            if inside:
                if line.strip() and not line[0].isspace():
                    break
                s = line.strip()
                if not s or s.startswith("#"):
                    continue
                k, _, v = s.partition(":")
                block[k.strip()] = v.split("#")[0].strip()
    return block


def read_scalar(scenario, key):
    """Read a top-level scalar field (e.g. rootme_flag:) from a scenario.yaml."""
    path = os.path.join("scenarios", scenario, "scenario.yaml")
    with open(path) as f:
        for line in f:
            if line.startswith(key + ":"):
                return line.partition(":")[2].split("#")[0].strip().strip('"').strip("'")
    return None


def read_target(scenario):
    """The `target:` block: the structured flag oracle (hijack_prefix/origin,
    legitimate_prefix/origin)."""
    return read_block(scenario, "target")


def vrps():
    """Routinator's VRP set as (network, maxlen, origin_asn) tuples."""
    try:
        d = json.loads(_docker(RTR, "sh", "-c", "curl -s http://localhost:8323/json"))
        return [(ipaddress.ip_network(v["prefix"]), int(v["maxLength"]),
                 int(str(v["asn"]).replace("AS", ""))) for v in d.get("roas", [])]
    except Exception:
        return []


def rpki_state(prefix, origin, vrp_list):
    """RFC 6811 origin validation of prefix+origin against the VRP set."""
    try:
        net = ipaddress.ip_network(prefix)
    except ValueError:
        return "unknown"
    covering = [(n, m, a) for (n, m, a) in vrp_list if net.subnet_of(n)]
    if not covering:
        return "notfound"
    if any(a == origin and net.prefixlen <= m for (n, m, a) in covering):
        return "valid"
    return "invalid"


def snapshot(node=OBSERVER):
    """best-path table of `node` (a container name) as prefix -> (origin_as,
    as_path[]). Defaults to the observer; scenarios whose effect is regional
    (route-leak, policy-trust-abuse) score at a specific transit instead."""
    try:
        routes = json.loads(_docker(node, "vtysh", "-c", "show ip bgp json")).get("routes", {})
    except Exception:
        return {}
    snap = {}
    for pfx, paths in routes.items():
        chosen = next((p for p in paths if p.get("bestpath") or p.get("best")), paths[0] if paths else None)
        if not chosen:
            continue
        asns = [int(x) for x in str(chosen.get("path", "")).split() if x.isdigit()]
        if asns:
            snap[pfx] = (asns[-1], asns)
    return snap


def _more_specific(p, others):
    pn = ipaddress.ip_network(p)
    return any(pn.subnet_of(ipaddress.ip_network(q)) and pn.prefixlen > ipaddress.ip_network(q).prefixlen
               for q in others if q != p)


def _event(typ, prefix, origin, aspath, vrp_list, scenario):
    return {"ts": _utc(), "scenario": scenario, "source": "collector:observer",
            "type": typ, "prefix": prefix, "origin_as": origin,
            "as_path": aspath, "rpki": rpki_state(prefix, origin, vrp_list)}


def diff(prev, cur, vrp_list, scenario):
    events = []
    for pfx, (o, ap) in cur.items():
        if pfx not in prev:
            typ = "more-specific" if _more_specific(pfx, cur) else "announce"
            events.append(_event(typ, pfx, o, ap, vrp_list, scenario))
        elif prev[pfx][0] != o:
            events.append(_event("origin-change", pfx, o, ap, vrp_list, scenario))
    for pfx, (o, ap) in prev.items():
        if pfx not in cur:
            events.append(_event("withdraw", pfx, o, ap, vrp_list, scenario))
    return events


def _write(out, scenario, target, flagged, timeline):
    with open(out, "w") as f:
        json.dump({"scenario": scenario, "target": target,
                   "flag_captured_at": flagged, "events": timeline}, f, indent=2)
    print(f"\n[scorer] {len(timeline)} events, flag "
          f"{'captured ' + flagged if flagged else 'not captured'}; wrote {out}")


def run_poll(args, target, out):
    """Increment 1: poll the observer's table and diff snapshots into events."""
    hp, ho = target.get("hijack_prefix"), int(target.get("hijack_origin", 0))
    timeline, prev, flagged, start = [], None, None, time.time()
    print(f"[scorer] polling the observer for '{args.scenario}' (Ctrl-C to stop)")
    print(f"[scorer] flag: {hp} reaching the table with origin {ho} (propagation)")
    try:
        while True:
            vrp_list = vrps()
            cur = snapshot()
            if prev is not None:
                for e in diff(prev, cur, vrp_list, args.scenario):
                    timeline.append(e)
                    print(f"  {e['ts']}  {e['type']:14} {e['prefix']:18} origin {e['origin_as']:<6} rpki={e['rpki']}")
            prev = cur
            if flagged is None and hp in cur and cur[hp][0] == ho:
                flagged = _utc()
                timeline.append({"ts": flagged, "scenario": args.scenario,
                                 "source": "scorer", "type": "flag", "prefix": hp,
                                 "origin_as": ho, "rpki": rpki_state(hp, ho, vrp_list),
                                 "detail": "propagation flag captured"})
                print(f"  *** FLAG CAPTURED: {hp} origin {ho} reached the observer ***")
            if args.duration and time.time() - start >= args.duration:
                break
            time.sleep(args.interval)
    except KeyboardInterrupt:
        pass
    _write(out, args.scenario, target, flagged, timeline)


def run_bmp(args, target, out):
    """Increment 2: read the bmp-collector's event stream with exact timing. The
    collector's full events.jsonl (including the initial RIB dump) is the raw
    artefact for heimdallr; the scorer reads from the current end, so its timeline
    is the post-start events, enriched with RPKI state and scored."""
    hp, ho = target.get("hijack_prefix"), int(target.get("hijack_origin", 0))
    timeline, flagged, start = [], None, time.time()
    print(f"[scorer] reading the bmp-collector feed for '{args.scenario}' (Ctrl-C to stop)")
    for _ in range(60):
        if os.path.exists(BMP_EVENTS):
            break
        time.sleep(1)
    if not os.path.exists(BMP_EVENTS):
        print(f"[scorer] no {BMP_EVENTS}; is the bmp-collector up?")
        return _write(out, args.scenario, target, None, [])
    f = open(BMP_EVENTS)
    f.seek(0, 2)   # skip the initial RIB dump; follow new events
    vrp_list, vrp_t = vrps(), time.time()
    try:
        while True:
            line = f.readline()
            if line:
                if time.time() - vrp_t > 10:
                    vrp_list, vrp_t = vrps(), time.time()
                try:
                    raw = json.loads(line)
                except ValueError:
                    continue
                o = raw.get("origin_as")
                ev = {"ts": raw["ts"], "scenario": args.scenario,
                      "source": "collector:bmp", "type": raw["type"],
                      "prefix": raw["prefix"], "origin_as": o,
                      "as_path": raw.get("as_path", []),
                      "rpki": rpki_state(raw["prefix"], o, vrp_list) if o is not None else "unknown",
                      "peer_as": raw.get("peer_as"), "policy": raw.get("policy")}
                timeline.append(ev)
                print(f"  {ev['ts']}  {ev['type']:9} {ev['prefix']:18} origin {str(ev['origin_as']):<6} rpki={ev['rpki']} ({ev['policy']})")
                if flagged is None and ev["type"] == "announce" and ev["prefix"] == hp and ev["origin_as"] == ho:
                    flagged = ev["ts"]
                    timeline.append({"ts": flagged, "scenario": args.scenario,
                                     "source": "scorer", "type": "flag", "prefix": hp,
                                     "origin_as": ho, "rpki": ev["rpki"],
                                     "detail": "propagation flag captured (bmp)"})
                    print(f"  *** FLAG CAPTURED: {hp} origin {ho} (bmp, exact timing) ***")
                continue
            if args.duration and time.time() - start >= args.duration:
                break
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    _write(out, args.scenario, target, flagged, timeline)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--scenario", default="false-origin-prefix-hijack")
    ap.add_argument("--source", choices=["poll", "bmp"], default="poll")
    ap.add_argument("--interval", type=float, default=2.0, help="poll seconds")
    ap.add_argument("--duration", type=float, default=0, help="0 = until Ctrl-C")
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    target = read_target(args.scenario)
    # The scorer's timeline is the lab's own CTF scoring record (it carries derived
    # fields: more-specific, the flag). It is NOT part of the heimdallr export, so it
    # is written under scoring/, never into the raw artefacts/<scenario>/ bundle.
    # See the design notes.
    out = args.out or os.path.join("scoring", args.scenario, "timeline.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    (run_bmp if args.source == "bmp" else run_poll)(args, target, out)


if __name__ == "__main__":
    main()
