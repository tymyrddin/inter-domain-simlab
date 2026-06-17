# Inter-domain SimLab: build plan and design record

This file is the handoff document. It captures what has been decided, the target
design, the first milestone, and the design questions still open. A future
session working inside this repo can read it without needing the original
conversation. Written 2026-06-13.

## Milestones at a glance

The canonical sequence. The numbering drifted as the build order changed, so this
is the version to trust; the section references point at the detail.

- M1, deployable core (done). The all-FRR core and the false-origin hijack on
  control and data plane. Section 5.
- M1.5, player layer (done). The ops host, the single-vantage looking glass and
  key-only access. Section 9.
- M2, MRT seed (done). A plausibly large backbone table. Section 15.
- M3, registry and governance zone (next). RPKI and ROV now, IRR as phase two.
  Section 17.
- M4, scorer. Normalises the observer's output into the event envelope,
  and produces the BMP feed and the log and dump exports heimdallr consumes.
  Section 18 (and sections 8, 14).
- M5, flask frontend. The control, player and observability UI. A GUI, teaching and
  scale layer over the CLI, gated on audience, not built by default (section 8). This
  was "milestone 2" in the first two-step plan; renumbered here.

Detection and response are not lab milestones. The detection rules live in
heimdallr (the detection lab) and the response doctrine in the blue docs
(`counter/impact/response.md`). What the lab owes them is telemetry, the real logs
and dumps, produced across M2 (MRT artefacts and the JSON timeline), M3 (RPKI
validator logs and ROA-change records) and M4 (the event envelope and BMP), not as
a milestone of their own.

Not yet built (deferred or planned, none of it half-started, all of it recorded
here so a "done" milestone never hides an open sibling):

- IRR phase two: the registry zone's second half, `registry-irr` (IRRd) and the
  bgpq4 prefix filters. Deferred by the RPKI-first/IRR-second decision (section 17).
  The RPKI half (M3) is complete; the IRR half is not started.
- The exchange zone: `ixp-rs` (a BIRD2 route server), zone 3 of section 4.
- The extra edge ASes: a multi-homed leaky customer, a hosting provider, a benign
  noise customer (zone 4). Only the victim and attacker exist today.
- Attack scenarios: three built, each committing a known-good telemetry bundle for
  heimdallr (`false-origin-prefix-hijack`, `incomplete-rpki-hijack`,
  `roa-poisoning-hijack`, the arm-then-hijack multi-stage). The remaining techniques
  need new capability: ExaBGP (true-origin MOAS, path-manipulation, malformed
  attributes), the IXP zone (more-specific-via-peering), multi-homing (route-leak),
  or IRR phase two (legitimacy-subversion).
- M5, the flask frontend: deliberately gated on audience (section 8), not built by
  default.

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
  working first; add the flask frontend later (M5; see the milestone list).
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
6. Observer and scorer (formerly gamemaster). The CTF spine and the only watcher in an attack-only lab. A route
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
| observer  | 65000 | passive collector, peers both transits, read-only |
| web         | n/a   | victim service behind 203.0.113.0/24 (nginx)      |
| eyeball     | n/a   | client generating traffic toward the victim       |

Relationships: transit-a and transit-b peer settlement-free; victim-as is a
customer of transit-a; attacker-as is a customer of transit-b; observer
receives both tables and announces nothing. Use `no bgp ebgp-requires-policy` on
the routers so routes flow without route-maps (a deliberately permissive lab).

### Addressing plan

Point-to-point /30 links on the data plane:

| Link                              | Network        | Addresses             |
|-----------------------------------|----------------|-----------------------|
| transit-a eth1 - transit-b eth1   | 10.0.0.0/30    | a=.1, b=.2            |
| transit-a eth2 - victim-as eth1   | 10.0.0.4/30    | a=.5, victim=.6       |
| transit-b eth2 - attacker-as eth1 | 10.0.0.8/30    | b=.9, attacker=.10    |
| transit-a eth3 - observer eth1  | 10.0.0.12/30   | a=.13, ob=.14         |
| transit-b eth3 - observer eth2  | 10.0.0.16/30   | b=.17, ob=.18         |
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
first try, and FRR's `show ip bgp json` doubles as the observer's structured
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
  observer.conf
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
scorer/
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
loose filtering it propagates and wins by longest-prefix match. The observer
sees a /25 appear with the attacker's origin AS. Scoring is propagation-based for
milestone 1 (the collector confirms the bogus announcement reached the table);
data-plane diversion of eyeball traffic is an enhancement.

### Scenarios built

