{
  # The point of the whole exercise: this cell lists ONLY what a headless
  # server needs. lanzaboote / nix-cachyos-kernel / himmelblau / tuigreet /
  # home-manager belong to cells/workstation and are never fetched here.
  inputs = {
    utils.url = "gitlab:rensa-nix/utils/v0.1.2?dir=lib";
    disko.url = "github:nix-community/disko/65fb947964bd44fc0008faf77d1fcb7a9f40bb32";
    colmena.url = "github:zhaofengli/colmena/dc22786a43315b212eeafe13409a7203328e5a30";
  };

  outputs = i:
    i
    // {
      # instantiate against the parent's single pkgs, per rensa's
      # "single instantiation" guidance
      utilsLib = i.utils.lib {inherit (i.parent.pkgs) lib;};
    };
}
