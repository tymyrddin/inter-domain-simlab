FROM alpine:3.20

# bmp-collector: the observer's BMP monitoring station (M4 increment 2). A small
# Python node, the same parser a host-side listener would need, sited on the
# network where a BMP station belongs (BMP is router-to-station, RFC 7854).
# python3 for the parser, iproute2 so the clab exec block can assign the /30.
RUN apk add --no-cache python3 iproute2

COPY bmp_collector.py /opt/bmp_collector.py

# events.jsonl is what the scorer reads (--source bmp); raw.bmp is the wire dump
# kept for parser iteration. Both land in the bind-mounted /out.
ENV BMP_PORT=1790
ENV BMP_OUT=/out/events.jsonl
ENV BMP_RAW=/out/raw.bmp

ENTRYPOINT ["python3", "/opt/bmp_collector.py"]
