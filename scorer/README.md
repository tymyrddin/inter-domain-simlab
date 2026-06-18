# Scorer (M4)

The scorer is the observer's analytical layer. The observer (AS65000) already
peers both transits and sees the whole table while announcing nothing; the scorer
reads what it sees, turns it into one event stream, checks the scenario's flag,
and writes the timeline that the detection lab (heimdallr) practises against.

It is a host-side tool, stdlib only, the same pattern as the seed's `filter.py`,
driven by `./ctl score`. Nothing is built into a container image.

## Running it

```bash
./ctl score                                  # poll the observer (increment 1)
./ctl score false-origin-prefix-hijack poll  # the same, named
./ctl score false-origin-prefix-hijack bmp   # read the bmp-collector feed (increment 2)
```

It prints events as they happen and the flag when it lands, and writes the
timeline on exit (Ctrl-C). Drive an attack in another shell
(`scenarios/<name>/attack.md`) and watch the events arrive. `poll` diffs the
observer's `show ip bgp json`; `bmp` reads the exact-timing event stream from the
bmp-collector (below).

## What it does

Three jobs in one loop:

- Watch. Poll the observer's table. (Increment 2 swaps the poll for the observer's
  native BMP feed, for exact event timing.)
- Normalise. Diff successive snapshots into one event envelope, designed fresh
  around what the observer emits, not inherited from red-lantern-sim.
- Score and emit. Evaluate the flag from the scenario's structured `target:` block
  (the `hijack_prefix` reaching the table with `hijack_origin`), not the prose
  `flag_condition.check`, and write the timeline. Scenarios whose effect is regional
  (route-leak, policy-trust-abuse) set `score_node:` so the flag is judged at a
  specific transit, and route-leak sets `leak_via:` to match the leaker AS in the
  path rather than a new origin (the origin is unchanged by a leak).

## The event envelope

One shape per event:

```json
{"ts":"2026-06-15T...Z","scenario":"false-origin-prefix-hijack",
 "source":"collector:observer","type":"more-specific",
 "prefix":"203.0.113.0/25","origin_as":65020,"as_path":[65002,65020],"rpki":"invalid"}
```

`type` is one of announce, more-specific, origin-change, withdraw, flag. The
`rpki` field is computed (RFC 6811) from Routinator's VRPs, so an event carries
both the routing fact and its validation state, which is what the ROA-poisoning
and RPKI-cover correlations key off downstream. With ROV toggled (`./ctl rov`,
`./ctl roa`, see the operator guide), the same run shows the /25 flip between
invalid and not-found.

## Artefacts and the heimdallr hand-off

Two outputs, kept apart on purpose. The scorer's timeline (the derived, labelled
record: more-specific, MOAS, the flag, the RPKI state per event) lands at
`scoring/<scenario>/timeline.json`. That is the lab's own scoring record and the
ground truth a detector is judged against; it never goes into the ingest bundle,
because a detector trained or tested on the answers is grading itself.

The heimdallr bundle is the raw, unlabelled half: `artefacts/<scenario>/` holds the
collector's `events.jsonl`, the RPKI export (VRPs, ROAs, the ROA-change history and
the validator log, `./ctl rpki-export`) and, for the IRR scenario, the route objects
and journal (`./ctl irr-export`). Copy that directory into heimdallr's `ingest/` and
its routing feeder reads it directly. The bundle carries the re-convergence noise the
routing system actually produced around the attack, not a filtered signal.

On a played scenario the session manager (`./ctl session`, the primary path) writes
both when the flag fires: the timeline to `scoring/` and the raw bundle to
`artefacts/`. `./ctl score` is the same scoring loop run standalone against a
hand-driven attack. Commit one known-good bundle per scenario.

## Increment 2: the BMP feed

BMP is a router-to-station protocol (RFC 7854), so the station is a node on the
fabric, not a host process: the `bmp-collector` (MycoSec's, like the observer)
hangs off the observer on a /30. The observer's FRR loads `bgpd_bmp.so` (`-M bmp`)
and a `bmp targets` block connects out to the collector, monitoring ipv4-unicast
pre and post policy. `clab/bmp/bmp_collector.py` parses route-monitoring messages
(BMP framing, then the embedded BGP UPDATE, then NLRI/withdrawals plus AS_PATH and
origin) into the event envelope and appends them to `access/bmp/events.jsonl`.

That `events.jsonl` is the raw artefact: the full stream, including the initial
RIB dump FRR sends on session start, which is the exact-timing source heimdallr's
cover and multi-stage fixtures read. `./ctl score ... bmp` reads it from the
current end (so it skips the dump), enriches each event with the RPKI state and
scores, the same as poll mode but with the router-stamped event time. The scorer
stays host-side stdlib; only the collector is a container.

Two things the feed shows as the router emits them, not massaged: FRR's
post-policy AS_PATH carries the observer's own AS at the head (the origin and
prefix are unaffected), and FRR stamps to the second but reuses a fixed
microsecond, so timing is router-stamped second precision.
