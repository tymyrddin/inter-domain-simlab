# Inter-domain SimLab

A containerlab-based inter-domain routing range. A live BGP fabric of transit
providers, customer ASes and a passive collector, where an attacker with a foothold
AS practises prefix hijacks, route leaks and RPKI abuse as a free-roam CTF.
Consequences emerge from what the player actually announces.

This is the routing counterpart to the OT estate in `ics-access-simlab`. Where that
lab models a utility's IT/OT boundary, this one models the public routing commons:
the global table, the relationships between autonomous systems, and the trust those
relationships quietly assume.

## Status

Milestones 1 and 1.5 are deployed and validated on containerlab 0.75. The all-FRR
core converges, the passive collector sees both tables while announcing nothing,
the first scenario (a false-origin /25 hijack) wins by longest-prefix match and
diverts traffic, and the player surface works end to end: key-only entry to an ops
host, an in-band pivot to the foothold router, and a single-vantage looking glass
that confirms the hijack went global. The registry plane (RPKI/IRR), an IXP route
server, larger scale from a real MRT seed, and the gamemaster scorer are the next
milestones. See `PLAN.md`.

## Dependencies

Linux only; Docker's fixed-IP bridge networking needs a real Linux host, not Docker
Desktop.

| Dependency   | Notes                                                        |
|--------------|--------------------------------------------------------------|
| Linux        | kernel 5.x+                                                  |
| Docker       | Engine 24+ (not Docker Desktop)                              |
| containerlab | 0.50+ (`bash -c "$(curl -sL https://get.containerlab.dev)"`) |
| sudo         | containerlab needs CAP_NET_ADMIN to create host bridges      |

## Quickstart

```bash
./ctl up         # build images, create the access bridge, deploy (prompts sudo)
./ctl player     # play locally: enter the attacker ops host (makes a cohort key)
./ctl down       # tear it down
```

From the ops host, `foothold` pivots into the attacker router and `lg` queries the
looking glass. `./ctl` itself is the operator's god-mode side; a player never uses
it beyond `player`.

## Topology (milestones 1 and 1.5)

Private ASNs (64512 to 65534), documentation prefixes (TEST-NET), no internet
egress, so the lab stays contained.

| Node         | ASN   | Role                                              |
|--------------|-------|---------------------------------------------------|
| transit-a    | 65001 | transit provider, peers with transit-b            |
| transit-b    | 65002 | transit provider, peers with transit-a            |
| victim-as    | 65010 | customer of transit-a, owns 203.0.113.0/24        |
| attacker-as  | 65020 | customer of transit-b, the player's foothold      |
| gamemaster   | 65000 | passive collector, peers both transits (operator) |
| lookingglass | 65005 | single-vantage public collector (player's `lg`)   |
| ops-host     | n/a   | the attacker's workstation, the player's entry    |
| web          | n/a   | victim service behind 203.0.113.0/24              |
| eyeball      | n/a   | client generating traffic toward the victim       |

The two transits peer settlement-free; victim and attacker are each a customer of a
different transit; filtering and origin validation are deliberately loose, which is
what the attacks exploit.

## Docs

- [docs/playing.md](docs/playing.md) for playing the lab: how to enter, the BGP moves you make from
  the foothold, and how to confirm them.
- [docs/operator.md](docs/operator.md) for running the lab: the full `ctl` reference, deploying,
  observing, and issuing cohort keys.
- [scenarios/](scenarios/) for the techniques, each with a briefing and a reference solution.
- `PLAN.md` for the design record and the milestone roadmap.
