# 2026-10-13 01:27:17 by RouterOS 7.24.2
# software id = TQJX-8F0P
#
# model = CRS309-1G-8S+
# serial number = REDACTED
/interface bridge
add name=bridge1 protocol-mode=none vlan-filtering=yes
/interface bonding
add mode=802.3ad name=bond1 slaves=sfp-sfpplus7,sfp-sfpplus8 \
    transmit-hash-policy=layer-3-and-4
add mode=802.3ad name=bond2 slaves=sfp-sfpplus1,sfp-sfpplus2 \
    transmit-hash-policy=layer-3-and-4
add mode=802.3ad name=bond3 slaves=sfp-sfpplus3,sfp-sfpplus4 \
    transmit-hash-policy=layer-3-and-4
/interface list
add name=WAN
add name=LAN
/interface bridge port
add bridge=bridge1 interface=ether1
add bridge=bridge1 interface=bond1
add bridge=bridge1 interface=bond2
add bridge=bridge1 interface=bond3
/ip neighbor discovery-settings
set discover-interface-list=all
/interface bridge vlan
add bridge=bridge1 tagged=bond1,bond2,bond3 vlan-ids=10
add bridge=bridge1 tagged=bond1,bond2,bond3 vlan-ids=20
add bridge=bridge1 tagged=bond1,bond2,bond3 vlan-ids=30
add bridge=bridge1 tagged=bond1,bond2,bond3 vlan-ids=40
add bridge=bridge1 tagged=bond1,bond2,bond3 vlan-ids=50
add bridge=bridge1 tagged=bond1,bond2,bond3 vlan-ids=60
add bridge=bridge1 tagged=bond1,bond2,bond3 vlan-ids=70
add bridge=bridge1 tagged=bond1,bond2,bond3 vlan-ids=80
add bridge=bridge1 tagged=bond3,bond2,bond1 vlan-ids=90
add bridge=bridge1 tagged=bond1,bond2,bond3 vlan-ids=110
/interface list member
add interface=ether1 list=WAN
add interface=sfp-sfpplus1 list=LAN
add interface=sfp-sfpplus2 list=LAN
add interface=sfp-sfpplus3 list=LAN
add interface=sfp-sfpplus4 list=LAN
add interface=sfp-sfpplus5 list=LAN
add interface=sfp-sfpplus6 list=LAN
add interface=sfp-sfpplus7 list=LAN
add interface=sfp-sfpplus8 list=LAN
/interface ovpn-server server
add mac-address=REDACTED name=ovpn-server1
/ip address
add address=192.168.1.2/24 interface=sfp-sfpplus1 network=192.168.1.0
/ip dns
set servers=192.168.1.1
/ip hotspot profile
set [ find default=yes ] html-directory=hotspot
/ip ipsec profile
set [ find default=yes ] dpd-interval=2m dpd-maximum-failures=5
/ip route
add gateway=192.168.1.1
/system clock
set time-zone-name=America/Chicago
/system routerboard settings
set enter-setup-on=delete-key
