# `fast`: raidz1 over the three 1 TB NVMe behind the ASM2824, for service
# state (fast/services/<svc>). Created by hand on the live host, not in
# disks/imladris.nix: disko would re-create (wipe) it on a reinstall.
# No fileSystems entry points at it, so nothing imports it unless listed here.
#
# Disk health: drivetemp exposes SATA temperatures in hwmon (NVMe has its own
# hwmon already); smartd watches every disk and only logs, no mail.
{
  inputs,
  cell,
}: {pkgs, ...}: {
  boot.zfs.extraPools = ["fast"];

  boot.kernelModules = ["drivetemp"];

  services.smartd = {
    enable = true;
    # Don't wake spun-down HDDs just to poll them.
    defaults.monitored = "-a -o on -S on -n standby,q";
    notifications.mail.enable = false;
    notifications.wall.enable = false;
  };

  environment.systemPackages = [
    pkgs.lm_sensors
    pkgs.smartmontools
  ];
}
