+++
title = "Replacing a Swiss ISP's Fiber Box: XGS-PON Bypass on NixOS, From Zero to RIPv2"
date = 2026-09-13
description = "Putting Salt's Fiber Box X6 in a drawer: cloning the ONU onto a WAS-110, and the RIPv2 announcement that turned out to gate the static IP. All in one NixOS config."

[taxonomies]
tags = ["nixos", "networking", "fiber", "security"]
+++
## Act 1 — Why replace the box

My ISP's router is unplugged in a drawer. My static IP works as a source address, native IPv6 is routed straight to the LAN with no NAT, and the whole thing runs from one NixOS config. The part that took weeks to figure out turned out to be a routing protocol from 1998.

Here's how it got there.

Salt (formerly Orange) ships every fiber subscriber in Switzerland a Sagemcom F5688 "Fiber Box X6." It does routing, Wi-Fi, VoIP, and firewalling. The web UI lets you change the Wi-Fi password and set up port forwarding. That's about it.

Now, if you just want internet that works, the box is fine. But I work in security, and running a closed-source firmware as my network perimeter makes me uncomfortable. I can't inspect the firewall rules the box applies. I can't run an IDS/IPS. I can't deploy honeypots or do any traffic analysis beyond what the box decides to show me. When something breaks at 2 AM, I get a blinking LED, not `tcpdump` and `journalctl`.

There's also a throughput argument. The box has a 10 Gbps XGS-PON uplink and a 10G RJ45 LAN port, so the hardware can theoretically move data. But the LAN copper ports are 2.5 Gbps, so you're capped at about a quarter of the line. Not a dealbreaker on its own, but it adds up.

One thing worth mentioning: Switzerland has no Routerfreiheit. Germany passed their Endgerätefreiheit in 2016, giving subscribers the right to use their own equipment. Nothing equivalent exists here. Salt's ToS doesn't explicitly forbid third-party gear, but doesn't support it either. You're on your own, and if you break something, that's your problem.

So the plan was: connect directly to Salt's XGS-PON OLT, run everything in NixOS, and put the Fiber Box in a drawer. Easier said than done, as it turned out.

<figure>
<img src="/diagrams/01-before.svg" alt="The stock setup: Salt OLT over fiber into the Sagemcom Fiber Box, which does routing, Wi-Fi, VoIP and firewalling behind closed firmware, out to LAN clients over 2.5G copper.">
<figcaption>The stock setup. Everything grey is the ISP's, and none of it is inspectable.</figcaption>
</figure>


## Act 2 — The hardware, and cutting the cord

### Why the CWWK S8 (Intel N305)

I spent a while looking for hardware and honestly couldn't find a better fit than the CWWK S8. It's the box the home router community has more or less settled on for x86 builds, and looking at the specs it's easy to see why:

- 2x SFP+ 10G cages on an Intel 82599ES (ixgbe), sitting directly on the PCIe bus. One for the ONU stick, one spare. No dongles, no adapters.
- 2x RJ45 2.5G Intel i226-V copper ports. One goes to an access point, the other to a wired device. That's a bridged LAN sorted.
- Aluminium case that works as a heatsink, with a single small fan in the center of the radiator. The N305 has a 15W TDP, so thermals aren't dramatic.
- TPM on board.
- Removable DDR5 (16 GB for now) and two M.2 slots: a 2280 holding a 1 TB NVMe, and a 2230 with 256 GB. You could put a Wi-Fi card in the 2230 slot, but I'd rather have extra storage.
- x86, so it runs NixOS. The entire system lives in one `configuration.nix`. A bad change is one `nixos-rebuild switch --rollback` away from undone.

I originally wanted the N355, but it was already out of stock due to chip shortages when I was buying. The N305 has enough headroom for a firewall plus Suricata, which was the plan from the start.

