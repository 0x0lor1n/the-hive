#!/usr/bin/env python3
"""Send an unsolicited IPv6 Neighbour Advertisement for a local address.

Why this is needed here: the BNG resolves our global address by sending a
neighbour solicitation to its solicited-node MULTICAST address, and the WAS-110
delivers multicast still carrying the VLAN 30 tag. The host drops tagged frames,
never answers, and the BNG cannot deliver our IPv6. Announcing proactively
sidesteps the solicitation entirely.

Sends with the Override flag set, both unicast to the gateway (whose MAC we
know, and unicast arrives untagged) and to all-nodes multicast.

usage: salt-nd-announce.py <iface> <target-ipv6> [gateway-mac gateway-ll]
"""
import socket
import struct
import sys

IFACE = sys.argv[1]
TARGET = sys.argv[2]
GW_MAC = sys.argv[3] if len(sys.argv) > 4 else None
GW_LL = sys.argv[4] if len(sys.argv) > 4 else None


def csum(data: bytes) -> int:
    if len(data) % 2:
        data += b"\x00"
    s = 0
    for i in range(0, len(data), 2):
        s += (data[i] << 8) + data[i + 1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def build(src_ip: bytes, dst_ip: bytes, mac: bytes, target: bytes) -> bytes:
    # NA: type 136, code 0, cksum, flags, target, then TLLA option (type 2)
    flags = 0x20000000                      # Override
    body = struct.pack("!I", flags) + target
    body += struct.pack("!BB", 2, 1) + mac  # target link-layer address option
    icmp = struct.pack("!BBH", 136, 0, 0) + body
    pseudo = src_ip + dst_ip + struct.pack("!I", len(icmp)) + b"\x00" * 3 + b"\x3a"
    c = csum(pseudo + icmp)
    icmp = struct.pack("!BBH", 136, 0, c) + body
    ipv6 = struct.pack("!IHBB", 0x60000000, len(icmp), 58, 255) + src_ip + dst_ip
    return ipv6 + icmp


s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
s.bind((IFACE, 0))
mac = s.getsockname()[4][:6]
target = socket.inet_pton(socket.AF_INET6, TARGET)

dests = [("all-nodes multicast",
          b"\x33\x33\x00\x00\x00\x01",
          socket.inet_pton(socket.AF_INET6, "ff02::1"))]
if GW_MAC:
    dests.append(("gateway unicast",
                  bytes.fromhex(GW_MAC.replace(":", "")),
                  socket.inet_pton(socket.AF_INET6, GW_LL)))

for label, eth_dst, dst_ip in dests:
    pkt = build(target, dst_ip, mac, target)
    s.send(eth_dst + mac + b"\x86\xdd" + pkt)
    print(f"NA for {TARGET} -> {label}")
s.close()
