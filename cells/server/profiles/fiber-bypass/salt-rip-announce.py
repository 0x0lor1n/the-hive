#!/usr/bin/env python3
"""Send a RIPv2 Response announcing our routes to the BNG.

This is the mechanism the Fiber Box uses to register the public /32 with
the BNG's source-guard ACL. Without it, the BNG only accepts the alias
address as a source and egress goes through CGNAT.

Discovered by capturing the Fiber Box's WAN traffic through a DAC cable
to enp1s0f1: it sends RIPv2 Responses to 224.0.0.9:520 every ~30s from
the alias address, announcing both the alias /20 and the public /32 with
metric 1 and next-hop self.

usage: salt-rip-announce.py <iface> <alias-ip> <public-ip> <alias-net> <alias-mask>
"""
import socket
import struct
import sys

IFACE = sys.argv[1]
ALIAS_IP = sys.argv[2]
PUBLIC_IP = sys.argv[3]
ALIAS_NET = sys.argv[4]
ALIAS_MASK = sys.argv[5]

DST = "224.0.0.9"
PORT = 520

header = struct.pack("!BBH", 2, 2, 0)

route1 = struct.pack("!HH4s4s4sI",
    2, 0,
    socket.inet_aton(ALIAS_NET),
    socket.inet_aton(ALIAS_MASK),
    socket.inet_aton("0.0.0.0"),
    1)

route2 = struct.pack("!HH4s4s4sI",
    2, 0,
    socket.inet_aton(PUBLIC_IP),
    socket.inet_aton("255.255.255.255"),
    socket.inet_aton("0.0.0.0"),
    1)

payload = header + route1 + route2

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, IFACE.encode() + b"\0")
s.bind((ALIAS_IP, PORT))
mreq = socket.inet_aton(DST) + socket.inet_aton(ALIAS_IP)
s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
s.sendto(payload, (DST, PORT))
print(f"RIPv2: {ALIAS_NET} + {PUBLIC_IP}/32 -> {DST}")
s.close()
