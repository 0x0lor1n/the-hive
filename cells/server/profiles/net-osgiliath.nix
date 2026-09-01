# osgiliath's network: static IPv4, matched by interface TYPE not by name.
#
# Values read off the live Debian install 2026-08-31 (iter 11 §2.2), not
# inferred. Static rather than DHCP because that is what the provider
# actually does: /etc/network/interfaces sources only interfaces.d/*, there
# is no networkd, and the default route carries `onlink`. Static works
# whether or not DHCP is also offered; the reverse is not true.
#
# THE NAMING TRAP: Debian reaches this NIC as `eth0` only because it boots
# with `net.ifnames=0 biosdevname=0`. NixOS uses predictable names, so a
# config written against `eth0` would silently match nothing and the machine
# would come up unreachable -- with the disko phase already past the point
# of no return. Matching on Type = "ether" avoids the question entirely:
# there is exactly one ethernet NIC, so it is unambiguous.
#
# This is the single highest-consequence file in the iteration.
{
  inputs,
  cell,
}: {host, ...}: {
  networking.useNetworkd = true;
  networking.useDHCP = false;

  systemd.network.networks."10-wan" = {
    matchConfig.Type = "ether";

    # From the ENCRYPTED half of globals (iter 11). IP addresses are treated
    # as sensitive in this repo, so neither the address nor the gateway
    # appears in any tracked file -- they live in secrets/globals.nix.age and
    # colmenaConfigurations.nix reads the SAME entry, so there is exactly one
    # place to change after a re-provision.
    address = [host.ipv4.address];

    routes = [
      {
        Gateway = host.ipv4.gateway;
        # Mirrors the `onlink` flag Debian's default route carries. The
        # gateway is inside the /24 so this is arguably redundant, but
        # matching the known-working config exactly is the cheapest
        # correctness available on a machine we cannot easily reach.
        GatewayOnLink = true;
      }
    ];

    dns = [
      "8.8.8.8"
      "8.8.4.4"
    ];

    # RA advertises two prefixes but assigns NO global address today, so
    # nothing here may depend on IPv6 for reachability. Accept it and move
    # on; add a static address later if snowcore documents one.
    networkConfig.IPv6AcceptRA = true;

    linkConfig.RequiredForOnline = "routable";
  };

  services.resolved.enable = true;

  # sshd is the only thing listening. services.openssh's openFirewall
  # default would cover 22, but stating it makes the exposed surface
  # readable in one place.
  networking.firewall.allowedTCPPorts = [22];
}
