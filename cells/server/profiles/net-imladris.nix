# LAN over the 10G DAC to minas-tirith enp1s0f1; .10 is a static lease on the
# enp7s0 MAC. enp8s0 (r8169 1G) is the spare: no address, not waited on.
# Rollback if the DAC dies: swap the two Name matches, re-key the .10 lease
# in the site secret, apply from the console.
{
  inputs,
  cell,
}: {...}: {
  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network.networks = {
    "10-lan" = {
      matchConfig.Name = "enp7s0";
      networkConfig.DHCP = "yes";
      # The router's static lease is keyed by MAC; networkd defaults to DUID.
      dhcpV4Config.ClientIdentifier = "mac";
      linkConfig.RequiredForOnline = "routable";
    };
    "20-spare" = {
      matchConfig.Name = "enp8s0";
      networkConfig = {
        DHCP = "no";
        LinkLocalAddressing = "no";
        IPv6AcceptRA = false;
      };
      linkConfig.RequiredForOnline = "no";
    };
  };

  # networkd hands DHCP DNS to resolved only; without it resolv.conf is empty.
  services.resolved.enable = true;
}
