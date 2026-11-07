{
  description = "One flake for the fleet, on rensa";

  inputs = {
    # Pinned to the SAME rev as cells/workstation's nixpkgs (which follows
    # chaotic/nixpkgs): one nixpkgs -> one nix -> one nix-plugins for the
    # devshell and every host. A root `follows` cannot reach a cell input, so
    # the rev is copied here and in cells/{server,repo}/flake.nix; the
    # nixpkgs-sync lefthook check fails the commit if they drift. Bump with
    # `nix flake update chaotic` in cells/workstation, then paste the rev.
    nixpkgs.url = "github:NixOS/nixpkgs/1c89083e451e891152365b799595cf7790a43325";
    ren.url = "gitlab:rensa-nix/core/v0.2.0?dir=lib";
    # Pinned by rev on purpose: colmenaHive below reads colmena's internal
    # __schema from this source and the CLI (same input, in the devshell)
    # asserts equality. Both halves must come from one revision.
    colmena.url = "github:zhaofengli/colmena/dc22786a43315b212eeafe13409a7203328e5a30";
    # No other inputs here: a root input is fetched by every host. Per-cell
    # dependencies (hisilome, lanzaboote, ...) live in cells/<cell>/flake.nix.
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
        (simple "theme")
        (simple "profiles")
        (simple "disks")
        (simple "nixosConfigurations")
        (simple "dns")
        (simple "packages")
        (simple "nixosModules")
        (simple "homeModules")
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
            # One nix for the whole fleet (oddlama's trick): the plugin only
            # dlopens into the exact client it was built for, and nixpkgs'
            # nix-plugins trails pkgs.nix by a release or two. Overriding
            # pkgs.nix pins the devshell client AND every host's nix.package
            # (default pkgs.nix), so `nixos-rebuild` on a host loads the
            # plugin too. The release is read off nix-plugins' inputs: the
            # two nixpkgs in this repo (root, workstation via nyx) carry
            # different ones.
            overlays = [
              (_final: prev: let
                l = prev.lib;
                pluginsNix = l.getVersion (l.findFirst (d: l.getName d == "nix-cmd") null prev.nix-plugins.buildInputs);
              in {
                nix = prev.nixVersions."nix_${l.versions.major pluginsNix}_${l.versions.minor pluginsNix}";
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
        // ren.get self [["workstation" "devshells"]]
        // ren.get self [["wintermute" "devshells"]];
      packages.x86_64-linux = ren.get self [["wintermute" "packages"]];
      # `agenix` (agenix-rekey CLI) runs `nix run .#agenix-rekey.<system>.<app>`.
      agenix-rekey = ren.get self [["repo" "agenixRekey"]];

      # Rensa has no colmena block, so the hive is emitted by hand. Exposed as
      # `colmenaHive`, never `colmena`: colmena's eval.nix asserts a raw hive
      # does not already carry __schema.
      colmenaHive = let
        toplevel = l.mapAttrs (_: v: v.config.system.build.toplevel) nodes;
        deploymentConfig = l.mapAttrs (_: v: v.config.deployment) nodes;
      in {
        inherit (import (inputs.colmena + "/src/nix/hive/eval.nix") {}) __schema;
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
