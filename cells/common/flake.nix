{
  # Shared by every machine class. Workstation-only inputs belong in their own
  # cell: a root or common input is fetched by every host.
  inputs = {
    impermanence.url = "github:nix-community/impermanence/fa627f4c8b8e92f58f58a73d99ee4e1304e64eb2";
    utils.url = "gitlab:rensa-nix/utils/v0.1.2?dir=lib";
  };

  outputs = i:
    i
    // {
      utilsLib = i.utils.lib {inherit (i.parent.pkgs) lib;};
    };
}
