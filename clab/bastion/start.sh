#!/bin/sh
# inter-domain-simlab bastion startup.
#   1. Stage the pivot key (lab-key, bind-mounted read-only at /run/lab-key) into
#      the player's ~/.ssh with private-key perms, so the menu can ProxyJump to the
#      scenario's Phase-1 box. The player never holds this key; it lives here.
#   2. Start sshd for the player's key-only entry (ForceCommand -> menu).
set -e

if [ -f /run/lab-key ]; then
    cp /run/lab-key /home/player/.ssh/id_ed25519
    chown player:player /home/player/.ssh/id_ed25519
    chmod 600 /home/player/.ssh/id_ed25519
fi

# The control channel to the host-side session manager (bind-mounted).
mkdir -p /control 2>/dev/null || true

/usr/sbin/sshd
echo "[bastion] sshd up (key-only). Entry is over the access LAN, no published port."

exec tail -f /dev/null
