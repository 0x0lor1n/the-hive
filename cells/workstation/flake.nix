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
    # colmena deliberately not declared: this cell is never deployed by colmena.
  };

  outputs = i:
    i
    // {
      utilsLib = i.utils.lib {inherit (i.parent.pkgs) lib;};
    };
}
