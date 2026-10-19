# The 203: address derives from the key: carried over in /persist, never
# generated, so a missing key fails the unit instead of moving the address.
{
  inputs,
  cell,
}: {
  config,
  site,
  ...
}: let
  wan = config.router.ports.wan;
in {
  services.yggdrasil = {
    enable = true;
    # Read by systemd as root (LoadCredential); the DynamicUser never sees it.
    settings = {
      PrivateKeyPath = "/persist/var/lib/yggdrasil/private.pem";
      IfName = "ygg0";
      # Don't answer nodeinfo with build/platform details.
      NodeInfoPrivacy = true;
      # Direct peering on the WAN's public v6. QUIC avoids TCP-over-TCP stalls.
      Listen = [
        "tls://[::]:443"
        "quic://[::]:443"
      ];
      # Inbound peering only for these keys; outbound peers are unaffected.
      AllowedPublicKeys = site.yggdrasil.allowedPublicKeys;
      Peers = import ../../common/__yggdrasil-peers.nix;
    };
  };

  systemd.network.networks."50-ygg0" = {
    matchConfig.Name = "ygg0";
    linkConfig.Unmanaged = true;
  };

  networking.firewall.interfaces = {
    ygg0 = {
      allowedTCPPorts = [22];
      allowedUDPPortRanges = [
        {
          from = 60000;
          to = 61000;
        }
      ];
    };
    ${wan} = {
      allowedTCPPorts = [443];
      allowedUDPPorts = [443];
    };
  };
}
