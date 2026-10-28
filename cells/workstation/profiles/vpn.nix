# `vpn up|down|status <name>` over hive.tunnels (role-*.nix, ygg-client.nix).
# Routing is host-global: one account's tunnel carries the other's traffic.
{
  pkgs,
  lib,
  config,
  host,
  ...
}: let
  units = config.hive.tunnels;
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
        # Resolve first: usage() inside $(...) only leaves the subshell.
        up)   [ $# = 2 ] || usage; u=$(unit "$2"); systemctl start "$u" ;;
        down) [ $# = 2 ] || usage; u=$(unit "$2"); systemctl stop "$u" ;;
        status)
          for n in ${lib.concatStringsSep " " (lib.attrNames units)}; do
            printf '%-10s %s\n' "$n" "$(systemctl is-active "$(unit "$n")")"
          done ;;
        *) usage ;;
      esac
    '';
  };
in {
  # name -> systemd unit. Everything that can be flipped from `vpn` / vpnmenu
  # / the bar.
  options.hive.tunnels = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = {};
  };

  config = lib.mkIf (!host.isVm) {
    environment.systemPackages = [vpn];

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
  };
}
