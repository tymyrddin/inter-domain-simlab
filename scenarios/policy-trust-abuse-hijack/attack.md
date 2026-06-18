# Reference solution: policy-trust abuse, preferred-path hijack

No more-specific, no forged origin. This chain wins on route-selection policy alone,
which is why monitoring that looks for "bad" routes sees nothing: every attribute is
legitimate. Local preference is checked before AS_PATH length, and operators set
customer routes above peer routes. You are a customer; the honest route arrives via a
peer. So you win.

You pick this scenario at the bastion and land in the foothold's vtysh.

## The sequence

1. Announce 203.0.113.0/24, the same prefix and length FDEI originates. FRR only
   advertises a prefix already in the RIB, so pair the network statement with a
   discard route:

       configure terminal
        ip route 203.0.113.0/24 Null0
        router bgp 65020
         address-family ipv4 unicast
          network 203.0.113.0/24
       end

2. At transit-b two paths now exist for 203.0.113.0/24: the victim's via the peer
   transit-a, and yours from its own customer. Customer-over-peer local-pref makes
   transit-b prefer you. Confirm at transit-b (the operator can show this with
   `./ctl ssh transit-b`); the lab flag fires when transit-b's best-path origin is
   65020.

## Why it works, and what it does not show

Everything is compliant: the prefix is the right length, the origin is your real AS,
the path is short and honest. The only "attack" is choosing to announce, through a
customer relationship, a route you are not entitled to, and letting policy do the rest.
Because the win rides on transit-b's preference it is regional: transit-a still prefers
its own customer FDEI, so only traffic crossing transit-b bends. A second eyeball on
transit-b would show the data-plane half; this build is the control-plane core.

## Cleanup / reset

Leave the scenario at the bastion and your announcement is withdrawn. There is no undo
move in your hands. A full reset is `./ctl down && ./ctl up`.
