# One bridge over both ports: mDNS/SSDP must cross, and Salt routes a single /64.
{
  inputs,
  cell,
}: {
  lib,
  config,
  site,
  ...
}: let
  br = config.router.lanBridge;
  net4 = "192.168.10";
  prefix6 = site.lan.prefix6;
in {
  options.router.lanBridge = lib.mkOption {
    type = lib.types.str;
    default = "br-lan";
  };

  config = {
    systemd.network.netdevs."15-br-lan" = {
      netdevConfig = {
        Name = br;
        Kind = "bridge";
        # Pinned: an inherited member MAC changes when a port drops off the
        # bus and churns every lease and neighbour entry.
        MACAddress = site.lan.mac;
      };
      # No loops; STP only adds a 15 s stall after link-up.
      bridgeConfig.STP = false;
    };

    systemd.network.networks."20-lan-ports" = {
      matchConfig.Name = config.router.ports.lan;
      networkConfig.Bridge = br;
      linkConfig.RequiredForOnline = "enslaved";
    };

    systemd.network.networks."30-lan" = {
      matchConfig.Name = br;
      address = [
        "${net4}.1/24"
        # ::1 is the WAN next hop Salt resolves; the LAN side is ::2.
        "${prefix6}::2/64"
      ];
      networkConfig = {
        ConfigureWithoutCarrier = true;
        DHCPServer = true;
        IPv6SendRA = true;
      };
      # Salt ignores DHCPv6-PD: the static /64 is announced as is.
      ipv6Prefixes = [{Prefix = "${prefix6}::/64";}];
      ipv6SendRAConfig = {
        EmitDNS = true;
        DNS = ["${prefix6}::2"];
        RouterLifetimeSec = 1800;
      };
      dhcpServerConfig = {
        PoolOffset = 100;
        PoolSize = 100;
        EmitDNS = true;
        DNS = ["${net4}.1"] ++ site.wan.dns4;
        EmitRouter = true;
        DefaultLeaseTimeSec = 3600;
        MaxLeaseTimeSec = 43200;
      };
      dhcpServerStaticLeases =
        map (l: {
          inherit (l) MACAddress;
          Address = "${net4}.${toString l.host}";
        })
        site.lan.staticLeases;
      linkConfig.RequiredForOnline = false;
    };

    services.resolved.settings.Resolve.DNSStubListenerExtra = "${net4}.1";
  };
}
