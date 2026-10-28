# employer: the employer (o) and its client (t). System side is vpn-o
# (wireguard), vpn-t (openvpn) and the o/t ssh keys (secrets.nix). The M365
# sign-in the employer's apps use is auth-entra.nix, which follows the
# account's auth, not this role.
{
  inputs,
  cell,
}: {
  pkgs,
  lib,
  config,
  host,
  ...
}: let
  vpn = import ./__vpn-lib.nix {inherit inputs config;};
in
  lib.mkIf (!host.isVm && config.hive.roleHolders.employer != []) {
    hive.tunnels = {
      vpn-o = "wg-quick-o.service";
      vpn-t = "openvpn-t.service";
    };

    environment.systemPackages = [pkgs.wireguard-tools];

    age.secrets = {
      vpn-o-conf = vpn.secret "o.conf";
      vpn-t-ovpn = vpn.secret "t.ovpn";
      vpn-t-auth = vpn.secret "t-auth";
    };

    # wg-quick reads DNS= itself (resolvconf), so the whole [Interface]/[Peer]
    # file is the secret; nothing to template.
    networking.wg-quick.interfaces.o = {
      configFile = config.age.secrets.vpn-o-conf.path;
      autostart = false;
    };

    # The server pushes its resolver as `dns server ...` (2.6 syntax), which
    # update-resolv-conf does not see; restate it as dhcp-option so
    # openresolv picks it up while the tunnel is up.
    services.openvpn.servers.t = vpn.ovpn "t" true ''
      dhcp-option DNS 10.109.0.2
    '';
  }
