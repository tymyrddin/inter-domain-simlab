FROM nlnetlabs/krill:v0.16.0

# registry-ca: FMDA's RPKI certificate authority and publication point (Krill),
# the lab's own trust anchor (testbed mode, self-contained, no internet). It
# issues ROAs for the lab's prefixes, the trust fabric the hijack scenarios
# subvert (PLAN.md section 17).
#
# The official image's entrypoint is kept: it builds krill.conf from KRILL_* env
# and runs krilld. We add only what the lab wiring needs on top:
#   iproute2  so the clab exec block can assign the services-segment IP (Krill
#             has no init of its own for eth1).
#   curl  for init-ca.sh: onboarding the FMDA CA to the testbed over the local
#             API, and fetching the TAL. The base (Alpine) already ships ip,
#             openssl and krillc.
#   rsync  Krill serves RRDP over HTTPS with a self-signed cert, which Routinator
#             will not use to retrieve the trust-anchor certificate. rsync is the
#             canonical RPKI transport and needs no TLS, so the lab validates over
#             rsync: rsyncd here serves Krill's repository and the TA cert.
USER root
RUN apk add --no-cache iproute2 curl rsync

# Config-driven (not the base image's env-gen entrypoint), so testbed mode is
# explicit and under our control. start.sh injects the per-deploy token and runs
# krilld; init-ca.sh is run later by ./ctl rpki-init to create the CA and ROAs.
COPY krill.conf   /etc/krill/krill.conf
COPY rsyncd.conf  /etc/rsyncd.conf
COPY start.sh     /opt/start.sh
COPY init-ca.sh   /opt/init-ca.sh
RUN chmod +x /opt/start.sh /opt/init-ca.sh

ENTRYPOINT ["/opt/start.sh"]
