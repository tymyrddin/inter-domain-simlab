FROM nlnetlabs/routinator:v0.15.2

# registry-rtr: FMDA's RPKI validator and RTR server (Routinator with its
# built-in RTR, so one container, not a separate Stayrtr; PLAN.md section 17
# decision 1). It validates the lab's own Krill testbed TA only, with no
# internet, and serves the validated payloads (VRPs) to the transits over RTR.
#
# We override the official entrypoint (which would install the five RIR TALs)
# with start.sh, so the only trust anchor is the local Krill one. iproute2 for
# the services-segment IP, curl kept for debugging the RRDP fetch.
USER root
RUN apk add --no-cache iproute2 curl

COPY routinator.conf /etc/routinator/routinator.conf
COPY start.sh        /opt/start.sh
RUN chmod +x /opt/start.sh

ENTRYPOINT ["/opt/start.sh"]
