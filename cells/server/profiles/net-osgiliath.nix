# Static IPv4, matched by interface type. Values read off the live install,
# not inferred: the provider does static via interfaces.d, no DHCP guarantee.
#
# Match on Type, not name: Debian saw `eth0` only because it boots with
# net.ifnames=0. A NixOS config written against eth0 would match nothing and
# the machine comes up unreachable after disko has already wiped it.
{
  inputs,
  cell,
}: {host, ...}: {
  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network.networks."10-wan" = {
    matchConfig.Type = "ether";
    address = [host.ipv4.address];
    routes = [
      {
        Gateway = host.ipv4.gateway;
        # Mirrors the onlink flag on Debian's default route.
        GatewayOnLink = true;
      }
    ];
    dns = [
      "8.8.8.8"
      "8.8.4.4"
    ];
    # RA advertises prefixes but assigns no global address; nothing may depend
    # on v6 for reachability.
    networkConfig.IPv6AcceptRA = true;
    linkConfig.RequiredForOnline = "routable";
  };

  services.resolved.enable = true;

  networking.firewall.allowedTCPPorts = [22];
}
