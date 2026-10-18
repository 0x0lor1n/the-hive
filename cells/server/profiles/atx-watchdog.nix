# Pro Micro on JCOM1 (/dev/ttyS0) drives the power switch: the B250 PCH
# cannot reboot or power off by itself, so reboot/poweroff hang without this.
{
  inputs,
  cell,
}: {...}: {
  imports = [inputs.atx-watchdog.nixosModules.default];

  services.atx-watchdog = {
    enable = true;
    probeDirs = ["/tank"];
  };
}
