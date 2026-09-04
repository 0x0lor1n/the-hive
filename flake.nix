{
  description = "One flake for the fleet, on rensa";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ren.url = "gitlab:rensa-nix/core/v0.2.0?dir=lib";
    # Pinned by rev on purpose: colmenaHive below reads colmena's internal
    # __schema from this source and the CLI (same input, in the devshell)
    # asserts equality. Both halves must come from one revision.
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
        (simple "palettes")
        (simple "profiles")
        (simple "disks")
        (simple "nixosConfigurations")
        (simple "packages")
        (simple "nixosModules")
        (simple "devshells")
        (simple "agenixRekey")
      ];

      # `inputs.nixpkgs` inside a block is the flake (deSystemize flattens
      # legacyPackages, so .lib resolves but stdenv builders do not). This is
      # the one instantiation every block uses as `inputs.pkgs`.
      transformInputs = system: i:
        i
        // {
          pkgs = import i.nixpkgs {
            inherit system;
            config.allowUnfree = true;
            # One nix for the whole fleet (oddlama's trick): nix-plugins does
            # not build against 2.34, and the plugin only dlopens into the
            # exact client it was built for. Overriding pkgs.nix pins the
            # devshell client AND every host's nix.package (default pkgs.nix),
            # so `nixos-rebuild` on a host loads the plugin too. Drop when
            # nix-plugins catches up.
            overlays = [
              (final: prev: {
                nix = prev.nixVersions.nix_2_31;
                nix-plugins = prev.nix-plugins.override {
                  nixComponents = prev.nixVersions.nixComponents_2_31;
                };
              })
            ];
          };
        };
    } (let
      l = inputs.nixpkgs.lib;
      nodes = ren.get self [["server" "nixosConfigurations"]];
      # Workstations: built and installed locally (disko image / nixos-rebuild),
      # never deployed by colmena, so they are NOT in colmenaHive below.
      workstations = ren.get self [["workstation" "nixosConfigurations"]];
    in {
      nixosConfigurations = nodes // workstations;
      devShells.x86_64-linux =
        ren.get self [["repo" "devshells"]]
        // ren.get self [["workstation" "devshells"]];
      # `agenix` (agenix-rekey CLI) runs `nix run .#agenix-rekey.<system>.<app>`.
      agenix-rekey = ren.get self [["workstation" "agenixRekey"]];

      # Rensa has no colmena block, so the hive is emitted by hand. Exposed as
      # `colmenaHive`, never `colmena`: colmena's eval.nix asserts a raw hive
      # does not already carry __schema.
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
          # Flake metadata is not on `self` inside outputs.
          description = "the fleet, deployed from rensa";
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
