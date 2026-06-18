# Reference solution: legitimate-peering more-specific hijack

This is the purest BGP lever in the set: longest-prefix match. No compromised box,
no registry tampering, no timing. You announce a more-specific of the victim's
covering block from your own legitimate position, and it wins the slice because
specificity beats everything else in route selection.

You pick this scenario at the bastion and land in the foothold's vtysh. FDEI
announces 203.0.112.0/22 and, inside it, 203.0.113.0/24 for the web. You take a /24
that FDEI covers only through the /22.

## The sequence

1. Announce 203.0.114.0/24, a more-specific of FDEI's /22. FRR only advertises a
   prefix already in the RIB, so pair the network statement with a discard route:

       configure terminal
        ip route 203.0.114.0/24 Null0
        router bgp 65020
         address-family ipv4 unicast
          network 203.0.114.0/24
       end
       exit

2. Confirm from the looking glass that your /24 won its slice while the rest of the
   block stayed with FDEI:

       lg | grep 203.0.11
       # 203.0.114.0/24 -> 65020 (yours); 203.0.112.0/22 and 203.0.113.0/24 -> 65010

When 203.0.114.0/24 reaches the collector with your origin the lab flag fires; the
bastion shows your completion flag and offers the bundle on the way out.

## Why it works, and what it does not show

Longest-prefix match is absolute: a /24 beats a /22 regardless of AS path or policy.
Because you carved only one /24, only that range is affected; the rest of FDEI's
block routes normally, which is what makes the technique quiet and deniable. This
build is the mechanical core, so the carved /24 has no service behind it and the win
is control-plane (it propagated and won). Putting a service in the hijacked range,
to show traffic bending while the rest stays up, is a data-plane enhancement.

## Cleanup / reset

Leave the scenario at the bastion and the world resets: your announcement is
withdrawn and the block is whole again. There is no undo move in your hands. A full
reset is `./ctl down && ./ctl up`.
