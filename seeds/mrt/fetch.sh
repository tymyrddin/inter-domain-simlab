#!/usr/bin/env bash
# fetch.sh — download a real RouteViews RIB dump and filter it into the lab seed.
#
# Operator-time only (needs network); the lab nodes stay contained. The default
# deploy does not run this: the committed seed.sample.mrt is enough for an
# offline ./ctl up. Run this to refresh the dump or to build a larger one for
# ramp testing (a 50k/100k seed needs the fetch; the default 10k ships in-repo).
#
# Usage: ./seeds/mrt/fetch.sh [COUNT]      (COUNT defaults to 10000)
# Output: seeds/mrt/seed.sample.mrt        (the file the topology binds)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
COUNT="${1:-10000}"
OUT="$HERE/seed.sample.mrt"

# Pick a Python with mrtparse: prefer the repo venv, install mrtparse if absent.
PY="$REPO/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"
if ! "$PY" -c "import mrtparse" 2>/dev/null; then
    echo "[fetch] installing mrtparse into $($PY -c 'import sys;print(sys.prefix)')"
    "$PY" -m pip install -q mrtparse
fi

# Most recent route-views2 RIB for the current UTC month.
BASE="http://archive.routeviews.org/route-views2/bgpdata"
MON="$(date -u +%Y.%m)"
RIB="$(curl -s "$BASE/$MON/RIBS/" \
        | grep -oE 'rib\.[0-9]{8}\.[0-9]{4}\.bz2' | sort -u | tail -1)"
if [ -z "$RIB" ]; then
    echo "[fetch] no RIB found for $MON under $BASE" >&2; exit 1
fi

RAW="$HERE/$RIB"
echo "[fetch] downloading $RIB ..."
curl -s -o "$RAW" "$BASE/$MON/RIBS/$RIB"

echo "[fetch] filtering to $COUNT prefixes ..."
"$PY" "$HERE/filter.py" "$RAW" "$OUT" --count "$COUNT"

echo "[fetch] done: $OUT ($(du -h "$OUT" | cut -f1)). Raw dump $RAW is gitignored."
