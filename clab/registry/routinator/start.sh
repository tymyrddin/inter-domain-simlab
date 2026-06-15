#!/bin/sh
# registry-rtr entrypoint. Order matters and Routinator's refresh is slow, so we
# control it here rather than leave the IP to a clab exec: bring the services
# interface up, then block until Krill has published its TAL and RRDP cert into
# the shared dir (./ctl rpki-init writes them), then run. Launching before the
# TAL exists would leave Routinator with no trust anchor until a restart.
set -eu

n=0
until ip link show eth1 >/dev/null 2>&1; do
    n=$((n + 1)); [ "$n" -ge 30 ] && break; sleep 1
done
ip addr add 10.0.0.34/28 dev eth1
ip link set eth1 up

# No DNS in the lab: resolve Krill's FQDN, used in the TAL's rsync URI.
grep -q fmda-ca.lab /etc/hosts || echo "10.0.0.33 fmda-ca.lab" >> /etc/hosts

echo "[rtr] waiting for the Krill TAL in /share (run ./ctl rpki-init) ..."
until [ -s /share/krill.tal ]; do sleep 2; done

mkdir -p /etc/routinator/tals
cp /share/krill.tal /etc/routinator/tals/krill.tal

echo "[rtr] starting Routinator against the local Krill TAL only"
exec routinator -c /etc/routinator/routinator.conf \
    --no-rir-tals --extra-tals-dir /etc/routinator/tals server
