# Ergohaven split keyboard + Vial. Workstation-wide, not per host: it is the
# user's daily keyboard and follows them to every machine.
#
# Ported verbatim from ~/nixos-config/config/hardware/ergohaven.nix: the udev
# rule is Vial's documented one, matched on the firmware's vial serial tag so
# the raw HID node is user-accessible without root.
{
  inputs,
  cell,
}: {pkgs, ...}: {
  environment.systemPackages = [pkgs.vial];

  services.udev.extraRules = ''
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{serial}=="*vial:f64c2b3c*", MODE="0660", GROUP="users", TAG+="uaccess", TAG+="udev-acl"
  '';
}
