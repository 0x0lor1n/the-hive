# Battery charge limit on the coreboot Precision 3520. Dell's threshold
# tokens went with its SMM, and the pack ignores the EC's own start/stop, so
# a timer toggles the EC's Peak Shift hold (__ec-charge.py). Every boot
# starts in `limit`; `charge-mode full` lasts until reboot.
{
  inputs,
  cell,
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hive.chargeHold;
  modes = ["limit" "full"];
  environment = {
    CHARGE_START = toString cfg.start;
    CHARGE_STOP = toString cfg.stop;
  };

  ec-charge = pkgs.writers.writePython3Bin "ec-charge" {flakeIgnore = ["E501"];} (builtins.readFile ./__ec-charge.py);

  charge-mode = pkgs.writeShellApplication {
    name = "charge-mode";
    runtimeInputs = [ec-charge pkgs.systemd];
    text = ''
      case "''${1:-status}" in
        status) ec-charge status ;;
        ${lib.concatStringsSep "|" modes}) systemctl start "charge-mode@$1.service" && ec-charge status ;;
        *) echo "usage: charge-mode [status|${lib.concatStringsSep "|" modes}]" >&2; exit 2 ;;
      esac
    '';
  };
in {
  options.hive.chargeHold = {
    start = lib.mkOption {
      type = lib.types.ints.between 5 100;
      default = 75;
      description = "Hold off (charging resumes) at or below this %.";
    };
    stop = lib.mkOption {
      type = lib.types.ints.between 5 100;
      default = 80;
      description = "Hold on (AC only, no charging) at or above this %.";
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.start < cfg.stop;
        message = "hive.chargeHold.start must be below stop";
      }
    ];

    environment.systemPackages = [charge-mode ec-charge];

    systemd.services.charge-hold = {
      description = "Battery charge hold (EC Peak Shift) at ${toString cfg.stop} %";
      inherit environment;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${ec-charge}/bin/ec-charge tick";
      };
    };
    systemd.timers.charge-hold = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "60s";
      };
    };

    systemd.services."charge-mode@" = {
      description = "Battery charge mode %i";
      inherit environment;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${ec-charge}/bin/ec-charge %i";
      };
    };

    # Same grant shape as cpu-governor.nix: only these unit names.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            (subject.isInGroup("wheel") || subject.isInGroup("networkmanager")) &&
            [${lib.concatMapStringsSep ", " (m: "\"charge-mode@${m}.service\"") modes}]
              .indexOf(action.lookup("unit")) >= 0) {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