Three scenarios exist, each committing a known-good telemetry bundle for heimdallr:

- `false-origin-prefix-hijack`: the /25 more-specific wins; under ROV it reads
  rpki=invalid and is dropped. The invalid-and-dropped record.
- `incomplete-rpki-hijack` (working title "Unsigned Ground"): an exact-origin MOAS on
  a not-found prefix, the ROV coverage gap (technique 4).
- `roa-poisoning-hijack` (working title "Pulling the Roots"): ROV on drops the /25 as
  invalid, `ctl roa poison` withdraws FDEI's ROA, the /25 resurfaces as rpki=notfound
  and wins. The arm-then-hijack multi-stage; the raw bundle pairs the ROA-change
  records (the arming) with the BMP events (the hijack).

True-origin MOAS, forging the victim's origin so ROV sees it valid, is not
hand-buildable in FRR and waits for ExaBGP: route-maps have no path-append and run
after the local-AS prepend, and the only working forge (`set as-path replace`) strips
the attacker's AS and is dropped by transit-b's enforce-first-as. It was left for
ExaBGP rather than faked or propped up with a contrived `no enforce-first-as`, which
empirically confirms open question 2's ExaBGP trigger.

That exhausts what is authorable on the existing machinery. The remaining techniques
need new capability: ExaBGP (true-origin MOAS, path-manipulation, malformed
attributes), the IXP zone (more-specific-via-peering), multi-homing (route-leak), or
IRR phase two (legitimacy-subversion). Working titles hold pending the op-red-lantern
runbooks.

## 8. Observer, scoring and the defence bridge

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
- Defence discussions: the observer's record (UPDATEs, withdrawals, RIB
  snapshots, origin and AS_PATH changes, RPKI states, and traffic diversion if
  data-plane scoring is on) is a captured timeline of the attack as a defender
  would have seen it. For heimdallr, commit the raw telemetry per scenario (the BMP
  event stream, the RPKI validator log, the VRP set, the ROA-change records), the
  observations a detector ingests, from which heimdallr derives the anomalies. The
  scorer's own timeline stays here as the CTF scoring record; it is not part of the
  heimdallr handoff. A run can be discussed without standing the lab up, and the raw
  telemetry replayed against detection rules as they are built.
- Flask frontend (M5), three faces: control (pick scenario + difficulty,
  deploy/reset, flip ROV/ROA/filter knobs), player (brief, foothold details, live
  scoreboard), observability (live looking glass, BMP stream, per-router RIB,
  RPKI outcomes, traffic view, timeline export). The UI is select-and-observe;
  attacking stays hands-on inside the attacker AS so it remains a real CTF rather
  than a click-through demo.

M5 value, gated on audience (reassessed 2026-06-15). The CLI now covers every
mechanic these faces were to expose: `ctl rov`/`roa` for the control knobs,
`ctl score` for the live scoreboard, `lg` and `ctl table` for observability, the
committed timeline for export, and BMP arriving with M4 increment 2. So M5 adds no
new capability; it is a presentation, accessibility and scale layer over a working
CLI. Its worth is a function of audience: it earns its place for cohorts, classrooms,
live demos or wider adoption, where a shared multi-player scoreboard and an
instructor console are what a CLI does badly, and it adds little for a solo,
CLI-comfortable user feeding heimdallr. So M5 is worth building only when that
audience is real; being on the list is not itself a reason to build it.

## 9. Player and operator access model

A CTF has two audiences, and they need different surfaces. Conflating them is the
current gap: milestone 1 works, but everything runs through `ctl` and host
`docker exec`, which is the operator's god-mode view, not a player on a
compromised box. The realistic foothold was half-built (the FRR image carries an
SSH daemon) but has nowhere to listen, because containment flushes the management
address off every node (`defaults.exec` in the topology), leaving host exec as the
only way in. The model below fixes that without giving up the operator's
flexibility.

