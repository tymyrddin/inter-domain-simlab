# Reference solution: ROA poisoning, the multi-stage sequence

The defence (RPKI ROV) is real and it works against the plain hijack. So this
sequence does not beat it on the wire; it removes the ROA the defence relies on,
then hijacks the now-uncovered prefix. Two stages, two actors, one timeline.

The arming (withdrawing the ROA) is a registry action, modelled here by the
operator knob `./ctl roa poison`. In the world it is whoever can reach FMDA's CA:
an insider, a stolen token, a compromised publication point. The routing action
(the announcement) is the player on the foothold.

## The sequence

1. Confirm the defence is on and the plain hijack fails:

       ./ctl rov on
       # on the foothold: announce 203.0.113.0/25 (as in Toadstool Takeover)
       ./ctl table | grep 203.0.113      # only the legitimate /24; the /25 is dropped (invalid)

2. Arm: withdraw FDEI's ROA. 203.0.113.0/24 goes from signed to not-found:

       ./ctl roa poison

3. The hijack lands. With the ROA gone, the /25 is not-found, ROV permits it, and
   longest-prefix gives it the win:

       ./ctl table | grep 203.0.113      # now the /25 wins, with origin 65020
       ./ctl score roa-poisoning-hijack  # the scorer flags it, rpki=notfound

## The telemetry bundle (for heimdallr)

This is the point of the scenario: a correlated, two-file record of a multi-stage
campaign that no single source explains.

       ./ctl rpki-export artefacts/roa-poisoning-hijack   # the ROA withdrawal (the arming)
       ./ctl score roa-poisoning-hijack                   # the timeline (the hijack, rpki=notfound)

The ROA-change record (Krill's log, the validator's state transition) is the
arming signal; the routing timeline shows the /25 winning as not-found. Read
together they are the ROA-poisoning, multi-stage pattern: a trust-system change
that only makes sense once the routing hijack it enabled shows up minutes later.

## Cleanup / reset

       ./ctl roa restore                 # put FDEI's ROA back; the /25 is invalid again, dropped
       # on the foothold: withdraw 203.0.113.0/25
       ./ctl rov off                     # back to the permissive baseline

Or `./ctl down && ./ctl up`.
