# Reference solution: route leak into an effective hijack

This one forges nothing. Mudflat Networks (AS65030) is a customer of both transits.
The valley-free rule says it should announce only its own space to its providers and
never pass one provider's routes to the other. Break that, and the receiving provider
prefers the leaked route because it arrives from a customer.

You pick this scenario at the bastion and land in Mudflat's vtysh. By default its
export to both upstreams is filtered to 198.18.0.0/24 (the PL-LEAKY-OUT prefix-list).

## The sequence

1. See Mudflat behaving: transit-b reaches FDEI's /24 directly via its peer transit-a
   (the operator can show this with `./ctl ssh transit-b`).

2. Add a stray prefix to Mudflat's export, the kind of "temporary exception" that
   never gets removed, so it re-announces FDEI's /24 (learned from transit-a) to
   transit-b:

       configure terminal
        ip prefix-list PL-LEAKY-OUT seq 10 permit 203.0.113.0/24
       end
       clear bgp ipv4 unicast 10.0.0.57 soft out

3. transit-b now has two paths to 203.0.113.0/24: via its peer transit-a, and via its
   customer Mudflat (you). Customer-over-peer local-pref makes it prefer the longer
   customer path, so FDEI's traffic through transit-b is dragged through you.

The lab flag fires when transit-b's best path to the /24 runs through AS65030.

## Why it works, and what it does not show

Nothing was spoofed: Mudflat really did learn the route and really did announce it.
The damage is policy plus a missing filter. Because the win rides on transit-b's
customer-over-peer preference it is regional: transit-a still reaches FDEI directly,
so only traffic crossing transit-b bends. That regional, deniable shape is the point.
This build shows the control-plane redirect; carrying and inspecting the diverted
traffic on Mudflat is a data-plane enhancement.

## Cleanup / reset

Leave the scenario at the bastion and the export filter is restored (the stray prefix
removed), so Mudflat is valley-free again. There is no undo move in your hands. A full
reset is `./ctl down && ./ctl up`.
