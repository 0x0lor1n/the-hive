{
  description = "Spike: is rensa a viable replacement for divnix/hive?";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ren.url = "gitlab:rensa-nix/core/v0.2.0?dir=lib";
    colmena.url = "github:zhaofengli/colmena";
  };

  outputs = {ren, self, ...} @ inputs:
    ren.buildWith {
      inherit inputs;
      cellsFrom = ./cells;
      systems = ["x86_64-linux"];
      cellBlocks = with ren.blocks; [
        (simple "test")
        (simple "nixosConfigurations")
      ];
      # rensa's answer to "instantiate nixpkgs once per system".
      transformInputs = system: i:
        i
        // {
          pkgs = import i.nixpkgs {inherit system;};
        };
    } {
      # spike A result, hoisted so it can be evaluated directly
      probe = ren.get self [["probe" "test"]];
      # spike C: evaluating this must FAIL (negative control)
      heavy = ren.get self [["heavy" "test"]];

      nixosConfigurations = ren.get self [["server" "nixosConfigurations"]];

      # SPIKE B: colmena's CLI schema, emitted by hand from rensa systems.
      # Under hive this was a blockType with a hidden transformer; here it is
      # plain code. __schema is read FROM THE PINNED COLMENA so it cannot drift
      # -- that is the single best idea in hive's implementation.
      colmenaHive = let
        l = inputs.nixpkgs.lib;
        nodes = ren.get self [["server" "nixosConfigurations"]];
        toplevel = l.mapAttrs (_: v: v.config.system.build.toplevel) nodes;
        deploymentConfig = l.mapAttrs (_: v: v.config.deployment) nodes;
      in {
        __schema = (import (inputs.colmena + "/src/nix/hive/eval.nix") {}).__schema;
        inherit nodes toplevel deploymentConfig;
        deploymentConfigSelected = names: l.filterAttrs (n: _: l.elem n names) deploymentConfig;
        evalSelected = names: l.filterAttrs (n: _: l.elem n names) toplevel;
        evalSelectedDrvPaths = names: l.mapAttrs (_: v: v.drvPath) (l.filterAttrs (n: _: l.elem n names) toplevel);
        metaConfig = {
          name = "nix-rensa";
          description = "rensa spike";
          machinesFile = null;
          allowApplyAll = false;
        };
        introspect = f: f {inherit (inputs) nixpkgs; lib = l; inherit nodes;};
      };
    };
}
