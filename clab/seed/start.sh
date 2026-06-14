#!/bin/sh
# seed entrypoint. Start gobgpd, wait for its API, then inject the first
# $SEED_COUNT records of the filtered MRT dump into the global RIB. GoBGP
# advertises them to both transits over eBGP with next-hop-self (its default),
# so the dump's public next-hops become reachable via the seed. Interface
# addresses are assigned by the clab exec block (GoBGP has no zebra).
set -eu

DUMP="${SEED_DUMP:-/seeds/seed.sample.mrt}"
COUNT="${SEED_COUNT:-10000}"

gobgpd -f /etc/gobgp/gobgpd.conf &
GPID=$!

(
    # Wait for the gobgpd gRPC API to answer before injecting.
    n=0
    until gobgp global rib summary >/dev/null 2>&1; do
        n=$((n + 1))
        [ "$n" -ge 60 ] && { echo "[seed] gobgpd API never came up"; exit 1; }
        sleep 1
    done
    if [ -f "$DUMP" ]; then
        echo "[seed] injecting up to $COUNT prefixes from $DUMP"
        gobgp mrt inject global "$DUMP" "$COUNT"
        echo "[seed] global RIB now: $(gobgp global rib summary 2>/dev/null | grep -o 'Path: [0-9]*')"
    else
        echo "[seed] no dump at $DUMP; advertising nothing (run ./ctl seed-fetch)"
    fi
) &

wait "$GPID"
