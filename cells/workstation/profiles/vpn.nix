# The `vpn` CLI over every on-demand tunnel on the host. Tunnels themselves
# come from the role that needs them, registered in hive.tunnels:
#
#   vpn-o      wireguard  wg-quick-o.service   employer   role-employer.nix
#   vpn-t      openvpn    openvpn-t.service    employer   role-employer.nix
#   vpn-w      openvpn    openvpn-w.service    freelance  role-freelance.nix
#   yggdrasil  yggstack   yggstack.service     any        ygg-client.nix
#
# Letters, not names: which organisation sits behind each lives only in the
# encrypted halves (secrets/*.age, secrets/user-*.nix.age). Every credential
# is an age.secret in /run/agenix (root, 0400), never a world-readable store
# file.
#
# networkmanager (Entra via himmelblau local_groups, auth-entra.nix) and
# wheel may start/stop exactly these units. wheel alone is auth_admin_keep on
# manage-units, i.e. a password prompt on every `vpn up`, hence the explicit
# grant. Routing is host-global: a tunnel raised by one account carries the
# other's traffic too.
#
# `vpn up|down|status <name>` wraps systemctl for every account.
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