Operator (observer, instructor). Full god-mode, unchanged. `ctl` plus host
`docker exec` deploy, reset and observe every node and the whole table. This is
where the clab and vtysh power lives and it stays exactly as it is. The flask
frontend (M5) is the operator's observability face.

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
- Observation through a player-facing looking glass, not the observer's table.
  This is a real FRR collector node peering with the live fabric (AS65005, read
  only); `show ip bgp` on it is the genuine routing table, never fabricated or
  faked. It stands in for a public route collector in role only, the vantage a
  player would use, not in its data. Its visibility is partial because it peers
  from a single point (real partiality from real topology, like a public looking
  glass with few peers), and any lag is real BGP convergence, never injected
  delay. The hijack shows up here only because it actually propagated. The point
  is to give the player an honest, limited vantage, not the observer's
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
ctl table     docker exec clab-inter-domain-observer vtysh -c "show ip bgp"
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
   avoiding a tool before a scenario needs it. Empirically confirmed (June 2026):
   true-origin MOAS, forging the victim's origin so ROV validates it, is the first
   concrete ExaBGP trigger. FRR route-maps cannot append a forged path (no append,
   and they run after the local-AS prepend), and the only working forge strips the
   attacker's AS and is dropped by enforce-first-as, so MOAS waits for ExaBGP rather
   than a contrived no-enforce-first-as workaround.
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
- The data. Every table a player or the observer reads is the genuine live RIB.
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
deploys, BGP converges, the observer receives both tables while announcing
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
in roughly this order, each closing a clean-room gap named in section 13: M3, the
registry and governance zone (Krill, Routinator, IRR) so there are defences to
beat (RPKI ROV, prefix filters, max-prefix; section 17); M4, the scorer (section 18),
which normalises the live collector output (`show ip bgp json`, plus BMP and logs)
into a fresh event envelope designed around what this lab actually emits (not
red-lantern-sim's schema, per sections 8 and 11), and where the log and dump
exports heimdallr consumes crystallise; and M5, the flask frontend
(section 8). Detection and response themselves are not lab milestones: they live in
heimdallr and the blue docs, fed by the telemetry the lab exports (open question 12).

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
observer (two feeds) and the lookingglass (single transit-a vantage) both see a
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
2. `./ctl table` (observer) shows ~10k+ routes with real origins and real
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
is up): both seed sessions Established; the observer carries 10003 routes from
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

| Node          | role      | asn   | func                        | lore            | status             |
|---------------|-----------|-------|-----------------------------|-----------------|--------------------|
| transit-a     | transit   | 65001 | LIR                         | FungusFiber     | canon              |
| transit-b     | transit   | 65002 | ISP (tier-1 upstream)       | Hyphalink       | coined             |
| victim-as     | victim    | 65010 | content (gov portal)        | FDEI            | canon              |
| attacker-as   | attacker  | 65020 | customer                    | Bracket Hosting | coined             |
| observer      | collector | 65000 | collector (operator/scorer) | MycoSec         | canon              |
| seed          | seed      | 65003 | transit (global feed)       | n/a             | the wider internet |
| lookingglass  | collector | 65005 | collector (public vantage)  | OpenHands       | canon              |
| ops-host      | host      | n/a   | host (attacker workstation) | Bracket Hosting | with attacker-as   |
| web           | host      | n/a   | content-host                | FDEI            | with victim-as     |
| eyeball       | client    | n/a   | eyeball                     | n/a             | the public         |
| registry-ca   | registry  | n/a   | RIR (Krill CA)              | FMDA            | built (M3)         |
| registry-rtr  | registry  | n/a   | RIR (Routinator)            | FMDA            | built (M3)         |
| bmp-collector | collector | n/a   | BMP station                 | MycoSec         | built (M4)         |

Planned nodes (not yet built):

| Node             | role     | asn   | func                     | lore              | status                  |
|------------------|----------|-------|--------------------------|-------------------|-------------------------|
| registry-irr     | registry | n/a   | RIR (IRRd)               | FMDA              | deferred, IRR phase two |
| ixp-rs           | ixp      | 65006 | IXP (BIRD2 route server) | FungIX            | coined (proposed)       |
| customer-leaky   | customer | 65030 | customer (multi-homed)   | Mudflat Networks  | coined (proposed)       |
| provider-hosting | transit  | 65040 | ISP (hosting)            | Sporehaul Hosting | coined (proposed)       |
| customer-benign  | customer | 65050 | customer (noise)         | Quietgrove        | coined (proposed)       |

Notes:

- An org that spans containers (the registry: a Krill CA, the RTR, IRRd) carries
  one `lore` (FMDA) on every part; the node key names the component (registry-ca,
  registry-rtr, registry-irr).
- `asn` appears only on BGP speakers. The registry services, ops-host, web and
  eyeball carry none; the IXP route server does. The suggested ASNs for the
  planned nodes (ixp-rs 65006, customer-leaky 65030, provider-hosting 65040,
  customer-benign 65050) are placeholders to confirm, not fixed.
- Lore comes from two places. Canon (from the earthworks docs): FungusFiber
  (transit-a), FMDA (the registry), MycoSec (observer), OpenHands (lookingglass),
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
  nodes (transit-a/b, victim-as, attacker-as, observer, seed, lookingglass,
  ops-host, web, eyeball), taking effect on the next `./ctl up`. The planned-node
  rows land with the registry/governance zone and the exchange.

