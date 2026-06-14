# Backbone seed (MRT route dump)

The lab seeds its backbone with a real route dump so the global table is
plausibly large, not just the lab's own handful of prefixes plus whatever a
player announces. A near-empty table makes a hijack the only thing in sight,
which is the one place the old red-lantern-sim went wrong. This is the real
thing: a GoBGP speaker (the `seed` node, AS65003) replays the dump as genuine
eBGP UPDATEs to both transits, and the routes propagate the way every other
route in the lab does.

## What is here

- `filter.py`: reads a raw RouteViews/RIS MRT RIB dump and writes a clean,
  sampled one. It keeps one entry per IPv4-unicast prefix (raw dumps carry one
  per collector peer), drops bogons, special-use space and the lab's own blocks,
  drops any route whose AS_PATH carries a lab ASN, and random-samples across the
  whole table. The real AS_PATH is preserved.
- `fetch.sh`: downloads the most recent route-views2 RIB and runs `filter.py`
  over it. Operator-time only, needs network.
- `seed.sample.mrt`: the committed sample (~10k prefixes), and the file the
  topology binds. It lets a fresh clone deploy offline.

Raw dumps (`*.bz2`, `*.gz`, other `*.mrt`) are gitignored; only the sample is
committed.

`filter.py` needs the `mrtparse` package to read MRT. It is the one dependency
here, and it is not declared in a requirements file: `fetch.sh` installs it on
demand (into the repo's `.venv` if present, otherwise the active Python). Running
`filter.py` directly wants `pip install mrtparse` first. Nothing at deploy time
needs it, since the committed sample is pre-built; it is only for a refresh.

## Scale (the SEED_COUNT dial)

`gobgp mrt inject global <file> <count>` takes the first `count` records.
`filter.py` shuffles its output, so the first `count` is a representative slice,
and `SEED_COUNT` becomes a clean size dial:

```
SEED_COUNT=10000 ./ctl up      # the committed sample, offline default
```

Larger tables need a fresh, larger dump (the committed sample only holds ~10k):

```
./ctl seed-fetch 50000         # download + filter to 50k, network needed
./ctl down && SEED_COUNT=50000 ./ctl up
```

A full default-free table is roughly 950k routes. The lab aims for plausible,
not complete (PLAN.md section 13): start at 10k, ramp, and note the comfortable
ceiling for your host here once measured. Every node in the no-policy mesh holds
the table, so memory and convergence climb with the count.

Measured on a 31 GiB host, two points so far, both converging in under a minute:

| SEED_COUNT | routes  | FRR node (holds the table) | seed (GoBGP) |
|------------|---------|----------------------------|--------------|
| 10000      | 10003   | 45 to 65 MiB               | 55 MiB       |
| 100000     | 100003  | 165 to 246 MiB             | 421 MiB      |

So an FRR node costs roughly 40 MiB of base plus about 1.7 KiB per route, and the
GoBGP seed a few times that. At 100k nothing is breathing hard: the heaviest node
is under 1 percent of RAM, and all ten nodes together stay under 2 GiB. There is
no ceiling in sight at 100k.

Extrapolating to a full default-free table (~950k routes) lands each FRR node near
1.5 to 1.7 GiB and the seed nearer 4 GiB, so roughly 12 to 16 GiB across the lab.
That is feasible on this 31 GiB host but is the point where it would want testing
rather than trusting the line; convergence time also climbs with the count. For
teaching, 100k already gives a table that reads like the real thing. Push higher
if a scenario needs it, and update this table with what your host does.

## What is real and what is not

Real: the prefixes, their origins and their AS_PATHs come straight from a public
collector. Origins matter for the later RPKI and IRR work, so they are kept
intact.

Abstracted, on purpose: the adjacency between the seed (AS65003) and the first
real AS in each path. The seed did not actually peer AS3356; it is replaying a
recorded path and eBGP prepends its own ASN. So the table looks realistic in
size, prefix-length spread and origin diversity, but the seed-to-first-hop link
is fictional from the topology's vantage. This is fine for the scenarios that
key off origin and prefix (origin hijack, more-specific, RPKI ROV). An
experiment that validates background adjacency (AS-path-anomaly work) would need
a dump mapped onto the lab topology, which is a separate, larger piece and is
deferred. Synthesising paths to fake that adjacency is off the table: it would
fabricate data, the one thing the lab does not do.

## Isolation

The seed cannot touch the experimental prefixes, by two independent layers:
`filter.py` strips the lab blocks and bogons from the dump, and each transit
carries an inbound prefix-list on the seed session (`PL-SEED-IN` in
`configs/transit-a.conf` and `configs/transit-b.conf`) that denies the same set,
each with `le 32` so no more-specific slips through. The /24-versus-/25
longest-prefix behaviour the lab tests is left exactly as it was.
