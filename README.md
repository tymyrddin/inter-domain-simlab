# Inter-domain SimLab

A containerlab-based inter-domain routing range. A live BGP fabric of transit
providers, customer ASes and a passive collector, where an attacker with a
foothold AS practises prefix hijacks, route leaks and RPKI abuse as a free-roam
CTF. Consequences emerge from what the player actually announces.

This is the routing counterpart to the OT estate in `ics-access-simlab`. Where
that lab models a utility's IT/OT boundary, this one models the public routing
commons: the global table, the relationships between autonomous systems, and the
trust those relationships quietly assume.

## Status

First milestone: a deployable all-FRR core (two transit ASes, a victim AS, an
attacker AS and a gamemaster collector) plus two host containers, and the first
scenario (false-origin prefix hijack). The registry plane (RPKI/IRR) and an IXP
route server are documented in `docs/design.md` as the next zones, not yet built.

The core deploys cleanly and has been validated on containerlab 0.75: BGP
converges, the gamemaster receives both tables while announcing nothing, and the
first scenario diverts live traffic. The registry plane and IXP are still notes,
not containers.

## Layout

```
clab/                 containerlab topology files
configs/              per-node router configs (FRR) and host content
scenarios/            one folder per attack technique (briefing, attack, solution)
gamemaster/           collector and scoring notes (flask frontend planned)
seeds/                real MRT route dumps and RPKI/IRR seed data (planned)
docs/                 design and architecture
ctl                   wrapper: up / down / looking glass / shell
```

## Dependencies

Linux only, Docker's fixed-IP bridge networking needs a real Linux host, not Docker Desktop.

| Dependency   | Notes                                                        |
|--------------|--------------------------------------------------------------|
| Linux        | kernel 5.x+                                                  |
| Docker       | Engine 24+ (not Docker Desktop)                              |
| containerlab | 0.50+ (`bash -c "$(curl -sL https://get.containerlab.dev)"`) |
| sudo         | containerlab needs CAP_NET_ADMIN to create host bridges      |

## Quickstart

```bash
./ctl up                # deploy the lab (prompts sudo for host bridges)
./ctl table             # the global table as the gamemaster sees it
./ctl lg                # same, as JSON for tooling
./ctl vtysh attacker-as # drive BGP in the attacker foothold
./ctl ssh attacker-as   # a plain shell on any node instead
./ctl down              # tear it down
```

## Walking the first scenario: false-origin hijack

The attacker AS boots clean. Launching the hijack is your job, which is the
point of a free-roam range: the table only lies once you make it.

1. Look at the baseline from the collector. The victim's /24 is there, originated
   by AS65010, and there is no more-specific yet:

   ```bash
   ./ctl table
   ```

2. Drop into the foothold and announce a more-specific of the victim's prefix.
   The /25 is not connected on your router, so a discard route puts it in the RIB
   for BGP to advertise:

   ```bash
   ./ctl vtysh attacker-as
   ```
   ```
   configure terminal
    ip route 203.0.113.0/25 Null0
    router bgp 65020
     address-family ipv4 unicast
      network 203.0.113.0/25
   end
   ```

3. Watch it propagate. The collector now lists the /25 with your AS (65020) as
   origin, and even transit-a, the victim's own upstream, prefers it over the
   legitimate /24 by longest-prefix match:

   ```bash
   ./ctl lg                                                    # 203.0.113.0/25, path ...65020
   docker exec clab-inter-domain-transit-a vtysh -c 'show ip bgp'
   ```

4. See the traffic bend. Everything for 203.0.113.0 to .127 now heads to you
   rather than the victim:

   ```bash
   docker exec -it clab-inter-domain-eyeball traceroute -n 203.0.113.10
   ```

   The path turns toward transit-b and the attacker. With the Null0 route in place
   the packets stop there, so this run both diverts and denies the victim's
   service. Swap the discard for a real next hop to forward and intercept instead.

Reset when you are done, either by withdrawing the route or by recycling the lab:

```bash
./ctl vtysh attacker-as     # configure terminal, then under router bgp 65020:
                            #   no network 203.0.113.0/25
                            # then at top level: no ip route 203.0.113.0/25 Null0
./ctl down && ./ctl up      # or just take the clean table back
```

The full briefing and reference solution live in
`scenarios/false-origin-prefix-hijack/`.

## The topology (milestone 1)

Five FRR routers and two hosts. Private ASNs (64512 to 65534), documentation
prefixes (TEST-NET), and no internet egress, so the lab stays contained.

| Node        | ASN   | Role                                              |
|-------------|-------|---------------------------------------------------|
| transit-a   | 65001 | transit provider, peers with transit-b            |
| transit-b   | 65002 | transit provider, peers with transit-a            |
| victim-as   | 65010 | customer of transit-a, owns 203.0.113.0/24        |
| attacker-as | 65020 | customer of transit-b, the player's foothold      |
| gamemaster  | 65000 | passive collector, peers both transits, read-only |
| web         | n/a   | victim service behind 203.0.113.0/24              |
| eyeball     | n/a   | client generating traffic toward the victim       |

Relationships: the two transits peer settlement-free; victim and attacker are
each a customer of a different transit; the gamemaster receives both tables but
announces nothing. Filtering and origin validation are deliberately loose, which
is what the attacks exploit.

## See also

- `scenarios/` for the techniques drawn from Operation Red Lantern.
