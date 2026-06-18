FROM alpine:3.20

# inter-domain-simlab bastion: the one door into the range. Players SSH in with a
# cohort key and meet a ForceCommand-locked welcome + scenario menu; there is no
# shell on this box and no attack tooling. On a choice the menu writes the
# selection to /control (the host-side `ctl session` enacts posture + loot) and
# ProxyJumps the player to the scenario's Phase-1 box with the pivot key staged at
# /run/lab-key. The bastion holds no god-mode: it requests, the operator enacts.
#
# Key-only, no published port: entry is over the internal access LAN, never a
# 0.0.0.0 port.

RUN apk add --no-cache openssh openssh-client bash coreutils

# `player` is the only account. No password; the cohort key is bind-mounted at
# deploy. passwd -d leaves an empty (not locked) password so sshd with UsePAM no
# still accepts pubkey; PasswordAuthentication no keeps entry key-only.
RUN adduser -D -s /bin/bash player \
 && passwd -d player \
 && mkdir -p /home/player/.ssh \
 && chown -R player:player /home/player/.ssh \
 && chmod 700 /home/player/.ssh \
 && ssh-keygen -A

COPY sshd_config /etc/ssh/sshd_config
COPY start.sh    /opt/start.sh
COPY motd        /etc/motd
COPY bin/menu    /usr/local/bin/menu
RUN chmod +x /opt/start.sh /usr/local/bin/menu

ENTRYPOINT ["/opt/start.sh"]
