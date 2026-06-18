# Playing the lab

You are the attacker. You come in through one door, the bastion, pick an operation,
and find yourself already positioned on the box that operation starts from. No
god-mode: you reach what you own and nothing else. Reconnaissance happens before
you arrive (the op-red-lantern runbooks and the recon notes); this page is the how,
the moves you make from the position you are handed and how you confirm them.

## Getting in

Playing locally, one command makes a cohort key and drops you at the bastion:

```bash
./ctl player
```

If someone runs the lab for you, they hand you a cohort key. Connect to the bastion
if you share its network, or jump through the lab host on a public deployment:

```bash
ssh -i cohort-key player@100.64.0.5                       # local
ssh -i cohort-key -J jump@<lab-host> player@100.64.0.5    # production
```

The world is set up for whatever you pick automatically, as part of the running
lab; there is nothing extra for anyone to start.

## The menu

You meet a welcome and a list of operations. Pick one and you are dropped onto its
starting box, with the world already set up for it (the defence in place, any
credential you need waiting in `/loot`). There is no shell on the bastion and no
tooling: it is only the door.

## The moves

Where you land depends on the operation.

A straight hijack lands you in the foothold router's vtysh. The core move is
announcing a prefix you do not own. FRR only advertises a `network` that is already
in the RIB, so pair it with a discard route:

```
configure terminal
 ip route 203.0.113.0/25 Null0
 router bgp 65020
  address-family ipv4 unicast
   network 203.0.113.0/25
 end
```

A more-specific (a /25 inside the victim's /24) wins by longest-prefix match,
whatever the AS path or policy. That is the whole lever.

A registry-tamper operation lands you on the workstation instead, because the move
starts off the routers. Read what you were left:

```bash
cat /loot/notes.txt
```

then arm with the credential you found and pivot to the router to announce:

```bash
launder      # legitimacy-subversion: register a clean route object in FMDA's IRR
poison       # roa-poisoning: withdraw FDEI's ROA from FMDA's CA
foothold     # SSH to the router and announce, as above
```

A route leak lands you on a different router again: the border router of a sloppy
multi-homed ISP you have compromised. Nothing is forged; you widen its export so it
re-announces a route learned from one provider to the other, and the receiving
provider prefers your customer path. Policy abuse, by contrast, lands you back on
your own foothold for a single honest-looking announcement that wins on the
upstream's customer-over-peer preference, not on specificity. The win for both is
regional, so the scorer judges them at the affected transit rather than the
omniscient collector.

Each scenario's `attack.md` spells out the exact sequence it expects. `lg` queries
the looking glass from any box that has it.

## Confirming

```bash
lg | grep 203.0.113   # your prefix next to the victim's, in a table of real routes
```

The looking glass is a single-transit, read-only vantage: the partial view the
outside world has, not the operator's full table. The backbone carries a seeded table
of real routes, so filter for your prefix rather than reading it whole.

When your announcement reaches the collector the lab flag fires on its own. Leave
the box (exit vtysh, or log out of the workstation) and the bastion shows your
completion flag and a one-line `scp` to download the run's telemetry bundle. That
bundle is raw observations, the same record a monitor would have collected, for the
detection lab.

## Cleanup, and the next operation

Leave the scenario at the bastion and the world resets to baseline: your
announcement withdrawn, any laundered object or poisoned ROA undone, the defence
returned to its default. Pick another operation and you are repositioned. There is
no undo move in your own hands: an attacker does not un-launder an object or
un-poison a ROA, that would re-block their own hijack. Reset is the operator's, or
a full `./ctl down && ./ctl up`.

## A caveat

The attack mechanics are real, but the lab hands you the announcing position instead
of making you earn it, and it compresses scale and time. Winning here is not the same
as winning unnoticed against a hardened, monitored network.
