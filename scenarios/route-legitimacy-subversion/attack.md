# Reference solution: route-legitimacy subversion

IRR prefix filtering is a real defence, and it works against the plain hijack: the
attacker's 203.0.113.0/25 has no route object in FMDA's IRR, so the prefix-list a
transit builds with bgpq4 drops it. This technique does not beat the filter on the
wire. It gives the filter a reason to let the hijack through, by registering a
clean-looking route object first.

You pick this scenario at the bastion and land on the registry-attacker
workstation. The world is already positioned: IRR filtering is on at the transit,
and a maintainer password for FMDA's IRR is on the box (`/loot`,
`cat /loot/notes.txt`). The password stands in for the abstracted compromise: in
the world it is a maintainer credential, a reused password, an unverified object
slipping through a proxy registry. Long-term positioning, registering the object
weeks ahead so it looks aged and unremarkable, is the part the lab compresses into
a session. Both moves are yours, from the boxes you hold.

## The sequence

1. See the defence hold. Pivot to the foothold and announce the /25; with IRR
   filtering on and no route object for it, the transit's prefix-list drops it:

       foothold
       #   configure terminal
       #   ip route 203.0.113.0/25 Null0
       #   router bgp 65020
       #    address-family ipv4 unicast
       #     network 203.0.113.0/25
       #   end
       #   exit
       lg | grep 203.0.113        # only the legitimate /24; the /25 is filtered out

2. Arm. Back on the workstation, launder a clean-looking route object for the
   hijack prefix into FMDA's IRR with the maintainer password you found:

       launder

   FMDA's IRR now carries route 203.0.113.0/25, origin AS65020. The transit rebuilds
   its bgpq4 prefix-list on its usual cycle and the /25 becomes permitted.

3. The hijack lands. Once the filter is rebuilt, longest-prefix gives the /25 the
   win. Confirm from the looking glass:

       lg | grep 203.0.113        # now the /25 wins, with origin 65020

When the /25 reaches the collector the lab flag fires; the bastion shows your
completion flag and offers the bundle on your way out.

## The telemetry bundle (for heimdallr)

A correlated record: a registry write that only makes sense once the routing hijack
it authorised shows up. The session manager assembles it when the flag fires;
download it from the bastion completion menu:

    scp -O -i <cohort-key> player@<lab-host>:/bundles/route-legitimacy-subversion/bundle.tar.gz .

The IRR-change record (the new route object and its journal entry, in the IRR
export) is the arming signal; the BMP events show the /25 winning. Read together
they are the legitimacy-subversion pattern: a registry object that looks legitimate
in isolation, explained only by the hijack it enabled. The bundle is raw
observations only.

## Cleanup / reset

Leave the scenario at the bastion and the world resets to baseline (the laundered
object removed, your announcement withdrawn, the filter returned to the permissive
default). There is no un-launder move: an attacker who removed their own object
would re-block their own hijack. A full reset is `./ctl down && ./ctl up`.
