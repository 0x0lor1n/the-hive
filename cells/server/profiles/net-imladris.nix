# LAN over an active-backup bond: enp7s0 (10G DAC to minas-tirith enp1s0f1)
# is primary, enp8s0 (r8169 1G, cable into the AP or a free br-lan port) the
# backup. bond0 rides whichever has carrier and moves back to the DAC as soon
# as it has link, so bringing the 10G card back is the whole failover.
# Not RouteMetric: that picks the outbound route only, while .10 must
# answer ARP on whichever port is live, and a lease is per MAC.
#
# .10 is the static lease on the bond MAC (site.lan.staticLeases on
# minas-tirith). The MAC is locally administered and derived from the host
# name: it survives a NIC swap and keeps hardware MACs out of this repo.
{
  inputs,
  cell,
}: {
  lib,
  pkgs,
  host,
  ...
}: let
  h = builtins.hashString "sha256" "${host.hostName}-bond0";
  bondMac = lib.concatStringsSep ":" (["02"] ++ map (i: builtins.substring (i * 2) 2 h) (lib.range 0 4));
in {
  environment.systemPackages = [pkgs.ethtool];

  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network.netdevs."10-bond0" = {
    netdevConfig = {
      Name = "bond0";
      Kind = "bond";
      MACAddress = bondMac;
    };
    bondConfig = {
      Mode = "active-backup";
      # Carrier polling; without it the bond never sees a dead link.
      MIIMonitorSec = "100ms";
      # Back to the primary as soon as it has link, not only on backup loss.
      PrimaryReselectPolicy = "always";
    };
  };

  systemd.network.networks = {
    # Either port may be unplugged; online is decided by bond0 alone.
    "10-bond0-primary" = {
      matchConfig.Name = "enp7s0";
      networkConfig = {
        Bond = "bond0";
        PrimarySlave = true;
      };
      linkConfig.RequiredForOnline = "no";
    };
    "10-bond0-backup" = {
      matchConfig.Name = "enp8s0";
      networkConfig.Bond = "bond0";
      linkConfig.RequiredForOnline = "no";
    };
    "20-lan" = {
      matchConfig.Name = "bond0";
      networkConfig.DHCP = "yes";
      # The router's static lease is keyed by MAC; networkd defaults to DUID.
      dhcpV4Config.ClientIdentifier = "mac";
      linkConfig.RequiredForOnline = "routable";
    };
  };

  # networkd hands DHCP DNS to resolved only; without it resolv.conf is empty.
  services.resolved.enable = true;
}