Sourcing it was its own small adventure. I found the S8 on Amazon, but it was out of stock. So I tracked down the warehouse on Alibaba, talked to them on the platform, and they arranged the purchase through Amazon for me. If you know, you know — routing an Alibaba order through Amazon gets you Amazon's returns and buyer protection on a box you'd otherwise be buying direct from a Shenzhen warehouse. The RAM I got separately on [ricardo.ch](https://www.ricardo.ch/) (the Swiss eBay); a couple of days of watching listings and a good DDR5 deal came up.

<!-- [PHOTO: the CWWK box with its top removed, showing the SFP+ cages and the WAS-110 stick inserted] -->

The ONU stick I bought is a Yunvo 10G SFP+ 1270/1577nm 20km SC/APC/UPC, pre-flashed with 8311 community firmware. Fair warning: it runs hot. Out of the box, idle temperature sits around 63 C. Inside the CWWK's aluminium case it crept up to 65 C. I stuck a small copper heatsink on it and that brought it down to about 55 C, which I can live with.

> **Tip:** Alibaba stick vendors talk to you over WhatsApp, not the platform. Before you pay, ask them for the stick's root password — it's often a per-batch value, and you will want a shell on the stick later. Get it in writing while they're still motivated to close the sale.

<!-- [PHOTO: the ONU stick with the copper heatsink attached] -->

### LiveUSB: the first boot

The CWWK arrived bare. No OS, nothing on the drives. I plugged in a NixOS LiveUSB alongside a monitor and keyboard.

> **Tip:** Ventoy with a NixOS ISO is great for this. One USB stick, multiple ISOs, no re-flashing when you want to try something else.

The LiveUSB had one job: prove that IPv6 works through the stick before committing to a full install. IPv6 is the easiest canary on Salt's network. It's statically configured (no DHCP, no PD, just a `/64` routed to the subscriber with `::1` as the next hop), so if the ONU identity is correct and the VEIP is working, IPv6 comes up with nothing more than the right addresses and a gateway.

`curl -6 https://ifconfig.co` returned the expected public address. Good. The fiber was alive.

### Flashing NixOS and going headless

With IPv6 confirmed, NixOS went onto the NVMe. The first real configuration included everything I needed to never plug in a monitor again.

**Yggdrasil** is an encrypted IPv6 mesh network. Every node gets a stable `200::/7` address derived from its cryptographic key. The router dials out to public peers in Germany and France (the published Swiss peer list is empty), and from that point it's reachable from any other Yggdrasil node on the planet. SSH is open on the `ygg0` interface only, never on the WAN.

**mosh** runs over UDP and predicts local echo, so typing feels instant even at 400 ms RTT through volunteer relay nodes. It survives suspend, roaming, and network changes that kill SSH sessions. Also scoped to `ygg0`, ports 60000-61000.

**USB tethering** is the actual lifeline, and the one I didn't appreciate enough until I needed it. When you pull the fiber out of the stick to experiment, the WAN dies. Yggdrasil goes down with it. SSH goes down with it. You're locked out of a headless box in another room.

The solution: plug in an Android phone with USB tethering enabled. It shows up as a `cdc_ncm` or `rndis_host` device. The trick is to match it by driver, not by interface name, because USB NICs get path-derived names like `enp0s20f0u6` that change depending on which physical USB port you use:

```nix
systemd.network.networks."40-tether" = {
  matchConfig = {
    Driver = [ "rndis_host" "cdc_ether" "cdc_ncm" "cdc_mbim" ];
    Type = "ether";
  };
  networkConfig.DHCP = "yes";
  dhcpV4Config.RouteMetric = 2048;
  ipv6AcceptRAConfig.RouteMetric = 2048;
  linkConfig.RequiredForOnline = false;
};
```

The `RouteMetric` is what makes this coexist peacefully with the primary WAN:

| Path | Metric | When it wins |
|---|---|---|
| WAN via the stick | 100 | Normal operation |
| Phone USB tether | 2048 | Fiber disconnected |

With metric 2048, the tether route only activates when the stick's metric-100 route is gone. Plug in the phone, pull the fiber, and within seconds Yggdrasil re-routes through mobile data. SSH stays up. I can experiment on the fiber path without losing access.

<figure>
<img src="/diagrams/03-tether.svg" alt="Failover topology: the router reaches the internet via the WAS-110 (metric 100) or an Android USB tether (metric 2048); both reach a Yggdrasil mesh that keeps SSH and mosh reachable regardless of which path is live.">
<figcaption>The lifeline. Pull the fiber and the metric-2048 tether takes over; Yggdrasil keeps the box reachable either way.</figcaption>
</figure>

After this was verified, the monitor and keyboard came off. They never went back.


## Act 3 — Cloning the ONU identity

### What the OLT expects

Salt runs a Nokia OLT (`ALCL`). It provisions services to a specific ONU identity: serial number, vendor ID, equipment ID, and software version. If any of these don't match what the OLT expects, the ONU registers on the PON but services never bind. You get a Layer 1 link and nothing else.

The 8311 firmware stores these as U-Boot environment variables:

```sh
fw_setenv 8311_gpon_sn      "<YOUR_SERIAL>"
fw_setenv 8311_vendor_id    "<YOUR_VENDOR>"
fw_setenv 8311_equipment_id "<YOUR_EQUIP_ID>"
fw_setenv 8311_hw_ver       "<YOUR_HW_VER>"
fw_setenv 8311_sw_verA      "<YOUR_SW_VER>"
fw_setenv 8311_sw_verB      "<YOUR_SW_VER>"
fw_setenv 8311_cp_hw_ver_sync 1
fw_setenv 8311_mib_file     prx300_1V.ini
fw_setenv 8311_internet_vlan 0
fw_setenv 8311_fix_vlans    1
fw_setenv 8311_iphost_mac   "<YOUR_WAN_MAC>"
```

One thing that will cost you hours if you miss it: `prx300_1V.ini`, not the default `prx300_1U.ini`. Salt provisions to a VEIP (Virtual Ethernet Interface Point), not a physical UNI. With the wrong MIB file, the OLT sees the ONU but can't bind any service to it. And there's a trap: saving anything in the 8311 LuCI page rewrites `8311_mib_file` back to `1U` silently. Don't touch that page after initial setup.

The basic bypass procedure (flashing 8311 firmware, setting U-Boot variables, verifying O5 state) is already documented on [pon.wiki](https://pon.wiki/guides/masquerade-as-the-salt-mobile-sa-fiber-box-x6-with-the-was-110/). This writeup picks up where that guide leaves off: you followed the instructions, your stick registers on the PON, IPv6 works, and then you discover your static IP doesn't.

### Extracting the values from the Fiber Box

The box doesn't expose ONU parameters in its web UI. They sit in the internal data model, behind the undocumented `/cgi/json-req` API. But the web UI itself uses that same API, which means the browser console works as an extraction tool.

There's a JavaScript object called `$.xmo` that queries the data model. Open the console while logged into the admin page:

```javascript
// All IP interfaces -- this is where the dual-address setup shows up
$.xmo.getValuesTree("Device/IP/Interfaces")

// ONU serial and vendor info
$.xmo.getValuesTree("Device/DeviceInfo")

// Routing table -- shows the gateway
$.xmo.getValuesTree("Device/Routing/Routers")

// DHCP client state on all VLANs
$.xmo.getValuesTree("Device/DHCPv4/Clients")

// VLAN terminations -- shows VLANs 30, 40, 69
$.xmo.getValuesTree("Device/Ethernet/VLANTerminations")
```

This is how every value in my NixOS config was found: the WAN MAC (which is different from the label MAC printed on the bottom of the box), the dual IPv4 addressing (public `/32` plus private `/20` alias), the VLAN IDs, the gateway addresses, the DNS servers. If you use the label MAC instead of the WAN MAC, the OLT won't recognise you.


## Act 4 — The IPv4 mystery

### Two addresses, one problem

With the ONU identity cloned and `prx300_1V.ini` loaded, the stick registered on the PON (O5 state) and services bound. IPv6 worked immediately. IPv4 didn't.

The `$.xmo` extraction had turned up something I didn't expect: the Fiber Box doesn't have one IPv4 address on the WAN. It has two, on the same VLAN:

| Interface | Address | Role |
|---|---|---|
| `IP_DATA` | `<YOUR_PUBLIC_IP>/32` | Public static IP |
| `IP_ALIAS` | `<YOUR_ALIAS_IP>/20` | Private, makes the gateway ARP-reachable |

The public `/32` was routed to us. I could see inbound packets arriving at the WAN interface with `tcpdump`. But using it as a source address? Impossible. Every outbound SYN left the interface and nothing came back. Not a timeout, not a RST. Zero response, every time.

Using the alias address as source worked, but through CGNAT. The egress IP showed up as `213.55.x.x`, a different Salt NAT pool address each time:

```
# Source: public /32 -> hangs forever
curl -4 --interface <YOUR_PUBLIC_IP> https://ifconfig.co

# Source: alias -> works, but CGNAT'd
curl -4 --interface <YOUR_ALIAS_IP> https://ifconfig.co
# 213.55.247.235
```

So the static IP existed and was routed to us, but the BNG's source-guard rejected it as an outbound source. Useless in both directions.

### Everything that didn't work

I tried everything I could think of, and quite a few things other people suggested. None of it worked:

**Gratuitous ARP** for the `/32` (both opcode 1 and 2). No effect. The source-guard is not ARP-learned.

**Equipment ID change** to match the stick's native identifier. The ONU re-registered fine (O5 state), but egress was still CGNAT. No effect on source-guard.

**Changing the subnet mask** from `/20` to `/22`, based on another Salt user's reported configuration on the Digitec forum. This broke IPv4 entirely. The gateway stopped answering ARP. I rolled back with `networkctl reconfigure`.

**MAP-E** (RFC 7597). I looked into it after a ChatGPT conversation suggested it might be relevant. It's not used by Salt. Their architecture is classical CGNAT with per-subscriber allocation on the BNG.

**DHCP on VLAN 30** with the box's identity (`option 60 = "sagem"`, `option 61 = WAN MAC`). Two DISCOVERs sent, zero inbound frames. Salt runs no DHCP server on the data VLAN. The box's own DHCP client on this VLAN sits permanently at `INIT`.

**VLAN 69 management session.** The theory was that the static IP's authorisation comes from a management DHCP session the box establishes on VLAN 69. I tested this end-to-end: the OLT provisions VLAN 69 to this ONU (OMCI MIB confirms gem1038, bridge port 57604), the tc filters are in place, and our frames leave the fiber (GEM counters increment). But `rx_frames=0`, always. Salt's management plane refuses to talk to this ONU. If the session can't be established, it can't be the authorisation mechanism.

**DHCPv6-PD.** Five solicits, zero replies. Salt doesn't delegate prefixes to third-party equipment.

At this point, every protocol reachable from the subscriber side had been tried. Something was writing an entry into the BNG's source-guard ACL, and none of my traffic was triggering it.

### The IPv6 ghost

A separate problem showed up during this period that I want to mention briefly because the fix ended up being relevant later. IPv6 would work, then silently die after about 20 minutes, while IPv4 (through CGNAT) kept going.

The cause turned out to be the BNG's IPv6 neighbour cache expiring. When it does, the BNG tries to re-resolve our address by sending an ICMPv6 Neighbour Solicitation to our solicited-node multicast address. The WAS-110 stick delivers this inbound multicast with the VLAN 30 tag still on it. The host drops tagged frames on an untagged interface. The solicitation never arrives, we never reply, and the BNG drops us.

IPv4 self-heals because we actively ARP for the gateway, and that teaches the BNG our MAC. IPv6 has no equivalent outbound trigger.

The fix: a systemd timer that sends an unsolicited Neighbour Advertisement every 30 seconds, before the cache can expire:

```nix
systemd.timers.salt-nd-announce = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnBootSec = "20s";
    OnUnitActiveSec = "30s";
  };
};
```

That fixed IPv6 reliability. The static IPv4 problem remained.


## Act 5 — The breakthrough

### Soldering iron on the table

By this point I had a soldering iron and an ESP-Prog programmer sitting on my desk. The Fiber Box's PCB has four UART pads in a row (I found them by looking up the QR code on the board: `800B090B2320`, which identifies the Sagemcom hardware revision). The plan was to solder on some headers, get a root shell through UART, and read the startup scripts to find whatever protocol I was missing.

I was buzzing out the pads with a multimeter when I looked over at the CWWK. The second SFP+ cage was sitting empty. The Fiber Box has a 10G SFP+ LAN port. And I happened to have a DAC cable in a drawer.

I put down the soldering iron.

### What if we just watched?

The idea was straightforward. We can't tap XGS-PON (it's point-to-point, 10 Gbps, AES-encrypted upstream). But we don't need fiber to see how the box behaves. A DAC cable (Direct Attach Copper) connects two SFP+ ports without optics, just twinax copper. Plug it between the CWWK's second SFP+ cage (`enp1s0f1`) and the box's 10G LAN port, power on the box without fiber, and the box boots up normally. It thinks it's talking to a LAN client. Every frame it sends is capturable.

No soldering required.

<figure>
<img src="/diagrams/04-dac.svg" alt="The DAC tap: a twinax DAC cable joins the Fiber Box's 10G LAN port to the CWWK's second SFP+ cage (enp1s0f1). With no fiber attached the box boots and talks to what it thinks is a LAN client, and tcpdump on enp1s0f1 captures every frame — revealing RIPv2 to 224.0.0.9.">
<figcaption>Watching the box without fiber. Its 10G LAN port speaks plain Ethernet into the spare SFP+ cage, and tcpdump does the rest.</figcaption>
</figure>

The box takes about two minutes to boot before the link comes up. Then:

```bash
sudo tcpdump -ni enp1s0f1 -e -w /tmp/box-wan.pcap
```

### What the capture showed

ARP, ND, LLDP, IGMP. The box chatters a lot on startup. But scrolling through the capture, one protocol jumped out that I wasn't expecting at all: **RIPv2**.

Every 30 seconds, the box sends a RIPv2 Response to `224.0.0.9:520` (the RIP multicast group), sourced from the alias address. The payload has exactly two route entries:

```
RIPv2 Response
  src: <YOUR_ALIAS_IP>:520 -> 224.0.0.9:520

  Route 1: <YOUR_ALIAS_NET>/20, metric 1, next-hop self
  Route 2: <YOUR_PUBLIC_IP>/32, metric 1, next-hop self
```

That's the mechanism. The Fiber Box announces its public `/32` to the BNG via RIP, and the BNG uses that to populate the source-guard ACL. Without this announcement, the BNG has no reason to accept the `/32` as a legitimate source address, so it doesn't.

RIPv2 in 2026. On a residential fiber connection. Announcing a host route for source validation. I can confidently say that no amount of DHCP option guessing, equipment ID changing, or VLAN probing would have led here. It's a routing protocol from 1998, sitting in the packet capture next to ARP and ND, doing a job nobody would think to look for.

### Testing

I wrote a quick Python script (54 lines, mostly `struct.pack` calls for the RIPv2 wire format):

```python
import socket, struct, sys

IFACE = sys.argv[1]
ALIAS_IP = sys.argv[2]
PUBLIC_IP = sys.argv[3]
ALIAS_NET = sys.argv[4]
ALIAS_MASK = sys.argv[5]

DST = "224.0.0.9"
PORT = 520

# RIPv2 Response header
header = struct.pack("!BBH", 2, 2, 0)

# Route 1: the alias subnet
route1 = struct.pack("!HH4s4s4sI", 2, 0,
    socket.inet_aton(ALIAS_NET),
    socket.inet_aton(ALIAS_MASK),
    socket.inet_aton("0.0.0.0"), 1)

# Route 2: the public /32
route2 = struct.pack("!HH4s4s4sI", 2, 0,
    socket.inet_aton(PUBLIC_IP),
    socket.inet_aton("255.255.255.255"),
    socket.inet_aton("0.0.0.0"), 1)

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE,
             IFACE.encode() + b"\0")
s.bind((ALIAS_IP, PORT))
mreq = socket.inet_aton(DST) + socket.inet_aton(ALIAS_IP)
s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
s.sendto(header + route1 + route2, (DST, PORT))
```

Ran it once. Then:

```bash
curl -4 https://ifconfig.co
```

My actual public IP. Not `213.55.x.x`. The static address, used as source. I verified from outside: inbound connections to the `/32` now completed a full handshake.

Weeks of dead ends, and one 54-line script later, it just worked. I'm genuinely glad I didn't have to solder UART headers onto that board.

### Making it permanent

Same pattern as the IPv6 ND announcer: a systemd oneshot triggered by a timer, every 30 seconds:

```nix
systemd.services.salt-rip-announce = {
  description = "Announce routes to the Salt BNG via RIPv2";
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${ripAnnounce}/bin/salt-rip-announce ${wanIf} "
      + "${wanAlias4} ${wanIp4} ${wanAlias4Net} ${wanAlias4Mask}";
  };
};

systemd.timers.salt-rip-announce = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnBootSec = "20s";
    OnUnitActiveSec = "30s";
    AccuracySec = "1s";
  };
};
```

With RIP running, the default route's `PreferredSource` can finally point at the public IP instead of the alias:

```nix
routes = [
  {
    Gateway = wanGw4;
    PreferredSource = wanIp4;  # was wanAlias4 before RIP
    Metric = 100;
  }
];
```

After the fix, measured results:

- ~7 Gbps on Ookla speed tests, limited by the N305's CPU rather than the link
- Static public IPv4 working as source, verified from outside
- Native IPv6 with the full `/64` routed to the LAN, SLAAC for all clients, no NAT
- The whole thing is one `configuration.nix` and two Python scripts. `nixos-rebuild switch` and done

The Fiber Box is in a drawer.

<figure>
<img src="/diagrams/02-after.svg" alt="The final topology: Salt OLT over fiber to the WAS-110 ONU stick with a cloned identity, into the CWWK S8 (Intel N305) running NixOS with an nftables firewall, salt-rip-announce and salt-nd-announce; out to LAN clients with static IPv4 and native IPv6 /64 SLAAC and no NAT. The Fiber Box sits unplugged in a drawer.">
<figcaption>The result. Green is mine now — one NixOS config, the static IP working as source, and native IPv6 with no NAT.</figcaption>
</figure>


## Coming next

The whole reason for owning the perimeter was to do something with it. Now that the router is a plain NixOS box with the raw WAN on an interface I control, the next posts pick up there:

- **Suricata IDS/IPS** on the WAN, inline. This was the plan from the start and the N305 was sized for it. Rules, tuning, and what residential fiber traffic actually looks like when you finally get to watch it.
- **Honeypots and traffic analysis** — the things a closed appliance never lets you run.


## Epilogue

The hardware setup took an afternoon. ONU identity cloning took a day. The static IP problem took everything else.

In terms of what actually moved the needle: `$.xmo` in the browser console was the only practical way to read the box's internal state without UART. `tcpdump` backed every conclusion, whether by what it captured or what it didn't. And the DAC cable plugged into an empty SFP+ port was the single most productive hour of the entire project. Without USB tethering through Yggdrasil and mosh, every failed experiment on the fiber path would have meant walking to the box and plugging in a monitor.

NixOS earned its keep too. When the `/22` mask test broke IPv4, `networkctl reconfigure` restored the working state in seconds. Every change was atomic and rollback-safe, which made aggressive experimentation a lot less scary.

What didn't matter, despite looking plausible at the time: equipment ID changes, VLAN 69 management sessions (carrier refused to serve the ONU), DHCP option fingerprinting (no DHCP server on the data VLAN at all), MAP-E (not used by Salt), and subnet mask tweaks (just broke things).

If you're attempting a similar bypass on Salt or another Swiss ISP, I'd suggest capturing what the original equipment puts on the wire before going down the DHCP and management VLAN rabbit holes. The answer, in my case, turned out to be a routing protocol from 1998 doing a job I didn't think to look for.

---

*CWWK S8 (Intel N305), WAS-110 with 8311 Community Firmware, NixOS 26.05, a DAC cable, and a lot of tcpdump.*
