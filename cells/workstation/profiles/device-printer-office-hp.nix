# The office HP (static IP set on the device; mDNS is filtered on the office
# Wi-Fi) so declare it by IP. Address lives in the encrypted globals half,
# not this public file. Driverless via IPP Everywhere. Only where an
# account carries the employer role.
#
# Not hardware.printers: its lpadmin runs in cups' ExecStartPost, which
# fails while the printer is unreachable and takes cupsd down to
# start-limit-hit off the office LAN. The queue persists in printers.conf.
{
  inputs,
  cell,
}: {
  lib,
  pkgs,
  config,
  globals,
  ...
}: let
  addr = globals.office.printer.address;
in
  lib.mkIf (addr != null && config.hive.roleHolders.employer != []) {
    systemd.services.ensure-printers = {
      description = "Add the office HP queue to CUPS";
      requires = ["cups.service"];
      after = ["cups.service"];
      path = [config.services.printing.package];
      serviceConfig.Type = "oneshot";
      script = ''
        lpadmin -p work-hp -E -v ipp://${addr}/ipp/print -m everywhere \
          -L Office -D "Office HP LaserJet MFP" \
          -o PageSize=A4 -o Duplex=DuplexNoTumble
        lpadmin -d work-hp
      '';
    };

    networking.networkmanager.dispatcherScripts = [
      {
        source = pkgs.writeShellScript "office-printer" ''
          [ "$2" = up ] && [ "$CONNECTION_ID" = corporate ] || exit 0
          exec ${config.systemd.package}/bin/systemctl start --no-block ensure-printers.service
        '';
      }
    ];
  }
