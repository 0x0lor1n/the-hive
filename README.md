# nix-rensa

One flake for the fleet, on [rensa](https://gitlab.com/rensa-nix/). Ported from
`divnix/hive`. First host: **osgiliath**, the VPS serving <https://hisilo.me>.

## Layout

```
cells/common     globals (public schema + encrypted values), shared profiles
cells/server     hosts: nixosConfigurations, disks, server profiles
cells/hisilome   the site + radio station: NixOS module, packages, dev stack
cells/repo       the deploy shell
```

Blocks are `{ inputs, cell, system, ... }`. `inputs.pkgs` is the one nixpkgs
instantiation (root `transformInputs`); `inputs.nixpkgs` is the flake, not a
package set. `inputs.self` is sourceInfo only. `inputs.cells.<c>.<block>` reads
another cell; a cell's own siblings are `cell.<block>`.

## Running

Everything that evaluates `globals` needs the deploy shell: the encrypted half
is decrypted at eval time by a nix-plugins extra-builtin, which the shell's
`NIX_CONFIG` loads. direnv enters it automatically.

```bash
nix build .#colmenaHive.toplevel.osgiliath
deploy-key                                # TPM PIN, 15-min TTL
colmena apply switch --on osgiliath
```

`colmenaHive` is hand-written in `flake.nix` -- rensa has no colmena block. Its
`__schema` is read from the pinned colmena input and the CLI (same input) asserts
equality, which is why colmena is pinned by rev and declared only at the root.

## Devshells

`.envrc` reads `.ren/devshell` to pick a cell; `dev` writes it and reloads:

```bash
dev                    # deploy shell
dev hisilome           # site + radio: zola, liquidsoap, icecast, process-compose
cd "$(dev hisilome)"   # also cd into the cell
```

`dev` is a PATH binary in every cell's shell (`nix/dev.sh`), not a shellHook
function: direnv exports env vars, not functions. A child cannot cd its parent,
hence the printed path. Dev shells are per service cell, not per host.

Local station: `cd cells/hisilome && process-compose up -f process-compose.yaml`
(add `-f process-compose.dev.yaml` for file watchers). Needs `music/`, which is
gitignored and rsynced in.

## Secrets

`secrets/globals.nix.age` holds the encrypted half of `globals` (IPs, password
hashes), encrypted to the PIN-less identity so eval is non-interactive.
`secrets/deploy/*.age` are encrypted to the PIN-protected identity: the deploy
key and colmena `deployment.keys` for icecast. Host pubkeys are public.

## Traps, measured

- A cell flake declaring inputs with no committed `flake.lock` resolves to an
  empty lockfile and silently uses the root input of the same name.
- `utils.importModules` applies `args` unconditionally; plain NixOS modules
  need `cells/*/profiles/default.nix`'s `functionArgs` dispatch.
- `mkDisk`'s freeform type is `diskoLib.toplevel`: declare `disk.main`, not
  `disko.devices.disk.main`.
- Colmena's modules read `_module.args.name`; set it when importing them into
  a plain system.
- `rensa-nix/utils` `mkHome.nix:25` references `config.bee.home`, which does not
  exist in `ren-module.nix`; `mkHome` is unusable until fixed upstream.
