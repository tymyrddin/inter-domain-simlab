#!/usr/bin/env bash
# ctl — inter-domain-simlab lab control.
#
# Command names and the clab-<lab>-<node> convention mirror ics-access-simlab's
# larger ctl, so this can grow toward generate/verify/clean later without
# renaming. Operator commands (table, lg, ssh, vtysh) are god-mode via docker
# exec. The player surface is reached over the access LAN, key-only.
#
# Commands:
#   up            generate keys, build images, create the access bridge, deploy
#   down          destroy the topology, remove the access bridge
#   table         looking glass: show ip bgp on the observer (operator)
#   lg            looking glass, structured: show ip bgp json (operator)
#   ssh NODE      shell on a node          (clab-inter-domain-NODE)
#   vtysh NODE    vtysh on a router node
#   player        play locally: enter the ops host with a cohort key (auto-made)
#   playtest      operator check of the player path, using the lab key
#   cohort-keys   generate a participant keypair to hand out
#   seed-fetch    refresh the backbone seed from a live RouteViews dump

set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

# BuildKit attaches OCI provenance attestations by default, which fetch registry
# metadata and hang in offline lab environments. Turn that off.
export BUILDX_NO_DEFAULT_ATTESTATIONS=1

LAB="inter-domain"
TOPO="clab/inter-domain.clab.yml"
OBS="clab-${LAB}-observer"
BRIDGE="idsl_access"
ACCESS_NET="100.64.0.0/24"
HOST_IP="100.64.0.254/24"
BASTION_IP="100.64.0.5"
# Backbone seed scale dial: how many prefixes the seed injects from the dump.
# The committed sample holds ~10k; larger needs ./ctl seed-fetch (network).
SEED_COUNT="${SEED_COUNT:-10000}"
# Registry/governance (M3): the services bridge and the registry container names.
SERVICES_BRIDGE="idsl_services"
REGPUB_BRIDGE="idsl_regpub"
REGISTRY_CA="clab-${LAB}-registry-ca"
REGISTRY_RTR="clab-${LAB}-registry-rtr"
REGISTRY_IRR="clab-${LAB}-registry-irr"
CMD="${1:-help}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Generate the lab access key on first use, then (re)build the authorized_keys
# files the topology bind-mounts. The committed image carries no credential;
# these files are created here and gitignored.
_ensure_keys() {
    mkdir -p access access/control access/bundles access/loot
    if [ ! -f lab-key ]; then
        ssh-keygen -t ed25519 -f lab-key -N "" -C "idsl-lab-key" -q
        echo "[ctl] Generated lab-key / lab-key.pub (gitignored, operator + in-lab pivot)"
    fi
    # The pivot key. admin (foothold), the workstation (ops-host) and glass (looking
    # glass) trust it; the bastion holds it and pivots with it. Never in a player's hand.
    cp lab-key.pub access/authorized_keys
    # The door (bastion) trusts cohort keys, plus the lab key so operator playtest enters.
    cat lab-key.pub > access/cohort_authorized_keys
    if [ -f cohort-key.pub ]; then
        cat cohort-key.pub >> access/cohort_authorized_keys
    fi
}

_ssh_lab() {
    ssh -i lab-key -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$@"
}

# Generate Krill's admin token once (gitignored). The committed image bakes no
# credential; the token is created here and passed to registry-ca at deploy.
# access/registry is the dir shared with Routinator for the TAL + RRDP cert.
_ensure_krill_token() {
    mkdir -p access access/registry
    if [ ! -f access/krill-token ]; then
        openssl rand -hex 24 > access/krill-token
        echo "[ctl] Generated access/krill-token (gitignored, registry-ca admin)"
    fi
    # Clear last deploy's trust material so registry-rtr blocks for the fresh
    # TAL + RRDP cert that rpki-init publishes, never a stale one.
    rm -f access/registry/krill.tal access/registry/krill-cert.pem
    # bmp-collector output dir; clear last run's stream so a fresh deploy starts clean.
    mkdir -p access/bmp
    rm -f access/bmp/events.jsonl access/bmp/raw.bmp
}

