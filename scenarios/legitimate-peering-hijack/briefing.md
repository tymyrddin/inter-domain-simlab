# Good Neighbour

You hold an announcing position on attacker-as (AS65020), Bracket Hosting, a small
customer of Hyphalink (transit-b). Nothing here is compromised: you have a
legitimate peering, the kind any small network has, and you announce what you like.
Filters are permissive, the way they often are.

victim-as (AS65010) is FDEI. Its allocation is 203.0.112.0/22, and it runs a public
service inside it behind 203.0.113.0/24. The covering /22 and the web's /24 both
originate from FDEI.

Your task: take one /24 out of FDEI's block without touching the rest. You announce
a more-specific the victim does not, and longest-prefix match hands you that slice
while every other part of the /22 still routes to FDEI. It looks like ordinary
traffic engineering, the sort IX members do every day.

## Getting in

Pick this operation at the bastion and you land in the foothold router's vtysh,
already in position. `lg` queries the public looking glass for the global table.

## Win condition

You win when the looking glass lists 203.0.114.0/24 with your AS (65020) as the
origin, while 203.0.112.0/22 and 203.0.113.0/24 still show FDEI (65010). Your
more-specific takes its /24; the rest of the block is untouched. That partial, quiet
result is the whole point of the technique. attack.md has the steps.
