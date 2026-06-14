FROM alpine:3.20

# inter-domain-simlab seed node. The one non-FRR router in the lab: a GoBGP
# speaker (AS65003) that replays a real, filtered MRT route dump as genuine eBGP
# UPDATEs to both transits, so the backbone carries a plausibly large table
# (PLAN.md sections 3 and 14). FRR cannot import MRT, which is why GoBGP arrives
# here (open question 2). It is the injector only; every other AS stays FRR.

ARG GOBGP_VERSION=4.6.0

# iproute2 so the clab exec block can assign eth1/eth2 (GoBGP has no zebra, so
# nothing else would). The GoBGP binaries are static Go, no extra runtime libs.
RUN apk add --no-cache iproute2 ca-certificates \
 && wget -qO- "https://github.com/osrg/gobgp/releases/download/v${GOBGP_VERSION}/gobgp_${GOBGP_VERSION}_linux_amd64.tar.gz" \
    | tar -xz -C /usr/local/bin gobgp gobgpd

COPY gobgpd.conf /etc/gobgp/gobgpd.conf
COPY start.sh    /opt/start.sh
RUN chmod +x /opt/start.sh

# SEED_COUNT is the scale dial: gobgp mrt inject takes the first N records of the
# (already shuffled, representative) dump. Default 10000; override per deploy.
ENV SEED_COUNT=10000
ENV SEED_DUMP=/seeds/seed.sample.mrt

ENTRYPOINT ["/opt/start.sh"]
