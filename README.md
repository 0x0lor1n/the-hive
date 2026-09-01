# nix-rensa — spike

Evaluating whether [rensa](https://gitlab.com/rensa-nix/) should replace
divnix/hive for `test-vm`. **Not production.** `test-vm` remains the live
configuration and osgiliath stays deployable from it.

Plan: `test-vm/.sisyphus/plans/iteration-14-rensa-spike.md`

## Results

| Spike | Question | Result |
| ----- | -------- | ------ |
| A | Does `rageImportEncrypted` survive rensa's `call-flake`? | **PASS** — decrypts inside a cell block |
| C | Is cell-flake laziness real? | **PASS** — a cell with an unfetchable input does not block others |
| B | Can colmena be driven from `utils.mkSystem`? | **PASS** — `colmena build` succeeds on a hand-emitted schema |

Each has a control: A was re-run after a false negative traced to NIX_CONFIG
mangling; C's heavy cell genuinely fails to evaluate; B fails on an undefined
option.

## Confirmed about rensa

- block signature is `{ inputs, cell, system }`
- `inputs.self` is **sourceInfo only** — anything defined in the soil is unreachable
- `transformInputs` injects a single `pkgs` per system, and works
- cell flakes need their **own committed `flake.lock`**; without one, inputs
  resolve to an empty lockfile *silently* (`call-flake.nix:26-29`)
- `__schema` can be read from the pinned colmena, so the pairing cannot drift

## Running

Requires `test-vm`'s devshell for the nix-plugins/nix_2_31 pairing:

```sh
cd ~/workspace/playground/test-vm && nix develop
cd ~/workspace/playground/nix-rensa
nix eval --json .#probe          # spike A
nix eval --json .#heavy          # spike C control: MUST fail
colmena build --on spike-host    # spike B
```
