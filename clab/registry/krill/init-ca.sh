#!/bin/sh
# init-ca.sh — onboard FMDA's CA and add the baseline ROAs, then publish the
# trust material Routinator needs. Run once after deploy (./ctl rpki-init), not
# at image build, because it talks to the running krilld.
#
# The testbed TA and the `fmda` CA live in the same Krill instance, so the
# RFC 8183 exchange is done with local krillc commands (children add / pubserver
# publishers add), not the testbed HTTP endpoints. Idempotent: a CA that already
# exists is left as is.
set -eu

CA=fmda
TOKEN="${KRILL_ADMIN_TOKEN:?KRILL_ADMIN_TOKEN must be set}"
API="https://localhost:3000"
SHARE=/share
# Lab prefixes the testbed TA delegates to FMDA so it can sign ROAs for them.
V4="192.0.2.0/24,198.51.100.0/24,203.0.113.0/24"

export KRILL_CLI_SERVER="$API/"
export KRILL_CLI_TOKEN="$TOKEN"

echo "[init-ca] waiting for krilld API ..."
until curl -ks -o /dev/null "$API/health"; do sleep 1; done
# On a fresh deploy Krill is still creating the testbed TA; it must exist before
# we can register FMDA as its child.
echo "[init-ca] waiting for the testbed TA ..."
until krillc list 2>/dev/null | grep -qx testbed; do sleep 2; done

if krillc list 2>/dev/null | grep -qx "$CA"; then
    echo "[init-ca] CA $CA already exists, ensuring ROAs and shared material"
else
    echo "[init-ca] creating CA $CA"
    krillc add --ca "$CA"

    # Repository under Krill's built-in publication server.
    krillc repo request --ca "$CA" > /tmp/pub_req.xml
    krillc pubserver publishers add --request /tmp/pub_req.xml >/dev/null
    krillc pubserver publishers response --publisher "$CA" > /tmp/repo_resp.xml
    krillc repo configure --ca "$CA" --response /tmp/repo_resp.xml

    # Parent: the testbed TA delegates the lab prefixes to FMDA.
    krillc parents request --ca "$CA" > /tmp/child_req.xml
    krillc children add --ca testbed --child "$CA" --ipv4 "$V4" \
        --request /tmp/child_req.xml > /tmp/parent_resp.xml
    krillc parents add --ca "$CA" --parent testbed --response /tmp/parent_resp.xml
fi

echo "[init-ca] waiting for delegated resources ..."
for _ in $(seq 1 30); do
    krillc parents refresh --ca "$CA" >/dev/null 2>&1 || true
    krillc show --ca "$CA" | grep -q "203.0.113.0/24" && break
    sleep 3
done

echo "[init-ca] adding baseline ROAs"
# FDEI's /24, valid only as a /24 from AS65010: this makes the attacker's
# 203.0.113.0/25 (origin 65020) RPKI-invalid, the defence ROV enforces.
# FungusFiber's eyeball segment (AS65001) and Bracket Hosting's own honest
# space (AS65020) are valid too. Tolerant of re-runs where a ROA exists.
for roa in \
    "203.0.113.0/24-24 => 65010" \
    "192.0.2.0/24-24 => 65001" \
    "198.51.100.0/24-24 => 65020"; do
    krillc roas update --ca "$CA" --add "$roa" 2>/dev/null \
        || echo "[init-ca]   ($roa already present)"
done

# Publish the TA cert into the rsync `ta` module so Routinator can retrieve the
# trust anchor over rsync (rsync://fmda-ca.lab/ta/ta.cer).
mkdir -p /var/krill/data/ta-rsync
curl -ks "$API/ta/ta.cer" -o /var/krill/data/ta-rsync/ta.cer

# The TAL is all Routinator needs from the shared dir; it points at the rsync TA
# URI. Written last, so registry-rtr unblocks only once ta.cer is in place.
echo "[init-ca] publishing TAL to $SHARE and TA cert to the rsync module"
mkdir -p "$SHARE"
curl -ks "$API/ta/ta.tal" -o "$SHARE/krill.tal"

echo "[init-ca] done; ROAs:"
krillc roas list --ca "$CA"
