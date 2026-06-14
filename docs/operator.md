# Operator guide

The operator runs and observes the lab. `ctl` and `docker exec` are god-mode: they
reach every node and the whole table. A player never sees any of this; the player
surface is in `docs/playing.md`.

## ctl reference

```
./ctl up            build images, create the access bridge, deploy (sudo)
./ctl down          destroy the topology, remove the access bridge (sudo)
./ctl table         the global table as the gamemaster sees it (show ip bgp)
./ctl lg            the same, as JSON for tooling
./ctl ssh NODE      a shell on a node (e.g. ./ctl ssh attacker-as)
./ctl vtysh NODE    vtysh on a router (e.g. ./ctl vtysh attacker-as)
./ctl player        play locally: enter the ops host on a cohort key (auto-made)
./ctl playtest      operator check of the player path, using the lab key
./ctl cohort-keys   make a participant keypair to hand out
./ctl seed-fetch [N]  refresh the backbone seed from a live RouteViews dump
```

Nodes: transit-a, transit-b, victim-as, attacker-as, gamemaster, lookingglass,
seed, ops-host, web, eyeball. Containers are named `clab-inter-domain-<node>`.

## Deploy and reset

`./ctl up` builds the three images (the FRR router, the ops host and the GoBGP
seed), brings up the `idsl_access` bridge, and deploys. A bounce is
self-contained: `./ctl down` then `./ctl up` rebuilds the images (so config
changes are picked up), recreates the bridge and redeploys. Keys persist across a
bounce, so a distributed cohort key stays valid. To rotate credentials, remove
`lab-key* cohort-key* access/` before `up`.

## The backbone seed (a plausibly large table)

The `seed` node (AS65003) replays a real, filtered route dump so the global table
carries tens of thousands of routes, not just the lab's own handful. The default
`./ctl up` uses the committed sample (~10k prefixes) and needs no network. The
size is a dial:

```bash
SEED_COUNT=50000 ./ctl up          # inject more (needs a larger dump first)
./ctl seed-fetch 50000             # download + filter a 50k dump, then redeploy
```

A larger table needs a fresh fetch (the committed sample only holds ~10k). Detail,
including what is real and what is abstracted, is in `seeds/mrt/README.md` and
`PLAN.md` section 15.

## Observing

`./ctl table` and `./ctl lg` read the gamemaster, the operator's full-visibility
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

With the seed in place the table is large, so `./ctl table` is best filtered
(`grep 203.0.113`) rather than read whole. The hijack wins for the same reason it
did against the empty table: longest-prefix match is indifferent to how much else
is in the RIB.

## Issuing cohort keys

Players enter on a key, never a password. Make one and hand out the private half:

```bash
./ctl cohort-keys
```

Local participants reach the ops host directly on the access bridge:

```bash
ssh -i cohort-key player@100.64.0.10
```

On a public host the access LAN is internal and no port is published, so players
jump through a restricted account the operator provisions on the lab host:

```bash
ssh -i cohort-key -J jump@<lab-host> player@100.64.0.10
```

Provisioning that jump account is host setup, outside `ctl`.

## Containment

Private ASNs and TEST-NET prefixes, no internet egress, and nothing bound to a
public interface. The lab is deliberately vulnerable inside and never reachable
from outside, and that isolation is the control that keeps the weak in-lab
credentials safe. See `PLAN.md` sections 9 and 13.
