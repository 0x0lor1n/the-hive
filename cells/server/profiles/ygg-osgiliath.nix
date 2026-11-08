# hisilo.me over Yggdrasil: a second, plain-HTTP door to the same site for
# people who already sit on the mesh. Separate node with its own key; it is
# NOT the home junction (minas-tirith yggdrasil.nix) and peers with public
# nodes only -- a tunnel to the home network from the public box would be the
# inbound path the launch plan forbids.
#
# The 201: address derives from the key, so the key is pinned: colmena uploads
# secrets/hisilome/yggdrasil-private.pem.age to /persist (deploy-osgiliath.nix).
# Not /run/keys: ssh rides this tunnel, so after a reboot ygg must come up
# before colmena can reach the box again.
#
# Address: 201:f885:7585:1739:35f4:1185:b21e:967d  (public key
# 41dea29e…699ede; both are derived, not secret, and may be published.)
{
  inputs,
  cell,
}: {
  config,
  lib,
  ...
}: let
  yggAddr = "201:f885:7585:1739:35f4:1185:b21e:967d";
in {
  services.yggdrasil = {
    enable = true;
    # Not `persistentKeys`: that generates on first boot, i.e. a new address
    # on every reinstall.
    settings = {
      PrivateKeyPath = "/persist/var/lib/yggdrasil/private.pem";
      IfName = "ygg0";
      IfMTU = 1280;
      NodeInfoPrivacy = true;
      # No Listen: this node accepts no inbound peerings and never answers on
      # the WAN; it dials out to public peers and that is the whole mesh
      # footprint. AllowedPublicKeys stays empty = nobody may peer in.
      Listen = [];
      Peers = import ../../common/__yggdrasil-peers.nix;
    };
  };

  # No key = unit fails = no silently regenerated address.

  systemd.network.networks."50-ygg0" = {
    matchConfig.Name = "ygg0";
    linkConfig.Unmanaged = true;
  };

  # nginx binds the ygg address explicitly; it exists only once the tunnel is
  # up, so let the socket bind lazily instead of failing nginx at boot.
  boot.kernel.sysctl."net.ipv6.ip_nonlocal_bind" = 1;

  services.hisilome.overlayListen = [
    {
      addr = "[${yggAddr}]";
      port = 80;
    }
  ];

  # No source filter on 22: an allowlist would put a home ygg address on the box.
  networking.firewall.interfaces.ygg0.allowedTCPPorts = [80 22];
}
