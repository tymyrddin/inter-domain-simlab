# Operator guide

The operator runs and observes the lab. `ctl` and `docker exec` are god-mode: they
reach every node and the whole table. A player never sees any of this; the player
surface is in `docs/playing.md`.

## ctl reference

```
./ctl up            build images, create the bridges, deploy (sudo)
./ctl down          destroy the topology, remove the bridges (sudo)
./ctl table         the global table as the observer sees it (show ip bgp)
./ctl lg            the same, as JSON for tooling
./ctl ssh NODE      a shell on a node (e.g. ./ctl ssh attacker-as)
./ctl vtysh NODE    vtysh on a router (e.g. ./ctl vtysh attacker-as)
./ctl session       the world-positioner, foreground, for debugging only (./ctl up
                    already runs it in the background as part of the lab)
./ctl player        play locally: enter the bastion on a cohort key (auto-made)
./ctl playtest      operator check of the player path, using the lab key
./ctl cohort-keys   make a participant keypair to hand out
./ctl seed-fetch [N]  refresh the backbone seed from a live RouteViews dump
./ctl rpki          the trust fabric: Routinator VRPs + FMDA ROAs
./ctl rov on|off    origin validation at the transits (defence posture)
./ctl irr on|off|rebuild   IRR prefix filtering at the transits (defence posture)
./ctl localpref on|off     customer-over-peer local-pref at the transits (route-leak,
                           policy-trust-abuse; never on at once with rov)
./ctl rpki-export [dir]    dump VRPs + ROAs + Routinator log for heimdallr
./ctl irr-export  [dir]    dump IRR route objects + journal for heimdallr
./ctl score [scenario] [poll|bmp]  score the flag, write the timeline; poll
                                   diffs the table, bmp reads the bmp-collector feed
```

Nodes: transit-a, transit-b, victim-as, attacker-as, customer-leaky, observer,
lookingglass, seed, registry-ca, registry-rtr, registry-irr, bmp-collector, bastion, ops-host, web,
eyeball. Containers are named `clab-inter-domain-<node>`.

## Deploy and reset

`./ctl up` builds the images (the FRR router, the ops host, the GoBGP seed, and
the Krill CA and Routinator validator), brings up the `idsl_access`, `idsl_services`
and `idsl_regpub` bridges, deploys, and onboards the RPKI trust anchor. A bounce is
self-contained: `./ctl down` then `./ctl up` rebuilds the images (so config
changes are picked up), recreates the bridges and redeploys. Keys persist across a
bounce, so a distributed cohort key stays valid. To rotate credentials, remove
`lab-key* cohort-key* access/` before `up`.

## The backbone seed

The `seed` node replays a real filtered route dump so the table is backbone-sized.
`SEED_COUNT` is the size dial; the committed ~10k sample is the offline default, and a
larger table needs a fresh fetch:

```bash
./ctl seed-fetch 50000 && SEED_COUNT=50000 ./ctl up
```

See `seeds/mrt/README.md`.

## Observing

`./ctl table` and `./ctl lg` read the observer, the operator's full-visibility
collector. `./ctl ssh` and `./ctl vtysh NODE` reach any node directly. This is the
omniscient view; the player's `lg` is a deliberately partial one.

## Observing an attack as it runs

To drive the false-origin hijack yourself, the steps are in
`scenarios/false-origin-prefix-hijack/attack.md`, run through `./ctl vtysh
attacker-as`. The operator's part is the god-mode view of what the attack does:

```bash
./ctl table | grep 203.0.113                                    # the /24 and the bogus /25, amid ~10k seed routes
docker exec clab-inter-domain-transit-a vtysh -c 'show ip bgp 203.0.113.10'  # the upstream prefers the /25
docker exec -it clab-inter-domain-eyeball traceroute -n 203.0.113.10   # traffic bends to the attacker
```

With the seed in place the table is large, so filter `./ctl table` (`grep 203.0.113`)
rather than reading it whole.

## The trust fabric (RPKI)

FMDA runs the lab's own RPKI, self-contained, no internet: `registry-ca` (Krill)
is the CA and testbed trust anchor, `registry-rtr` (Routinator) validates and
serves the result to the transits over RTR. `./ctl up` onboards it and signs the
baseline ROAs (FDEI's /24 from AS65010, and the two other lab prefixes).
`./ctl rpki` shows the VRPs and the ROAs.

Origin validation is off by default, so the core stays permissive. As a defence
posture an operator can turn it on:

```bash
./ctl rov on                 # the transits drop RPKI-invalid routes
# the attacker's 203.0.113.0/25 is invalid (covered by FDEI's /24 ROA): dropped
./ctl rov off                # back to the permissive baseline
```

The attacker's counter, withdrawing FDEI's ROA so the /25 goes not-found, is the
`roa-poisoning-hijack` scenario, performed by the player from a compromised CA
position (a planted token, a real call to Krill's API), not an operator knob. When
a player picks it at the bastion, the lab sets ROV on, plants the token, and
restores the ROA on reset.

A ROA change takes a few seconds to propagate (Routinator re-validates, the transits
re-pull), then re-check with `./ctl table | grep 203.0.113`. `./ctl rpki-export` dumps
the VRP set, the ROA history and Routinator's log for the detection lab (heimdallr).

One caution that applies to every node: never `docker restart` a node or restart
its in-container FRR (`frrinit.sh restart`). Containerlab creates the data-plane
interfaces at deploy and a restart drops them, leaving the node with only its
management interface. To apply a changed config or daemon option, do a clean
`./ctl down && ./ctl up`.

## Issuing cohort keys

Players enter on a key, never a password. Make one and hand out the private half:

```bash
./ctl cohort-keys
```

Local participants reach the bastion directly on the access bridge:

```bash
ssh -i cohort-key player@100.64.0.5
```

On a public host the access LAN is internal and no port is published, so players
jump through a restricted account the operator provisions on the lab host:

```bash
ssh -i cohort-key -J jump@<lab-host> player@100.64.0.5
```

Provisioning that jump account is host setup, outside `ctl`.

## Containment

Private ASNs and TEST-NET prefixes, no internet egress, and nothing bound to a public
interface. The lab is vulnerable inside and unreachable from outside.
