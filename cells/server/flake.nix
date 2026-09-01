{
  # The point of the whole exercise: this cell lists ONLY what a headless
  # server needs. lanzaboote / nix-cachyos-kernel / himmelblau / tuigreet /
  # home-manager belong to cells/workstation and are never fetched here.
  inputs = {
    utils.url = "gitlab:rensa-nix/utils/v0.1.2?dir=lib";
    disko.url = "github:nix-community/disko/65fb947964bd44fc0008faf77d1fcb7a9f40bb32";
    # colmena is NOT declared here: its nixosModules must come from the same pin
    # the root reads `__schema` from, or the deployed modules and the CLI schema
    # can drift apart. Cell blocks see root inputs, so `inputs.colmena` resolves
    # to that one pin.
  };

  outputs = i:
    i
    // {
      # instantiate against the parent's single pkgs, per rensa's
      # "single instantiation" guidance
      utilsLib = i.utils.lib {inherit (i.parent.pkgs) lib;};
    };
}
