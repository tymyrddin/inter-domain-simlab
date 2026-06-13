#!/bin/sh
# inter-domain-simlab ops-host startup.
#   1. Stage the lab access key (bind-mounted read-only at /run/lab-key) into
#      the player's ~/.ssh with private-key perms, so the foothold/lg helpers
#      can use it. A read-only root-owned bind mount would be rejected by ssh.
#   2. Start sshd for the player's key-only entry.
set -e

if [ -f /run/lab-key ]; then
    cp /run/lab-key /home/player/.ssh/id_ed25519
    chown player:player /home/player/.ssh/id_ed25519
    chmod 600 /home/player/.ssh/id_ed25519
fi

/usr/sbin/sshd
echo "[ops-host] sshd up (key-only). Entry is over the access LAN, no published port."

exec tail -f /dev/null