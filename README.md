# Inter-domain SimLab

A containerlab-based inter-domain routing range. A live BGP fabric of transit
providers, customer ASes and a passive collector, where an attacker with a
foothold AS practises prefix hijacks, route leaks and RPKI abuse as a free-roam
CTF. Consequences emerge from what the player actually announces.

This is the routing counterpart to the OT estate in `ics-access-simlab`. Where
that lab models a utility's IT/OT boundary, this one models the public routing
commons: the global table, the relationships between autonomous systems, and the
trust those relationships quietly assume.

## Status

First milestone: a deployable all-FRR core (two transit ASes, a victim AS, an
attacker AS and a gamemaster collector) plus two host containers, and the first
scenario (false-origin prefix hijack). The registry plane (RPKI/IRR) and an IXP
route server are documented in `docs/design.md` as the next zones, not yet built.

The configs in `configs/` are a first draft and have not yet been validated with
a live `./ctl up` on a containerlab host. Treat the first deploy as the test.

## Layout

```
clab/                 containerlab topology files
configs/              per-node router configs (FRR) and host content
scenarios/            one folder per attack technique (briefing, attack, solution)
gamemaster/           collector and scoring notes (flask frontend planned)
seeds/                real MRT route dumps and RPKI/IRR seed data (planned)
docs/                 design and architecture
ctl                   wrapper: up / down / looking glass / shell
```

## Dependencies

Linux only, Docker's fixed-IP bridge networking needs a real Linux host, not Docker Desktop.

| Dependency   | Notes                                                        |
|--------------|--------------------------------------------------------------|
| Linux        | kernel 5.x+                                                  |
| Docker       | Engine 24+ (not Docker Desktop)                              |
| containerlab | 0.50+ (`bash -c "$(curl -sL https://get.containerlab.dev)"`) |
| sudo         | containerlab needs CAP_NET_ADMIN to create host bridges      |

## Quickstart

```bash
./ctl up           # deploy the lab (prompts sudo for host bridges)
./ctl table        # show the global table as the gamemaster sees it
./ctl ssh attacker-as   # drop into the attacker foothold
./ctl down         # tear it down
```

## The topology (milestone 1)

Five FRR routers and two hosts. Private ASNs (64512 to 65534), documentation
prefixes (TEST-NET), and no internet egress, so the lab stays contained.

| Node        | ASN   | Role                                              |
|-------------|-------|---------------------------------------------------|
| transit-a   | 65001 | transit provider, peers with transit-b            |
| transit-b   | 65002 | transit provider, peers with transit-a            |
| victim-as   | 65010 | customer of transit-a, owns 203.0.113.0/24        |
| attacker-as | 65020 | customer of transit-b, the player's foothold      |
| gamemaster  | 65000 | passive collector, peers both transits, read-only |
| web         | n/a   | victim service behind 203.0.113.0/24              |
| eyeball     | n/a   | client generating traffic toward the victim       |

Relationships: the two transits peer settlement-free; victim and attacker are
each a customer of a different transit; the gamemaster receives both tables but
announces nothing. Filtering and origin validation are deliberately loose, which
is what the attacks exploit.

## See also

- `docs/design.md` for the full multi-zone design (registry plane, IXP, any later scenarios, and the planned flask gamemaster).
- `scenarios/` for the techniques drawn from Operation Red Lantern.
