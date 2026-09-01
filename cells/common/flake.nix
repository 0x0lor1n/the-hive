{
  # Shared by every machine class. Workstation-only inputs belong in their own
  # cell: a root or common input is fetched by every host.
  inputs = {
    impermanence.url = "github:nix-community/impermanence/7b1d382faf603b6d264f58627330f9faa5cba149";
    utils.url = "gitlab:rensa-nix/utils/v0.1.2?dir=lib";
  };

  outputs = i:
    i
    // {
      utilsLib = i.utils.lib {inherit (i.parent.pkgs) lib;};
    };
}
