# Toadstool Takeover

You hold a foothold on attacker-as (AS65020), Bracket Hosting, a small customer of
Hyphalink (transit-b) out on the frontier. You legitimately announce
198.51.100.0/24, your hosting space, and nobody looks at you twice.

victim-as (AS65010) is FDEI, the energy and infrastructure ministry and a
FungusFiber customer. It runs a public service behind 203.0.113.0/24 and
originates it. Neither transit filters what its customers announce.

Your task: make traffic for that service come to you instead. You do not need to
break into anything else. The routing table is the vulnerability.

## Getting in

Playing locally, `./ctl player` drops you at the bastion. Pick this operation from
the menu and you land in the foothold router's vtysh, already in position. `lg`
queries the public looking glass for the global table. No god-mode: you reach what
you own and the looking glass, nothing else.

## Win condition

`lg` is a public route collector, the view the rest of the world has. You win
when it lists 203.0.113.0/25 with your AS (65020) as the origin. The legitimate
/24 stays put; your more-specific sits next to it and takes the traffic by
longest-prefix match.

For the data-plane bonus, point the hijacked range at a host you control instead of
discarding it (`ip route 203.0.113.0/25 100.64.0.10` on the foothold), so the
victim's traffic bends onto that box rather than into a black hole. The brief is
enough to start; attack.md has the steps if you want them.