# Static IPv4, matched by interface type. Values read off the live install,
# not inferred: the provider does static via interfaces.d, no DHCP guarantee.
#
# Match on Type, not name: Debian saw `eth0` only because it boots with
# net.ifnames=0. A NixOS config written against eth0 would match nothing and
# the machine comes up unreachable after disko has already wiped it.
{
  inputs,
  cell,
}: {
  host,
  lib,
  ...
}: {
  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network.networks."10-wan" = {
    matchConfig.Type = "ether";
    address = [host.ipv4.address] ++ lib.optional (host.ipv6 != null) host.ipv6.address;
    routes =
      [
        {
          Gateway = host.ipv4.gateway;
          # Mirrors the onlink flag on Debian's default route.
          GatewayOnLink = true;
        }
      ]
      ++ lib.optional (host.ipv6 != null) {
        Gateway = host.ipv6.gateway;
        GatewayOnLink = true;
      };
    dns = [
      "8.8.8.8"
      "8.8.4.4"
    ];
    # RA advertises prefixes but assigns no global address: v6 is static
    # (globals ipv6, set once the provider enables it) or absent. The AAAA
    # record follows the same value (dns.nix), so v6 is never advertised
    # before it answers.
    networkConfig.IPv6AcceptRA = true;
    linkConfig.RequiredForOnline = "routable";
  };

  services.resolved.enable = true;

  networking.firewall.allowedTCPPorts = [22];
}
