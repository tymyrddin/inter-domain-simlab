# Scorer

The observer (AS65000) peers both transits and sees the whole table while announcing
nothing. The scorer reads that, turns successive snapshots (or the BMP feed) into one
event stream, scores the scenario flag, and writes the timeline. Host-side, stdlib
only.

## Running it

The running lab scores each play on its own. To run it by hand against a hand-driven
attack:

```bash
./ctl score                                  # poll the observer
./ctl score false-origin-prefix-hijack bmp   # read the bmp-collector feed instead
```

It prints events as they arrive and the flag when it lands. The flag comes from the
scenario's `target:` block; regional scenarios add `score_node:` (judge at a transit)
and `leak_via:` (match a leaker in the path, since a leak does not change the origin).

## Two outputs, kept apart

- `scoring/<scenario>/timeline.json` — the scorer's labelled record (more-specific,
  MOAS, the flag, the RPKI state per event). The lab's scoring record and the ground
  truth a detector is judged against. It never goes to heimdallr: a detector tested on
  the answers is grading itself.
- `artefacts/<scenario>/` — the raw, unlabelled bundle heimdallr ingests:
  `events.jsonl` (one JSON event per line: prefix, origin, AS_PATH, RPKI state), the
  RPKI export (`./ctl rpki-export`) and, for the IRR scenario, the route objects and
  journal (`./ctl irr-export`). It keeps the re-convergence noise the routing system
  actually produced, not a filtered signal.

## The BMP feed

`./ctl score ... bmp` reads exact-timing events from the `bmp-collector` node, which
hangs off the observer and writes the raw stream to `access/bmp/events.jsonl`. The
parser and the wire details live in `clab/bmp/`.
