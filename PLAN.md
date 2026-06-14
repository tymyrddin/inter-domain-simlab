# Inter-domain SimLab: build plan and design record

This file is the handoff document. It captures what has been decided, the target
design, the first milestone, and the design questions still open. A future
session working inside this repo can read it without needing the original
conversation. Written 2026-06-13.

## 1. What this is and why it exists

A containerlab-based, attack-only, free-roam CTF that simulates inter-domain (BGP) routing and the attacks against it. A
player gets a foothold on an attacker-controlled autonomous system and chooses their own path: prefix
hijacks, route leaks, RPKI abuse, traffic interception. Consequences emerge from
what they actually announce, the same philosophy as `ics-access-simlab` ("vulnerabilities are properties of the
simulated systems, not configuration options").

It replaces `red-lantern-sim`. That repo was a fine exploration but it was a
deterministic telemetry generator with mock feeds (the RIPE RIS and RouteViews
"feeds" were fakes that emit synthetic events). This repo does the real thing: a
live BGP fabric where the table actually changes and traffic actually bends. It
does not build on red-lantern-sim. That code, its schema, its feeds and its
detection rules are treated as not realistic and are not inherited.
red-lantern-sim is deprecated, not a dependency.

## 2. Place in the wider ecosystem

Three domain simulators, split by substrate as well as subject:

- OT estate: `ics-access-simlab` (live containerlab). Unseen University Power &
  Light. The pattern this repo copies.
- Inter-domain routing estate: THIS repo (live containerlab). Replaces
  `red-lantern-sim`.
- Enterprise interior estate: a future `mycosec-simlab` (live containerlab), for
  the LAN/host/service attacks (IPv6 RA takeover, DHCP poisoning, the Neural
  Ghost compute-tenant intrusion, the Broken Trust CI/CD bridge). Not started.

The axis: between networks (this repo) versus within a network (mycosec) versus
the OT estate. Any future scenario sorts itself by which vantage the defender
watches from: the global routing table, or local host/wire telemetry.

`red-lantern-detection` is not a drop-in consumer. Its Wazuh decoders/rules,
Splunk SPL, Elastic KQL and IOC generation were written against the fake sim, so
they are unvalidated against real BGP telemetry and are not assumed to work. Any
detection layer for this lab is built fresh against the real collector output
(see sections 8 and 11). The old repo can be glanced at for coverage ideas, not
inherited as a working contract.

### Source material to read

- Red-team doctrine (the nine techniques): `red/source/docs/scarlet/op-red-lantern/`
  (the `runbooks/` folder, formerly `bench/`, is the nine-technique taxonomy; `index.rst`
  frames the operation). Online: https://red.tymyrddin.dev/docs/scarlet/op-red-lantern/
- Earthworks entities: `red/source/docs/earthworks/` (fungusfiber, mycosec, fmda,
  fungolia). FungusFiber is Fungolia's sole regional LIR and primary provider, the
  lab's in-world subject; FMDA (the Fungolia Digital Media Authority) is the
  IP-block authority, the registry/RIR whose in-world home is the governance zone.
- Blue dramatisations: `blue/source/docs/scenarios/` (`bgp-route-hijack.md` is
  Toadstool Takeover; `ai-bgp-hijack.md` is Spore Cloud; `index.rst` frames the
  sets).
- What is being replaced: `red-lantern-sim/` (event schema at
  `telemetry/schemas/bgp_event.json`; engine, feeds and scenarios models worth
  reading before discarding).
- May or may not: Blue consumer to keep feeding: `red-lantern-detection/`.
- The pattern to follow: `ics-access-simlab/` (its `ctl`, `clab/`, `zones/`,
  `orchestrator/generate.py`, `books/`, `challenges/` and README).

## 3. Decisions already made

- Live containerlab, not telemetry generation. Replace red-lantern-sim.
- Attack-only, free-roam CTF. The attacker AS is a real router the player drives
  by hand. Scenario folders are optional scaffolding (briefing, flag, reference
  solution), not rails. An expert ignores them; a novice follows the brief.
- Contained: private ASNs (64512 to 65534), TEST-NET documentation prefixes
  (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24), no internet egress. Contain by
  blocking egress at the lab edge, not by removing in-band reachability, so nodes
  stay reachable for player SSH and the looking glass (see section 9).
- Player and operator access are separate (section 9). Players enter through one
  ops host and work in-band; `ctl` and host `docker exec` are operator-only.
- Public-server safety (section 9): key-based SSH only, no password auth, and no
  published ports. The committed image ships no working password; credentials are
  generated per deploy. The lab is vulnerable inside, never reachable from the
  internet.
- Realism scope (section 13): the attack mechanics, the data and route propagation
  are real; initial access, scale and time are deliberately abstracted. Fabricated
  data is the one thing forbidden. It stays a CTF, with guided briefings as the
  on-ramp.
- Clean break from red-lantern-sim. It is treated as not realistic; nothing is
  built on its code, schema, feeds or detection rules. The event model is designed
  from scratch around what the live collector actually emits.
- Real data replaces fake feeds. Seed the backbone with a real MRT route dump
  downloaded from RouteViews or RIPE RIS archives, so the global table is
  plausibly large. (The old mock feeds are not reused.)
- Milestone approach: get the live free-roam topology plus a CLI looking glass
  working first; add the flask gamemaster frontend second.
- Milestone 1 is all-FRR for deployability (one router image everywhere).
  ExaBGP and GoBGP come in later as richer attacker/collector tooling.

## 4. Target architecture: the six zones

This is the full design the lab grows into. Milestone 1 (section 5) builds a
subset.

1. Registry and governance plane. The trust fabric the attacks subvert.
   Containers: an RPKI CA and publication point (Krill), an RTR server feeding
   validation to routers (Stayrtr, fed by Routinator or rpki-client), and an IRR
   database (IRRd). This is where ROAs exist or do not, and where IRR objects get
   laundered. FMDA's in-world home as the IP-block authority (the registry/RIR);
   FungusFiber sits under it as the LIR, holding an allocation and issuing ROAs for
   its own space.
2. Backbone and transit. The default-free core: two or three FRR routers acting
   as Tier-1/Tier-2 providers, seeded with a real MRT dump, and the place where
   filtering, RPKI origin validation, max-prefix and IRR-built prefix filters
   either happen or do not.
3. Exchange. An IXP route server (BIRD2) where members peer. Needed for the
   more-specific-via-peering and policy-trust scenarios.
4. Edge and customers. Four or five FRR ASes: a victim owning the target prefix,
   a compromised-customer attacker foothold, a multi-homed leaky customer, a
   hosting provider, a benign customer for noise.
5. Traffic plane. The data plane that proves a control-plane attack worked: an
   nginx victim service behind the target prefix, and eyeball clients sending
   traffic to it, so a hijack visibly diverts flows and interception can MITM.
6. Gamemaster. The CTF spine and the only observer in an attack-only lab. A route
   collector with a BMP feed and a looking glass, a scorer that watches the table
   and checks flag conditions, and (planned) a flask frontend. It does not
   defend; it verifies and records.

## 5. Milestone 1: the deployable core

All-FRR, five routers and two hosts. This is what to build and validate first.

| Node        | ASN   | Role                                              |
|-------------|-------|---------------------------------------------------|
| transit-a   | 65001 | transit provider, peers with transit-b            |
| transit-b   | 65002 | transit provider, peers with transit-a            |
| victim-as   | 65010 | customer of transit-a, owns 203.0.113.0/24        |
| attacker-as | 65020 | customer of transit-b, the player's foothold      |
| gamemaster  | 65000 | passive collector, peers both transits, read-only |
| web         | n/a   | victim service behind 203.0.113.0/24 (nginx)      |
| eyeball     | n/a   | client generating traffic toward the victim       |

Relationships: transit-a and transit-b peer settlement-free; victim-as is a
customer of transit-a; attacker-as is a customer of transit-b; gamemaster
receives both tables and announces nothing. Use `no bgp ebgp-requires-policy` on
the routers so routes flow without route-maps (a deliberately permissive lab).

### Addressing plan

Point-to-point /30 links on the data plane:

| Link                              | Network        | Addresses             |
|-----------------------------------|----------------|-----------------------|
| transit-a eth1 - transit-b eth1   | 10.0.0.0/30    | a=.1, b=.2            |
| transit-a eth2 - victim-as eth1   | 10.0.0.4/30    | a=.5, victim=.6       |
| transit-b eth2 - attacker-as eth1 | 10.0.0.8/30    | b=.9, attacker=.10    |
| transit-a eth3 - gamemaster eth1  | 10.0.0.12/30   | a=.13, gm=.14         |
| transit-b eth3 - gamemaster eth2  | 10.0.0.16/30   | b=.17, gm=.18         |
| victim-as eth2 - web eth1         | 203.0.113.0/24 | victim-as=.1, web=.10 |
| transit-a eth4 - eyeball eth1     | 192.0.2.0/24   | a=.1, eyeball=.10     |

- victim-as announces 203.0.113.0/24 (a `network` statement; the /24 is connected
  on eth2).
- attacker-as legitimately holds 198.51.100.0/24 (its hosting space) and uses it
  for normal announcements.
- eyeball default route via transit-a (192.0.2.1); web default route via
  victim-as (203.0.113.1).

### Why all-FRR for milestone 1

One router image (`quay.io/frrouting/frr`) maximises the chance the lab deploys
first try, and FRR's `show ip bgp json` doubles as the gamemaster's structured
feed for the scorer. ExaBGP (for crafting arbitrary/malformed/timed
announcements) and GoBGP (as a dedicated BMP collector) are upgrades, not
milestone-1 dependencies.

### Container/image notes (to confirm on first deploy)

- Routers: `quay.io/frrouting/frr` (pin a version, e.g. 9.1.x). Bind
  `/etc/frr/daemons` (bgpd=yes, zebra=yes) and `/etc/frr/frr.conf` per node.
  Integrated config needs `service integrated-vtysh-config`.
- Hosts (web, eyeball): an image with iproute2 plus a simple HTTP server and
  curl, e.g. `wbitt/network-multitool` or `nicolaka/netshoot`. Set IPs and routes
  via containerlab `exec`. Confirm the web root path for the served flag content.

## 6. Repo tree (target)

```
clab/                     containerlab topology (one base file + scenario overlays)
configs/
  daemons                 shared FRR daemons file
  transit-a.conf          per-node frr.conf
  transit-b.conf
  victim-as.conf
  attacker-as.conf
  gamemaster.conf
  web/index.html          the victim-served content (a flag/identifier)
orchestrator/
  generate.py             builds clab files + manifests from lab.yaml (later)
scenarios/
  <technique>/
    scenario.yaml         roles, target prefix, expected effect, flag condition
    briefing.md           player-facing brief (lore from op-red-lantern)
    attack.md             the steps / reference solution
    solution.md           instructor notes
    overlay.clab.yml      optional extra nodes/links this scenario needs
gamemaster/
  README.md               collector + scorer + flask plan
  flags.yaml              per-scenario flag definitions (later)
seeds/
  mrt/                    real RouteViews/RIS MRT dump (later)
  rpki/                   ROAs present for some prefixes, absent for others (later)
  irr/                    IRR objects (later)
docs/
  plan.md or this PLAN.md
lab.yaml                  selects active scenario + difficulty knobs (later)
ctl                       wrapper: up / down / table / lg / ssh
tests/
```

## 7. Scenarios: the nine techniques

From `op-red-lantern/runbooks/` (formerly `bench/`). Each maps onto the topology as follows.

1. false-origin-prefix-hijack (compromised customer announces a victim prefix).
   Needs: attacker customer, a transit that does not filter/validate, victim,
   collector. THE FIRST SCENARIO TO BUILD.
2. route-leak-hijack (multi-homed customer re-announces provider routes). Needs:
   a customer with two upstreams plus a peer.
3. legitimate-peering → more-specific hijack (longest-prefix via the IXP).
   Needs: the IXP route server.
4. incomplete-rpki -> opportunistic hijack (hijack a not-found prefix). Needs:
   the registry plane (Krill + RTR) and routers doing ROV.
5. policy-trust-abuse → preferred-path hijack (exploit local-pref, customer over
   peer over upstream). Needs: a customer relationship to inject a preferred path.
6. strategic-traffic-interception (stealth hijack, observe and forward). Needs:
   the traffic plane and a return path; data-plane scoring.
7. path-manipulation (selective degradation via AS_PATH). Needs: a multi-upstream
   attacker.
8. route-legitimacy-subversion (long-term positioning, clean IRR objects). Needs:
   the IRR and time.
9. deniable-routing-disruption (selective withdraws for narrative effect). Needs:
   the attacker controlling a transited prefix; data-plane scoring.

In-world dramatisations (the FungusFiber blue scenarios) map onto these:
Toadstool Takeover = false-origin/compromised-customer (1); Spore Cloud =
AI-driven stealth interception (6), timed to a window shorter than a human desk
reacts.

### First scenario to build: false-origin via more-specific

Concrete and deployable on the milestone-1 core. The attacker announces
203.0.113.0/25 (a more-specific of the victim's /24) with itself as origin. With
loose filtering it propagates and wins by longest-prefix match. The gamemaster
sees a /25 appear with the attacker's origin AS. Scoring is propagation-based for
milestone 1 (the collector confirms the bogus announcement reached the table);
data-plane diversion of eyeball traffic is an enhancement.

## 8. Gamemaster, scoring and the defence bridge

- Output format: the real telemetry sources define the event model from scratch.
  The live collector's outputs (FRR bgpd logs, BMP messages, FRR/GoBGP JSON, any
  RPKI validation logs) are normalised into one event envelope designed for this
  lab. Nothing is inherited from red-lantern-sim's schema; the envelope is shaped
  by what the real collector actually emits.
- Detection is a fresh build, not a port. red-lantern-detection's rules were only
  exercised against the fake sim, so they are not trusted here. The only thing
  worth taking from it is the list of signals worth detecting (new origins,
  more-specifics, AS_PATH anomalies, RPKI-invalid announcements, withdrawals); the
  decoders and rules themselves are written and validated against this lab's real
  output. Treat the whole detection layer as work, not reuse.
- Scoring modes: propagation-based (the collector sees the bad route reach the
  DFZ) is the default and the easy start; data-plane (the player actually
  intercepts or kills the victim's traffic) is added for the interception and
  disruption scenarios where the traffic is the point.
- Defence discussions: the gamemaster's record (UPDATEs, withdrawals, RIB
  snapshots, origin and AS_PATH changes, RPKI states, and traffic diversion if
  data-plane scoring is on) is a captured timeline of the attack as a defender
  would have seen it. Commit one known-good run per scenario as artefacts (MRT +
  JSON timeline) so people can discuss the defence without standing the lab up,
  and so a run can be replayed against detection rules as they are built.
- Flask frontend (milestone 2), three faces: control (pick scenario + difficulty,
  deploy/reset, flip ROV/ROA/filter knobs), player (brief, foothold details, live
  scoreboard), observability (live looking glass, BMP stream, per-router RIB,
  RPKI outcomes, traffic view, timeline export). The UI is select-and-observe;
  attacking stays hands-on inside the attacker AS so it remains a real CTF rather
  than a click-through demo.

## 9. Player and operator access model

A CTF has two audiences, and they need different surfaces. Conflating them is the
current gap: milestone 1 works, but everything runs through `ctl` and host
`docker exec`, which is the operator's god-mode view, not a player on a
compromised box. The realistic foothold was half-built (the FRR image carries an
SSH daemon) but has nowhere to listen, because containment flushes the management
address off every node (`defaults.exec` in the topology), leaving host exec as the
only way in. The model below fixes that without giving up the operator's
flexibility.

Operator (gamemaster, instructor). Full god-mode, unchanged. `ctl` plus host
`docker exec` deploy, reset and observe every node and the whole table. This is
where the clab and vtysh power lives and it stays exactly as it is. The flask
gamemaster (milestone 2) is the operator's observability face.

Player (the attacker). A thin, constrained surface on top of the same lab:

- One sanctioned entry: an attacker ops host, the attacker's workstation, the only
  box a player is handed. It carries the offensive tooling (vtysh client, bgpq4,
  ExaBGP/GoBGP, scapy, curl, tcpdump, traceroute). Entry to it is the CTF starting
  point; issue per-cohort credentials the way ics-access-simlab does with
  `ctl cohort-keys`.
- Everything else in-band from there. The player SSHes from the ops host to the
  compromised foothold router (this is what the SSH-in-image was for) with player
  credentials and drives BGP in its vtysh. No host `docker exec`, no reaching nodes
  the player does not own.
- Observation through a player-facing looking glass, not the gamemaster's table.
  This is a real FRR collector node peering with the live fabric (AS65005, read
  only); `show ip bgp` on it is the genuine routing table, never fabricated or
  faked. It stands in for a public route collector in role only, the vantage a
  player would use, not in its data. Its visibility is partial because it peers
  from a single point (real partiality from real topology, like a public looking
  glass with few peers), and any lag is real BGP convergence, never injected
  delay. The hijack shows up here only because it actually propagated. The point
  is to give the player an honest, limited vantage, not the gamemaster's
  omniscient RIB, and never a cheat: faking what the table shows would defeat the
  whole lab.
- Impact seen from the attacker's own vantage: victim-destined traffic arriving on
  the foothold (tcpdump, or real connections in the interception variant) and the
  looking glass showing the player's origin. Not traceroute-from-the-victim, which
  is the operator's confirmation.

Containment has to change to allow this. Contain by blocking egress at the lab
edge (drop forwarding from the access network, or run it without NAT) instead of
flushing the management interface. Flushing removed the only in-band reachability
and is what forced the host-exec workflow; reversing it keeps nodes reachable for
SSH and the looking glass while still denying the internet.

What this preserves: the operator keeps full god-mode and the underlying
clab/vtysh flexibility is untouched; the player simply gets a realistic, limited
layer above it. Mapping the milestone-1 walkthrough onto this: `./ctl table` and
the `docker exec transit-a`/`eyeball` peeks are operator confirmations; the player
equivalents are the looking glass and tcpdump on the foothold.

Deploying on a public server (decided controls). This lab is meant to run on a
cloud host for a cohort, so the access plane is hardened, not assumed safe. Two
hard rules. Key-based SSH only: no password authentication anywhere, the FRR
image's `admin` and `glass` users move to keys, matching ics-access-simlab's key
model. And no published ports: nothing is bound to the host's public interface,
the lab subnets are firewalled off the public NIC, and even the ops-host entry is
reached over an internal-only path rather than a `0.0.0.0` port. The committed
image therefore carries no working password; per-deploy credentials are generated
at `ctl up` the way the reference issues cohort keys. The lab is deliberately
vulnerable inside, and never reachable from the internet. Weak in-lab credentials
are only ever safe behind that isolation, so the isolation is an enforced, tested
control, not folklore.

Status: milestone 1.5 is built (not yet deployed). The ops host, the player
looking glass and key-only access are in the tree; the operator plane is
unchanged. Containment is by reachability scoping, not egress-blocking: the M1
routers keep the mgmt-eth0 flush (no egress) and the new access LAN is a host
bridge with no NAT and no default, so it adds reachability without adding egress.
This meets the model's goal (nodes reachable in-band for player SSH and the
looking glass) without un-flushing mgmt or touching host iptables.

