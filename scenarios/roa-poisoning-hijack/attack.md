# Reference solution: ROA poisoning, the multi-stage sequence

The defence (RPKI ROV) is real and it works against the plain hijack. So this
sequence does not beat it on the wire; it removes the ROA the defence relies on,
then hijacks the now-uncovered prefix. Two stages, one timeline.

You pick this scenario at the bastion and land on the registry-attacker
workstation. The world is already positioned for you: ROV is on at the transits,
and a token for FMDA's RPKI CA is sitting on the box (`/loot`, `cat /loot/notes.txt`).
The token stands in for the abstracted compromise: in the world it is whoever can
reach FMDA's CA, an insider, a stolen token, a compromised publication point. Both
moves below are yours, performed from the boxes you hold.

## The sequence

1. See the defence hold. Pivot to the foothold and announce the /25; with ROV on
   and FDEI's ROA in place it is RPKI-invalid and the transit drops it:

       foothold
       #   configure terminal
       #   ip route 203.0.113.0/25 Null0
       #   router bgp 65020
       #    address-family ipv4 unicast
       #     network 203.0.113.0/25
       #   end
       #   exit
       lg | grep 203.0.113        # only the legitimate /24; the /25 never arrives

2. Arm. Back on the workstation, withdraw FDEI's ROA from Krill with the token you
   found. 203.0.113.0/24 goes from signed to not-found:

       poison

3. The hijack lands. Once the validator drops the VRP, the /25 is not-found, ROV
   permits it, and longest-prefix gives it the win. Confirm from the looking glass:

       lg | grep 203.0.113        # now the /25 wins, origin 65020

When the /25 reaches the collector the lab flag fires; the bastion shows your
completion flag and offers the bundle on your way out.

## The telemetry bundle (for heimdallr)

This is the point of the scenario: a correlated, two-file record of a multi-stage
campaign that no single source explains. The session manager assembles it when the
flag fires; download it from the bastion completion menu:

    scp -O -i <cohort-key> player@<lab-host>:/bundles/roa-poisoning-hijack/bundle.tar.gz .

The ROA-change record (Krill's log and the validator's state transition, in the
RPKI export) is the arming signal; the BMP events show the /25 winning as
not-found. Read together they are the ROA-poisoning, multi-stage pattern: a
trust-system change that only makes sense once the routing hijack it enabled shows
up minutes later. The bundle is raw observations only, no scorer timeline.

## Cleanup / reset

Leave the scenario at the bastion and the world resets to baseline (FDEI's ROA
restored, your announcement withdrawn, ROV returned to the permissive default).
There is no un-poison move: an attacker who restored the ROA would re-block their
own hijack. A full reset is `./ctl down && ./ctl up`.
