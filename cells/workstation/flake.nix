{
  # Workstation-only inputs. Deliberately NOT root or common inputs: a root
  # input is fetched by every host, and cells/server must never gain lanzaboote
  # or mkcreds (see .hermes/state/port-test-vm.md -> server-isolation).
  inputs = {
    # Cell flakes cannot follow a root input, so lanzaboote's nixpkgs is pinned
    # here to the SAME rev as the root flake.lock. Keep them equal when bumping,
    # or lanzaboote's Rust toolchain is built from a second nixpkgs.
    nixpkgs.url = "github:NixOS/nixpkgs/34ab99075ac4f7e40cf037eef32cb1c360bb85e9";

    utils.url = "gitlab:rensa-nix/utils/v0.1.2?dir=lib";
    disko.url = "github:nix-community/disko/65fb947964bd44fc0008faf77d1fcb7a9f40bb32";

    # test-vm booted v1.0.0 (e8c096a), but it sets boot.bootspec.enable, which
    # the root nixpkgs pin has since removed (hard assertion). Master no longer
    # sets it; the options used here (pkiBundle, autoGenerateKeys, autoEnrollKeys)
    # are unchanged between the two.
    lanzaboote.url = "github:nix-community/lanzaboote/d2326588612480c96d5fefb885f57b4660a85584";
    lanzaboote.inputs.nixpkgs.follows = "nixpkgs";
    # Same pin as test-vm. Seals a systemd credential against a PREDICTED PCR 15
    # (systemd#38763).
    mkcreds.url = "github:codgician/mkcreds/112d95f75913829b5ac54d7608b384a0f242e09e";
    mkcreds.inputs.nixpkgs.follows = "nixpkgs";
    # Same pins as test-vm. Server secrets stay on colmena deployment.keys.
    agenix.url = "github:ryantm/agenix/b027ee29d959fda4b60b57566d64c98a202e0feb";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix-rekey.url = "github:oddlama/agenix-rekey/8b9c179bc1300ab130c90f2d25426bf0e7a2b58d";
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";
    # Same rev test-vm's flake.lock resolved from himmelblau main. auth-entra.nix
    # patches the source (libhimmelblau bump, tpm feature), so bump deliberately.
    himmelblau.url = "github:himmelblau-idm/himmelblau/791372aad3c5bce2baddd5b794399f58fbd56c61";
    himmelblau.inputs.nixpkgs.follows = "nixpkgs";
    # Same branch as test-vm; used ONLY as a NixOS module (home-manager.users),
    # never standalone (utils.mkHome is broken upstream). release-25.05 against
    # an unstable nixpkgs is intentional, home.enableNixpkgsReleaseCheck = false.
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # tuigreet is NOT an input: the nixpkgs pin already ships the maintained
    # fork (tuigreet/tuigreet 0.11.1, ex NotAShelf) that test-vm overlaid in.
    # colmena deliberately not declared: this cell is never deployed by colmena.
  };

  outputs = i:
    i
    // {
      utilsLib = i.utils.lib {inherit (i.parent.pkgs) lib;};
    };
}