Decided within this model (built that way):

- One entry point. The foothold is reachable only over the access LAN from the
  ops host; admin's key is bound on attacker-as alone, so no other AS accepts a
  player SSH. No direct player SSH to the foothold from outside.
- Looking glass is an SSH service for now: a single-transit vantage (AS65005,
  one real peering session) read via the ForceCommand-locked `glass` user. A web
  face and extra vantage points stay a later upgrade, each a real peering, never
  faked data.

## 10. ctl wrapper (intended commands)

```
ctl up        sudo containerlab deploy -t clab/inter-domain.clab.yml
ctl down      sudo containerlab destroy -t clab/inter-domain.clab.yml --cleanup
ctl table     docker exec clab-inter-domain-gamemaster vtysh -c "show ip bgp"
ctl lg        same as table but "show ip bgp json" (structured)
ctl ssh NODE  docker exec -it clab-inter-domain-NODE sh
```

Container names are `clab-<labname>-<node>`.

## 11. red-lantern-sim: prior art, not a foundation

red-lantern-sim is treated as not realistic and nothing is built on it. Do not
inherit its schema, feeds, engine, telemetry generators, output adapters or
detection rules. The single lesson worth carrying is the negative one: synthetic
feeds and handwritten events did not reflect real routing, which is why this lab
is a live fabric instead.

