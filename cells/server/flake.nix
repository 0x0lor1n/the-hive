{
  inputs = {
    utils.url = "gitlab:rensa-nix/utils/v0.1.2?dir=lib";
    disko.url = "github:nix-community/disko/65fb947964bd44fc0008faf77d1fcb7a9f40bb32";
    # The site + radio station, consumed only by profiles/site-hisilome.nix.
    # Its NixOS module builds with the host's pkgs (i.parent.pkgs), so its own
    # nixpkgs is lock-only: nothing in the osgiliath closure comes from it.
    # Pinned by rev; bump deliberately after `nix build github:0x0lor1n/hisilome`.
    hisilome.url = "github:0x0lor1n/hisilome/70c516938a04fbcf572d43e4967364e3db8ac7b4";

    # agenix for ZFS hosts; pins match cells/workstation, else a second copy.
    nixpkgs.url = "github:NixOS/nixpkgs/34ab99075ac4f7e40cf037eef32cb1c360bb85e9";
    agenix.url = "github:ryantm/agenix/b027ee29d959fda4b60b57566d64c98a202e0feb";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix-rekey.url = "github:oddlama/agenix-rekey/8b9c179bc1300ab130c90f2d25426bf0e7a2b58d";
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";
    # colmena deliberately not declared: its nixosModules must come from the
    # root pin that colmenaHive reads __schema from.
  };

  outputs = i:
    i
    // {
      utilsLib = i.utils.lib {inherit (i.parent.pkgs) lib;};
    };
}
