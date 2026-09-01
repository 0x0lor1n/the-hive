{
  # Shared by every machine class. Deliberately small: anything only a
  # workstation needs (lanzaboote, nix-cachyos-kernel, himmelblau, tuigreet,
  # home-manager, mkcreds) belongs in cells/workstation and must never appear
  # here, or the isolation proven by spike C is lost.
  inputs = {
    impermanence.url = "github:nix-community/impermanence/7b1d382faf603b6d264f58627330f9faa5cba149";
    utils.url = "gitlab:rensa-nix/utils/v0.1.2?dir=lib";
  };

  outputs = i:
    i
    // {
      # instantiated against the parent's single pkgs, per rensa's
      # "single instantiation" guidance
      utilsLib = i.utils.lib {inherit (i.parent.pkgs) lib;};
    };
}
