#!/usr/bin/env python3
"""session.py - the operator-side session manager (./ctl session).

A foreground loop that turns the bastion's menu selections into a positioned world.
It watches the /control channel the bastion writes to and, per scenario the player
picks:

  1. sets the world posture (rov/irr/roa) the scenario calls for,
  2. plants the loot the scenario's Phase-1 box needs (a maintainer password or a
     CA token) into access/loot, which the workstation sees at /loot,
  3. signals the bastion that the world is ready, so it drops the player on,
  4. while the scenario is active, runs the operator/validator automation a real
     network would (rebuild IRR filters, nudge the validator) so a laundered object
     or a withdrawn ROA takes effect,
  5. watches the observer for the scenario's flag; on capture, assembles the raw
     heimdallr bundle and tells the bastion the run is complete,
  6. on release (the player leaves the scenario) resets the world to baseline and
     clears the loot.

The session manager is operator god-mode: it deploys posture and resets the world.
It never performs the attack. The attack is the player's, from the Phase-1 box.
Reset is operator world-reset (restore the ROA, delete the laundered object), which
is legitimate here for the same reason `./ctl down && ./ctl up` is.

Stdlib only, the scorer.py pattern. Run from the repo root via `./ctl session`.
"""
import os
import shutil
import subprocess
import sys
import tarfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scorer  # read_block, read_target, snapshot

LAB = "inter-domain"
REGISTRY_CA = f"clab-{LAB}-registry-ca"
REGISTRY_RTR = f"clab-{LAB}-registry-rtr"
REGISTRY_IRR = f"clab-{LAB}-registry-irr"

CONTROL = os.path.join("access", "control")
LOOT = os.path.join("access", "loot")
BUNDLES = os.path.join("access", "bundles")
BMP_EVENTS = os.path.join("access", "bmp", "events.jsonl")

# FDEI's baseline ROA and the laundered route object the scenarios touch.
FDEI_ROA = "203.0.113.0/24-24 => 65010"
LAUNDER_PK = ("203.0.113.0/25", "AS65020")

TICK = 3  # seconds between control-channel polls


# ---------------------------------------------------------------------------
# shelling out: reuse ctl for posture/exports, docker exec for registry reset
# ---------------------------------------------------------------------------

