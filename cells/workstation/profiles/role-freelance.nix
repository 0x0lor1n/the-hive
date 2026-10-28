# freelance: client work under the user's own name. System side is vpn-w
# (openvpn) and the w ssh keys (secrets.nix). Only on hosts where some
# account holds the role; the `vpn` wrapper and its polkit rule are vpn.nix.
{
  inputs,
  cell,
}: {
  lib,
  config,
  host,
  ...
}: let
  vpn = import ./__vpn-lib.nix {inherit inputs config;};
in
  lib.mkIf (!host.isVm && config.hive.roleHolders.freelance != []) {
    hive.tunnels.vpn-w = "openvpn-w.service";

    age.secrets = {
      vpn-w-ovpn = vpn.secret "w.ovpn";
      vpn-w-auth = vpn.secret "w-auth";
    };

    # Split-horizon: the pushed resolver answers internal 10.x for hosts
    # whose public addresses are dead from inside the tunnel.
    # redirect-gateway takes api.anthropic.com too, and it is unreachable
    # through w (pxpipe 502s); send Anthropic's inbound /23 around it.
    # The client's network overlaps the home LAN (192.168.10.0/24); the
    # on-link route beats redirect-gateway's /1s, so the hosts reached on
    # their side need a /32 into the tunnel. Home .33 is unreachable while w is up.
    services.openvpn.servers.w = vpn.ovpn "w" true ''
      route 160.79.104.0 255.255.254.0 net_gateway
      route 192.168.10.33 255.255.255.255 vpn_gateway
    '';

    # AUTH_FAILED (MFA push not yet approved) exits 0; Restart=always turned
    # that into a push storm. Link drops are handled in-process by ping-restart.
    systemd.services.openvpn-w.serviceConfig.Restart = lib.mkForce "on-failure";
  }
