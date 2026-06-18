# Pulling the Roots

This one is not all yours. The clean hijack of FDEI's /24 (Toadstool Takeover)
dies the moment origin validation comes on, because FMDA signed the prefix and the
providers can check it. You cannot out-route a ROA. So do not try; remove it.

A ROA is just a record in FMDA's RPKI. If someone with a hand on the registry,
an insider, a stolen credential, a compromised CA, withdraws FDEI's ROA, the
prefix goes from signed to not-found. Validation has nothing left to check, and
ROV drops invalid, not not-found. The defence is still on; it just has nothing to
say. Then the same hijack you watched fail sails through.

This is a two-handed move, and both hands are yours. Pick this operation at the
bastion and you land on the registry-attacker workstation, where a token for FMDA's
CA is waiting (`cat /loot/notes.txt`). The trust half, withdrawing the ROA, you do
there. The routing half, the announcement, you do from the foothold once the cover
is gone. The point is that the attack on the routing system can begin in the trust
system, hours or days earlier, and the two only make sense read together.

## The shape

1. ROV is on. The /25 hijack is RPKI-invalid and dropped. Nothing works yet.
2. On the workstation, withdraw FDEI's ROA with the token you hold (`poison`, the
   arming). 203.0.113.0/24 becomes not-found.
3. Pivot to the foothold (`foothold`) and announce 203.0.113.0/25. It is now
   not-found, ROV permits it, and it wins by longest-prefix. The hijack you could not
   land before lands now.

You confirm it the usual way: `lg` shows your /25 with origin 65020, while ROV is
still on. The difference from Toadstool Takeover is not on the wire; it is in the
registry.