## 17. Registry and governance zone: RPKI, ROV and IRR

The MRT seed gave the core a populated table; this zone gives it a trust fabric to
subvert and defend. It builds zone 1 of section 4 (FMDA, the IP-block authority):
an in-lab RPKI hierarchy and an IRR database, so origin validation, ROA
manipulation and IRR-built prefix filters become real, the defences the attacks
have to beat. It is the next milestone after the seed (section 14), and it is what
gives heimdallr the RPKI and trust-signal telemetry its correlation practice needs
(see "Telemetry for detection practice" below).

### Decisions (settled with the user)

1. Routinator with its built-in RTR, not a separate Stayrtr. registry-rtr is one
   container (validator plus RTR) rather than two. The split Stayrtr would add buys
   realism not worth the extra container here.
2. RPKI first, IRR second. RPKI (Krill + Routinator + ROAs + ROV) is the larger
   unlock: origin validation as a defence, the incomplete-RPKI and RPKI-cover
   techniques, and the ROA-poisoning correlation fixture. IRR (IRRd + bgpq4 prefix
   filters, the legitimacy-subversion technique) follows.
3. ROV off by default, toggled per scenario. The permissive core stays permissive;
   a scenario turns ROV on at transit-a/transit-b as the defence the attacker has
   to beat. This is the first of the section 8 "flip ROV/ROA/filter knobs" controls.
4. Self-contained trust. Krill runs as the lab's own trust anchor (testbed mode),
   the validator points a local TAL at it, and nothing reaches the real RPKI.
   Containment is unchanged: no internet egress.

### Milestone scope

This milestone delivers the infrastructure and the knobs, proven on the existing
false-origin scenario, with no new scenario folder. The build is Krill, Routinator
and RTR, the ROV and ROA toggles, and the telemetry export. It is proven by signing
FDEI's /24, turning ROV on at the transits so the attacker's /25 validates as
invalid and is dropped (the hijack fails), then poisoning FDEI's ROA so the hijack
returns under cover. A short note records this in the existing scenario.

Technique 4 (incomplete-rpki, the opportunistic hijack of not-found space) is a
distinct scenario, and is now built as `incomplete-rpki-hijack` (an exact-origin MOAS
on a not-found prefix, the ROV coverage gap), alongside `roa-poisoning-hijack` (the
arm-then-hijack multi-stage). Both followed once the fabric here was validated; their
targets draw on the seeded global table's not-found prefixes (section 15). The
built-scenarios list is in section 7.

### Components (the FMDA zone, naming per section 16)

- registry-ca: Krill, the CA and publication point, holding the lab trust anchor
  and issuing ROAs for lab prefixes. hostname FMDA-CA.
- registry-rtr: Routinator, fetching from Krill, validating against the local TAL,
  and serving validated payloads (VRPs) to the routers over RTR. hostname FMDA-RTR.
- registry-irr: IRRd, the IRR database (phase two). hostname FMDA-IRR.

None speaks BGP, so none carries an ASN.

### Approach

- Trust anchor and ROAs. Krill provides the lab TA and a CA under it; ROAs are
  created for the lab's own prefixes. FungusFiber's and FDEI's space gets valid
  ROAs; the seed/global prefixes stay unsigned (RPKI-unknown, as the seed design
  already leaves them); selected prefixes are left unsigned or given deliberately
  wrong ROAs to set up the not-found and invalid cases per scenario.
- Validation to the routers, enforcement toggled live. Routinator fetches Krill's
  publication point over RRDP, validates against the local TAL, and serves VRPs over
  RTR (TCP 3323 by default for Routinator). The `rpki` cache block stays resident in
  the transit configs, so VRPs are fetched continuously and `show rpki prefix` shows
  validation state whether or not enforcement is on: validation always computes
  validity, ROV is only the choice to act on it. The ROV route-map (drop or
  de-prefer invalids) is committed but bound to the eBGP neighbours only when ROV is
  on. `ctl rov on` binds it and does a soft inbound clear to re-evaluate; `ctl rov
  off` removes the binding and re-clears. No redeploy and no FRR restart, so a
  hijack can be watched winning and then dropped the moment ROV flips on.
- IRR (phase two). IRRd holds route objects; bgpq4 builds prefix filters from them
  on the transits, and the legitimacy-subversion technique works by laundering
  clean IRR objects ahead of an announcement.

