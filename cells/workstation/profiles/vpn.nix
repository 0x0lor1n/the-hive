# The three VPN profiles as system units with agenix runtime secrets. Every
# credential is an age.secret in /run/agenix (root, 0400) rather than a
# home-manager file in the world-readable store, and the tunnels are ordinary
# systemd units the accounts start and stop over polkit:
#
#   o   wireguard  wg-quick-o.service    employer
#   t   openvpn    openvpn-t.service     employer's client
#   w   openvpn    openvpn-w.service     freelance client
#
# Letters, not names: which organisation sits behind each lives only in the
# encrypted halves (secrets/*.age, secrets/user-*.nix.age).
#
# All three belong to the Entra account (networkmanager group via himmelblau
# local_groups, auth-entra.nix); wheel keeps them for the local account.
# wheel alone is auth_admin_keep on manage-units, i.e. a password prompt on
# every `vpn up`, hence the explicit grant. Routing is host-global: a tunnel
# raised by one account carries the other's traffic too.
#
# `vpn up|down|status <name>` wraps systemctl for both accounts.
#
# Secret sources: secrets/vpn/<name>.age, rekeyed per host into
# secrets/rekeyed/<host>/ like the ssh identities. wg-quick takes the whole
# [Interface]/[Peer] file; openvpn takes the .ovpn verbatim (inline
# ca/cert/key, so the file itself is the secret) plus a two-line
# auth-user-pass file. Real hosts only: the VM has no rekeyed bundle.
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
  flakeRoot = inputs.self.outPath;
  secret = name: {
    rekeyFile = "${flakeRoot}/secrets/vpn/${name}.age";
    mode = "0400";
  };
  units = {
    o = "wg-quick-o.service";
    t = "openvpn-t.service";
    w = "openvpn-w.service";
  };
  vpn = pkgs.writeShellApplication {
    name = "vpn";
    runtimeInputs = [pkgs.systemd pkgs.coreutils];
    text = ''
      usage() {
        echo "usage: vpn up|down <${lib.concatStringsSep "|" (lib.attrNames units)}>   |   vpn status" >&2
        exit 2
      }
      unit() {
        case "$1" in
          ${lib.concatStringsSep "\n          " (lib.mapAttrsToList (n: u: "${n}) echo ${u} ;;") units)}
          *) usage ;;
        esac
      }
      case "''${1:-}" in
        up)   [ $# = 2 ] || usage; systemctl start "$(unit "$2")" ;;
        down) [ $# = 2 ] || usage; systemctl stop "$(unit "$2")" ;;
        status)
          for n in ${lib.concatStringsSep " " (lib.attrNames units)}; do
            printf '%-3s %s\n' "$n" "$(systemctl is-active "$(unit "$n")")"
          done ;;
        *) usage ;;
      esac
    '';
  };
in
  lib.mkIf (!host.isVm) {
    environment.systemPackages = [vpn pkgs.wireguard-tools];

    age.secrets = {
      vpn-o-conf = secret "o.conf";
      vpn-t-ovpn = secret "t.ovpn";
      vpn-t-auth = secret "t-auth";
      vpn-w-ovpn = secret "w.ovpn";
      vpn-w-auth = secret "w-auth";
    };

    # wg-quick reads DNS= itself (resolvconf), so the whole [Interface]/[Peer]
    # file is the secret; nothing to template.
    networking.wg-quick.interfaces.o = {
      configFile = config.age.secrets.vpn-o-conf.path;
      autostart = false;
    };

    services.openvpn.servers = let
      ovpn = name: pushedDns: {
        config = ''
          config ${config.age.secrets."vpn-${name}-ovpn".path}
          auth-user-pass ${config.age.secrets."vpn-${name}-auth".path}
        '';
        autoStart = false;
        updateResolvConf = pushedDns;
      };
    in {
      t = ovpn "t" false;
      # Split-horizon: the pushed resolver answers internal 10.x for hosts
      # whose public addresses are dead from inside the tunnel.
      w = ovpn "w" true;
    };

    # AUTH_FAILED (MFA push not yet approved) exits 0; Restart=always turned
    # that into a push storm. Link drops are handled in-process by ping-restart.
    systemd.services.openvpn-w.serviceConfig.Restart = lib.mkForce "on-failure";

    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        var units = ${builtins.toJSON (lib.attrValues units)};
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            (subject.isInGroup("networkmanager") || subject.isInGroup("wheel")) &&
            units.indexOf(action.lookup("unit")) >= 0) {
          return polkit.Result.YES;
        }
      });
    '';
  }
