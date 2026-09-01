{
  description = "This is my take on one-flake-to-rule-them-all";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ren.url = "gitlab:rensa-nix/core/v0.2.0?dir=lib";
    # root-level too, so the soil can read colmena's __schema constant
    colmena.url = "github:zhaofengli/colmena/dc22786a43315b212eeafe13409a7203328e5a30";
  };

  outputs = {
    ren,
    self,
    ...
  } @ inputs:
    ren.buildWith {
      inherit inputs;
      cellsFrom = ./cells;
      systems = ["x86_64-linux"];

      cellBlocks = with ren.blocks; [
        (simple "globals")
        (simple "secretsConfig")
        (simple "profiles")
        (simple "disks")
        (simple "nixosConfigurations")
        (simple "packages")
        (simple "nixosModules")
        (simple "devshells")
      ];

      # rensa's answer to "instantiate nixpkgs once per system". Also what
      # makes `inputs.pkgs` available to every block -- note `inputs.nixpkgs`
      # is NOT a package set here, because deSystemize flattens
      # `.legacyPackages.<system>` rather than the flake root.
      transformInputs = system: i:
        i
        // {
          pkgs = import i.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        };
    } (let
      l = inputs.nixpkgs.lib;
      nodes = ren.get self [["server" "nixosConfigurations"]];
    in {
      # nixos-anywhere resolves this; agenix-rekey would too.
      nixosConfigurations = nodes;

      # `nix develop` / direnv. The repo cell owns tooling; hosts never see it.
      devShells.x86_64-linux = ren.get self [["repo" "devshells"]];

      # Colmena's CLI schema, emitted by hand -- rensa has no colmena block.
      # ~25 lines, and clearer than hive's hidden transformer.
      #
      # __schema is read FROM THE PINNED COLMENA so the pairing cannot drift.
      # Exposed as `colmenaHive`, never `colmena`: colmena's own eval.nix
      # asserts a raw hive does not already carry __schema.
      colmenaHive = let
        toplevel = l.mapAttrs (_: v: v.config.system.build.toplevel) nodes;
        deploymentConfig = l.mapAttrs (_: v: v.config.deployment) nodes;
      in {
        __schema = (import (inputs.colmena + "/src/nix/hive/eval.nix") {}).__schema;
        inherit nodes toplevel deploymentConfig;
        deploymentConfigSelected = names: l.filterAttrs (n: _: l.elem n names) deploymentConfig;
        evalSelected = names: l.filterAttrs (n: _: l.elem n names) toplevel;
        evalSelectedDrvPaths = names:
          l.mapAttrs (_: v: v.drvPath) (l.filterAttrs (n: _: l.elem n names) toplevel);
        metaConfig = {
          name = "nix-rensa";
          # A literal, NOT `inherit (self) description`: flake metadata is not
          # exposed on `self` inside `outputs`, so that reads as a missing attr.
          description = "osgiliath, deployed from rensa";
          machinesFile = null;
          allowApplyAll = false;
        };
        introspect = f:
          f {
            lib = l;
            inherit nodes;
            inherit (inputs) nixpkgs;
          };
      };
    });
}
