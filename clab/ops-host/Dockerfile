FROM wbitt/network-multitool:latest

# inter-domain-simlab attacker ops host: the player's workstation and the one
# sanctioned entry into the lab. It carries recon and traffic tooling and an
# SSH client for pivoting to the foothold; it does not run BGP itself. The
# offensive announcement crafting (ExaBGP/GoBGP/bgpq4) is a later upgrade, in
# milestone 1.5 the player drives the foothold's own vtysh by hand.
#
# Key-only, no published port: the player enters over the internal access LAN
# (reached from the operator host's bridge address), never from a 0.0.0.0 port.

RUN apk add --no-cache openssh openssh-client tcpdump mtr bind-tools curl traceroute bash

# `player` is the entry account. No password; the authorized key (a cohort key)
# is bind-mounted at deploy time. The lab access key used to pivot to the
# foothold is staged at /run/lab-key and copied in by start.sh with safe perms.
# passwd -d gives an empty (not locked) password. adduser -D leaves the account
# locked with `!`, and sshd with UsePAM no refuses even pubkey auth to a locked
# account. Not a usable credential: PasswordAuthentication no and
# PermitEmptyPasswords no keep entry key-only.
RUN adduser -D -s /bin/bash player \
 && passwd -d player \
 && mkdir -p /home/player/.ssh \
 && chown -R player:player /home/player/.ssh \
 && chmod 700 /home/player/.ssh \
 && ssh-keygen -A

COPY sshd_config   /etc/ssh/sshd_config
COPY start.sh      /opt/start.sh
COPY motd          /etc/motd
COPY bin/foothold  /usr/local/bin/foothold
COPY bin/lg        /usr/local/bin/lg
RUN chmod +x /opt/start.sh /usr/local/bin/foothold /usr/local/bin/lg

ENTRYPOINT ["/opt/start.sh"]