Built fresh here (not from red-lantern-sim):

- The event envelope, designed around what the live collector actually emits.
- The detection layer, written and validated against real lab telemetry.
- The scenario format (`scenarios/*/scenario.yaml`), designed for real lab actions
  and used as a test oracle.

From elsewhere, still good (these are not red-lantern-sim):

- The op-red-lantern technique taxonomy and the lore/narrative, which live in the
  red docs (`red/source/docs/scarlet/op-red-lantern/` and `earthworks/`), not in
  the sim.
- The ics-access-simlab build pattern (ctl, clab, configs, dual licence).
- Difficulty tiers (easy/medium/advanced) as a config axis, a generic idea.

On reproducibility: a live lab is less deterministic than the old generator (BGP
convergence timing varies). Get it back where it helps by scripting attack actions
with fixed timing, seeding controlled noise, and keeping scenario.yaml as the
expected-outcome oracle, none of which requires the old code.

## 12. Open design questions

These are not yet decided. A future session can resolve them with the user.

1. Scoring default. Recommended: propagation-based first, data-plane added only
   for interception (6) and disruption (9). Confirm.
2. RESOLVED. The question splits by role. GoBGP arrives now, as the MRT seed
   injector node only (section 15), not as the attacker; native `gobgp mrt
   inject` is the reason FRR's lack of MRT import is no obstacle. ExaBGP stays
   deferred, and its trigger is now nameable: the first scenario needing
   announcements vtysh cannot produce by hand (crafted, malformed or precisely
   timed UPDATEs), which points at technique 7 and any malformed-attribute work,
   not at the false-origin scenario already built. The attacker foothold stays
   hand-driven FRR until such a scenario lands, keeping the free-roam feel and
   avoiding a tool before a scenario needs it.
