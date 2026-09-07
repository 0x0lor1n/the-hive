# Replacing Salt Fiber Box with a CWWK S8: XGS-PON bypass on NixOS

*How I replaced my ISP's locked-down router with a fanless mini PC running NixOS, plugged an XGS-PON stick straight into its SFP+ cage, and measured 7 Gbit/s on a 10G Swiss fiber line.*

---

## Why replace the ISP box at all?

Salt (a Swiss fiber ISP) ships a Sagemcom F5688 "Fibre Box X6" with every XGS-PON subscription. It works fine for most people. So why spend time replacing it?

**1. I cannot run anything on it.** I want to run [Suricata](https://suricata.io/) (a network IDS/IPS) inspecting all traffic. The Fiber Box runs locked firmware with no shell access. The `admin` account has a restricted profile and cannot reach critical config subtrees. A `super` account exists but its password is unknown. No custom software, no monitoring, no learning.

**2. I want a single declarative config I can version-control.** The Fiber Box is configured through a web GUI and managed remotely by Salt's ACS. If it dies, I am restoring from memory. With NixOS, the entire router -- firewall rules, DHCP, IPv6 RA, DNS, VPN, IDS -- is one `configuration.nix` I can `git push` and `nixos-rebuild switch` onto a fresh box in minutes.

**3. Throughput.** By plugging the ONU stick directly into a 10G SFP+ cage, the ISP box is removed from the data path entirely. Measured result: **7.0 Gbit/s** download, where the Fiber Box capped at 2.6 Gbit/s on the same host (limited by the 2.5 GbE copper port, not the box itself -- but the point stands).

<!-- PHOTO: the CWWK S8 with its case open, showing the SFP+ cages and the WAS-110 stick inserted -->

---

## The hardware: CWWK S8

The CWWK S8 is a fanless mini PC built around the **Intel i3-N305** (8 Efficiency cores, 15W TDP). It has become the community favourite for DIY home routers in the 8311 XGS-PON bypass community.

| | CWWK S8 |
|---|---|
| CPU | Intel i3-N305, 8C/8T, up to 3.8 GHz |
| RAM | 16 GB DDR5 (soldered) |
| 10G NICs | **2x Intel 82599ES SFP+** -- direct cages for SFP+ modules |
| 2.5G NICs | 2x Intel I226-V -- copper LAN ports |
| Storage | 2x M.2 NVMe (PCIe x1 each) |
| TDP | 15W, passively cooled (fanless aluminium case) |
| Idle power | ~12W at the wall |

**Why this box:**

- **SFP+ cages are the killer feature.** Most DIY routers need a media converter or a PCIe SFP+ card. The CWWK S8 has two SFP+ cages built in on the Intel 82599ES -- the most battle-tested 10G NIC in Linux. One cage for the ONU stick, one spare for a 10GBASE-T transceiver or DAC.

- **Enough CPU for Suricata at line rate.** The N305 has 8 cores with AES-NI. OPNsense and pfSense users on the same chip report Suricata at 5+ Gbit/s with AF_PACKET.

- **Fanless = silent and reliable.** This sits in a living room. Zero moving parts, zero noise.

- **Four real NICs on PCIe.** Two 10G SFP+ and two 2.5G copper. No USB dongles, no out-of-tree drivers. All mainline Linux.

- **The 8311 community runs on this exact board.** The [8311 Discord](https://discord.gg/XbTWBbSG4p) is full of CWWK S8 owners. When someone reports "this config works," it is almost always on an N305 with an 82599ES.

<!-- PHOTO: the back panel of the CWWK S8, showing the 2x SFP+ cages and 2x RJ45 ports -->

### One hardware caveat: thin PCIe lanes

The N305 has only 9 PCIe lanes. Both I226-V copper ports train at PCIe 2.0 x1, and the NVMe slots are x1 too. A single-lane link has no fallback -- if the contact goes marginal, the device **hard-detaches** instead of retraining at reduced width.

I had one I226-V fall off the bus while working inside the case (fitting a heatsink to the ONU stick). A **cold power-off** (not a warm reboot -- the root port needs a full power cycle) brought it back. The box is solid in normal operation, just be careful during physical work.

There is also a **PCI bus renumbering trap**: when a device disappears, downstream bus numbers shift. An SSD that was at `04:00.0` moves to `03:00.0` to fill the gap, which can look like the SSD took over the NIC's address. Do not pull SSDs over this -- they are innocent. Check root ports with `lspci -tv` instead of bus addresses.

---

## The ONU stick: WAS-110 with 8311 Community Firmware

The [WAS-110](https://pon.wiki/xgs-pon/ont/bfw-solutions/was-110/) is an SFP+ form factor XGS-PON ONU built on the MaxLinear PRX126 chipset. It plugs directly into the CWWK's SFP+ cage and replaces the ISP box at the fiber layer.

I run **8311 Community Firmware v2.8.3**. It provides a LuCI web interface at `192.168.11.1` and SSH root access. Configuration is through U-Boot environment variables that persist across reboots.

<!-- PHOTO: the WAS-110 stick next to the Fiber Box's native SFP+ module for size comparison -->

**Critical:** the Intel 82599ES rejects non-Intel SFP+ modules by default. Without this kernel module option, the stick is detected but the link never comes up:

```nix
boot.extraModprobeConfig = "options ixgbe allow_unsupported_sfp=1";
```

---

## Step 1: Extract line facts from the Fiber Box

Before configuring the stick, you need the Fiber Box's identity and network parameters. This is the most important step, and the one where I discovered the critical value that no guide mentions.

### The browser console: $.xmo

The Fiber Box's web UI (`http://192.168.1.1/2.0/gui/`) loads a JavaScript object called `$.xmo` in the browser console. This gives direct access to the TR-181 data model -- a tree of every setting and status value the box knows.

Open DevTools (F12), go to the Console tab, and try:

```javascript
// Get device info -- model, firmware, serial
$.xmo.getValuesTree("Device/DeviceInfo")
  .then(r => console.log(JSON.stringify(r, null, 2)))

// Get ALL IP interfaces -- this is where the critical discovery is
$.xmo.getValuesTree("Device/IP/Interfaces")
  .then(r => console.log(JSON.stringify(r, null, 2)))

// Get routing table -- check which routes are ENABLED vs ERROR
$.xmo.getValuesTree("Device/Routing/Routers")
  .then(r => console.log(JSON.stringify(r, null, 2)))

// Get VLAN assignments
$.xmo.getValuesTree("Device/Ethernet/VLANTerminations")
  .then(r => console.log(JSON.stringify(r, null, 2)))

// Get DHCP client state (is the box using DHCP or static?)
$.xmo.getValuesTree("Device/DHCPv4/Clients")
  .then(r => console.log(JSON.stringify(r, null, 2)))

// Get optical info -- ONU serial, vendor, hardware version
$.xmo.getValuesTree("Device/Optical")
  .then(r => console.log(JSON.stringify(r, null, 2)))
```

> **Tip:** The output can be huge. Copy the full JSON into a file and search through it with `jq`. Some fields are marked `_XMO_WRITE_ONLY_` -- these are credentials the box will not reveal through the API.

### Scripting it: the /cgi/json-req API

For more reliable extraction, script the API directly. The Fiber Box exposes `POST /cgi/json-req` with form-encoded bodies. Authentication uses **SHA-512** (not MD5 as on older Sagemcom models):

```
credential = SHA512(username + ":" + server_nonce + ":" + SHA512(password))
auth_key   = SHA512(credential + ":" + request_id + ":" + cnonce + ":JSON:/cgi/json-req")
```

The request body must be `application/x-www-form-urlencoded` with a single field `req=<json>`. Sending raw JSON returns a 400.

Here is a minimal Python client that handles the full auth handshake:

```python
#!/usr/bin/env python3
"""Minimal Sagemcom /cgi/json-req client."""
import hashlib, json, random, sys, urllib.parse, urllib.request

HOST = "192.168.1.1"
URL = f"http://{HOST}/cgi/json-req"
USER = "admin"
PASSWORD = "your-admin-password"  # printed on the box label

HASH = lambda s: hashlib.sha512(s.encode()).hexdigest()

def post(payload):
    body = urllib.parse.urlencode(
        {"req": json.dumps(payload, separators=(",", ":"))}).encode()
    req = urllib.request.Request(
        URL, data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())

class Box:
    def __init__(self):
        self.session_id = 0
        self.server_nonce = ""
        self.request_id = -1
        self.cnonce = random.randrange(10_000, 100_000_000)

    def _auth_key(self, request_id):
        cred = HASH(f"{USER}:{self.server_nonce}:{HASH(PASSWORD)}")
        return HASH(f"{cred}:{request_id}:{self.cnonce}:JSON:/cgi/json-req")

    def _envelope(self, actions, request_id, session_id, priority=True):
        return {"request": {
            "id": request_id, "session-id": session_id,
            "priority": priority, "actions": actions,
            "cnonce": self.cnonce, "auth-key": self._auth_key(request_id)}}

    def login(self):
        action = [{"id": 0, "method": "logIn", "parameters": {
            "user": USER, "persistent": "true",
            "session-options": {
                "nss": [{"name": "gtw",
                         "uri": "http://sagemcom.com/gateway-data"}],
                "language": "ident",
                "context-flags": {"get-content-name": True,
                                  "local-time": True},
                "capability-depth": 2,
                "capability-flags": {"name": True, "default-value": False,
                                     "restriction": True,
                                     "description": False},
                "time-format": "ISO_8601",
                "write-only-string": "_XMO_WRITE_ONLY_",
                "undefined-write-only-string": "_XMO_UNDEFINED_WRITE_ONLY_"}}}]
        reply = post(self._envelope(action, 0, "0"))
        params = reply["reply"]["actions"][0]["callbacks"][0]["parameters"]
        self.session_id = params["id"]
        self.server_nonce = params.get("nonce", "")
        self.request_id = 0
        return True

    def get(self, xpath):
        self.request_id += 1
        action = [{"id": 0, "method": "getValue",
                   "xpath": urllib.parse.quote(xpath, safe="/"),
                   "options": {}}]
        reply = post(self._envelope(action, self.request_id,
                                    self.session_id, priority=False))
        return reply["reply"]["actions"][0]["callbacks"][0]["parameters"]

box = Box()
box.login()
for path in sys.argv[1:]:
    print(json.dumps(box.get(path), indent=2)[:12000])
```

Usage:

```bash
python3 sagemcom.py "Device/IP/Interfaces" "Device/Optical" "Device/Routing/Routers"
```

### What you need to find

Here are the specific values to extract and where they live:

| Value | Where to find it | Example |
|---|---|---|
| ONU serial | `Device/Optical` → `SerialNumber` | `GFAB` + 8 digits |
| Vendor ID | `Device/Optical` → `VendorId` | `GFAB` |
| Equipment ID | `Device/DeviceInfo` → `ModelName` | `NJJ Fibre Box` |
| HW version | `Device/Optical` → `HWVersion` | `XGSR1644` |
| SW version | `Device/Optical` → `SWVersion` | `SGCk100` |
| WAN MAC | `Device/IP/Interfaces` → look for the interface on VLAN 30, check `MACAddress` | `6C:99:61:0E:xx:xx` |
| **Public IPv4** | `Device/IP/Interfaces` → interface named `IP_DATA` → `IPv4Address` | your `/32` static IP |
| **Alias IPv4** | `Device/IP/Interfaces` → interface named `IP_ALIAS` → `IPv4Address` | a `/20` private address |
| IPv6 address | `Device/IP/Interfaces` → `IP_DATA` → `IPv6Address` | your `::1/64` |
| IPv6 gateway | `Device/Routing/Routers` → the v6 default route → `NextHop` | typically `fe80::xxxx` |
| Data VLAN | `Device/Ethernet/VLANTerminations` | `30` for Salt |
| DNS servers | `Device/DNS/Client/Servers` | Salt's resolver IPs |

**The critical discovery: `IP_ALIAS`.** The Fiber Box carries **two** IPv4 addresses on the data VLAN, not one. Every bypass guide mentions only the public `/32`. The second address is a private `/20` alias in the `10.x.x.x` range that:

1. Makes the carrier's gateway ARP-reachable (it refuses ARP from the public IP)
2. Is the **only** source address the BNG accepts for outbound traffic

Without this address, IPv4 is completely dead. This is the single non-obvious fact that makes Salt XGS-PON bypass work, and I have not seen it documented anywhere else.

> **How to spot it:** In the `Device/IP/Interfaces` output, look for an interface named `IP_ALIAS` on the same underlying layer as `IP_DATA`. It will have a private `10.x.x.x` address with a `/20` mask. The per-subscriber addressing follows a pattern where the last two octets are the same across all VLANs (data, VoIP, mgmt), only the second octet changes.

### Verifying the routing table

```javascript
// In the browser console:
$.xmo.getValuesTree("Device/Routing/Routers")
  .then(r => {
    // Look for routes with Status: "ENABLED" vs "ERROR"
    // The gateway route via 10.x.0.1 will show ERROR
    // The on-link route will show ENABLED
    // This is the box telling you it also struggles with the gateway!
    console.log(JSON.stringify(r, null, 2))
  })
```

In the routing table, you will likely see the gateway-based route sitting at `Status: ERROR` while an equivalent on-link route is `ENABLED`. This is the box itself confirming that the gateway has quirks.

---

## Step 2: Configure the WAS-110 stick

SSH into the stick (`ssh root@192.168.11.1`, password is on the 8311 wiki) and set the U-Boot environment:

```sh
# Identity -- must match your Fiber Box exactly
fw_setenv 8311_gpon_sn      <YOUR_ONU_SERIAL>
fw_setenv 8311_vendor_id    <YOUR_VENDOR_ID>         # first 4 chars of serial
fw_setenv 8311_equipment_id "NJJ Fibre Box"
fw_setenv 8311_hw_ver       XGSR1644
fw_setenv 8311_sw_verA      SGCk100
fw_setenv 8311_sw_verB      SGCk100
fw_setenv 8311_cp_hw_ver_sync 1

# VEIP mode -- essential for Salt
fw_setenv 8311_mib_file     prx300_1V.ini

# Deliver data VLAN untagged toward the host
fw_setenv 8311_internet_vlan 0
fw_setenv 8311_fix_vlans    1

# Clone the Fiber Box's WAN MAC
fw_setenv 8311_iphost_mac   <YOUR_WAN_MAC_lowercase_colon_separated>
```

Key points:

- **`prx300_1V.ini` is mandatory for Salt.** Salt provisions to a VEIP (Virtual Ethernet Interface Point). The default `prx300_1U.ini` presents a physical UNI and the OLT never binds services. The stick will register, show O5 state, and pass zero traffic.
- **Do not save the 8311 page in LuCI** after setting `8311_mib_file` -- saving rewrites it back to `1U`.
- The `8311_internet_vlan 0` setting makes the stick deliver data-VLAN frames untagged to the host. The VLAN tagging/untagging happens inside the stick, so your host interface sees plain Ethernet.

Verify PON state after inserting the fiber:

```bash
# On the stick via SSH:
pon psg
# Look for: current=5x (O5 = operational)
# If current=1x, there is no downstream light -- check fiber connection
```

---

## Step 3: The NixOS configuration

### WAN interface

The SFP+ port needs MAC cloning (the OLT checks it) and all the addresses discovered from the Fiber Box:

```nix
let
  wanIf    = "enp1s0f0";        # first SFP+ port
  wanMac   = "<YOUR_WAN_MAC>";  # from the Fiber Box, NOT the label MAC
  wanIp4   = "<YOUR_PUBLIC_IP>";
  wanAlias = "<YOUR_ALIAS_IP>";
  wanMask  = 20;                # the /20 from IP_ALIAS
  wanIp6   = "<YOUR_IPV6>::1";
  wanGw4   = "<YOUR_V4_GATEWAY>";
  wanGw6   = "<YOUR_V6_GATEWAY>";   # typically fe80::xxxx
in
{
  # Clone the Fiber Box's WAN MAC onto the SFP+ port
  systemd.network.links."10-wan" = {
    matchConfig.OriginalName = wanIf;
    linkConfig.MACAddress = wanMac;
  };

  systemd.network.networks."10-wan" = {
    matchConfig.Name = wanIf;
    address = [
      "192.168.11.2/24"                       # management net to the stick
      "${wanIp4}/32"                           # public IP
      "${wanAlias}/${toString wanMask}"         # THE ALIAS -- makes the gateway work
      "${wanIp6}/128"                          # /128 not /64 -- the prefix belongs on the LAN
    ];
    networkConfig = {
      IPv6AcceptRA = false;                    # we configure everything statically
      LinkLocalAddressing = "ipv6";
    };
    routes = [
      {
        Gateway = wanGw4;
        PreferredSource = wanAlias;            # NOT the public IP!
        Metric = 100;
      }
      {
        Gateway = wanGw6;
        Metric = 100;
      }
    ];
    linkConfig.RequiredForOnline = false;
  };
}
```

**Critical detail:** `PreferredSource` must be the alias address, not the public IP. The BNG silently drops anything sourced from the public `/32`. Without `PreferredSource`, source selection picks the `192.168.11.2` management address and nothing works.

### LAN bridge

Both copper I226-V ports are bridged into a single LAN segment:

```nix
  lanIf    = "br-lan";
  lanPorts = [ "enp3s0" "enp2s0" ];
  lanMac   = "<PINNED_MAC>";   # use one port's permanent MAC

  # Bridge device
  systemd.network.netdevs."15-br-lan" = {
    netdevConfig = {
      Name = lanIf;
      Kind = "bridge";
      MACAddress = lanMac;   # pin it so it doesn't change when ports flap
    };
    bridgeConfig.STP = false;   # no loops, skip the 15s forwarding delay
  };

  # Enslave both copper ports
  systemd.network.networks."20-lan-ports" = {
    matchConfig.Name = lanPorts;
    networkConfig.Bridge = lanIf;
    linkConfig.RequiredForOnline = "enslaved";
  };
```

> **Why bridge?** One flat L2 segment means mDNS/SSDP discovery works (Chromecast, AirPlay) and a single IPv6 `/64` covers everything. Salt will not delegate a second prefix, so a separate subnet would mean no IPv6 for the second port.

> **Why pin the MAC?** Without it, the bridge inherits the lowest member MAC and changes it when ports come and go, churning DHCP leases and neighbour entries.

### LAN services: DHCP, DNS, IPv6 SLAAC

```nix
  systemd.network.networks."30-lan" = {
    matchConfig.Name = lanIf;
    address = [
      "${lanNet}.1/24"
      "${lanNet6}::2/64"    # ::1 stays on WAN as Salt's next hop
    ];
    networkConfig = {
      ConfigureWithoutCarrier = true;
      DHCPServer = true;
      IPv6SendRA = true;
    };
    ipv6Prefixes = [
      { Prefix = "${lanNet6}::/64"; }
    ];
    ipv6SendRAConfig = {
      EmitDNS = true;
      DNS = [ "${lanNet6}::2" ];
    };
    dhcpServerConfig = {
      PoolOffset = 100;     # .100 through .199
      PoolSize = 100;
      EmitDNS = true;
      DNS = [ "${lanNet}.1" ];
    };
  };
```

Every device on the LAN gets **native, publicly routable IPv6** via SLAAC. No NAT66, no prefix translation.

### Firewall

```nix
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ lanIf ];

    # ESSENTIAL: public IPv6 on the LAN means every device is globally
    # reachable without this. Conntrack allows replies; unsolicited inbound
    # is dropped.
    filterForward = true;

    # ESSENTIAL on a multi-homed box. Without it, replies on non-primary
    # interfaces are silently dropped by nftables' strict rpfilter rule.
    checkReversePath = "loose";
  };

  # SSH must NOT be open on the WAN -- set this explicitly
  services.openssh = {
    enable = true;
    openFirewall = false;   # default is true, which opens 22 on ALL interfaces
  };
```

### The ND keepalive timer

The BNG's IPv6 neighbour cache expires after ~20 minutes. When it re-resolves, it sends a solicitation to your solicited-node multicast address, but the stick delivers multicast with the VLAN tag still on -- the host drops it and IPv6 dies.

The fix is a systemd timer that sends unsolicited Neighbour Advertisements every 30 seconds:

```nix
  systemd.services.salt-nd-announce = {
    description = "Announce our IPv6 to the BNG";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${ndAnnounce}/bin/salt-nd-announce ${wanIf} ${wanIp6} ${bngMac}";
    };
  };

  systemd.timers.salt-nd-announce = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "20s";
      OnUnitActiveSec = "30s";
    };
  };
```

The script crafts raw ICMPv6 NA packets with the Override flag, sent both to all-nodes multicast (`ff02::1`) and unicast to the gateway's known MAC:

```python
#!/usr/bin/env python3
"""Send unsolicited IPv6 Neighbour Advertisement."""
import socket, struct, sys

IFACE = sys.argv[1]
TARGET = sys.argv[2]
GW_MAC = sys.argv[3] if len(sys.argv) > 3 else None

def build(src_ip, dst_ip, mac, target):
    flags = 0x20000000  # Override
    body = struct.pack("!I", flags) + target
    body += struct.pack("!BB", 2, 1) + mac  # target link-layer address
    # ... ICMPv6 with pseudo-header checksum, wrapped in IPv6 ...
    # Full source in the repo

s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
s.bind((IFACE, 0))
mac = s.getsockname()[4][:6]
target = socket.inet_pton(socket.AF_INET6, TARGET)

# Send to all-nodes multicast
s.send(b"\x33\x33\x00\x00\x00\x01" + mac + b"\x86\xdd" + pkt)

# Also unicast to the gateway if we know its MAC
if GW_MAC:
    gw_bytes = bytes.fromhex(GW_MAC.replace(":", ""))
    s.send(gw_bytes + mac + b"\x86\xdd" + pkt_to_gw)
```

---

## Step 4: The debugging process

### Setting up the lifeline first

**Before touching the fiber**, set up a reliable out-of-band path. This box has no Bluetooth radio (verified: `btmgmt info` returns 0 items). The debug lifeline is an **Android USB tether**:

```nix
# Match by kernel driver, not interface name -- USB NICs get
# path-derived names that change with the physical USB port
systemd.network.networks."40-tether" = {
  matchConfig = {
    Driver = [ "rndis_host" "cdc_ether" "cdc_ncm" "cdc_mbim" ];
    Type = "ether";
  };
  networkConfig.DHCP = "yes";
  dhcpV4Config.RouteMetric = 2048;   # only used when WAN is down
};
```

On top of the tether, [Yggdrasil](https://yggdrasil-network.github.io/) (an encrypted IPv6 mesh overlay) gives the box a **stable address** reachable from anywhere. Even behind Salt's CGNAT where no inbound IPv4 is possible, I can SSH in from any network in the world -- through the USB tether when the WAN is broken, or through the WAN once it works.

Combined with [mosh](https://mosh.org/) for interactive comfort (local echo prediction, survives network changes and suspend), the workflow is:

1. Plug phone into the box, enable USB tethering
2. `mosh nixos@<yggdrasil-address>` from the laptop
3. Move the fiber from the ISP box to the stick
4. Debug in the same terminal session -- the mosh connection survives the network change

Route metrics decide which path carries traffic (lowest wins):
- **100** -- WAN via the ONU stick
- **1024** -- copper fallback toward the ISP box
- **2048** -- phone USB tether

### Debugging commands

Once the fiber is in the stick, here is the debugging sequence:

```bash
# 1. Check PON state -- is the stick registered on the OLT?
ssh root@192.168.11.1 'pon psg'
# Want: current=5x (O5 = operational)

# 2. Check the SFP+ link
ip -br link show enp1s0f0
# Want: UP, not NO-CARRIER

# 3. Watch for ANY traffic from the carrier
sudo tcpdump -ni enp1s0f0 -c 20
# You should see ARP, ND, possibly DHCP from other subscribers

# 4. Test IPv6 first -- it is simpler and works immediately if the
#    stick config is correct
curl -6 -s --max-time 8 https://ifconfig.co
# Should show your IPv6 address

# 5. Test IPv4 -- this is where the alias matters
curl -4 -s --max-time 8 https://ifconfig.co
# If this fails, check: do you have the alias address?
ip addr show enp1s0f0 | grep "10\."

# 6. If IPv4 is broken, check ARP resolution to the gateway
sudo arping -I enp1s0f0 -S <YOUR_ALIAS_IP> <YOUR_GATEWAY> -c 3
# Want: replies. If no replies, the alias address or gateway is wrong.

# Now try from the public IP to confirm it doesn't work:
sudo arping -I enp1s0f0 -S <YOUR_PUBLIC_IP> <YOUR_GATEWAY> -c 3
# This will get ZERO replies -- confirming the BNG's source check

# 7. Check the ND keepalive is running
systemctl status salt-nd-announce.timer
journalctl -u salt-nd-announce --since "5 min ago"

# 8. Verify IPv6 neighbour resolution
ip -6 neigh show dev enp1s0f0
# The gateway should be REACHABLE or STALE, not FAILED

# 9. Watch for the VLAN-tagged multicast bug
sudo tcpdump -ni enp1s0f0 -e ip6 | grep "vlan 30"
# If you see vlan-tagged frames, the ND keepalive is what saves you
```

### The IPv4 wall (and how I got past it)

With only the public `/32` configured (following every guide I could find), IPv4 was completely dead:

- Gateway answered no ARP -- looked like a phantom
- Outbound SYNs left but zero replies arrived
- `tcpdump` confirmed packets genuinely leaving and genuinely not coming back

I tested everything: link routes, proxy ARP, gratuitous ARP, DHCP with various identities. Nothing.

**The breakthrough:** querying `Device/IP/Interfaces` on the live Fiber Box via the `/cgi/json-req` API revealed `IP_ALIAS` -- a second IPv4 address on the same VLAN that no guide mentioned. Adding it fixed everything in one shot.

The gateway `10.x.0.1` **does** answer ARP -- but only when the request is sourced from the alias address. From the public `/32`, it stays silent. That conditional behaviour is what makes it look nonexistent when you only have the public IP configured.

### The 20-minute IPv6 death

After getting IPv4 working, IPv6 started dying after ~20 minutes. IPv4 kept working. Rebooting the stick brought it back temporarily.

**It is not thermal** (though the stick does idle at ~63C). It is the BNG's **IPv6 neighbour cache expiring**:

1. My initial config pinned the v6 gateway with `nud permanent`, stopping the host from doing ND
2. BNG's cache entry for our address aged out
3. BNG sent a solicitation to our solicited-node multicast address
4. The stick delivered it with the **VLAN 30 tag still attached**
5. Host dropped the tagged frame on an untagged interface
6. BNG marked us unreachable → IPv6 dead

Diagnostic:
```bash
# Watch for tagged multicast on the WAN interface
sudo tcpdump -ni enp1s0f0 -e ip6 | grep vlan
# You'll see vlan 30-tagged ND solicitations from the BNG and
# from other subscribers on the shared VLAN 30 broadcast domain
```

Fix: remove the static neighbour pin (dynamic ND works fine) and run the unsolicited NA timer described above.

### Other traps

- **`checkReversePath = "loose"` is mandatory.** Default NixOS emits a strict nftables rpfilter rule. On a multi-homed box, replies on non-primary interfaces are silently dropped. Symptom: USB tether gets a DHCP lease, resolves DNS, but every TCP handshake dies. Check with `nstat -az | grep IPReversePathFilter`.

- **Interface names vs port labels.** Do not assume `enp2s0` = ETH1. Plug a cable in and watch which interface gains carrier: `ip monitor link`.

- **`openssh.openFirewall` defaults to `true`** in NixOS. With a publicly routable IPv6 address, this exposes SSH to the entire internet. Set `openFirewall = false` explicitly.

- **Salt filters ICMP.** `ping` to the gateway or DNS servers always fails. Use `curl` for connectivity tests.

---

## Results

### Throughput

| | Download | Upload | Ping |
|---|---|---|---|
| Through ONU stick (Ookla, IPv6) | **7,035 Mbit/s** | **5,438 Mbit/s** | 2.5 ms |
| Through ONU stick (8 streams, IPv4) | 7,579 Mbit/s | -- | -- |
| Through Fiber Box (capped by 2.5 GbE host port) | 2,322 Mbit/s | 2,319 Mbit/s | 2.8 ms |

The stick delivers the full line speed. Four parallel TCP streams are not enough to saturate a 10G link; use eight.

### What works

- Full-speed 10G XGS-PON bypass
- IPv4 (CGNAT) and IPv6 (native, public, no NAT) simultaneously
- LAN with DHCP, DNS caching, IPv6 SLAAC for all devices
- Fully declarative NixOS configuration -- one file, version-controlled
- Remote access via Yggdrasil from anywhere
- USB tether as out-of-band recovery

### What does not work

**The static IPv4 address.** Salt assigns a static IP to the subscription. Inbound traffic for it does arrive at the WAN interface. But the BNG refuses it as a source address -- replies are dropped and the IP is unusable in both directions. Egress goes through CGNAT instead, appearing as a shared `213.55.x.x` address.

I exhaustively tested every host-side approach: gratuitous ARP, on-link routing, DHCP with the Fiber Box's identity (option 60 = `sagem`, option 61 = WAN MAC) on data VLAN 30, DHCP on management VLAN 69, DHCPv6-PD. The management VLAN is provisioned by the OLT (tc filters and GEM ports exist) but the carrier never answers. The BNG's source-guard entry appears to be written by ACS provisioning tied to the Fiber Box's identity. No host-side protocol can trigger it.

**For inbound services, IPv6 is the answer.** The full `/64` is routed to the subscriber with no NAT. A VPS with an nginx reverse proxy over IPv6, or a direct AAAA DNS record, works cleanly.

---

## What I would do differently

1. **Query the Fiber Box's API first.** The `/cgi/json-req` API (or `$.xmo` in the browser console) is the single richest source of ground truth. I spent a full day debugging IPv4 blind before thinking to read the box's own configuration. `Device/IP/Interfaces` should be step one.

2. **Set up the out-of-band path before touching the fiber.** Yggdrasil + mosh + USB tether should be working before the first `ip link set enp1s0f0 up`.

3. **Do not trust forum posts for IP addressing.** Every Salt bypass thread I found listed only the public IP. The alias was discovered by querying the actual box. Your ISP may have undocumented addressing that nobody has written about.

---

## Shopping list

| Component | Role | Approx. price (CHF) |
|---|---|---|
| CWWK S8 (i3-N305, 16GB) | Router / firewall | ~250 |
| WAS-110 (BFW Solutions) | XGS-PON SFP+ ONU stick | ~80 |
| 8311 Community Firmware v2.8.3 | Stick operating system | free |
| NixOS 26.05 | Router OS | free |
| WiFi AP in bridge mode | WiFi access | whatever you have |

The Fiber Box goes back in its packaging as a backup.

<!-- PHOTO: the final setup -- CWWK S8 with the fiber connected to the WAS-110 in the SFP+ cage, copper to the AP, and the status LEDs -->
