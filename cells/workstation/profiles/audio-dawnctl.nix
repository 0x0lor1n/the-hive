# Moondrop DAWN PRO 2: dawnctl CLI + udev uaccess on its hidraw node, so the
# seat user drives the DAC without root. elster-only (raptorLaptop): the input
# is a local checkout under /srv/workspace that other hosts do not have.
{
  inputs,
  cell,
}: {
  imports = [inputs.dawnctl.nixosModules.default];
  services.dawnctl.enable = true;
}
