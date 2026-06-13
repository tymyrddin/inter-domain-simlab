#!/bin/sh
# inter-domain-simlab router startup wrapper.
#   1. Start sshd so the in-lab admin plane (admin/admin -> vtysh) is reachable.
#   2. Hand off to the upstream FRR docker-start, which boots zebra + bgpd from
#      the bind-mounted /etc/frr/frr.conf and /etc/frr/daemons.
set -e

/usr/sbin/sshd
echo "[router] sshd up on :22 (default creds: admin/admin -> vtysh)"

exec /usr/lib/frr/docker-start