# Unsigned Ground

You hold the foothold on attacker-as (AS65020), Bracket Hosting, a small customer
of Hyphalink (transit-b). FMDA has signed Fungolia's own space, so FDEI's prefix
carries a ROA now and the providers can validate it. You have watched a clean
hijack of FDEI's /24 get dropped the moment origin validation came on. Signed
space bites back.

So leave it alone. The seeded global table is full of prefixes FMDA never signed,
foreign allocations out in the wider internet that nobody has put a ROA behind. To
a validating router those are not-found, and ROV drops invalid, not not-found. An
unsigned prefix is open ground, and most of the internet is unsigned.

Your task: take one. 1.7.19.0/24 belongs to a distant network (AS9583) and is
unsigned. Originate it as yourself: your path is shorter than the real one, so
traffic for it bends to you, and the providers' ROV waves it through because there
is no ROA to say otherwise. You do not need to break anything; the gap in RPKI's
coverage is the opening.

## Getting in

Playing locally, `./ctl player` drops you at the bastion. Pick this operation from
the menu and you land in the foothold router's vtysh, already in position. `lg`
queries the public looking glass for the global table. No god-mode: you reach what
you own and the looking glass, nothing else.

## Win condition

`lg` is a public route collector, the view the rest of the world has. You win when
it lists 1.7.19.0/24 with your AS (65020) as the origin, while origin validation is
on at the providers. The real holder is still out there; you are simply the shorter,
unsigned path, and validation has nothing to check you against.

The brief is enough to start; attack.md has the steps if you want them.
