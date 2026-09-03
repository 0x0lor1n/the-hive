# nix-rensa

One flake for the fleet, on [rensa](https://gitlab.com/rensa-nix/). Ported from
`divnix/hive`. Hosts: **osgiliath** (VPS, <https://hisilo.me>) and **sevastopol**
(workstation rehearsal VM -- ZFS native encryption, TPM-sealed unlock, Secure
Boot via lanzaboote, impermanence).

## Layout

```
cells/common       globals (public schema + encrypted values), shared profiles
cells/server       hosts: nixosConfigurations, disks, server profiles
cells/workstation  hosts: nixosConfigurations, disks, desktop profiles, home-manager
cells/hisilome     the site + radio station: NixOS module, packages, dev stack
cells/theme        palette as data (kanagawa: colors, roles, ansi); every desktop colour reads from it
cells/repo         the deploy shell
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

Workstation hosts are plain `nixosConfigurations`, not colmena nodes. The VM is
built and booted from `cells/workstation/devshells.nix` (`ws-image`, `ws-vm-run`,
`ws-switch` -> `/mnt/share/activate.sh` inside the guest). Procedure and state
for the rehearsal live in `.hermes/state/port-test-vm.md`.

`sevastopol` runs the CachyOS kernel + `zfs_cachyos` from the pinned `chaotic`
input (`profiles/layer-kernel.nix`); `specialisation.safe` is stock nixpkgs
kernel + ZFS as a boot fallback. Prebuilt binaries come from
`nyx-cache.chaotic.cx`, declared in `nix.settings` for the guest and needed in
the builder's own `nix.conf` too (`~/.config/nix/nix.conf` here), otherwise the
kernel builds from source.

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

## pxpipe

`cells/repo/packages.nix` builds [pxpipe](https://github.com/evan-choi/pxpipe-go)
(pinned by hash), a local proxy that compacts Claude requests before they leave
the machine. `pxpipe-install` in the deploy shell writes a user systemd unit
from the store path -- it is not a Nix module, so it works on non-NixOS hosts.

```bash
pxpipe-install                       # systemctl --user enable --now pxpipe
journalctl --user -u pxpipe -f       # per-request: applied= saved= cache_read=
```

Hermes reaches it via `base_url: http://pxpipe.anthropic.com:47821`; the name
is pinned to `127.0.0.1` in `/etc/hosts` so the `/anthropic` suffix survives.

## nixq

`cells/repo/nixq` is a Go PATH shim shipped as `nix` in the deploy shell. It
sits in front of the real `nix` client and squeezes progress noise out of stderr
(plan lists, `copying path`, `building '…'`) into one summary line. From the
first `error:` line onward everything is verbatim; warnings, traces and unknown
lines always survive (fail-open).

When stderr is a TTY, `NIXQ=off` is set, or the subcommand is interactive
(`run`, `shell`, `develop`, `repl`, `log`), nixq execs the real nix with zero
overhead. `NIXQ_REAL_NIX` in the shellHook pins `nix_2_31` so the nix-plugins
ABI match survives PATH shadowing.

## rtk

[rtk](https://github.com/rtk-ai/rtk) (Rust, pinned tag in
`cells/repo/packages.nix`) compresses common command output (`git status/diff/log`,
`cargo test`, `ls`, `grep`, …) before it reaches the model. Telemetry disabled
via `RTK_TELEMETRY_DISABLED=1` in the shellHook. The Hermes plugin
(`rtk init --agent hermes`) is not yet wired; see
`.hermes/state/post-dellvis-tooling.md`.

## Secrets

`secrets/globals.nix.age` is the encrypted half of `globals` (IPs, password
hashes), to the PIN-less identity so eval is non-interactive. `secrets/deploy.age`
is the fleet deploy key, to the PIN-protected identity. `secrets/<cell>/*.age`
are that service's colmena `deployment.keys`. Pubkeys are public.

Workstation hosts use agenix-rekey: `secrets/generated/<host>/` holds generated
material, `secrets/rekeyed/<host>/` the copies for that host's key
(`agenix generate` / `agenix rekey`). Both are keyed by hostname -- renaming a
host means regenerating.

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
- `networking.hostId` is derived from the hostname and ZFS pools remember it:
  after a rename the pool imports only with force (`storage-zfs.nix` sets
  `boot.zfs.forceImportRoot` for VMs; a real host would need it once).
- `environment.sessionVariables` / greetd env do not reach the compositor
  session; `XDG_CURRENT_DESKTOP` must be exported by the launcher script itself
  (`layer-compositor.nix`'s `dwl-session`), or dbus/xdg-desktop-portal see nothing.
- `nix.settings.extra-substituters` on the target does nothing for the machine
  that *builds* it; the cache must be in the builder's own `nix.conf`.
