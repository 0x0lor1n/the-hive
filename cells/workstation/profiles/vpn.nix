# The three VPN profiles from jarvis (users/shared/security/vpn.nix), as
# system units with agenix runtime secrets instead of home-manager files.
#
# Why not the home module 1:1: jarvis rendered the wireguard PrivateKey and
# the openvpn auth-user-pass files through xdg.configFile.text, i.e. into
# the world-readable nix store (flagged in the port plan). Here every
# credential is an age.secret in /run/agenix (root, 0400), and the tunnels
# are ordinary systemd units the accounts start and stop over polkit:
#
#   owt   wireguard  wg-quick-owt.service    Entra (employer)
#   tiko  openvpn    openvpn-tiko.service    Entra (employer)
#   wrs   openvpn    openvpn-wrs.service     local (freelance client)
#
# The account split is enforced by polkit, not by which home carries an
# alias: the networkmanager group (himmelblau local_groups, auth-entra.nix)
# may manage the two employer units; the local user is wheel and may manage
# anything. Routing is host-global by design (plan: "SETTLED"): a tunnel
# raised by one account carries the other's traffic too.
#
# `vpn up|down|status <name>` wraps systemctl for both accounts.
#
# Secret sources: secrets/vpn/<name>.age (master identities + recovery),
# rekeyed per host into secrets/rekeyed/<host>/ like the ssh identities;
# the plaintexts came out of jarvis's vpn-{owt,tiko,wrs}.nix.age +
# user.nix.age (decrypted once on penrose with the PIN identity). wg-quick
# takes the whole [Interface]/[Peer] file; openvpn takes the .ovpn verbatim
# (inline ca/cert/key, so the file itself is the secret) plus a two-line
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
    owt = "wg-quick-owt.service";
    tiko = "openvpn-tiko.service";
    wrs = "openvpn-wrs.service";
  };
  vpn = pkgs.writeShellApplication {
    name = "vpn";
    runtimeInputs = [pkgs.systemd pkgs.coreutils];
    text = ''
      usage() {
        echo "usage: vpn up|down <owt|tiko|wrs>   |   vpn status" >&2
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
            printf '%-5s %s\n' "$n" "$(systemctl is-active "$(unit "$n")")"
          done ;;
        *) usage ;;
      esac
    '';
  };
in
  lib.mkIf (!host.isVm) {
    environment.systemPackages = [vpn pkgs.wireguard-tools];

    age.secrets = {
      vpn-owt-conf = secret "owt.conf";
      vpn-tiko-ovpn = secret "tiko.ovpn";
      vpn-tiko-auth = secret "tiko-auth";
      vpn-wrs-ovpn = secret "wrs.ovpn";
      vpn-wrs-auth = secret "wrs-auth";
    };

    # wg-quick reads DNS= itself (resolvconf), so the whole jarvis
    # [Interface]/[Peer] file is the secret; nothing to template.
    networking.wg-quick.interfaces.owt = {
      configFile = config.age.secrets.vpn-owt-conf.path;
      autostart = false;
    };

    services.openvpn.servers = let
      ovpn = name: {
        config = ''
          config ${config.age.secrets."vpn-${name}-ovpn".path}
          auth-user-pass ${config.age.secrets."vpn-${name}-auth".path}
        '';
        autoStart = false;
        # jarvis ran plain `sudo openvpn --config`, no resolvconf hook; keep
        # that until a profile is seen to need pushed DNS.
        updateResolvConf = false;
      };
    in {
      tiko = ovpn "tiko";
      wrs = ovpn "wrs";
    };

    # The Entra account (no wheel) may raise and drop the two employer
    # tunnels; nothing else in systemd. wrs stays with the local user (wheel).
    # wheel alone is auth_admin_keep on manage-units (password prompt every
    # `vpn up wrs`, seen 2026-09-15), so grant that one unit explicitly too —
    # symmetric with owt/tiko on the Entra side, checklist says "no password".
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            subject.isInGroup("networkmanager") &&
            (action.lookup("unit") == "${units.owt}" ||
             action.lookup("unit") == "${units.tiko}")) {
          return polkit.Result.YES;
        }
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            subject.isInGroup("wheel") &&
            action.lookup("unit") == "${units.wrs}") {
          return polkit.Result.YES;
        }
      });
    '';
  }