# Onboard the FMDA CA to the testbed TA and add the baseline ROAs, against the
# running krilld. Idempotent (init-ca.sh skips a CA that already exists).
_rpki_init() {
    local tok; tok="$(cat access/krill-token 2>/dev/null || true)"
    echo "[ctl] Onboarding FMDA CA + baseline ROAs (registry-ca) ..."
    docker exec -e KRILL_ADMIN_TOKEN="$tok" "$REGISTRY_CA" /opt/init-ca.sh
}

# Apply ("") or remove ("no ") a named inbound route-map on a transit's eBGP
# neighbours, then soft-refresh. Used for both RM-ROV-IN (./ctl rov) and
# RM-LP-CUSTOMER (./ctl localpref); both live committed-but-unbound in the configs,
# and the two are never bound at once (their scenarios are disjoint).
_rmap_apply() {
    local node="$1" asn="$2" rmap="$3" kw="$4"; shift 4
    {
        echo "configure terminal"; echo "router bgp $asn"
        echo "address-family ipv4 unicast"
        for nb in "$@"; do echo "${kw}neighbor $nb route-map $rmap in"; done
        echo "end"; echo "clear bgp ipv4 unicast * soft in"
    } | docker exec -i "clab-${LAB}-${node}" vtysh >/dev/null
}

# Build an IRR prefix-list for one customer AS from FMDA's route objects (bgpq4 on
# registry-irr, -p to allow the lab's private ASNs) and load it onto the customer's
# transit. PL-IRR-<asn> then permits exactly what the IRR authorises, no more.
_irr_build_load() {
    local node="$1" asn="$2" pl
    # -T disables bgpq4 pipelining: it is a throughput optimisation for large
    # AS-SET expansions (no benefit for the lab's single-AS lookups) and it avoids
    # a rare, non-deterministic hang seen in bgpq4's pipelined exchange with IRRd.
    # -p allows the lab's private ASNs.
    pl="$(docker exec "$REGISTRY_IRR" bgpq4 -T -h localhost -p -l "PL-IRR-${asn}" "AS${asn}" 2>/dev/null)"
    { echo "configure terminal"; echo "$pl"; echo "end"; } \
        | docker exec -i "clab-${LAB}-${node}" vtysh >/dev/null
}

# Bind ("") or unbind ("no ") PL-IRR-<asn> inbound on a transit's customer neighbour.
_irr_apply() {
    local node="$1" bgpasn="$2" asn="$3" kw="$4" nb="$5"
    {
        echo "configure terminal"; echo "router bgp $bgpasn"
        echo "address-family ipv4 unicast"
        echo "${kw}neighbor $nb prefix-list PL-IRR-${asn} in"
        echo "end"; echo "clear bgp ipv4 unicast * soft in"
    } | docker exec -i "clab-${LAB}-${node}" vtysh >/dev/null
}

# After rpki-init, wait for Routinator to serve VRPs, then kick the transits' RTR
# sessions. FRR does not retry hard if the cache was unreachable when bgpd loaded
# the rpki config (which it is on a fresh deploy, before Routinator is serving).
_rpki_link() {
    echo "[ctl] waiting for Routinator VRPs, then linking the transits' RTR ..."
    local n
    for _ in $(seq 1 40); do
        n=$(docker exec "$REGISTRY_RTR" sh -c 'curl -s http://localhost:8323/metrics 2>/dev/null | grep "routinator_vrps_final " | grep -v "^#" | awk "{print \$2}"' 2>/dev/null)
        [ -n "$n" ] && [ "$n" != "0" ] && break
        sleep 2
    done
    for t in transit-a transit-b; do
        docker exec "clab-${LAB}-$t" vtysh -c 'rpki reset' >/dev/null 2>&1
    done
}

