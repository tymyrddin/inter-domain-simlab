FROM quay.io/frrouting/frr:9.1.0

# inter-domain-simlab router image. One image for every AS in the lab: the
# transits, the victim, the attacker foothold and the gamemaster collector all
# run the same FRR build. sshd plus an admin user that lands straight in vtysh
# gives the player an interactive foothold (the free-roam CTF point: SSH into
# the attacker AS and drive BGP by hand), which a stock image plus
# `containerlab exec` cannot offer.

USER root

# openssh for the in-lab admin plane; tcpdump for the player to watch the wire
# (useful once data-plane diversion comes into scope). No SNMP or iptables: this
# lab is deliberately permissive and has no packet-filter policy to enforce.
RUN apk add --no-cache openssh tcpdump

# `admin` lands directly in vtysh on login. The enable secret in each frr.conf
# gates `configure terminal`. Both credentials are intentionally weak; the lab
# is a routing maze, not a hardening exercise.
RUN adduser -D -s /usr/bin/vtysh admin \
 && echo 'admin:admin' | chpasswd \
 && adduser admin frrvty \
 && ssh-keygen -A

COPY sshd_config /etc/ssh/sshd_config
COPY start.sh    /opt/start.sh
RUN chmod +x /opt/start.sh \
 && touch /etc/frr/vtysh.conf \
 && chown frr:frr /etc/frr/vtysh.conf

ENTRYPOINT ["/sbin/tini", "--", "/opt/start.sh"]