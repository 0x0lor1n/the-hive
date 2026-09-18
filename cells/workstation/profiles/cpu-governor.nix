# CPU frequency policy, switched from the powermenu (home/desktop/menus.nix).
#
# intel_pstate in active mode exposes exactly two governors on this hardware,
# `performance` and `powersave` (verified on elster 2026-09-17:
# scaling_available_governors). Writing scaling_governor needs root, so the
# switch is a template unit both accounts reach over polkit; making the sysfs
# files group-writable through a udev rule would be the hack this repo avoids.
#
# Not a `powerManagement.cpuFreqGovernor` setting: that is a boot-time default,
# not something a menu can flip.
{
  inputs,
  cell,
}: {
  pkgs,
  lib,
  ...
}: let
  governors = ["performance" "powersave"];
in {
  systemd.services."cpu-governor@" = {
    description = "Set the CPU frequency governor to %i";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      ExecStart = "${pkgs.writeShellScript "cpu-governor" ''
        set -eu
        case "$1" in
          ${lib.concatStringsSep "|" governors}) ;;
          *) echo "unknown governor: $1" >&2; exit 2 ;;
        esac
        n=0
        for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
          [ -w "$f" ] || continue
          printf '%s' "$1" > "$f"
          n=$((n + 1))
        done
        # Writing nothing is a failure, not a no-op: the menu reports what
        # this unit returns.
        [ "$n" -gt 0 ] || { echo "no writable scaling_governor" >&2; exit 1; }
      ''} %i";
    };
  };

  # Both accounts may flip it: the Entra user is the desktop plane and has no
  # wheel (auth-entra.nix), so it goes by the networkmanager group the same way
  # the employer VPN units do (vpn.nix). Only these two unit names — the rule
  # must not become a general manage-units grant.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          (subject.isInGroup("wheel") || subject.isInGroup("networkmanager")) &&
          [${lib.concatMapStringsSep ", " (g: "\"cpu-governor@${g}.service\"") governors}]
            .indexOf(action.lookup("unit")) >= 0) {
        return polkit.Result.YES;
      }
    });
  '';
}
