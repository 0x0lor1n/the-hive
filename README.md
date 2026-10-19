# nix-rensa

One flake for the fleet, on [rensa](https://gitlab.com/rensa-nix/). Ported from
`divnix/hive`.

| host | role | hardware | runs |
|---|---|---|---|
| osgiliath | blog + radio | VPS, snowcore.io | nginx, [hisilome](https://github.com/0x0lor1n/hisilome): <https://hisilo.me>, liquidsoap + icecast |
| minas-tirith | router | CWWK S8, Intel N305 | nftables WAN/LAN, fiber bypass, yggdrasil |
| imladris | NAS | MSI B250M PRO-VD, Intel i5-6600T | TorrServer |
| elster | workstation, work | HP ZBook Firefly 16 G10 | dwl desktop, Entra login |
| penrose | workstation, home | Dell Latitude 5580 | under maintenance |

Every host: impermanence (ephemeral root, state in `/state` and `/persist`).
Storage: ZFS with native encryption and TPM-sealed unlock on the workstations
and minas-tirith, plain ZFS on imladris (no TPM), btrfs with rollback on
osgiliath. Workstations add Secure Boot (lanzaboote) and the CachyOS kernel.
**sevastopol** is the retired QEMU rehearsal of the workstation config.

## Docs

```
docs/secrets.md              eval-time vs runtime secrets, TPM identities, agenix-rekey, colmena keys
docs/agent-tooling.md        pxpipe, nixq, rtk: what sits between the agents and the model
docs/install-workstation.md  a new workstation end to end
docs/keys/                   keybindings (Russian); docs/cheatsheets/ printable
docs/nas-*.md                imladris: hardware, ZFS layout, vs Synology
```

## Layout

```
cells/common       globals (public schema + encrypted values), shared profiles, theme (kanagawa palette: colors, roles, ansi)
cells/server       hosts: nixosConfigurations, disks, server profiles
cells/workstation  hosts: nixosConfigurations, disks, desktop profiles, home-manager
cells/deck         the shell + terminal toolkit: homeModules shared by every account on every workstation
cells/repo         the deploy shell, pinned agent tooling
cells/wintermute   coreboot tooling for the Latitude 5580; read by no host
```

Blocks are `{ inputs, cell, system, ... }`. `inputs.pkgs` is the one nixpkgs
instantiation (root `transformInputs`); `inputs.nixpkgs` is the flake, not a
package set. `inputs.self` is sourceInfo only. `inputs.cells.<c>.<block>` reads
another cell; a cell's own siblings are `cell.<block>`.

## Running

Everything that evaluates `globals` needs the deploy shell: the encrypted half
is decrypted at eval time by a nix-plugins extra-builtin, which the shell's
`NIX_CONFIG` loads. direnv enters it automatically. Details: `docs/secrets.md`.

Servers (osgiliath, minas-tirith, imladris) are colmena nodes:

```bash
nix build .#colmenaHive.toplevel.osgiliath
deploy-key                                # TPM PIN, 15-min TTL
colmena apply switch --on osgiliath
```

`colmenaHive` is hand-written in `flake.nix` -- rensa has no colmena block. Its
`__schema` is read from the pinned colmena input and the CLI (same input) asserts
equality, which is why colmena is pinned by rev and declared only at the root.

Workstations are plain `nixosConfigurations`, not colmena nodes, rebuilt on
the machine itself (`sudo` drops `NIX_CONFIG`, `--sudo` keeps it):

```bash
nixos-rebuild switch --sudo --flake .#elster
```

The VM is built and booted from `cells/workstation/devshells.nix` (`ws-image`,
`ws-vm-run`, `ws-switch` -> `/mnt/share/activate.sh` inside the guest).

Workstations run the CachyOS kernel + `zfs_cachyos` from the pinned `chaotic`
input (`profiles/layer-kernel.nix`); `specialisation.safe` is stock nixpkgs
kernel + ZFS as a boot fallback. Prebuilt binaries come from
`nyx-cache.chaotic.cx`, declared in `nix.settings` for the host and needed in
the builder's own `nix.conf` too when building for another machine, otherwise
the kernel builds from source.

## Devshells

`.envrc` reads `.ren/devshell` to pick a cell; `dev` writes it and reloads:

```bash
dev                    # deploy shell
dev workstation        # or any other cell with a devshell
cd "$(dev workstation)" # also cd into the cell
```

`dev` is a PATH binary in every cell's shell (`nix/dev.sh`), not a shellHook
function: direnv exports env vars, not functions. A child cannot cd its parent,
hence the printed path. Dev shells are per service cell, not per host.

The site and the radio station live in their own flake,
[github:0x0lor1n/hisilome](https://github.com/0x0lor1n/hisilome), consumed here
as the `hisilome` input; `cells/server/profiles/site-hisilome.nix` is the host
side (domain, cert, secrets, firewall).

## Accounts

Two planes on a workstation: the local user (`layer-users-local`) holds the
checkout, the TPM identities (`himmelblaud` group), `wheel` and nix
trusted-users -- it is the only account that can `unlock-secrets` or rebuild.
The Entra user is desktop-only (no `wheel`, no TPM); untrusted apps there run
under nixpak (`cells/workstation/packages.nix`).

The split models corporate role separation -- a restricted daily driver, admin
out of band -- and not a boundary between two people: one operator holds both
accounts. Development state is shared on purpose (the `hive` group,
`/srv/workspace`); key material is granted per key, not by default.

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
