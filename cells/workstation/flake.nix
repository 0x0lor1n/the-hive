{
  # Workstation-only inputs, not root or common inputs: a root input is fetched
  # by every host, and cells/server must never gain lanzaboote or mkcreds in
  # its closure.
  inputs = {
    # Cell flakes cannot follow a root input, so lanzaboote's nixpkgs is pinned
    # here to the same rev as the root flake.lock. Keep them equal when
    # bumping, or lanzaboote's Rust toolchain builds from a second nixpkgs.
    nixpkgs.url = "github:NixOS/nixpkgs/34ab99075ac4f7e40cf037eef32cb1c360bb85e9";

    utils.url = "gitlab:rensa-nix/utils/v0.1.2?dir=lib";
    disko.url = "github:nix-community/disko/65fb947964bd44fc0008faf77d1fcb7a9f40bb32";

    # Not the v1.0.0 tag: it sets boot.bootspec.enable, which the nixpkgs pin
    # has removed (hard assertion). Master no longer sets it; the options used
    # here (pkiBundle, autoGenerateKeys, autoEnrollKeys) are unchanged.
    lanzaboote.url = "github:nix-community/lanzaboote/d2326588612480c96d5fefb885f57b4660a85584";
    lanzaboote.inputs.nixpkgs.follows = "nixpkgs";
    # Seals a systemd credential against a predicted PCR 15 (systemd#38763).
    mkcreds.url = "github:codgician/mkcreds/112d95f75913829b5ac54d7608b384a0f242e09e";
    mkcreds.inputs.nixpkgs.follows = "nixpkgs";
    # Workstation secrets only; server secrets stay on colmena deployment.keys.
    agenix.url = "github:ryantm/agenix/b027ee29d959fda4b60b57566d64c98a202e0feb";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    agenix-rekey.url = "github:oddlama/agenix-rekey/8b9c179bc1300ab130c90f2d25426bf0e7a2b58d";
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";
    # Pinned to a main rev, not a release: auth-entra.nix patches the source
    # (libhimmelblau bump, tpm feature), so bump deliberately.
    himmelblau.url = "github:himmelblau-idm/himmelblau/791372aad3c5bce2baddd5b794399f58fbd56c61";
    himmelblau.inputs.nixpkgs.follows = "nixpkgs";
    # Used only as a NixOS module (home-manager.users), never standalone
    # (utils.mkHome is broken upstream). release-25.05 against an unstable
    # nixpkgs is intentional, home.enableNixpkgsReleaseCheck = false.
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # CachyOS kernel + matching zfs_cachyos, pre-built on nyx-cache.chaotic.cx.
    # Pinned to the nyx rev whose own nixpkgs lock == our nixpkgs pin above
    # (34ab9907); any drift between the two turns the kernel into a local
    # build. Bump both together. Only the overlay is consumed (layer-kernel);
    # nyx's NixOS modules are not imported (mkSystem passes a ready `pkgs`, so
    # `nixpkgs.overlays` from a module would be silently ignored anyway).
    chaotic.url = "github:chaotic-cx/nyx/43fe06999491eabd2ec15c221f5066e39d6a5a51";
    chaotic.inputs.nixpkgs.follows = "nixpkgs";
    # bwrap + xdg-dbus-proxy sandboxes for untrusted desktop apps (packages.nix).
    # Only lib.nixpak is consumed; its NixOS module targets systemPackages.
    nixpak.url = "github:nixpak/nixpak/333bd8c7ca0c014e61be1933b3c131c9dfa20218";
    nixpak.inputs.nixpkgs.follows = "nixpkgs";
    # Firefox hardening (policies.json + phoenix.cfg) for the Entra user's
    # browser. Pinned to a release tag; `dev` is the default branch and moves
    # daily. Two halves, both needed: `overlays.default` (withPhoenix wrapper)
    # goes through inputs.pkgs.extend in nixosConfigurations.nix -- a module's
    # nixpkgs.overlays is ignored here -- and nixosModules.default supplies the
    # /etc/firefox files + programs.firefox.policies.
    phoenix.url = "git+https://gitlab.com/celenityy/Phoenix?ref=refs/tags/2026.09.01.1";
    phoenix.inputs.nixpkgs.follows = "nixpkgs";
    # Spotify client patching (adblock, keyboardShortcut, ...) for the desktop
    # home. Consumed as a home-manager module + legacyPackages catalogue; its
    # nixpkgs is a channel tarball, so follow ours. Weekly "CI update" bumps
    # track Spotify's own releases; pin to the current HEAD, bump on demand.
    spicetify.url = "github:Gerg-L/spicetify-nix/09eed5c95105aada9ffabd4c7eb6b345dc4ba66f";
    spicetify.inputs.nixpkgs.follows = "nixpkgs";
    # zsh-defer / zsh-vi-mode / llm-agents are not inputs: the first two ship
    # in the nixpkgs pin, llm-agents is re-exported by cells/repo/packages.nix.
    # tuigreet is not an input either: the nixpkgs pin already ships the
    # maintained fork (tuigreet/tuigreet 0.11.1).
    # colmena is absent: this cell is never deployed by colmena.
  };

  outputs = i:
    i
    // {
      utilsLib = i.utils.lib {inherit (i.parent.pkgs) lib;};
    };
}
