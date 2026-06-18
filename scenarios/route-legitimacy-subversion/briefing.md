# Briefing: Good Standing

FungusFiber's transits have started filtering customers against FMDA's IRR. Your
usual trick, announcing a more-specific of FDEI's 203.0.113.0/24, dies at the
border now: there is no route object that says Bracket Hosting may originate it, so
the prefix-list built from the registry drops it before it ever propagates.

The filter is only as honest as the registry behind it. FMDA's IRR will accept a
route object from anyone who can satisfy the maintainer, and the database does not
ask whether the object is true, only whether it is authorised. You have a way to
write to it.

Your job: make the hijack look legitimate before you make it. Register a route
object for 203.0.113.0/25 under your own AS, let the transit rebuild its filter
from the registry, and the door the filter was holding shut opens on its own. Then
announce, the way you always would.

Pick this operation at the bastion and you land on the registry-attacker
workstation, where the maintainer password is waiting (`cat /loot/notes.txt`). The
registry write is the quiet part, done there with `launder`; the announcement is the
loud part, done from the foothold (`foothold`). Done in the right order, the loud
part looks like routine.

The reference solution is in attack.md; an expert can skip it.