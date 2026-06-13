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
# gates `configure terminal`. Key-only auth: no password is set, so the account
# cannot be logged into until a deploy-time public key is bind-mounted onto
# /home/admin/.ssh/authorized_keys (see ctl and the topology). The committed
# image therefore carries no working credential, which is the rule for a lab
# that runs on a public host.
# passwd -d gives an empty (not locked) password. adduser -D leaves the account
# locked with `!`, and sshd with UsePAM no refuses even pubkey auth to a locked
# account. Empty is not a usable credential here: PasswordAuthentication no and
# PermitEmptyPasswords no mean no password (empty or otherwise) is ever accepted
# over SSH; entry is by key only.
RUN adduser -D -s /usr/bin/vtysh admin \
 && adduser admin frrvty \
 && passwd -d admin \
 && mkdir -p /home/admin/.ssh \
 && chown -R admin:admin /home/admin/.ssh \
 && chmod 700 /home/admin/.ssh \
 && ssh-keygen -A

# `glass` is the read-only looking-glass identity. Its sshd ForceCommand (see
# sshd_config) runs a single `show ip bgp` and exits, so a player can query a
# collector's table without any route into configuration mode. It is in frrvty
# so vtysh can read the bgpd socket, and nothing else. Same key-only rule: no
# password, the authorized key arrives at deploy time. Harmless on every router
# but only exposed on the lookingglass node the player can reach.
RUN adduser -D -s /bin/sh glass \
 && adduser glass frrvty \
 && passwd -d glass \
 && mkdir -p /home/glass/.ssh \
 && chown -R glass:glass /home/glass/.ssh \
 && chmod 700 /home/glass/.ssh

COPY sshd_config /etc/ssh/sshd_config
COPY start.sh    /opt/start.sh
RUN chmod +x /opt/start.sh \
 && touch /etc/frr/vtysh.conf \
 && chown frr:frr /etc/frr/vtysh.conf

ENTRYPOINT ["/sbin/tini", "--", "/opt/start.sh"]