Build dependency, confirmed: the upstream FRR 9.1.0 image already ships RPKI
support, so no rebuild is needed. It carries `bgpd_rpki.so` and librtr (rtrlib
0.8), and bgpd is built `--enable-rpki`. Enabling it is a config step, not an image
change: bgpd loads the module with `-M rpki` (in the daemons file or bgpd_options).
The image also ships `bgpd_bmp.so`, so FRR can emit BMP natively for the scorer milestone (M4) and heimdallr's cover
and multi-stage fixtures, without
necessarily adding GoBGP for it.

### Addressing (new)

A small services segment connects the registry nodes to the transits, for the RTR
session and the publication fetch. A /28 off the existing block (for example
10.0.0.32/28) carries registry-ca/rtr/irr, with the transits reaching Routinator's
RTR. Exact addresses are a build detail; the registry nodes carry no ASN.

### Files

To create:

- `clab/registry/` build/config for Krill, Routinator and IRRd.
- per-node config: Krill CA, trust anchor and ROA set; Routinator TAL pointing at
  Krill plus its RTR config; the IRRd database seed.
- per-scenario ROA/ROV overlays: which prefixes are signed, with which ROAs, and
  whether ROV is on.

To modify:

- `clab/inter-domain.clab.yml`: add registry-ca, registry-rtr, registry-irr (labels
  per section 16) and the services-segment links.
- `configs/transit-a.conf`, `transit-b.conf`: a resident `rpki` cache block pointing
  at Routinator (VRPs always fetched), plus a committed ROV route-map that is bound
  to the eBGP neighbours only when ROV is on (off by default).
- `ctl`: bring the registry nodes up; `rov on` / `rov off` to bind and unbind the
  ROV route-map live with a soft inbound clear (no restart), and a knob to load a
  scenario's ROA set.

### Telemetry for detection practice (the heimdallr export)

This zone is the source of the RPKI and trust-signal telemetry heimdallr's routing
correlation practises against, so it is built to emit, as capturable files:

- Routinator's validation logs: VRP changes and validation-state transitions
  (valid, invalid, not-found).
- Krill's ROA-change records: ROA creation, modification and expiry, the
  arming-phase signal the ROA-poisoning pattern keys off.

With these alone heimdallr can practise the ROA-poisoning correlation, since the
arming phase needs only RPKI logs. The RPKI-cover and multi-stage patterns also
need BMP routing events, which arrive with the scorer milestone (M4), so this
zone unblocks the ROA-poisoning fixture now and the cover and multi-stage fixtures
complete once the scorer lands. These raw telemetry files are the heimdallr export, the
observations a detector ingests. The scorer's timeline (section 18) is inter-domain's own
scoring record and is not part of the export. Commit one known-good export per scenario,
per section 8.

### Verification

1. Krill up with a lab TA; ROAs created for the FungusFiber and FDEI prefixes;
   Routinator validates them via the local TAL and serves VRPs over RTR.
2. transit-a and transit-b receive VRPs (`show rpki cache`, `show rpki prefix`).
   With ROV off, behaviour is unchanged from today.
3. Enable ROV on the transits: the false-origin /25 hijack of a ROA-covered prefix
   now validates as invalid and is dropped or de-preferred, so the hijack fails and
   the defence holds.
4. ROA poisoning: alter or withdraw the victim's ROA so the bogus origin validates
   or the prefix goes not-found, and the hijack succeeds again under cover.
   Routinator logs the state transition; Krill logs the ROA change.
5. The telemetry above exports as files; commit one known-good export per scenario.
6. Phase two: IRRd holds route objects; bgpq4 builds a prefix filter on a transit;
   the legitimacy-subversion technique announces under a laundered-clean IRR object.

### Out of scope and open questions

- RESOLVED: FRR RPKI support is present in the upstream 9.1.0 image (bgpd_rpki.so
  plus librtr, built --enable-rpki). ROV needs only the module loaded (`-M rpki`),
  no image rebuild.
- Delegated CA hierarchy: whether FungusFiber (the LIR) gets a child CA under FMDA's
  trust anchor, or all ROAs issue from the one FMDA CA. One CA is enough for the
  milestone; a delegated child CA is a later realism upgrade.
- When phase two (IRR) lands: with the legitimacy-subversion scenario, or earlier if
  prefix filters are wanted sooner.
- Exact RTR port and the services-segment addressing, both build details.

### Built and validated (RPKI phase)