_vrp_count() {
    docker exec "$REGISTRY_RTR" sh -c \
        'curl -s http://localhost:8323/metrics | grep "routinator_vrps_final " | grep -v "^#" | awk "{print \$2}"' \
        2>/dev/null
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

case "$CMD" in

  up)
    _ensure_keys
    _ensure_krill_token
    KRILL_TOKEN="$(cat access/krill-token)"
    echo "[ctl] Building images ..."
    docker build -q -t clab-router        clab/frr
    docker build -q -t idsl-ops-host      clab/ops-host
    docker build -q -t idsl-seed          clab/seed
    docker build -q -t idsl-registry-ca   clab/registry/krill
    docker build -q -t idsl-registry-rtr  clab/registry/routinator
    docker build -q -t idsl-registry-irr  clab/registry/irrd
    docker build -q -t idsl-bmp-collector clab/bmp
    docker build -q -t idsl-bastion       clab/bastion
    echo "[ctl] Creating bridges $BRIDGE, $SERVICES_BRIDGE, $REGPUB_BRIDGE (sudo) ..."
    sudo ip link add "$BRIDGE" type bridge 2>/dev/null || true
    sudo ip link set "$BRIDGE" up
    sudo ip addr add "$HOST_IP" dev "$BRIDGE" 2>/dev/null || true
    sudo ip link add "$SERVICES_BRIDGE" type bridge 2>/dev/null || true
    sudo ip link set "$SERVICES_BRIDGE" up
    # The registry-public segment (submission face); internal, no host IP, like services.
    sudo ip link add "$REGPUB_BRIDGE" type bridge 2>/dev/null || true
    sudo ip link set "$REGPUB_BRIDGE" up
    echo "[ctl] Deploying topology (seed injects $SEED_COUNT prefixes) ..."
    # SEED_COUNT and KRILL_TOKEN are read by the topology's ${VAR:=default}
    # substitutions; pass them through sudo.
    sudo SEED_COUNT="$SEED_COUNT" KRILL_TOKEN="$KRILL_TOKEN" \
        containerlab deploy -t "$TOPO"
    _rpki_init || echo "[ctl] rpki-init did not finish; check ./ctl rpki then rerun ./ctl rpki-init"
    _rpki_link
    echo ""
    echo "  Lab is up."
    echo "  Session manager:         ./ctl session      (run in another terminal, positions the world)"
    echo "  Play locally:            ./ctl player       (enter the bastion with a cohort key)"
    echo "  Operator looking glass:  ./ctl table        (./ctl lg for JSON)"
    echo "  RPKI status:             ./ctl rpki         (re-onboard: ./ctl rpki-init)"
    echo "  Cohort keys for others:  ./ctl cohort-keys"
    echo "  Stop:                    ./ctl down"
    ;;

  down)
    sudo containerlab destroy --cleanup -t "$TOPO"
    # `containerlab destroy` only knows the nodes in the current topology, so a
    # container whose node was renamed or removed lingers as an orphan and blocks
    # the next deploy ("lab already deployed"). Reap anything still named for this
    # lab, which catches orphans regardless of how the topology has drifted.
    orphans="$(docker ps -aq --filter "name=clab-${LAB}-" 2>/dev/null)"
    if [ -n "$orphans" ]; then
        echo "[ctl] Reaping orphaned $LAB containers (topology drift) ..."
        docker rm -f $orphans >/dev/null
    fi
    echo "[ctl] Removing bridges $BRIDGE, $SERVICES_BRIDGE, $REGPUB_BRIDGE (sudo) ..."
    sudo ip link del "$BRIDGE" 2>/dev/null || true
    sudo ip link del "$SERVICES_BRIDGE" 2>/dev/null || true
    sudo ip link del "$REGPUB_BRIDGE" 2>/dev/null || true
    ;;

  table)
    docker exec "$OBS" vtysh -c "show ip bgp"
    ;;

  lg)
    docker exec "$OBS" vtysh -c "show ip bgp json"
    ;;

  ssh)
    NODE="${2:?usage: ./ctl ssh NODE}"
    exec docker exec -it "clab-${LAB}-${NODE}" sh
    ;;

  vtysh)
    NODE="${2:?usage: ./ctl vtysh NODE}"
    exec docker exec -it "clab-${LAB}-${NODE}" vtysh
    ;;

  seed-fetch)
    # Refresh the backbone seed from a live RouteViews dump (network needed).
    # Optional COUNT arg for a larger table; the default deploy uses the
    # committed ~10k sample and needs no fetch. Apply a new size with:
    #   ./ctl down && SEED_COUNT=50000 ./ctl up   (after seed-fetch 50000)
    COUNT="${2:-$SEED_COUNT}"
    "$REPO/seeds/mrt/fetch.sh" "$COUNT"
    echo "[ctl] Seed refreshed. Redeploy to use it: ./ctl down && SEED_COUNT=$COUNT ./ctl up"
    ;;

  rpki-init)
    # (Re)onboard the FMDA CA and baseline ROAs. Run automatically by ./ctl up;
    # rerun by hand if it did not finish first time.
    _rpki_init
    ;;

  rov)
    # Turn origin validation on/off at the transits (off by default). The
    # route-bearing eBGP neighbours: transit-a {peer, victim, seed},
    # transit-b {peer, attacker, seed}.
    case "${2:-}" in
      on)  KW="" ;;
      off) KW="no " ;;
      *)   echo "usage: ./ctl rov on|off"; exit 1 ;;
    esac
    _rmap_apply transit-a 65001 RM-ROV-IN "$KW" 10.0.0.2 10.0.0.6 10.0.0.26
    _rmap_apply transit-b 65002 RM-ROV-IN "$KW" 10.0.0.1 10.0.0.10 10.0.0.30
    echo "[ctl] ROV $2 on transit-a and transit-b"
    ;;

  localpref)
    # Customer-over-peer local-preference at the transits (off by default), bound on
    # the customer neighbours only so customer-learned routes win on policy rather
    # than specificity. Used by route-leak and policy-trust-abuse. Never on at once
    # with ROV (those scenarios run ROV off), so the inbound route-map slot is free.
    case "${2:-}" in
      on)  KW="" ;;
      off) KW="no " ;;
      *)   echo "usage: ./ctl localpref on|off"; exit 1 ;;
    esac
    _rmap_apply transit-a 65001 RM-LP-CUSTOMER "$KW" 10.0.0.6 10.0.0.54
    _rmap_apply transit-b 65002 RM-LP-CUSTOMER "$KW" 10.0.0.10 10.0.0.58
    echo "[ctl] local-preference $2 on transit-a and transit-b (customer neighbours)"
    ;;

  irr)
    # IRR prefix filtering, a per-scenario toggle off by default (like ROV). bgpq4
    # on registry-irr turns FMDA's route objects into per-customer prefix-lists; on
    # binds them inbound on the customer neighbours (transit-a {victim 65010},
    # transit-b {attacker 65020}). The legitimacy-subversion attack launders a route
    # object into IRRd, then `irr rebuild` re-derives the filter and the new prefix
    # passes. See PLAN.md section 19.
    case "${2:-}" in
      rebuild)
        _irr_build_load transit-a 65010
        _irr_build_load transit-b 65020
        for t in transit-a transit-b; do
            docker exec "clab-${LAB}-$t" vtysh -c 'clear bgp ipv4 unicast * soft in' >/dev/null 2>&1
        done
        echo "[ctl] IRR prefix-lists rebuilt from FMDA on transit-a and transit-b"
        ;;
      on)
        _irr_build_load transit-a 65010
        _irr_build_load transit-b 65020
        _irr_apply transit-a 65001 65010 "" 10.0.0.6
        _irr_apply transit-b 65002 65020 "" 10.0.0.10
        echo "[ctl] IRR filtering ON: customers filtered to their FMDA route objects"
        ;;
      off)
        _irr_apply transit-a 65001 65010 "no " 10.0.0.6
        _irr_apply transit-b 65002 65020 "no " 10.0.0.10
        echo "[ctl] IRR filtering OFF: permissive baseline"
        ;;
      *) echo "usage: ./ctl irr on|off|rebuild"; exit 1 ;;
    esac
    ;;

  irr-export)
    # Capture the IRR-change telemetry heimdallr correlates: the current FMDA route
    # objects (the registry state, including any laundered one) and the journal of
    # changes (the NRTM add/delete record, the arming signal). Commit one known-good
    # bundle per scenario (PLAN.md sections 8 and 19).
    OUT="${2:-irr-export}"; mkdir -p "$OUT"
    for asn in 65010 65020 65001; do
        echo "# AS$asn"
        docker exec "$REGISTRY_IRR" bgpq4 -T -h localhost -p -l "PL-IRR-${asn}" "AS${asn}" 2>/dev/null
    done > "$OUT/irr-routes.txt"
    # The change journal is IRRd's own raw record (keep_journal); read it from the
    # database rather than NRTM (which needs a mirror access list). The bulk seed
    # load is not journalled, so a play's journal is exactly the launder add/delete.
    docker exec "$REGISTRY_IRR" su postgres -c \
        "psql irrd -A -F'|' -c \"SELECT serial_global, operation, object_class, rpsl_pk, timestamp FROM rpsl_database_journal ORDER BY serial_global;\"" \
        > "$OUT/irr-journal.txt" 2>/dev/null
    echo "[ctl] IRR telemetry exported to $OUT/ (irr-routes.txt, irr-journal.txt)"
    ;;

  rpki-export)
    # Capture the RPKI trust-signal telemetry heimdallr practises against: the
    # current VRP set, the FMDA ROA list and change history (the ROA-poisoning
    # arming signal), and Routinator's validation log. Commit a known-good one
    # per scenario (PLAN.md sections 8 and 17).
    OUT="${2:-rpki-export}"
    mkdir -p "$OUT"
    tok="$(cat access/krill-token 2>/dev/null || true)"
    KX="docker exec -e KRILL_CLI_TOKEN=$tok -e KRILL_CLI_SERVER=https://localhost:3000/ $REGISTRY_CA krillc"
    docker exec "$REGISTRY_RTR" sh -c 'curl -s http://localhost:8323/json' > "$OUT/vrps.json" 2>/dev/null
    $KX roas list --ca fmda > "$OUT/roas.txt" 2>/dev/null
    $KX history commands --ca fmda > "$OUT/roa-history.txt" 2>/dev/null
    docker logs "$REGISTRY_RTR" > "$OUT/routinator.log" 2>&1
    echo "[ctl] RPKI telemetry exported to $OUT/ (vrps.json, roas.txt, roa-history.txt, routinator.log)"
    ;;

  rpki)
    # Operator view of the trust fabric: Routinator's VRP counts and the RTR
    # session, plus the FMDA CA's ROAs.
    echo "=== Routinator (registry-rtr) VRPs ==="
    docker exec "$REGISTRY_RTR" sh -c \
        'curl -s http://localhost:8323/metrics | grep -E "routinator_vrps_final|routinator_rtr" | grep -v "^#"' \
        2>/dev/null || echo "  (Routinator not answering yet; TAL loaded? see ./ctl rpki-init)"
    echo "=== FMDA CA ROAs (registry-ca) ==="
    tok="$(cat access/krill-token 2>/dev/null || true)"
    docker exec -e KRILL_CLI_TOKEN="$tok" -e KRILL_CLI_SERVER="https://localhost:3000/" \
        "$REGISTRY_CA" krillc roas list --ca fmda 2>/dev/null \
        || echo "  (no ROAs yet; run ./ctl rpki-init)"
    ;;

  score)
    # M4 scorer: watch the observer, normalise to events, score the flag, and write
    # the timeline under scoring/ (the lab's scoring record, not the heimdallr
    # bundle; PLAN.md sections 8 and 18). Stdlib-only Python.
    # Source: poll (increment 1, default) or bmp (increment 2, the bmp-collector
    # feed with exact event timing). Usage: ./ctl score [scenario] [poll|bmp]
    SCEN="${2:-false-origin-prefix-hijack}"
    SRC="${3:-poll}"
    PY="$REPO/.venv/bin/python"; [ -x "$PY" ] || PY="$(command -v python3)"
    exec "$PY" "$REPO/scorer/scorer.py" --scenario "$SCEN" --source "$SRC"
    ;;

  session)
    # Operator-side session manager: watch the bastion's /control channel and, per
    # scenario the player selects, set the world posture (rov/irr/roa), plant the
    # loot on the start box, arm the scorer for the flag, copy the bundle on
    # completion, and reset to baseline on release. Foreground loop, run alongside
    # the lab in its own terminal. See scorer/session.py.
    PY="$REPO/.venv/bin/python"; [ -x "$PY" ] || PY="$(command -v python3)"
    exec "$PY" "$REPO/scorer/session.py"
    ;;

  cohort-keys)
    ssh-keygen -t ed25519 -f "$REPO/cohort-key" -N "" -C "idsl-cohort-key" -q
    echo "[ctl] Generated cohort-key / cohort-key.pub (gitignored)"
    _ensure_keys   # refreshes the bind-mounted authorized_keys live, no redeploy
    echo ""
    echo "  Distribute the private key to participants:  $REPO/cohort-key"
    echo ""
    echo "  Local play, the host is on the access bridge ($BRIDGE, ${HOST_IP%/*}):"
    echo "      ssh -i cohort-key player@$BASTION_IP"
    echo ""
    echo "  Production, the access LAN is internal and there is no published port."
    echo "  Players jump through a restricted account on the lab host:"
    echo "      ssh -i cohort-key -J jump@<lab-host> player@$BASTION_IP"
    ;;

  playtest)
    # Operator check: walk the player path straight after `up`, using the lab
    # key. No cohort key needed, so this works the moment the lab is up.
    echo "[ctl] (operator) entering the bastion via lab-key ..."
    _ssh_lab "player@$BASTION_IP"
    ;;

  player)
    # The real player entry, using the cohort key. Playing locally, generate one
    # on the fly so a solo player can just run this. authorized_keys is bind-
    # mounted, so the ops host sees the refreshed file with no redeploy.
    if [ ! -f cohort-key ]; then
        echo "[ctl] No cohort key yet, generating one for local play ..."
        ssh-keygen -t ed25519 -f cohort-key -N "" -C "idsl-cohort-key" -q
    fi
    _ensure_keys
    echo "[ctl] Entering the bastion as player ($BASTION_IP) via cohort-key ..."
    echo "[ctl] (run './ctl session' in another terminal so scenarios position the world)"
    ssh -i cohort-key -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "player@$BASTION_IP"
    ;;

  help|*)
    cat <<EOF