3. RESOLVED. Seed after the core, which now deploys cleanly. The design is
   section 15: a GoBGP injector replaying a filtered, representatively-sampled
   real RIB dump over eBGP, scale as a dial (default ~10k, ramp to the host's
   ceiling).
4. RESOLVED. Topology structure: one base topology, then base plus per-scenario
   overlays as scenarios multiply. The ics-access-simlab per-zone split (one
   .clab.yaml per zone) was considered and set aside on purpose, not overlooked:
   that repo splits because its zones are isolated security domains joined only
   at policed boundaries, whereas this lab's subject is an inter-AS mesh whose
   whole point is that everything connects. Milestone 1 is a single hand-written
   topology (clab/inter-domain.clab.yml); scenarios add nodes and links via
   overlays, never zones. Do not "fix" this back to a per-zone split.
5. RESOLVED. Adopt ics-access-simlab's custom-built FRR-with-SSH image rather
   than the stock image plus `containerlab exec`. The custom image (FRR 9.1.0 +
   openssh + an admin user that lands in vtysh) gives the player a real
   interactive foothold to drive BGP by hand, which is the free-roam point;
   stock + exec only pushes config non-interactively. Build files reused from
   the reference at clab/frr/ (Dockerfile, start.sh, sshd_config), trimmed of the
   ICS-only iptables/SNMP machinery. Per-node addressing/policy comes from
   configs/*.conf and a shared configs/daemons. Pinned: FRR 9.1.0, host image
   wbitt/network-multitool. Still to pin when their zones land: route server
   (BIRD2 assumed); RPKI stack (Krill + Routinator + Stayrtr assumed).
6. Flask frontend scope: does the control face also drive scenario selection and
   config, or observe only? (Section 8 assumes it drives.)
7. RESOLVED. Adopt ics-access-simlab's dual-licence trio by copying its files:
   LICENSE (Polyform Noncommercial 1.0.0) + COMMERCIAL-LICENSE.md +
   SECURITY-RESEARCH-EXCEPTION.md, plus DISCLAIMER and CODE-OF-CONDUCT.md. Done.
8. Retiring red-lantern-sim: it is deprecated and not a dependency. Confirm
   whether to archive the repo outright or leave it read-only as historical
   reference. There is no schema cutover, since nothing here builds on it.
9. On-ramp balance: how much guided scaffolding (briefings, hints) versus pure
   free-roam, and whether to ship a "guided mode" flag.
10. RESOLVED (convention). Node naming follows the four-key label scheme (role,
    asn, func, lore) plus the FRR hostname for the lore name, set out in section
    16. The convention and the canon-anchored lore (FungusFiber, FMDA, MycoSec,
    OpenHands) are fixed; the remaining TBD lore names (transit-b, victim-as,
    attacker-as and the new edge nodes) are tracked there and filled in with the
    user, not invented.
11. RESOLVED. This repo carries its own CLAUDE.md with the British-English/
    no-em-dash/no-bold/no-"should" style rules, scoped to Markdown and prose
    only. Code and config (FRR .conf, shell, Dockerfiles, clab .yml) follow code
    conventions, not the prose rules.
12. The detection layer: red-lantern-detection's rules were only run against the
    fake sim and are not trusted here. Decide whether to rebuild detection inside
    this repo or in a fresh repo, and track validating it against real lab output
    as its own piece of work.

## 13. Realism scope: what is real and what is abstracted

A recurring worry deserves a fixed answer, so this section is the charter. Two
different things get called "unrealistic" and only one is fatal.

Real, and never compromised:

- The mechanics. Real FRR, real eBGP sessions, real route propagation, real
  longest-prefix-match, and real RPKI/IRR once those zones land. A hijack works for
  the exact reasons it works on the real internet, never through a lab hook.
- The data. Every table a player or the gamemaster reads is the genuine live RIB.
  The looking glass shows real routes from a real peering vantage. Nothing is
  fabricated, hidden or delayed. This is the line red-lantern-sim crossed and this
  lab does not.
- The confirmation surface. A player verifies a hijack the way a real attacker
  does, through a public-style looking glass with partial visibility, not an
  omniscient view. Public route collectors (RIS, RouteViews, ISP looking glasses)
  are genuinely attacker-available, so this is realism, not a gift.

Deliberately abstracted, the normal scope of any focused range:

- Initial access. The lab hands the player an announcing position (a foothold on
  the attacker AS) rather than making them phish a NOC, burn a router CVE or steal
  an IRR/RPKI credential first. This matches the op-red-lantern bench, whose
  techniques all begin from a position already gained; acquiring the position is a
  different lab. This is the main boundary of what the lab teaches.
- Scale. A handful of ASes seeded from a real MRT dump, not the whole default-free
  zone. The table is plausible, not complete.
- Time. Campaigns that run for months in the wild (legitimacy subversion) are
  compressed to a session.

The test the lab holds itself to: the attack succeeds through real BGP, the
confirmation surface shows real data, and the player never has god-mode
visibility. It does not also simulate getting into the announcing position.
Measuring it against "did they compromise the router themselves too" is measuring
it against a different lab.

CTF, not demo. The realism above is enough for a real CTF: winning requires
understanding routing, and scoring keys off real effect (it propagated, traffic
bent). Guided briefings per scenario are the on-ramp for players new to the
tooling (open question 9), so the lab serves both the hand-held walk and the
free-roam challenge without becoming a passive demo.

## 14. Current status

Milestone 1 (deployed and validated on containerlab 0.75). The all-FRR core
deploys, BGP converges, the gamemaster receives both tables while announcing
nothing, and the false-origin /25 propagates, wins by longest-prefix match and
diverts eyeball traffic. Built:

- `clab/inter-domain.clab.yml` base topology; `clab/frr/` custom router image;
  `configs/daemons` + per-node `configs/*.conf` + `configs/web/index.html`.
- `ctl`, the dual-licence trio + DISCLAIMER + CODE-OF-CONDUCT, and
  `scenarios/false-origin-prefix-hijack/` (deployable on the base, no overlay).

Milestone 1.5 (deployed, player paths validated). The player surface from
section 9, key-only and entered over the internal access LAN:

- `clab/ops-host/` ops-host image (sshd key-only, recon tooling, `foothold` and
  `lg` pivot helpers); in the topology as `network-mode: none` on the access LAN.
- `lookingglass` collector (AS65005, `configs/lookingglass.conf`): single-transit
  vantage, read-only, read via the ForceCommand-locked `glass` user. Validated:
  `glass@lookingglass` returns one table, everything via 65001 (the one transit).
- FRR image and ops-host image are key-only (no baked password); admin's key is
  bound on attacker-as only, glass's on lookingglass only.
- Access auth gotcha, fixed: `adduser -D` leaves accounts locked (`!`), and sshd
  with `UsePAM no` refuses even pubkey to a locked account. Both images run
  `passwd -d` to leave an empty (not locked) password; `PasswordAuthentication no`
    + `PermitEmptyPasswords no` keep entry key-only regardless.
- `ctl`: key generation, the `idsl_access` bridge lifecycle, both image builds,
  `cohort-keys`, `player` (real player, cohort key, auto-made locally) and
  `playtest` (operator check via the lab key). Access material is gitignored.

Access model, local versus production. Local play: the operator host holds
100.64.0.254 on the access bridge, so `./ctl player` connects straight to the ops
host. Production (public host): the access LAN is internal and no port is
published, so players jump in, `ssh -i cohort-key -J jump@<lab-host>
player@100.64.0.10`, through a restricted account the operator provisions on the
host. Standing up that jump account is host provisioning, out of `ctl` scope.

The full attack loop through the player surface is now validated end to end: cohort
key, `foothold`, announce the /25, and `lg` shows it winning from the single-transit
vantage (path 65001 65002 65020). The data-plane redirect is validated too: swapping
the foothold's `Null0` discard for `ip route 203.0.113.0/25 100.64.0.10` pulls the
victim's traffic (eyeball ICMP and an HTTP SYN to .10:80) onto the attacker's ops
host, with an operator traceroute terminating there. FRR enables IP forwarding on
its own, so no sysctl tweak was needed. The scenario docs follow the player path,
and the docs are reorganised to match: a slim `README.md` front door,
`docs/operator.md` (running and observing the lab), `docs/playing.md` (the player's
moves and how to confirm them), and the per-scenario briefings.

Milestone 2 (the MRT seed) is built and validated, so a hijack is no longer the
only thing in the table; the design and the deploy results are section 15. Next,
in roughly this order, each closing a clean-room gap named in section 13: the
registry and governance zone (Krill, Routinator, IRR) so there are defences to
beat (RPKI ROV, prefix filters, max-prefix); and the gamemaster scorer, which
normalises the live collector output (`show ip bgp json`, plus BMP/logs later)
into a fresh event envelope designed around what this lab actually emits (not
red-lantern-sim's schema, per sections 8 and 11). Detection and response (open
question 12) follows.

## 15. MRT seed: a plausibly large backbone table

The M1/M1.5 core is built and validated, but the global table is nearly empty:
the lab's own handful of prefixes plus the hijack under test. A real backbone
carries a large default-free-zone table, and the later goals (RPKI ROV, prefix
filters, max-prefix, AS-path-based detection) only mean something against a
populated RIB. This is the next milestone from section 14, and open question 3 is
now answerable: the core works, so seed it.

The seed is real, not faked. Per the charter (sections 3 and 13), the dump is
replayed as genuine BGP UPDATEs over a real eBGP session, never stuffed into a
table. FRR cannot import MRT, which is the trigger to bring in GoBGP (open
question 2 resolves here): GoBGP is added as the injector node only; everything
else stays FRR.

Four design concerns shaped it, all settled with the user:

1. Scale. A full v4 table (~950k routes) across the no-policy mesh risks OOM and
   slow convergence on one host. Scale is a dial, default ~10k, ramp and record
   the host's comfortable ceiling. This matches "plausible, not complete"
   (section 13).
2. Injection. Real propagation via `gobgp mrt inject`, never table stuffing.
3. Prefix interaction. The seed cannot touch the experimental prefixes, so
   longest-prefix selection on 203.0.113.0/24 against the /25 is unchanged.
   Guaranteed twice: by filtering the dump, and by an inbound prefix-list on the
   transits' seed neighbour.
4. AS-path realism. Real AS_PATHs are kept (real origins, which RPKI/IRR need;
   realistic path length and diversity). The seed-to-first-hop adjacency is
   fictional from the topology's vantage. This is a named, deliberate boundary,
   scoped out the way section 13 scopes initial access, scale and time.
   Synthesising topology-consistent paths is rejected: it would fabricate data.

### Approach

A new GoBGP node, `seed` (AS65003), peers eBGP with both transits over two new
/30 links and replays a filtered, representatively-sampled RIB dump. The transits
learn the routes and propagate them onward as they carry everything else, so the
gamemaster (two feeds) and the lookingglass (single transit-a vantage) both see a
large, real table. Origins stay real; the seed AS is prepended by normal eBGP,
and GoBGP rewrites next-hop to itself on advertisement so the dump's public
next-hops become reachable via the seed.

### Addressing (new links)

| Link                          | Network      | Addresses       |
|-------------------------------|--------------|-----------------|
| transit-a eth6 <-> seed eth1  | 10.0.0.24/30 | a=.25, seed=.26 |
| transit-b eth4 <-> seed eth2  | 10.0.0.28/30 | b=.29, seed=.30 |

transit-a's next free index is eth6 (eth1 to eth5 in use), transit-b's is eth4
(eth1 to eth3 in use); confirmed against clab/inter-domain.clab.yml.

### Files to create

- `clab/seed/Dockerfile`: GoBGP on a small base (the released gobgp binary on
  alpine, mirroring the lean style of clab/frr/Dockerfile). Ships gobgpd and
  gobgp. No credentials, no published ports.
- `clab/seed/gobgpd.conf`: TOML global config, as = 65003, router-id, two
  neighbours (10.0.0.25 as 65001, 10.0.0.29 as 65002).
- `clab/seed/start.sh`: assign and bring up eth1 (10.0.0.26/30) and eth2
  (10.0.0.30/30), since a non-FRR node has no zebra to do it; launch gobgpd; wait
  for both sessions; then `gobgp mrt inject global /seeds/mrt/<sample>
  $SEED_COUNT`. SEED_COUNT comes from an env var (default 10000), the scale dial.
  The interface assignment can live in the clab exec block instead, matching
  web/eyeball/ops-host; either way it happens before gobgpd peers.
- `seeds/mrt/fetch.sh`: operator-time download of a RIB dump from RouteViews
  (route-views2 RIBs) or RIPE RIS into seeds/mrt/. Egress is operator-host only;
  lab nodes stay contained.
- `seeds/mrt/filter.sh` (or a small Python script using the existing .venv):
  produce a v4-unicast, bogon-free, lab-prefix-free, lab-ASN-free dump from the
  raw download, sampled representatively across the whole table (a stride or
  shuffle, not the first N, because `gobgp mrt inject` takes the first count
  entries and MRT RIBs are prefix-ordered, so a naive count grabs a contiguous
  low-address block narrow in prefix-length and origin diversity). Drops: the
  three TEST-NET blocks the lab uses (192.0.2.0/24, 198.51.100.0/24,
  203.0.113.0/24 and any more-specifics), 10.0.0.0/8, 100.64.0.0/10, standard
  bogons and special-use, and any route whose AS_PATH contains a lab ASN (64512
  to 65534). Emits MRT for `gobgp mrt inject`.
- `seeds/mrt/.gitignore`: ignore raw dumps; commit one small filtered sample for
  reproducibility (section 8's known-good artefacts). The committed sample is the
  file the topology binds, sized to the default SEED_COUNT, so a fresh clone
  deploys offline; ramps to 50k/100k regenerate a larger clean dump at the same
  path via seed-fetch (network).
- `seeds/mrt/README.md`: how to fetch, filter and refresh; the host's recorded
  ceiling; the named adjacency limitation written down.

### Files to modify

- `clab/inter-domain.clab.yml`: add the seed node (image idsl-seed, project-
  prefixed to match idsl-ops-host, binding the committed sample), two links to the
  transits, the interface-assignment exec, and an addressing comment block.
- `configs/transit-a.conf`, `configs/transit-b.conf`: add the seed neighbour and
  an inbound prefix-list applied to that neighbour only, denying the lab prefixes
  with `le 32` (catching any more-specific) and bogons, permitting the rest. This
  is the belt-and-braces guarantee for concern 3; it leaves the permissive
  customer/peer behaviour the attack relies on untouched (the deny list is the
  set the dump filter uses).
- `ctl`: build the seed image in `up`; add `seed-fetch` (fetch + filter) and
  honour SEED_COUNT. Keep the existing image-build and deploy flow.
- `docs/playing.md` and `docs/operator.md`: note the now-large table and how the
  looking glass reflects it; the player workflow is otherwise unchanged.

### Why these choices

- GoBGP injector only: native `gobgp mrt inject global <file> <count>` is exactly
  this job, with count as the scale dial and no custom MRT-to-config tooling. The
  rest of the fabric stays FRR, preserving M1's one-image deployability.
- Two-layer isolation (dump filter plus transit inbound prefix-list): the filter
  keeps the dump clean; the prefix-list guarantees isolation even if a dump slips
  something through, independent of dump provenance.
- Real AS_PATHs: origins stay real for the RPKI/IRR milestone; the fictional
  adjacency is documented, not hidden.

### Verification

End to end, on the deploy host:

1. `./ctl seed-fetch`, then `SEED_COUNT=10000 ./ctl up`. The lab deploys; both
   seed eBGP sessions to the transits come up.
2. `./ctl table` (gamemaster) shows ~10k+ routes with real origins and real
   AS_PATHs (paths begin 65001 65003 ... or 65002 65003 ...). Spot-check that a
   few prefixes resolve to plausible real origin ASNs, and that next-hop resolves
   via the seed (.26/.30).
3. Isolation: no background route covers or competes with 203.0.113.0/24; none of
   192.0.2.0/24, 198.51.100.0/24, 100.64.0.0/10, 10.0.0.0/8 appears from the seed.
4. Regression: run the existing false-origin walkthrough. The attacker announces
   203.0.113.0/25, it propagates, wins by longest-prefix match, and the data-plane
   redirect still pulls eyeball traffic. Behaviour identical to today.
5. Looking glass: `glass@lookingglass` shows the large table from its single
   transit-a vantage; the hijack still shows the path 65001 65002 65020.
6. Stability and ramp: record memory and convergence at 10k, then raise SEED_COUNT
   (50k, 100k) until the host gets uncomfortable; note the comfortable ceiling in
   seeds/mrt/README.md.
7. Commit one known-good seeded artefact (filtered sample plus a captured table)
   per section 8.

### Out of scope (named boundaries)

- Topology-consistent adjacency for background routes. Real AS_PATHs are kept; the
  seed-to-first-hop adjacency is fictional. A future path-validity experiment
  (technique 7, or AS-path-anomaly detection) would need a dedicated
  dump-to-topology mapping, deferred and possibly never built.
- IPv6: the lab is v4 only; the filter keeps v4 unicast.
- The registry/governance zone (Krill, Routinator, IRRd) and the scorer are the
  milestones after this one, unchanged by this work.

### Built and validated

Built as specified, with two implementation notes where reality refined the spec:
the seed image is `idsl-seed` (GoBGP 4.6.0 on alpine), and the dump tooling is
`seeds/mrt/filter.py` plus `seeds/mrt/fetch.sh`, not a `filter.sh`. FRR has no
native MRT, but the deeper reason the filter is Python is that a re-emit was
needed anyway: `filter.py` reads the raw dump with mrtparse and writes a fresh
minimal TABLE_DUMP_V2 holding one entry per prefix. Raw RouteViews records carry
~20 entries per prefix (one per collector peer), and since `gobgp mrt inject`
counts entries, the one-entry re-emit is what makes SEED_COUNT a prefix-count
dial rather than a few-hundred-prefix one. The real AS_PATH is preserved
byte-for-byte in value.

Tree: `clab/seed/{Dockerfile,gobgpd.conf,start.sh}`;
`seeds/mrt/{filter.py,fetch.sh,seed.sample.mrt,README.md}` with a `.gitignore`
exception so only the sample is committed; the seed node and two /30 links in the
topology; `PL-SEED-IN` inbound prefix-lists on both transits; `ctl` builds
idsl-seed, gains `seed-fetch`, and honours SEED_COUNT.

The committed sample is 10000 prefixes drawn from route-views2 rib.20260614, 5040
distinct origins, prefix lengths spread /9 to /24. Validated on deploy (the lab
is up): both seed sessions Established; the gamemaster carries 10003 routes from
5043 origins with paths reading `65001 65003 <real path>` (and the two-hop
`65002 65001 65003 ...`); transit-a installs seed routes via 10.0.0.26 with
next-hop-self, reachable. Isolation holds: none of 203.0.113.0/24, its
more-specifics, 192.0.2.0/24, 198.51.100.0/24, 100.64.0.0/10 or 10.0.0.0/8
appears from the seed. Regression intact: the attacker's 203.0.113.0/25 still
wins by longest-prefix for 203.0.113.10, the looking glass shows it via
`65001 65002 65020`, and the data-plane redirect still pulls eyeball ICMP and
HTTP onto the attacker's ops host with the operator traceroute terminating there.
Ramped and measured on a 31 GiB host: at SEED_COUNT=10000 each FRR node holding
the table sits at 45 to 65 MiB, and at 100000 (table 100003 routes, hijack
regression still winning) at 165 to 246 MiB, the seed 421 MiB, both converging
under a minute. So roughly 40 MiB of base plus ~1.7 KiB per route per FRR node;
100k is comfortable with the whole lab under 2 GiB. A full ~950k table
extrapolates to 12 to 16 GiB across the lab, feasible on this host but the point
worth testing rather than trusting. The per-host numbers live in
seeds/mrt/README.md. The seed loop-rejects its own 10000 routes when the transits
echo them back (AS-path loop prevention), accepting only the three lab prefixes,
which is the correct behaviour, not a filter gap.

## 16. Node naming convention

Naming in the lab spans four surfaces, each for a different audience, and the
convention is to keep them separate rather than overload one. The clab `labels`
carry the recorded identity; the FRR `hostname` carries the played one.

Label keys:

- `role`: the lab-mechanics class (transit, victim, attacker, collector, seed,
  registry, ixp, customer, host, client). The operational hat.
- `asn`: the BGP ASN, only on nodes that speak BGP. Services and hosts omit it.
- `func`: the industry role, the LIR / RIR / ISP / IXP / content / eyeball
  vocabulary.
- `lore`: the in-world org (FungusFiber, FMDA, and so on), absent where the node
  is not an org.

Two rules hold the surfaces apart:

- The clab node key (transit-a, registry-rtr) stays functional and stable. It is
  the operator handle: it becomes the container name `clab-inter-domain-<node>`
  and is what `ctl` and `docker exec` address. Renaming it churns ctl, config
  filenames and docs, so lore never goes here.
- Lore is recorded in the `lore` label and experienced in the FRR `hostname`.
  transit-a runs `hostname FungusFiber-Core`; the registry RTR runs
  `hostname FMDA-RTR`. The player who pivots in meets the in-world name; the
  operator still addresses `transit-a`. The two diverging is deliberate.

Current nodes:

| Node | role | asn | func | lore | status |
|------|------|-----|------|------|--------|
| transit-a | transit | 65001 | LIR | FungusFiber | canon |
| transit-b | transit | 65002 | ISP (tier-1 upstream) | Hyphalink | coined |
| victim-as | victim | 65010 | content (gov portal) | FDEI | canon |
| attacker-as | attacker | 65020 | customer | Bracket Hosting | coined |
| gamemaster | collector | 65000 | collector (operator/scorer) | MycoSec | canon |
| seed | seed | 65003 | transit (global feed) | n/a | the wider internet |
| lookingglass | collector | 65005 | collector (public vantage) | OpenHands | canon |
| ops-host | host | n/a | host (attacker workstation) | Bracket Hosting | with attacker-as |
| web | host | n/a | content-host | FDEI | with victim-as |
| eyeball | client | n/a | eyeball | n/a | the public |

Planned nodes (the six-zone build):

| Node | role | asn | func | lore | status |
|------|------|-----|------|------|--------|
| registry-ca | registry | n/a | RIR (Krill CA) | FMDA | proposed |
| registry-rtr | registry | n/a | RIR (Routinator/Stayrtr) | FMDA | proposed |
| registry-irr | registry | n/a | RIR (IRRd) | FMDA | proposed |
| ixp-rs | ixp | 65006 | IXP (BIRD2 route server) | FungIX | coined (proposed) |
| customer-leaky | customer | 65030 | customer (multi-homed) | Mudflat Networks | coined (proposed) |
| provider-hosting | transit | 65040 | ISP (hosting) | Sporehaul Hosting | coined (proposed) |
| customer-benign | customer | 65050 | customer (noise) | Quietgrove | coined (proposed) |

Notes:

- An org that spans containers (the registry: a Krill CA, the RTR, IRRd) carries
  one `lore` (FMDA) on every part; the node key names the component (registry-ca,
  registry-rtr, registry-irr).
- `asn` appears only on BGP speakers. The registry services, ops-host, web and
  eyeball carry none; the IXP route server does. The suggested ASNs for the
  planned nodes (ixp-rs 65006, customer-leaky 65030, provider-hosting 65040,
  customer-benign 65050) are placeholders to confirm, not fixed.
- Lore comes from two places. Canon (from the earthworks docs): FungusFiber
  (transit-a), FMDA (the registry), MycoSec (gamemaster), OpenHands (lookingglass),
  and FDEI, the Fungolian Department of Energy & Infrastructure, the victim. The
  rest are coinages in the Fungolia palette, not from the earthworks docs:
  Hyphalink (the foreign tier-1 upstream, hyphae being the mycelial links),
  Bracket Hosting (the small compromised frontier customer), and, for the planned
  nodes, FungIX, Mudflat Networks, Sporehaul Hosting and Quietgrove. The coined
  names are deliberate inventions, not discovered canon; if any later earthworks
  page names these roles, the canon name wins.
- Config header comments stay keyed to the node key, the operator handle
  (`! transit-a, AS65001`). Lore lives in the label and the FRR hostname, not the
  operator-facing header. A parenthetical cross-reference
  (`! transit-a (FungusFiber), AS65001`) is optional, left out by default to avoid
  churn.
- Applied as of June 2026: the labels and FRR hostnames are set on the M1/M1.5
  nodes (transit-a/b, victim-as, attacker-as, gamemaster, seed, lookingglass,
  ops-host, web, eyeball), taking effect on the next `./ctl up`. The planned-node
  rows land with the registry/governance zone and the exchange.
