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
#   table         looking glass: show ip bgp on the gamemaster (operator)
#   lg            looking glass, structured: show ip bgp json (operator)
#   ssh NODE      shell on a node          (clab-inter-domain-NODE)
#   vtysh NODE    vtysh on a router node
#   player        play locally: enter the ops host with a cohort key (auto-made)
#   playtest      operator check of the player path, using the lab key
#   cohort-keys   generate a participant keypair to hand out

set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

# BuildKit attaches OCI provenance attestations by default, which fetch registry
# metadata and hang in offline lab environments. Turn that off.
export BUILDX_NO_DEFAULT_ATTESTATIONS=1

LAB="inter-domain"
TOPO="clab/inter-domain.clab.yml"
GM="clab-${LAB}-gamemaster"
BRIDGE="idsl_access"
ACCESS_NET="100.64.0.0/24"
HOST_IP="100.64.0.254/24"
OPS_HOST_IP="100.64.0.10"
CMD="${1:-help}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Generate the lab access key on first use, then (re)build the authorized_keys
# files the topology bind-mounts. The committed image carries no credential;
# these files are created here and gitignored.
_ensure_keys() {
    mkdir -p access
    if [ ! -f lab-key ]; then
        ssh-keygen -t ed25519 -f lab-key -N "" -C "idsl-lab-key" -q
        echo "[ctl] Generated lab-key / lab-key.pub (gitignored, operator + in-lab pivot)"
    fi
    # admin (foothold) and glass (looking glass) trust the lab access key.
    cp lab-key.pub access/authorized_keys
    # The ops-host player trusts the lab key plus any cohort key.
    cat lab-key.pub > access/player_authorized_keys
    if [ -f cohort-key.pub ]; then
        cat cohort-key.pub >> access/player_authorized_keys
    fi
}

_ssh_lab() {
    ssh -i lab-key -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$@"
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

case "$CMD" in

  up)
    _ensure_keys
    echo "[ctl] Building images ..."
    docker build -q -t clab-router   clab/frr
    docker build -q -t idsl-ops-host clab/ops-host
    echo "[ctl] Creating access bridge $BRIDGE (sudo) ..."
    sudo ip link add "$BRIDGE" type bridge 2>/dev/null || true
    sudo ip link set "$BRIDGE" up
    sudo ip addr add "$HOST_IP" dev "$BRIDGE" 2>/dev/null || true
    echo "[ctl] Deploying topology ..."
    sudo containerlab deploy -t "$TOPO"
    echo ""
    echo "  Lab is up."
    echo "  Operator looking glass:  ./ctl table        (./ctl lg for JSON)"
    echo "  Operator foothold:       ./ctl vtysh attacker-as"
    echo "  Operator playtest:       ./ctl playtest  then  foothold  /  lg"
    echo "  Play locally:            ./ctl player    (generates a cohort key)"
    echo "  Cohort keys for others:  ./ctl cohort-keys"
    echo "  Stop:                    ./ctl down"
    ;;

  down)
    sudo containerlab destroy --cleanup -t "$TOPO"
    echo "[ctl] Removing access bridge $BRIDGE (sudo) ..."
    sudo ip link del "$BRIDGE" 2>/dev/null || true
    ;;

  table)
    docker exec "$GM" vtysh -c "show ip bgp"
    ;;

  lg)
    docker exec "$GM" vtysh -c "show ip bgp json"
    ;;

  ssh)
    NODE="${2:?usage: ./ctl ssh NODE}"
    exec docker exec -it "clab-${LAB}-${NODE}" sh
    ;;

  vtysh)
    NODE="${2:?usage: ./ctl vtysh NODE}"
    exec docker exec -it "clab-${LAB}-${NODE}" vtysh
    ;;

  cohort-keys)
    ssh-keygen -t ed25519 -f "$REPO/cohort-key" -N "" -C "idsl-cohort-key" -q
    echo "[ctl] Generated cohort-key / cohort-key.pub (gitignored)"
    _ensure_keys   # refreshes the bind-mounted authorized_keys live, no redeploy
    echo ""
    echo "  Distribute the private key to participants:  $REPO/cohort-key"
    echo ""
    echo "  Local play, the host is on the access bridge ($BRIDGE, ${HOST_IP%/*}):"
    echo "      ssh -i cohort-key player@$OPS_HOST_IP"
    echo ""
    echo "  Production, the access LAN is internal and there is no published port."
    echo "  Players jump through a restricted account on the lab host:"
    echo "      ssh -i cohort-key -J jump@<lab-host> player@$OPS_HOST_IP"
    ;;

  playtest)
    # Operator check: walk the player path straight after `up`, using the lab
    # key. No cohort key needed, so this works the moment the lab is up.
    echo "[ctl] (operator) entering ops-host via lab-key ..."
    _ssh_lab "player@$OPS_HOST_IP"
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
    echo "[ctl] Entering ops-host as player ($OPS_HOST_IP) via cohort-key ..."
    ssh -i cohort-key -o IdentitiesOnly=yes \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "player@$OPS_HOST_IP"
    ;;

  help|*)
    cat <<EOF
Usage: ./ctl <command>

Operator (god-mode):
  up            generate keys, build images, create access bridge, deploy
  down          destroy the topology, remove the access bridge
  table         looking glass: show ip bgp on the gamemaster
  lg            looking glass, structured: show ip bgp json
  ssh NODE      shell on a node       (e.g. ./ctl ssh attacker-as)
  vtysh NODE    vtysh on a router     (e.g. ./ctl vtysh attacker-as)

Player surface:
  player        play locally: enter the ops host with a cohort key (auto-made)
  playtest      operator check of the player path, using the lab key
  cohort-keys   generate a participant keypair to hand out (local or via -J)

Nodes: transit-a transit-b victim-as attacker-as gamemaster lookingglass
       ops-host web eyeball
EOF
    ;;

esac