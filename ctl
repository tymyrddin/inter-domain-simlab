#!/usr/bin/env bash
# ctl — inter-domain-simlab lab control.
#
# Slim by design (milestone 1). Command names and the clab-<lab>-<node>
# container convention mirror ics-access-simlab's larger ctl, so this can grow
# toward generate/verify/clean later without renaming anything.
#
# Usage:
#   ./ctl <command>
#
# Commands:
#   up            build the router image, deploy the topology
#   down          destroy the topology and clean up
#   table         looking glass: show ip bgp on the gamemaster
#   lg            looking glass, structured: show ip bgp json on the gamemaster
#   ssh NODE      drop into a shell on a node (clab-inter-domain-NODE)
#   vtysh NODE    drop into vtysh on a router node

set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

# BuildKit attaches OCI provenance attestations by default, which fetch registry
# metadata and hang in offline lab environments. Turn that off.
export BUILDX_NO_DEFAULT_ATTESTATIONS=1

LAB="inter-domain"
TOPO="clab/inter-domain.clab.yml"
GM="clab-${LAB}-gamemaster"
CMD="${1:-help}"

case "$CMD" in

  up)
    echo "[ctl] Building clab-router image ..."
    docker build -q -t clab-router clab/frr
    echo "[ctl] Deploying topology ..."
    sudo containerlab deploy -t "$TOPO"
    echo ""
    echo "  Lab is up."
    echo "  Looking glass:  ./ctl table        (./ctl lg for JSON)"
    echo "  Foothold:       ./ctl vtysh attacker-as"
    echo "  Stop:           ./ctl down"
    ;;

  down)
    sudo containerlab destroy --cleanup -t "$TOPO"
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

  help|*)
    cat <<EOF
Usage: ./ctl <command>

  up            build the router image, deploy the topology
  down          destroy the topology and clean up
  table         looking glass: show ip bgp on the gamemaster
  lg            looking glass, structured: show ip bgp json
  ssh NODE      shell on a node       (e.g. ./ctl ssh attacker-as)
  vtysh NODE    vtysh on a router     (e.g. ./ctl vtysh attacker-as)

Nodes: transit-a transit-b victim-as attacker-as gamemaster web eyeball
EOF
    ;;

esac