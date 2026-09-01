# SPIKE B: can colmena be driven from what utils.mkSystem produces?
#
# mkSystem returns a standard eval-config.nix result, so .config.system.build
# .toplevel and .config.deployment should both be present. Colmena's four
# nixosModules are imported here so `deployment.*` exists at all.
{
  inputs,
  cell,
  system,
  ...
}: let
  inherit (inputs) utilsLib disko colmena pkgs;
in {
  spike-host = utilsLib.mkSystem {
    ren = {
      inherit system pkgs;
      inherit disko;
    };

    imports = [
      colmena.nixosModules.deploymentOptions
      colmena.nixosModules.keyChownModule
      colmena.nixosModules.keyServiceModule
      colmena.nixosModules.assertionModule
    ];

    networking.hostName = "spike-host";
    system.stateVersion = "24.11";
    boot.loader.grub.devices = ["/dev/vda"];
    fileSystems."/" = {
      device = "/dev/vda1";
      fsType = "ext4";
    };

    deployment = {
      targetHost = "198.51.100.10"; # TEST-NET-2, deliberately not a real host
      targetUser = "root";
      buildOnTarget = false;
      tags = ["spike"];
    };
  };
}
