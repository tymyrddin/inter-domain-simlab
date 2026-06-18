FROM wbitt/network-multitool:latest

# inter-domain-simlab registry-attacker workstation: the Phase-1 box for the
# registry-tamper scenarios. The bastion (the door) drops the player here for
# legitimacy-subversion and roa-poisoning; from here they submit to FMDA's IRR
# (launder) or withdraw FDEI's ROA from Krill (poison) over the regpub segment,
# using credentials planted in /loot, then pivot to the foothold to announce.
# It runs no BGP itself; it carries curl + an SSH client for the pivot.
#
# Key-only, no published port: reached only via the bastion's pivot key over the
# internal access LAN, never from a 0.0.0.0 port.

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
COPY bin/launder   /usr/local/bin/launder
COPY bin/poison    /usr/local/bin/poison
RUN chmod +x /opt/start.sh /usr/local/bin/foothold /usr/local/bin/lg \
             /usr/local/bin/launder /usr/local/bin/poison

ENTRYPOINT ["/opt/start.sh"]