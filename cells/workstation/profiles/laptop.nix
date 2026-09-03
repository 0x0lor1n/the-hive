# Laptop shape: radios, lid, and the things a VM or a VPS never has.
# Battery tuning is deliberately absent -- penrose has no battery installed
# (dmidecode type 22 empty, no BAT0); add it when one shows up.
#
# NetworkManager rather than iwd: that is what the old install ran and what
# the user knows. wpa_supplicant is NM's default backend.
{
  inputs,
  cell,
}: {
  lib,
  host,
  ...
}: {
  networking.networkmanager.enable = true;
  # The local user manages connections without a polkit prompt.
  users.users.${host.userName}.extraGroups = ["networkmanager"];

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

  # NM state and pairing survive the @blank rollback.
  environment.persistence."/persist".directories = [
    "/etc/NetworkManager/system-connections"
    "/var/lib/bluetooth"
  ];
}