The RPKI phase is built and validated end to end; IRR stays phase two. The tree:
`clab/registry/krill/` (Krill testbed CA plus an rsyncd) and
`clab/registry/routinator/`; the `registry-ca`, `registry-rtr` nodes and the
`idsl_services` /28 in the topology; `-M rpki` in `configs/daemons`; an `rpki
cache 10.0.0.34 3323` block and the `RM-ROV-IN` route-map on both transits; and
`ctl` gains `rpki`, `rpki-init`, `rov on|off`, `roa poison|restore` and
`rpki-export`. The Krill admin token and the TAL/cert share live under `access/`
(gitignored).

One design point took real digging, worth recording because the first answer was
wrong. The plan assumed RRDP (HTTPS), and an early build fell back to rsync on the
belief that Routinator 0.15.2 simply would not retrieve over Krill's self-signed
HTTPS. A later spike found the real story has two layered blockers, neither of them
about trusting the cert. First, Routinator refuses RRDP to a "dubious" host by
default, and fmda-ca.lab resolving to 10.0.0.33 (RFC1918) is one, so it skipped the
fetch entirely (that is the "does not even attempt" symptom, a host-policy rejection
no amount of trust config can fix); `allow-dubious-hosts` clears it. Second,
rustls/webpki will not accept a self-signed certificate that doubles as the server
leaf, where curl and OpenSSL happily do, so Krill now mints a proper chain: a local
self-signed FMDA Lab Root CA signs a separate fmda-ca.lab leaf, Krill serves the
leaf, and Routinator trusts the root via `rrdp-root-certs` (the leaf also carries a
serverAuth EKU). With both in place, validation runs over native RRDP/HTTPS,
repository and trust-anchor cert alike, the way a production relying party does. The
rsyncd stays as the fallback transport, so VRPs load even if RRDP is unavailable.
Onboarding is done with local krillc (`children add` under the testbed TA,
`pubserver publishers add`), not the testbed HTTP endpoints, and the lab stays
self-contained: a local root CA and Krill's own testbed trust anchor, no public CA
and no internet. The note that `rrdp-root-certs` "did not help" earlier was the
dubious-host policy blocking the fetch before trust ever entered into it.

Two operational facts the deploy flow handles. FRR does not retry the RTR session
hard if the cache was unreachable when bgpd loaded the rpki config, which it is on
a fresh deploy before Routinator is serving, so `ctl up` waits for VRPs then does
`rpki reset` on the transits. Routinator's default refresh is slow (ten minutes),
so the config lowers `refresh` to 30 seconds for an unattended cadence that suits a
lab, and `ctl roa` additionally nudges it with SIGUSR1 and
waits for its VRP count to change before re-pulling routes on the transits, so a
deliberate ROA change takes effect in seconds rather than waiting on any loop.

Validated on the live lab: both transits hold an RTR session and receive the three
FMDA VRPs; with ROV off the attacker's 203.0.113.0/25 wins (baseline unchanged);
`ctl rov on` makes it RPKI-invalid and drops it, so FDEI's /24 wins and the hijack
fails; `ctl roa poison` withdraws FDEI's ROA, the /25 goes not-found and the hijack
succeeds again under cover; `ctl roa restore` closes it. A standing caution, also in
the operator notes: never restart a containerlab node or its in-container FRR (it
drops the clab veths and strands the data plane); apply config changes with a clean
`./ctl down && ./ctl up`.

## 18. Scorer (M4): watching, normalising and emitting the timeline

The scorer is M4, the observer's analytical layer. The observer (AS65000) already
receives both transit tables and announces nothing; the scorer reads what it sees,
turns it into one fresh event stream, checks the scenario's flag, and writes the
timeline artefact heimdallr practises against. It is the scoring half of the CTF
spine and the main place the telemetry exports crystallise (section 8, and the
at-a-glance list).

### Decisions

- Event source: poll first, BMP next. Increment 1 polls the observer's
  `show ip bgp json` and diffs successive snapshots into events, enough for
  propagation scoring and a coarse timeline. Increment 2 adds the native BMP feed
  (FRR ships `bgpd_bmp.so`, confirmed in section 17) for the real-time,
  exact-timing event stream heimdallr's cover and multi-stage fixtures need. Poll
  reaches a working scorer fast; BMP is de-risked separately.
- Host-side Python, no new image. `scorer/scorer.py`, the same pattern as the seed's
  `filter.py`, driven by `ctl score [scenario]`. Nothing new built into a container
  image.
- Flag from structured fields, not prose. The scenario's `target:` block already
  carries `hijack_prefix`, `hijack_origin` and the legitimate origin and prefix, so
  the scorer evaluates the flag from those rather than parsing the prose
  `flag_condition.check`.

### What the scorer does

Three jobs, in one loop:

- Watch. Poll the observer's table (increment 2: consume its BMP feed).
- Normalise. Turn the raw collector output into one event envelope, designed fresh
  around what the observer actually emits, not red-lantern-sim's schema.
- Score and emit. Evaluate the flag from the scenario's `target:` block, print a
  live scoreboard, and write a JSON timeline artefact.

### Event envelope

One shape for every event, fresh around the collector output:

```
{"ts":"...Z","scenario":"false-origin-prefix-hijack","source":"collector:observer",
 "type":"announce|withdraw|origin-change|more-specific|rpki-state",
 "prefix":"203.0.113.0/25","origin_as":65020,"as_path":[65002,65020],"rpki":"invalid"}
```

The `rpki` field is annotated from the validator (section 17), so an event carries
both the routing fact and its validation state, which is what the ROA-poisoning and
RPKI-cover correlations key off downstream.

### Artefacts and the heimdallr export

The heimdallr export is raw telemetry only, the observations a real monitor receives:
the BMP event stream (announce/withdraw with prefix, origin and AS_PATH, the
exact-timing `events.jsonl` from the collector), the RPKI validator log (per-route
validity), the VRP set, and the ROA-change records. heimdallr derives more-specific,
MOAS and the campaign shape from these against its own baseline.

What does not cross is the scorer's `timeline.json`. It carries the derived answers
(`more_specific`, `moas`, the flag) because the scorer computed them, so shipping it to a
detector would be detecting on the answer key, the red-lantern-sim mistake. The timeline
is inter-domain's own scoring record and stays here; heimdallr judges its detections
against the scenario brief, not against the scorer's output.

So the hand-off is a file copy of the raw telemetry into heimdallr's `ingest/`. Commit
one known-good raw-telemetry bundle per scenario (section 8).

Built and verified (2026-06-16): the three scenarios were played live and their raw
bundles committed under `artefacts/<scenario>/` (events.jsonl, routinator.log,
vrps.json, roa-history.txt). Confirmed observations-only, no `timeline.json` in any
bundle, no derived fields, and provenance from the live BMP collector (the
80,036-event roa-poisoning re-convergence flood, BMP pre and post-policy tags, the
observer AS at the path head). Ready for heimdallr's ingest.

### Files

To create:

- `scorer/scorer.py`: the poll, diff, normalise and score loop (the `filter.py`
  pattern).
- `scorer/README.md`: how to run it, the envelope, the artefact layout.
- `artefacts/<scenario>/`: the committed raw-telemetry bundle, observations only:
  `events.jsonl` from the collector, the validator log, the VRP set, the ROA-change
  records. The scorer's `timeline.json` is the lab's own scoring record and lives
  under `scoring/`, never in the bundle.

To modify:

- `ctl`: a `score [scenario]` command that runs the scorer against the observer and
  writes the timeline.

Increment 2 adds the BMP feed as a container collector: a `bmp-collector` node on a
/30 to the observer (a normal lab link, not a host bridge). The observer's FRR loads
`bgpd_bmp.so` (`-M bmp` in `configs/daemons`, alongside `-M rpki`) and a `bmp targets`
block in `observer.conf` connects out to the collector, monitoring ipv4-unicast pre
and post policy. The collector parses BMP route-monitoring messages (BMP framing to
the embedded BGP UPDATE to NLRI and withdrawals plus AS_PATH and origin) into the
same event envelope with the BMP timestamp, exact timing instead of the poll diff,
and writes it where the scorer reads it (`--source bmp`). The scorer stays host-side
stdlib; only the collector is a container, and the parser is the same code a
host-side listener would need, just sited on the network where a BMP station runs.

### Verification

1. `./ctl score false-origin-prefix-hijack` against the running lab prints a live
   scoreboard and, on the hijack, flags the win from the `target:` block.
2. The raw bundle is written to `artefacts/false-origin-prefix-hijack/` (events.jsonl
   plus the RPKI validator log, VRP set and ROA-change records); the scorer's timeline
   goes to `scoring/<scenario>/`, not the bundle.
3. The bundle copied into heimdallr's `ingest/` is read by its routing feeder into
   Wazuh, observations only, no derived fields.
4. With ROV toggled (section 17), the events carry the announcement and the validator's
   RPKI state, and ROA poisoning shows the prefix returning, so the same raw bundle
   exercises the ROA-poisoning detection.
5. Increment 2: the BMP feed records the same run with exact timing, and the cover
   and multi-stage fixtures use that stream.

### Out of scope and open questions

- Poll interval for increment 1 (the timeline granularity until BMP lands), a tuning
  detail.