Usage: ./ctl <command>

Operator (deploy, observe, world posture):
  up            generate keys, build images, create bridges, deploy
                (SEED_COUNT=N ./ctl up sets the backbone table size)
  down          destroy the topology, remove the bridges
  session       session manager: watch the bastion, set posture/loot per scenario,
                arm the scorer, copy the bundle on completion (run alongside the lab)
  table         looking glass: show ip bgp on the observer
  lg            looking glass, structured: show ip bgp json
  ssh NODE      shell on a node       (e.g. ./ctl ssh attacker-as)
  vtysh NODE    vtysh on a router     (e.g. ./ctl vtysh attacker-as)
  seed-fetch [N]  refresh the backbone seed from a live dump (network needed)
  rpki          show the trust fabric: Routinator VRPs + FMDA ROAs
  rpki-init     (re)onboard the FMDA CA and baseline ROAs
  rov on|off    origin validation on/off at the transits (defence posture)
  irr on|off|rebuild  IRR prefix filtering at the transits (defence posture)
  localpref on|off    customer-over-peer local-pref at the transits (route-leak,
                      policy-trust-abuse; never on at once with rov)
  rpki-export [dir]   dump VRPs + ROAs + Routinator log (telemetry for heimdallr)
  irr-export  [dir]   dump IRR route objects + journal (telemetry for heimdallr)
  score [scenario] [poll|bmp]  score the flag + write the timeline; poll (M4 inc 1)
                               or bmp (inc 2, the bmp-collector feed, exact timing)

Player surface (the door):
  player        play locally: enter the bastion with a cohort key (auto-made)
  playtest      operator check of the player path, using the lab key
  cohort-keys   generate a participant keypair to hand out (local or via -J)

Attacker actions are NOT here: the player performs them from the Phase-1 box the
bastion drops them on (vtysh on the foothold; bin/launder and bin/poison on the
registry workstation). Cleanup is ./ctl down && ./ctl up, never an undo verb.

Nodes: transit-a transit-b victim-as attacker-as customer-leaky observer
       lookingglass seed registry-ca registry-rtr registry-irr bmp-collector
       bastion ops-host web eyeball
EOF
    ;;

esac