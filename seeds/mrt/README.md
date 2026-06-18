# Backbone seed (MRT route dump)

A GoBGP node (`seed`, AS65003) replays a real, filtered route dump as eBGP UPDATEs to
both transits, so the global table is backbone-sized rather than just the lab's own
prefixes. The routes propagate like any other.

## What is here

- `filter.py` — reads a raw RouteViews/RIS MRT dump and writes a clean, sampled one:
  one entry per IPv4-unicast prefix, bogons and lab blocks dropped, any path carrying a
  lab ASN dropped, random-sampled across the table, real AS_PATHs preserved. Needs
  `mrtparse` (`fetch.sh` installs it; or `pip install mrtparse` to run it directly).
- `fetch.sh` — downloads the latest route-views2 RIB and filters it. Network needed.
- `seed.sample.mrt` — the committed ~10k sample the topology binds, so a fresh clone
  deploys offline. Raw dumps (`*.bz2`/`*.gz`/`*.mrt`) are gitignored.

## Scale (the SEED_COUNT dial)

`gobgp mrt inject` takes the first `count` records and `filter.py` shuffles its output,
so `SEED_COUNT` is a clean size dial:

```bash
SEED_COUNT=10000 ./ctl up                            # the committed sample (offline default)
./ctl seed-fetch 50000 && SEED_COUNT=50000 ./ctl up  # bigger needs a fresh dump (network)
```

Every table-holding node grows with the count. At 100k the whole lab stays well under
2 GiB on a 31 GiB host; a full ~950k table extrapolates to 12-16 GiB and is the point to
test rather than trust. Measure on your host and note it here.

## What is abstracted

The prefixes, origins and AS_PATHs are real (origins matter for the RPKI and IRR work).
The one fiction is the link between the seed and the first real AS in each path: the
seed replays recorded paths and prepends its own ASN, so that hop is not a real peering.
Fine for the origin, more-specific and ROV scenarios; AS-path-adjacency work would need
a dump mapped onto the topology, which is deferred. Synthesising paths to fake it is
off the table.

## Isolation

The seed cannot touch the lab's experimental prefixes, two ways: `filter.py` strips the
lab blocks from the dump, and each transit carries an inbound `PL-SEED-IN` prefix-list
denying the same set (`le 32`, so no more-specific slips through).
