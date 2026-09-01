# Disks, one file per device. Merged into `disko.devices` by
# `utils.collectDisks cell.disks` in nixosConfigurations.nix -- rensa's
# intended idiom, replacing test-vm's single diskoConfigurations.nix with its
# mkDisk/mkBtrfsDisk helpers.
{
  inputs,
  cell,
  system,
  ...
}:
inputs.utilsLib.importModules {
  dir = ./.;
  args = {inherit inputs cell system;};
  usePathAsKeys = true;
}
