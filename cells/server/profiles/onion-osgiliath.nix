# hisilo.me as a v3 onion: Tor on the box, nginx on a loopback port, no
# clearnet exposure of either. Same site, same location set as the ygg door
# (services.hisilome.overlayListen), no TLS because the onion IS the
# transport auth.
#
# The .onion name derives from hs_ed25519_secret_key, so the key is pinned:
# colmena uploads secrets/hisilome/onion-hs_ed25519_secret_key.age to
# /run/keys (deploy-osgiliath.nix); the nixpkgs module's root ExecStartPre
# copies it into /run/tor/onion/hisilome/ before tor drops privileges. A new
# VPS with the same key keeps the name printed in the post.
#
# Name: hisilojocbfh7h3qnp5dssb6xukuq2q3sd4jc5hrgajazsokpgsq5pqd.onion
# (mkp224o vanity "hisilo", 2026-11-06; the name is public by definition.)
{
  inputs,
  cell,
}: {...}: let
  onion = "hisilojocbfh7h3qnp5dssb6xukuq2q3sd4jc5hrgajazsokpgsq5pqd.onion";
  # Loopback only. Not 8000/8080: those are the station's internal ports.
  onionPort = 8081;
in {
  services.tor = {
    enable = true;
    # Not a relay, not a client SOCKS: nothing on this box needs to reach
    # the Tor network outbound, and relaying would make the VPS a public
    # Tor node with the traffic and attention that brings.
    client.enable = false;
    relay.onionServices.hisilome = {
      version = 3;
      secretKey = "/run/keys/onion-hs_ed25519_secret_key";
      map = [
        {
          port = 80;
          target = {
            addr = "127.0.0.1";
            port = onionPort;
          };
        }
      ];
    };
    settings = {
      # Onion-only daemon: no SOCKS listener at all.
      SOCKSPort = [];
      # Vanguards-lite style defence against guard discovery is on by default
      # in 0.4.7+; keep the hs-side defaults otherwise.
    };
  };

  # Key is a colmena deployment.key: tor.service is ordered after
  # onion-hs_ed25519_secret_key-key.service by colmena's keyServiceModule.

  services.hisilome.overlayListen = [
    {
      addr = "127.0.0.1";
      port = onionPort;
    }
  ];

  # Tor users already know where they are; the header is for clearnet
  # visitors whose Tor Browser can offer the upgrade.
  services.hisilome.onionLocation = onion;

  # Nothing opens in the firewall: nginx listens on loopback, tor dials out.
}
