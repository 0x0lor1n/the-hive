{
  inputs = {
    utils.url = "gitlab:rensa-nix/utils/v0.1.2?dir=lib";
    disko.url = "github:nix-community/disko/65fb947964bd44fc0008faf77d1fcb7a9f40bb32";
    # The site + radio station, consumed only by profiles/site-hisilome.nix.
    # Its NixOS module builds with the host's pkgs (i.parent.pkgs), so its own
    # nixpkgs is lock-only: nothing in the osgiliath closure comes from it.
    # Pinned by rev; bump deliberately after `nix build github:0x0lor1n/hisilome`.
    hisilome.url = "github:0x0lor1n/hisilome/50a725320fde7d321b5b92dd6179d32fe532dfc4";
    # colmena deliberately not declared: its nixosModules must come from the
    # root pin that colmenaHive reads __schema from.
  };

  outputs = i:
    i
    // {
      utilsLib = i.utils.lib {inherit (i.parent.pkgs) lib;};
    };
}
