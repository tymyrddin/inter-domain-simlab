# Mudslide

You are not in your own network this time. Reconnaissance turned up Mudflat Networks
(AS65030), a small regional ISP that buys transit from both FungusFiber (transit-a)
and Hyphalink (transit-b). It is the kind of shop that runs copy-pasted configs and
never cleans up: easy to get onto, and once you are on its border router you can make
it misbehave without forging anything.

Mudflat is well-behaved by default: it announces only its own 198.18.0.0/24 to its
two providers. But it also learns the rest of the table from them, including FDEI's
203.0.113.0/24. If you make Mudflat re-announce FDEI's route to Hyphalink, Hyphalink
sees two ways to reach FDEI: directly from its peer FungusFiber, and from its customer
Mudflat. Providers prefer customers. So Hyphalink routes FDEI's traffic the long way,
through you, and calls it normal.

## Getting in

Pick this operation at the bastion and you land in Mudflat's vtysh, already on the
box. `lg` queries the public looking glass; the win, though, is at Hyphalink
(transit-b), so that is where the scorer checks.

## Win condition

You win when transit-b's best path to 203.0.113.0/24 runs through AS65030 (you), even
though the origin is still FDEI (65010). No prefix was forged and no origin changed; a
single export slip turned a leak into a redirect. attack.md has the steps.