def ctl(*args):
    subprocess.run(["./ctl", *args], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def docker(node, *cmd, capture=False):
    r = subprocess.run(["docker", "exec", node, *cmd],
                       capture_output=True, text=True)
    return r.stdout if capture else None


def krill_token():
    try:
        with open(os.path.join("access", "krill-token")) as f:
            return f.read().strip()
    except OSError:
        return ""


def _krillc(*args):
    tok = krill_token()
    docker(REGISTRY_CA, "sh", "-c",
           f"KRILL_CLI_TOKEN={tok} KRILL_CLI_SERVER=https://localhost:3000/ "
           f"krillc {' '.join(args)}")


def roa_present():
    tok = krill_token()
    out = docker(REGISTRY_CA, "sh", "-c",
                 f"KRILL_CLI_TOKEN={tok} KRILL_CLI_SERVER=https://localhost:3000/ "
                 f"krillc roas list --ca fmda", capture=True) or ""
    return "203.0.113.0/24" in out


def roa_restore():
    """World-reset: re-publish FDEI's ROA if a poison run withdrew it."""
    if not roa_present():
        _krillc("roas", "update", "--ca", "fmda", "--add", f'"{FDEI_ROA}"')
        _nudge_validator()


def _nudge_validator():
    """Make Routinator re-validate now and re-pull on the transits (its periodic
    refresh is slow). The validator/operator automation, sped up for the lab."""
    docker(REGISTRY_RTR, "pkill", "-USR1", "routinator")
    time.sleep(2)
    for t in ("transit-a", "transit-b"):
        docker(f"clab-{LAB}-{t}", "vtysh", "-c",
               "clear bgp ipv4 unicast * soft in")


def launder_delete():
    """World-reset: remove a laundered route object via the maintainer email path
    (operator god-mode reset; the player's launder used the real HTTP API)."""
    pfx, origin = LAUNDER_PK
    msg = (f"From: reset@fmda.lab\nSubject: reset\n\n"
           f"route: {pfx}\norigin: {origin}\nmnt-by: MAINT-FMDA\n"
           f"source: FMDA\ndelete: cleanup\npassword: fmda\n")
    subprocess.run(["docker", "exec", "-i", REGISTRY_IRR,
                    "irrd_submit_email", "--config", "/etc/irrd/irrd.yaml"],
                   input=msg, text=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ---------------------------------------------------------------------------
# posture + loot
# ---------------------------------------------------------------------------

def apply_posture(posture):
    ctl("rov", "on" if posture.get("rov") == "on" else "off")
    ctl("irr", "on" if posture.get("irr") == "on" else "off")
    ctl("localpref", "on" if posture.get("localpref") == "on" else "off")
    if posture.get("roa", "baseline") == "baseline":
        roa_restore()


def plant_loot(kind):
    os.makedirs(LOOT, exist_ok=True)
    for f in os.listdir(LOOT):
        os.remove(os.path.join(LOOT, f))
    if kind == "maint-fmda":
        _write(os.path.join(LOOT, "maint-fmda"), "fmda\n")
        _write(os.path.join(LOOT, "notes.txt"),
               "Found on this box: the MAINT-FMDA maintainer password.\n"
               "It writes to FMDA's IRR. See `launder`.\n")
    elif kind == "krill-token":
        _write(os.path.join(LOOT, "krill-token"), krill_token() + "\n")
        _write(os.path.join(LOOT, "notes.txt"),
               "Found on this box: a token for FMDA's RPKI CA (Krill).\n"
               "It can change FMDA's ROAs. See `poison`.\n")


def clear_loot():
    if os.path.isdir(LOOT):
        for f in os.listdir(LOOT):
            os.remove(os.path.join(LOOT, f))


# ---------------------------------------------------------------------------
# active-scenario automation + flag + bundle
# ---------------------------------------------------------------------------

def infra_tick(scen, posture):
    """The operator/validator automation a real network runs, sped up: rebuild the
    IRR prefix-filters (so a laundered object is picked up) and nudge the validator
    (so a withdrawn ROA's VRP clears)."""
    if posture.get("irr") == "on":
        ctl("irr", "rebuild")
    if scen == "roa-poisoning-hijack":
        _nudge_validator()


def assemble_bundle(scen, ev_offset):
    """The raw heimdallr bundle: this play's BMP events plus the registry-change
    records. Observations only; no scorer timeline, no derived fields."""
    out = os.path.join(BUNDLES, scen)
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out, exist_ok=True)
    # This play's slice of the BMP event stream.
    if os.path.exists(BMP_EVENTS):
        with open(BMP_EVENTS) as f:
            f.seek(ev_offset)
            with open(os.path.join(out, "events.jsonl"), "w") as o:
                o.write(f.read())
    # Registry-change telemetry, scenario-dependent.
    ctl("rpki-export", out)
    if scen in ("route-legitimacy-subversion",):
        ctl("irr-export", out)
    # One downloadable archive.
    with tarfile.open(os.path.join(out, "bundle.tar.gz"), "w:gz") as tar:
        for name in sorted(os.listdir(out)):
            if name != "bundle.tar.gz":
                tar.add(os.path.join(out, name), arcname=os.path.join(scen, name))


def reset_foothold():
    """World-reset: return the foothold to baseline by withdrawing the known hijack
    announcements (the player's network statements and their discard statics). Reset
    is operator world-reset, like ./ctl down && ./ctl up.

    Fed to vtysh on stdin, not as multiple -c args: stdin is processed line by line
    and keeps config-mode context, where a -c sequence aborts (and loses mode) on the
    first 'no' that matches nothing. The harmless 'Can't find' lines are ignored."""
    script = (
        "configure terminal\n"
        "router bgp 65020\n"
        " address-family ipv4 unicast\n"
        "  no network 203.0.113.0/25\n"
        "  no network 203.0.113.0/24\n"
        "  no network 1.7.19.0/24\n"
        "  no network 203.0.114.0/24\n"
        " exit-address-family\n"
        "exit\n"
        "no ip route 203.0.113.0/25 Null0\n"
        "no ip route 203.0.113.0/24 Null0\n"
        "no ip route 1.7.19.0/24 Null0\n"
        "no ip route 203.0.114.0/24 Null0\n"
        "no ip route 203.0.113.0/25 100.64.0.10\n"
        "end\n"
    )
    subprocess.run(["docker", "exec", "-i", f"clab-{LAB}-attacker-as", "vtysh"],
                   input=script, text=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def reset_leak():
    """World-reset: remove the stray export prefix the route-leak player added, so
    customer-leaky is valley-free again and stops leaking the victim route."""
    script = ("configure terminal\n"
              "no ip prefix-list PL-LEAKY-OUT seq 10\n"
              "end\n"
              "clear bgp ipv4 unicast 10.0.0.57 soft out\n")
    subprocess.run(["docker", "exec", "-i", f"clab-{LAB}-customer-leaky", "vtysh"],
                   input=script, text=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def reset_world():
    ctl("rov", "off")
    ctl("irr", "off")
    ctl("localpref", "off")
    launder_delete()
    roa_restore()
    reset_foothold()
    reset_leak()
    clear_loot()


# ---------------------------------------------------------------------------
# control channel
# ---------------------------------------------------------------------------

def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def _read(name):
    try:
        with open(os.path.join(CONTROL, name)) as f:
            return f.read().strip()
    except OSError:
        return ""


def _clear(name):
    try:
        os.remove(os.path.join(CONTROL, name))
    except OSError:
        pass


def main():
    os.makedirs(CONTROL, exist_ok=True)
    os.makedirs(LOOT, exist_ok=True)
    os.makedirs(BUNDLES, exist_ok=True)
    for n in ("request", "ready", "completed", "release"):
        _clear(n)
    active = None      # scenario currently positioned
    posture = {}
    target = {}
    score_container = f"clab-{LAB}-observer"  # where the flag is judged (regional scenarios use a transit)
    leak_via = None    # route-leak: the AS that must appear in the path (origin is unchanged)
    ev_offset = 0
    completed = False
    prev = None        # last snapshot, for the scoring-timeline diff
    timeline = []      # the scorer's per-run event record (-> scoring/<scenario>/)
    last_infra = 0.0
    INFRA_EVERY = 12   # seconds between operator/validator automation ticks
    print("[session] watching the bastion control channel (Ctrl-C to stop).")
    print("[session] world starts at baseline; pick a scenario at the bastion.")
    try:
        while True:
            rel = _read("release")
            if rel:
                print(f"[session] release '{rel}': resetting world to baseline.")
                reset_world()
                for n in ("request", "ready", "completed", "release"):
                    _clear(n)
                active, completed, prev, timeline = None, False, None, []
                time.sleep(TICK)
                continue

            req = _read("request")
            if req and req != active:
                print(f"[session] positioning for '{req}' ...")
                posture = scorer.read_block(req, "posture")
                position = scorer.read_block(req, "position")
                target = scorer.read_target(req)
                score_container = f"clab-{LAB}-{scorer.read_scalar(req, 'score_node') or 'observer'}"
                leak_via = scorer.read_scalar(req, "leak_via")
                apply_posture(posture)
                plant_loot(position.get("loot", "none"))
                ev_offset = os.path.getsize(BMP_EVENTS) if os.path.exists(BMP_EVENTS) else 0
                active, completed, prev, timeline = req, False, None, []
                _write(os.path.join(CONTROL, "ready"), req)
                print(f"[session] '{req}' ready (posture {posture}, "
                      f"loot {position.get('loot','none')}). Player may proceed.")

            elif active and not completed:
                if time.time() - last_infra > INFRA_EVERY:
                    infra_tick(active, posture)
                    last_infra = time.time()
                # Poll the scoring node once; diff into the per-run timeline and check
                # the flag from the same snapshot (reusing scorer).
                vrp_list = scorer.vrps()
                cur = scorer.snapshot(score_container)
                if prev is not None:
                    timeline.extend(scorer.diff(prev, cur, vrp_list, active))
                prev = cur
                if leak_via:
                    # route-leak: the victim prefix's best path runs through the
                    # leaker AS, even though the origin is unchanged.
                    fp = target.get("legitimate_prefix")
                    fo = int(target.get("legitimate_origin", 0))
                    hit = fp in cur and int(leak_via) in cur[fp][1]
                    fdetail = f"leaked: {fp} best path via AS{leak_via}"
                else:
                    fp = target.get("hijack_prefix")
                    fo = int(target.get("hijack_origin", 0))
                    hit = fp in cur and cur[fp][0] == fo
                    fdetail = "propagation flag captured"
                if hit:
                    flagged = scorer._utc()
                    timeline.append({"ts": flagged, "scenario": active, "source": "scorer",
                                     "type": "flag", "prefix": fp, "origin_as": fo,
                                     "rpki": scorer.rpki_state(fp, fo, vrp_list),
                                     "detail": fdetail})
                    out = os.path.join("scoring", active, "timeline.json")
                    os.makedirs(os.path.dirname(out), exist_ok=True)
                    scorer._write(out, active, target, flagged, timeline)
                    assemble_bundle(active, ev_offset)
                    _write(os.path.join(CONTROL, "completed"), active)
                    completed = True
                    print(f"[session] FLAG '{active}'; wrote {out} and "
                          f"{os.path.join(BUNDLES, active)}/bundle.tar.gz")

            time.sleep(TICK)
    except KeyboardInterrupt:
        print("\n[session] stopping; resetting world to baseline.")
        reset_world()


if __name__ == "__main__":
    main()
