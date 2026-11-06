# hisilo.me over Yggdrasil: a second, plain-HTTP door to the same site for
# people who already sit on the mesh. Separate node with its own key; it is
# NOT the home junction (minas-tirith yggdrasil.nix) and peers with public
# nodes only -- a tunnel to the home network from the public box would be the
# inbound path the launch plan forbids.
#
# The 201: address derives from the key, so the key is pinned: colmena uploads
# secrets/hisilome/yggdrasil-private.pem.age to /run/keys at deploy (see
# deploy-osgiliath.nix), same path as the icecast passwords. A new VPS with the
# same key keeps the address printed in the post.
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
      PrivateKeyPath = "/run/keys/yggdrasil-private.pem";
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

  # The key is uploaded pre-activation by colmena (keyServiceModule orders
  # yggdrasil after yggdrasil-private.pem-key.service); the nixpkgs module
  # hands it to the DynamicUser through LoadCredential. No key = unit fails =
  # no silently regenerated address.

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

  # Port 80 on ygg0 only. The WAN firewall rules (site-hisilome.nix) are
  # per-port, not per-interface, so 80 there is already open; this adds no
  # WAN exposure. ssh stays WAN-only: nothing on the mesh may log in.
  networking.firewall.interfaces.ygg0.allowedTCPPorts = [80];
}
