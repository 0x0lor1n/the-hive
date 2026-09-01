---
name: rensa-nix
description: rensa-nix framework — buildWith, blocks, utils, direnv semantics.
version: 1.1.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [nix, rensa, flakes, nixos, colmena, disko, direnv]
    related_skills: [terse-comments]
---

# rensa-nix

Framework facts for gitlab.com/rensa-nix (core, utils, direnv), from source.
Repo-specific traps live in README.md; this file is the framework only.
`references/api.md` has signatures and line cites.

## When to Use

Any edit under `cells/`, `flake.nix`, or `.envrc`, or any `[ren] while ...`
error.

## Model (core/lib/core/builder.nix)

- `ren.buildWith { inputs; cellsFrom; systems; cellBlocks; transformInputs } soil`
  produces `${system}.${cell}.${block}.${target}` and merges `soil` on top.
- Block file: `{ inputs, cell, system, ... }: { <target> = ...; }`. The
  ellipsis is required; `system` is passed.
- Block types: `simple`, `dynamic` (CLI actions), `autodiscover`.
- `ren.get self [["cell" "block"]]` reads a target back for the soil.
- `.#__ren.cells`, `.#__ren.cellsFrom` identify a rensa flake.

## What a block receives (import-signature.nix)

- `inputs.self` = `sourceInfo // {rev}`. No flake outputs on self.
- `deSystemize` (cutoff 3) lifts `<input>.<system>` one level: `inputs.nixpkgs.lib`
  resolves, stdenv builders do not. Use the `pkgs` from `transformInputs`.
- A cell's `flake.nix` outputs are merged into `inputs` (loader.nix:26-33).
  With no committed `flake.lock` the cell's inputs resolve to an empty lock
  and fall through to the root input of the same name.
- `inputs.cells.<c>.<block>` is another cell; own siblings are `cell.<block>`.
- Root inputs are visible to every cell.

## utils (utils/lib)

- `mkSystem` calls nixpkgs `eval-config.nix` with `system = null` and prepends
  `ren-module.nix`; not `lib.nixosSystem`. Set `_module.args` yourself.
- `ren.*` options are exactly: `system pkgs disko home-manager nixos-wsl
  nix-darwin` (ren-module.nix). `pkgs` must be instantiated.
- `mkDisk` freeform type is `diskoLib.toplevel`: `disk.<name>`, not
  `disko.devices.disk.<name>`. `collectDisks cell.disks` feeds `disko.devices`.
- `importModules` applies `args` unconditionally (default.nix:79).
- `mkHome.nix:25` reads `config.bee.home`, which `ren-module.nix` does not
  define. Unusable until fixed upstream (v0.1.2).

## direnv (direnvrc v0.3.0)

- `use ren //cell/block/target` → `.#<system>.<cell>.<block>.<target>` via
  `nix print-dev-env`, cached in `.ren/direnv/`; watches only that cell.
- `read_state k` / `write_state k v` ↔ `.ren/<k>`.
- direnv exports env vars, including PATH, into the interactive shell — not
  shell functions. A devshell function defined in a shellHook never reaches
  zsh; a PATH binary does.
- `nix develop` execs bash regardless of `$SHELL`.

## Colmena

No block. Hand-write `colmenaHive` in the soil; read `__schema` from the
pinned colmena source and ship the CLI from the same input. Expose as
`colmenaHive`, not `colmena`. Import `colmena.nixosModules.{deploymentOptions,
keyChownModule,keyServiceModule,assertionModule}` and set `_module.args.name`.
