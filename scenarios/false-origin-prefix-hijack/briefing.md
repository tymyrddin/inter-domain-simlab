# Toadstool Takeover

You hold a foothold on attacker-as (AS65020), a small customer of transit-b out
on the frontier. You legitimately announce 198.51.100.0/24, your hosting space,
and nobody looks at you twice.

FungusFiber, the regional registry, runs a customer service behind
203.0.113.0/24, originated by victim-as (AS65010), a customer of the other
provider. Neither transit filters what its customers announce.

Your task: make traffic for that service come to you instead. You do not need to
break into anything else. The routing table is the vulnerability.

## Foothold

    ./ctl vtysh attacker-as          # interactive, drops you in vtysh
    # or: ./ctl ssh attacker-as      # a shell, then run `vtysh`

## Win condition

The gamemaster collector (AS65000) sees both providers' tables. You win when it
shows 203.0.113.0/25 in the table with your AS (65020) as the origin:

    ./ctl lg                         # show ip bgp json on the collector

For the data-plane bonus, get eyeball's request for http://203.0.113.10/ served
from your side rather than the real FungusFiber page.

If you already know inter-domain attacks, stop reading and go. Otherwise, see
attack.md for the steps.