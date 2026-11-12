# The office HP (static IP set on the device; mDNS is filtered on the office
# Wi-Fi) so declare it by IP. Address lives in the encrypted globals half,
# not this public file. Driverless via IPP Everywhere. Only where an
# account carries the employer role: elsewhere ensure-printers would time
# out against an address that is never on the LAN.
{
  inputs,
  cell,
}: {
  lib,
  config,
  globals,
  ...
}: {
  hardware.printers = lib.mkIf (globals.office.printer.address != null && config.hive.roleHolders.employer != []) {
    ensureDefaultPrinter = "work-hp";
    ensurePrinters = [
      {
        name = "work-hp";
        description = "Office HP LaserJet MFP";
        location = "Office";
        deviceUri = "ipp://${globals.office.printer.address}/ipp/print";
        model = "everywhere";
        ppdOptions = {
          PageSize = "A4";
          Duplex = "DuplexNoTumble";
        };
      }
    ];
  };
}
