# House Rules

You hold your usual foothold on attacker-as (AS65020), Bracket Hosting, a customer of
Hyphalink (transit-b). This time you forge nothing and you announce nothing more
specific. You exploit the one thing every operator trusts: their own routing policy.

Operators prefer routes from customers over routes from peers, because a customer is
who they are paid to carry, and that preference outranks AS_PATH length entirely. So
if you, a customer of Hyphalink, announce the very same 203.0.113.0/24 that FDEI
originates, Hyphalink prefers your copy over the one it learns from its peer
FungusFiber, even though both are the same length. Policy beats the honest route.

## Getting in

Pick this operation at the bastion and you land in the foothold's vtysh, already in
position. The win is at Hyphalink (transit-b), so that is where the scorer checks.

## Win condition

You win when transit-b's best path to 203.0.113.0/24 has your AS (65020) as origin,
chosen over the equally-specific FDEI route purely on customer preference. FungusFiber
(transit-a) still prefers its own customer FDEI, so the takeover is regional, which is
what makes it quiet. attack.md has the steps.
