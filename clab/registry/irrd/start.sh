#!/bin/bash
# registry-irr entrypoint: bring up a local PostgreSQL and Redis, initialise the
# IRRd schema, load FMDA's seed objects, then run IRRd in the foreground. Fully
# self-contained, no internet. eth1 (10.0.0.37/28) is assigned by the clab exec
# block, like registry-ca. See PLAN.md section 19.
set -e

id irrd >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin irrd
mkdir -p /var/run/irrd && chown irrd:irrd /var/run/irrd
# GnuPG keyring dir IRRd requires (mode 700 for gpg), even though lab auth is a password.
mkdir -p /var/lib/irrd/gnupg && chown -R irrd:irrd /var/lib/irrd && chmod 700 /var/lib/irrd/gnupg

# --- PostgreSQL (local, trust auth: contained lab) ---
PGBIN="$(ls -d /usr/lib/postgresql/*/bin | head -1)"
PGDATA=/var/lib/postgresql/data
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    mkdir -p "$PGDATA" && chown -R postgres:postgres "$PGDATA"
    su postgres -c "$PGBIN/initdb -D $PGDATA -A trust" >/dev/null
fi
su postgres -c "$PGBIN/pg_ctl -D $PGDATA -o '-c listen_addresses=localhost' -w start" >/dev/null
su postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='irrd'\" | grep -q 1 \
    || psql -c \"CREATE ROLE irrd LOGIN PASSWORD 'irrd';\"" >/dev/null
su postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='irrd'\" | grep -q 1 \
    || psql -c \"CREATE DATABASE irrd OWNER irrd;\"" >/dev/null

# --- Redis (local) ---
redis-server --daemonize yes --bind 127.0.0.1 --port 6379 >/dev/null

# --- IRRd schema ---
export IRRD_CONFIG_FILE=/etc/irrd/irrd.yaml
irrd_database_upgrade --config /etc/irrd/irrd.yaml

# --- seed FMDA (fill the maintainer auth with a known lab password, "fmda") ---
HASH="MD5-PW $(python3 -c "import crypt; print(crypt.crypt('fmda', crypt.mksalt(crypt.METHOD_MD5)))")"
sed "s|@@AUTH@@|$HASH|" /seed/fmda.db.tmpl > /seed/fmda.db
irrd_load_database --config /etc/irrd/irrd.yaml --source FMDA --serial 1 /seed/fmda.db \
    || echo "[irrd] seed load reported an issue (see above); IRRd still starting"

echo "[irrd] starting IRRd (FMDA authoritative source, whois on :43)"
exec irrd --config /etc/irrd/irrd.yaml --foreground