# Laptop shape: radios, lid, and the things a server never has.
# Battery charge limit: device-battery-dell-ec.nix (penrose).
#
# NetworkManager rather than iwd; wpa_supplicant is NM's default backend.
{
  inputs,
  cell,
}: {
  lib,
  pkgs,
  config,
  ...
}: {
  # The machine lives in Geneva; base.nix's UTC is a mkDefault for servers.
  time.timeZone = "Europe/Zurich";

  networking.networkmanager.enable = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };

  # Lid: with no battery the machine lives on AC; closing the lid should not
  # suspend a box that may be running builds over ssh.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
  };

  # Printing: CUPS, driverless (IPP Everywhere). avahi + nssmdns4 lets
  # printers that announce over mDNS show up in CUPS without knowing an IP.
  services.printing = {
    enable = true;
    drivers = [pkgs.cups-filters];
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    # Announce ourselves too (off by default): the `Host <peer>` entries in
    # layer-users-local point at <name>.local, both laptops are DHCP.
    settings.publish = {
      disable-publishing = false;
      publish-addresses = true;
    };
  };
  # `lp` group: add/remove printers and use the CUPS web UI without root.
  users.users = lib.genAttrs config.hive.localUsers (_: {extraGroups = ["networkmanager" "lp"];});

  # NM state, pairing, and printers survive the @blank rollback.
  environment.persistence."/persist".directories = [
    "/etc/NetworkManager/system-connections"
    "/var/lib/bluetooth"
    "/var/lib/cups"
  ];
}