- The flask frontend (M5) consumes the same scorer output as its live scoreboard;
  building it is M5, not here.
- RESOLVED: the BMP listener is a container collector (a `bmp-collector` node on a
  /30 to the observer), not a host-side process behind a bespoke bridge. BMP is a
  router-to-station protocol, so the station belongs on the network as a node, which
  is also the self-contained, production-shippable shape (no host bridge, no
  host-process dependency). The scorer stays host-side stdlib and reads the
  collector's output (`--source bmp`); only the collector is a container. The
  marginal cost over host-side is a Dockerfile, the parser being the same either way.
  The milestone-1 "no new image" ethos was a deployability convenience, not a
  production principle, and increment 2 is past it.

### Built and validated (M4 increment 1)

Increment 1 is built and validated; the BMP feed stays increment 2. The tree:
`scorer/scorer.py` (host-side, stdlib only, the `filter.py` pattern),
`scorer/README.md`, `ctl score [scenario]`, and the scorer's timeline at
`scoring/<scenario>/timeline.json` (the lab's scoring record, kept out of the
raw heimdallr bundle). The observer node is renamed from
`gamemaster` (the operator-facing handle; the MycoSec lore hostname is unchanged),
which is what the `gamemaster/` to `scorer/` move and the topology and ctl edits
carry.

The scorer polls the observer's `show ip bgp json`, diffs successive snapshots
into the event envelope (announce, more-specific, origin-change, withdraw, flag),
annotates each event's RPKI state by RFC 6811 against Routinator's VRPs, scores the
flag from the scenario's `target:` block, and writes the timeline on exit. The
validation logic (the validation states, the scenario reader, the diff) is
unit-tested off the lab in `tests/test_scorer.py`, stdlib `unittest`, no lab and
no docker, run with `python3 -m unittest discover -s tests`.

Validated on the live lab: with the false-origin hijack announced mid-run, the
scorer emitted `more-specific 203.0.113.0/25 origin 65020 rpki=invalid`, captured
the propagation flag, and wrote a well-formed `timeline.json` (under
`scoring/false-origin-prefix-hijack/`, the scoring record, not the raw bundle).
The `rpki: invalid` annotation is the
signal the ROA-poisoning correlation keys off; under `ctl rov on` / `roa poison`
the same prefix's state flips, exercising that fixture from one run.

One operational fix the rename surfaced: a renamed or removed node orphans its old
container, because `containerlab destroy` only knows the current topology's nodes,
and the orphan then blocks the next deploy ("lab already deployed"). `ctl down` now
reaps any container named for this lab after destroy, so topology drift self-heals.

### Built and validated (M4 increment 2)

The BMP feed is built and validated, so M4 is complete. The tree:
`clab/bmp/` (a thin Python `bmp-collector` node, `bmp_collector.py` is the
BMP/BGP-UPDATE parser), the node and the `observer eth3 <-> bmp-collector eth1`
/30 (`10.0.0.48/30`) in the topology, `-M bmp` in `configs/daemons`, a
`bmp targets` block in `observer.conf` monitoring ipv4-unicast pre and post
policy, and `scorer.py --source bmp` / `ctl score [scenario] [poll|bmp]`. The
collector writes the full event stream to `access/bmp/events.jsonl` (the raw
artefact, including the initial RIB dump, the exact-timing source for heimdallr's
cover and multi-stage fixtures); the scorer reads from the current end, so its
timeline is the post-start events, enriched and scored.

Validated live: the observer's FRR connects out to the collector and the BMP
session comes up (route-monitoring pre and post policy); the collector parses the
~40k-message initial dump plus updates, and `ctl score ... bmp` captured the
announced /25 as `announce 203.0.113.0/25 origin 65020 rpki=invalid (post)` with
the router-stamped timestamp, fired the flag, and wrote
`scoring/false-origin-prefix-hijack/timeline-bmp.json`. The poll timeline
(`timeline.json`) stays the increment-1 scoring record. Both live under
`scoring/`; the committed `artefacts/<scenario>/` bundle is raw observations only.

Two faithful-to-the-wire notes worth recording, since the event model is meant to
be what the collector actually emits. FRR's post-policy route-monitoring carries
the observer's own AS at the head of the AS_PATH (so `[65000, 65001, 65010]` for
FDEI's /24); the origin (the last ASN) and the prefix are unaffected, so scoring
is unaffected, and the path is recorded as sent rather than massaged. And FRR
stamps every message with the router clock to the second but reuses a fixed
microsecond value, so BMP timing is router-stamped second precision, still the
right source (when the router saw the route, not when a poll noticed), just not
sub-second.
