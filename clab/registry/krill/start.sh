#!/bin/sh
# registry-ca entrypoint. Inject the per-deploy admin token into the config (so
# no credential is baked into the image), then run krilld. The services-segment
# IP is assigned by the clab exec block; krilld binds 0.0.0.0 so it does not need
# eth1 up to start. The FMDA CA and ROAs are created afterwards by ./ctl
# rpki-init (init-ca.sh), not here, because that talks to the running API.
set -eu

CONF=/etc/krill/krill.conf
FQDN=fmda-ca.lab
if [ -n "${KRILL_ADMIN_TOKEN:-}" ]; then
    sed -i "s|^admin_token .*|admin_token = \"${KRILL_ADMIN_TOKEN}\"|" "$CONF"
fi

# Pre-seed Krill's HTTPS cert with a SAN. Krill's own self-signed cert carries
# only a key-hash CN and no subjectAltName, which modern TLS (Routinator's RRDP
# fetch) rejects. Generating one here, before krilld first starts, makes Krill
# use it, so Routinator can verify https://fmda-ca.lab once it trusts the cert.
SSL=/var/krill/data/ssl
if [ ! -f "$SSL/cert.pem" ]; then
    mkdir -p "$SSL"
    # Two-level cert chain for native RRDP. rustls/webpki rejects a self-signed
    # cert that is also the server leaf (curl/OpenSSL tolerate it, rustls does
    # not), so a local self-signed root CA signs a separate fmda-ca.lab leaf:
    # Krill serves the leaf, and Routinator trusts the root via rrdp-root-certs
    # (init-ca.sh stages it). All minted locally with openssl, no public CA and
    # no internet.
    #
    # Root CA: the trust anchor Routinator is told to trust.
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$SSL/ca-key.pem" -out "$SSL/ca-cert.pem" \
        -subj "/CN=FMDA Lab Root CA" \
        -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
    #
    # Server leaf for fmda-ca.lab, signed by the root: SAN + serverAuth, CA:FALSE.
    openssl req -newkey rsa:2048 -nodes \
        -keyout "$SSL/key.pem" -out "$SSL/server.csr" \
        -subj "/CN=$FQDN" 2>/dev/null
    cat > "$SSL/leaf.ext" <<EXT
subjectAltName=DNS:$FQDN
extendedKeyUsage=serverAuth
basicConstraints=critical,CA:FALSE
EXT
    openssl x509 -req -in "$SSL/server.csr" -days 3650 \
        -CA "$SSL/ca-cert.pem" -CAkey "$SSL/ca-key.pem" -CAcreateserial \
        -extfile "$SSL/leaf.ext" -out "$SSL/cert.pem" 2>/dev/null
fi
mkdir -p /var/krill/data /var/krill/data/ta-rsync

# rsyncd serves the repository and the TA cert to Routinator (no TLS). It can
# start before Krill has published; the dirs fill in once krilld and rpki-init
# run. The TA cert is written into ta-rsync by init-ca.sh.
rsync --daemon --config /etc/rsyncd.conf

exec krill -c "$CONF"
