FROM python:3.11-slim

# registry-irr: FMDA's IRR database, real IRRd v4 (irrdnet/irrd). Self-contained:
# it bundles PostgreSQL and Redis in the one container, the way registry-ca bundles
# Krill and rsyncd, so the lab needs no external services and no internet. bgpq4 on
# the transits queries this over the IRRd whois protocol (TCP 43). See PLAN.md s19.

ENV DEBIAN_FRONTEND=noninteractive
# build-essential (not bare gcc) plus Cython: irrd pulls C-extension deps
# (datrie needs Cython, py-radix-sr needs a full toolchain) that have no wheels
# for python:3.11-slim and must compile from source.
RUN apt-get update && apt-get install -y --no-install-recommends \
        postgresql redis-server gnupg bgpq4 whois \
        build-essential libpq-dev libffi-dev \
        iproute2 ca-certificates \
    && pip install --no-cache-dir Cython \
    && pip install --no-cache-dir irrd \
    && rm -rf /var/lib/apt/lists/*

COPY irrd.yaml /etc/irrd/irrd.yaml
COPY fmda.db.tmpl /seed/fmda.db.tmpl
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 43 8080
CMD ["/start.sh"]