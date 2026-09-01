# nix-rensa

A port of **osgiliath** — the KVM VPS that serves <https://hisilo.me> — from
`divnix/hive` to the [rensa](https://gitlab.com/rensa-nix/) stack, kept beside
`test-vm` rather than replacing it.

Two questions, answered separately:

1. **Does rensa work for us?** — three spikes, below. Answered before any port.
2. **Does the port reproduce the machine we already run?** — measured against
   the incumbent, below.

## 1. Spikes

Each spike has a control, so a pass means something.

| Spike | Question | Result |
| --- | --- | --- |
| **A** | Does `rageImportEncrypted` survive `call-flake`? | **PASS** — decrypts inside a cell block |
| **B** | Can colmena be driven from `utils.mkSystem`? | **PASS** — `colmena build` reaches "All done!" |
| **C** | Is per-cell laziness real? | **PASS** — a cell with an unfetchable input fails to evaluate; its neighbour succeeds |

Spike A nearly produced a false negative: the first run reported
`hasFunction: false`, which would have read as "rensa breaks extra-builtins"
and killed the design. The cause was a `NIX_CONFIG` reconstruction inside
nested quoting, not rensa.

## 2. Does the port reproduce osgiliath?

Yes. Compared against `test-vm`'s `colmenaHive.toplevel.nixos-osgiliath`, with
both pinned to the same nixpkgs:

| Measure | Result |
| --- | --- |
| `nix store diff-closures` | empty |
| Closure size | 4,494,911,208 bytes — **equal** |
| Closure paths | 1207 vs 1207 — **equal** |
| Files present on one side only | **0** |
| Files differing byte-for-byte | 16 |
| Files still differing once store hashes are masked | **0** |
| Semantic config surface (15 keys: 77 systemd services, filesystems, persistence, firewall, nginx, openssh, bootloader, users, tmpfiles, packages) | **identical** |
| colmena `deploymentConfig` (10 fields) | **identical** |

The 16 files differ only because this repo is a different directory, so the
flake's source hash differs and propagates into anything referencing it. The
site derivation is a case in point: a different store path, byte-identical
content.

### Two measurement traps, both hit

- **Comparing across different nixpkgs.** The first comparison showed hundreds
  of package differences and a spurious `fuse`. Both repos were on different
  nixpkgs; `programs.fuse.enable` defaulted to `true` in 26.05 and `false` in
  26.11. Pinning both to the same revision removed every difference.
- **Reading `flake.lock` node *names* instead of the root node's input map.**
  The node called `nixpkgs` belongs to a dependency. test-vm's actual nixpkgs
  is `d233902` (26.05), reached via the node named `nixpkgs_5`.

A closing check nearly went unmade: the first file-by-file diff counted only
files that *differ*, not files present on one side alone. Adding that check is
what surfaced hive's `/etc/nixos/configuration.nix` guard.

## 3. What the port measures about isolation

| | test-vm | nix-rensa |
| --- | --- | --- |
| Root inputs | 16 | 3 |
| Total locked nodes | 109 | 24 |

Not a like-for-like comparison — test-vm also carries the workstation, and
nix-rensa does not yet. The structural claim is the one spike C proved: adding
a workstation cell will not change what the *server* fetches. osgiliath's cells
declare `impermanence, utils, disko, colmena` and never see `lanzaboote`,
`nix-cachyos-kernel`, `himmelblau`, `home-manager`, `tuigreet`,
`nixos-extra-modules`, `agenix`, or `agenix-rekey`.

## 4. Porting differences worth knowing

Measured, not read off the documentation:

- Block signature is `{ inputs, cell, system }` — hive's was exactly
  `{ inputs, cell }`, so every block file needs an ellipsis.
- **`inputs.self` is sourceInfo only.** test-vm's `inputs.self.secretsConfig`
  is unreachable by construction, so `secretsConfig` became its own block.
- **`inputs.nixpkgs` is the flake, not a package set.** Under hive it arrived
  instantiated. `inputs.nixpkgs.lib` still resolves (deSystemize flattens
  `legacyPackages`), so the failure surfaces late as a missing
  `writeShellApplication`. Use `inputs.pkgs`, from `transformInputs`.
- **Cell-flake outputs land directly in `inputs`**, while `inputs.cells.<c>`
  holds that cell's *blocks*. Reading the latter from inside the same cell is
  infinite recursion.
- **Cell flakes need their own committed `flake.lock`** or their inputs
  silently resolve to an empty lockfile.
- `utils.importModules` applies its `args` unconditionally, so it cannot load
  hive's plain-NixOS-module profiles. `cells/*/profiles/default.nix` detects
  the shape with `builtins.functionArgs` instead.
- `mkDisk`'s freeform type is `diskoLib.toplevel`, so a disk is declared as
  `disk.main`, not `disko.devices.disk.main`.
- Colmena defaults `deployment.targetHost` to the node name via
  `_module.args.name`, which its own evaluator supplies. Importing its modules
  into a plain `nixosSystem` requires setting that, or every `config.deployment`
  read fails with `attribute 'name' missing`.
- Flake metadata is not on `self` inside `outputs`: `inherit (self) description`
  is a missing attribute.
- hive's colmena transformer adds an `/etc/nixos/configuration.nix` guard that
  colmena itself does not. Ported explicitly.

## 5. What this does not settle

That rensa is technically viable is settled. Whether to move is not:

- `utils` last saw a commit in April; bus factor is one.
- `utils/lib/mkHome.nix:25` has a `bee.home` bug that blocks the vm-zfs port
  (it uses home-manager). Not yet reported upstream.
- `colmenaHive` here is hand-written rather than emitted by a transformer. It
  reads `__schema` from the pinned colmena so it cannot drift, but it is ~25
  lines this repo now owns.

## Direnv

`.envrc` uses rensa's own [direnv integration](https://gitlab.com/rensa-nix/direnv),
pinned to `v0.3.0` by content hash (verified against the tag before pinning):

```bash
source "$(fetchurl https://gitlab.com/rensa-nix/direnv/-/raw/v0.3.0/direnvrc sha256-...)"
cell="$(read_state devshell)"
use ren //"${cell:-repo}"/devshells/"${cell:-repo}"   # repo -> //repo/devshells/default
```

`use ren //<cell>/<block>/<target>` resolves to the **raw rensa output tree** --
`.#x86_64-linux.repo.devshells.default` -- not the flake's `devShells`
passthrough, and it watches only that cell. Measured watch set for the deploy
shell:

```
.envrc  flake.nix  flake.lock
cells/repo/flake.nix  cells/repo/flake.lock  cells/repo/devshells.nix
```

So editing `cells/server`, `cells/hisilome` or any host does not reload the
shell. State (profiles, gcroots, `PRJ_*`) lives in a gitignored `.ren/`.

Bumping the version means re-running `direnv fetchurl <url>` and replacing both
the tag and the hash.

### Switchable devshells

The `.envrc` above reads `.ren/devshell` (rensa's `read_state`) to choose which
cell's shell to load. `dev`, a shell function in every cell's shellHook, is the
switch:

```bash
dev            # back to the deploy shell (repo/devshells/default), cd repo root
dev hisilome   # the site + radio shell (zola, liquidsoap, process-compose),
               #   cd cells/hisilome
```

`dev <cell>` is *not* `nix develop`. It writes the cell name to `.ren/devshell`,
`cd`s into the cell dir, and runs `direnv reload`, so the environment is layered
into **your current shell** — zsh stays zsh, no spawned bash — and rensa's
watches and gcroots are preserved. It is a shell *function* (sourced from
`nix/dev-switch.sh` into each shellHook), not a packaged binary, because a child
process cannot `cd` its parent; sharing it across cells is what lets `dev` switch
*back* from a service shell. The choice persists in `.ren/` across `cd` out and
back. There is deliberately no per-cell `.envrc`: the root one plus `dev` is the
single source of truth for which shell is active.

Dev shells are keyed to a **service cell**, not a host — a machine is deployed,
not developed. `cells/hisilome` has a shell because the site runs locally; a
headless host cell has none. This is the std/paisano convention: a devshell is
a target inside a cell's `devshells` block, grouped with that cell's concern.

### What wiring it up caught

`cells/repo` declared a `colmena` input but had no committed `flake.lock`, so
that input resolved to an **empty lockfile** and silently fell through to the
root's `colmena`. It worked only because both pinned the same revision.

The fix was not to add a lock but to remove the duplicate pin: the root's
colmena is the one `colmenaHive` reads `__schema` from, and the CLI asserts that
schema equals its own constant. One pin makes the mismatch impossible instead of
merely unlikely. `cells/server` lost its `colmena` declaration for the same
reason -- its `nixosModules` must come from the pin the schema is read from. The
toplevel is byte-identical across that change.

`cells/common`, `cells/server` and `cells/repo` have committed locks;
`cells/hisilome` declares no inputs, so it needs none.

## The devshell's own inputs

`cells/repo` declares `llm-agents` (numtide), which supplies `hermes-agent` —
on `PATH` as `hermes`. It sits in this cell rather than the root precisely
because a root input is visible to *every* cell: `cells/server` would then
carry an LLM agent in a headless VPS's fetch set. Measured after adding it:

| | before | after |
| --- | --- | --- |
| Root inputs / locked nodes | 3 / 11 | **3 / 11** — unchanged |
| `osgiliath` toplevel `drvPath` | `mx5by7mx…` | **`mx5by7mx…`** — identical |

That is the isolation claim of §3 exercised in the one direction that matters:
adding tooling changed nothing about the machine.

`llm-agents` deliberately does **not** `follows` our nixpkgs. Forcing it aborts
evaluation — its package set references `nodejs_26`, which our pin lacks, and
touching any single package forces the whole set (the abort surfaces from the
unrelated `hermes-desktop`). Its own nixpkgs also lets numtide's cache serve
these prebuilt. `test-vm`'s flake carries the same note for the same input.

## Running it

Everything that evaluates `globals` must run inside the deploy shell — the
encrypted half is decrypted at eval time by `rageImportEncrypted`, which needs
nix-plugins. `nix develop`, or direnv drops you in automatically:

```bash
nix build .#colmenaHive.toplevel.osgiliath   # build the machine
colmena build --on osgiliath                  # or via colmena

deploy-key                                    # load THE fleet deploy key
                                              #   (TPM PIN, 15-min TTL)
colmena apply switch --on osgiliath           # cut over
```

`deploy-key` is the single fleet-wide loader (renamed from the earlier
per-host `osgiliath-key`): one PIN-gated identity authenticates every colmena
target, so a second host adds a `--on <host>` argument, not a second key. The
PIN prompt is by design — no unattended process can deploy.

osgiliath was cut over from the old `divnix/hive` repo (`test-vm`) to this one
with `colmena apply switch`; because the closure is byte-identical, the switch
was a no-op at the system level. This repo now manages the machine.
