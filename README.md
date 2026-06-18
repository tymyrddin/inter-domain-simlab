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

Milestones 1 through 4 are deployed and validated on containerlab 0.75, and the
attacker surface is fully player-driven. The all-FRR core converges and a passive
collector sees both tables while announcing nothing. A real MRT seed gives a
backbone-sized table; the registry plane runs RPKI origin validation (live ROV and
ROA state, validated over native RRDP) and an IRR database with bgpq4 prefix filters;
and the observer's scorer normalises a BMP feed into an event timeline.

Players enter through one bastion, pick an operation from a menu, and are dropped
onto the box that operation starts from, with the world positioned for it by a
session manager (`./ctl session`). Seven scenarios play end to end from that
position. On the routing-mechanics side: false-origin and legitimate-peering
more-specific hijacks, and a route leak from a separate multi-homed ISP. On the
routing-governance side: an incomplete-RPKI not-found hijack, a policy-trust-abuse
preferred-path hijack, and two registry-tamper chains (ROA poisoning and IRR
legitimacy subversion) the player performs from a registry workstation with planted
credentials, never an operator knob. Each run produces a raw telemetry bundle, noise
and all, for the detection lab (heimdallr).

Remaining build: an IXP route server and extra edge ASes and the scenarios that
still need them (path manipulation, deniable disruption), the data-plane half of the
interception and degradation effects, and the flask frontend (M5), which stays gated
on audience. See `PLAN.md`.

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
./ctl up         # build images, create the bridges, deploy (prompts sudo)
./ctl session    # position the world per the scenario the player picks (run alongside)
./ctl player     # play locally: enter the bastion (makes a cohort key)
./ctl down       # tear it down
```

You come in at the bastion, pick an operation from a menu, and are dropped onto the
box it starts from: the foothold router in vtysh for a straight hijack, or the
registry-attacker workstation (`launder`, `poison`) for a registry-tamper move, from
where you pivot to the foothold with `foothold` and confirm with `lg`. `./ctl` is the
operator's god-mode side; a player never uses it.

## Topology (milestones 1 and 1.5)

Private ASNs (64512 to 65534), documentation prefixes (TEST-NET), no internet
egress, so the lab stays contained.

| Node           | ASN   | Role                                               |
|----------------|-------|----------------------------------------------------|
| transit-a      | 65001 | transit provider, peers with transit-b             |
| transit-b      | 65002 | transit provider, peers with transit-a             |
| victim-as      | 65010 | customer of transit-a, owns 203.0.112.0/22 + /24   |
| attacker-as    | 65020 | customer of transit-b, the player's foothold       |
| customer-leaky | 65030 | multi-homed leaky ISP (the route-leak position)    |
| observer       | 65000 | passive collector, peers both transits (operator)  |
| lookingglass   | 65005 | single-vantage public collector (player's `lg`)    |
| bastion        | n/a   | the one door: a menu, then drops you on the box    |
| ops-host       | n/a   | the registry-attacker workstation (launder/poison) |
| web            | n/a   | victim service behind 203.0.113.0/24               |
| eyeball        | n/a   | client generating traffic toward the victim        |

The two transits peer settlement-free; victim and attacker are each a customer of a
different transit; filtering and origin validation are deliberately loose, which is
what the attacks exploit.

## Docs

- [docs/playing.md](docs/playing.md) for playing the lab: how to enter, the BGP moves you make from
  the foothold, and how to confirm them.
- [docs/operator.md](docs/operator.md) for running the lab: the full `ctl` reference, deploying,
  observing, and issuing cohort keys.
- [scenarios](scenarios) for the techniques, each with a briefing and a reference solution.
