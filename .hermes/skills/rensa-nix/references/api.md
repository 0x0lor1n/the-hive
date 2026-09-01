# rensa-nix — API reference (from source)

Line cites are against the repos as of: core @ e5f47b57 (main), utils v0.1.2,
devshell v0.1.0, direnv v0.3.0. Clone to re-verify:
`git clone --depth 1 https://gitlab.com/rensa-nix/{core,utils,devshell,direnv}.git`

## core/lib/core/builder.nix — buildWith

```
build = { inputs, cellsFrom, cellBlocks ? [blocks.autodiscover],
          transformInputs ? system: i: i, ... } @ args: ...
```
- `systems`: `args.systems`, else `import inputs.systems`, else the 4 defaults
  (x86_64/aarch64 × linux/darwin).
- Output shape per system: `{ ${system}.${cell}.${block} = target; }`.
- Adds `__ren = { __schema = "v0"; cells = [...]; init; actions;
  cellsFrom = <basename>; }`. `nix eval .#__ren.cells` / `.#__ren.cellsFrom`.
- `buildWith args` returns `build args // { __functor = flip recursiveUpdate; }`
  — so `ren.buildWith {...} soil` merges `soil` (your CLI-compat outputs) ON TOP
  via a custom `recursiveUpdate` (builder.nix:73-104; `__ren.init` lists get
  flattened, everything else takes the soil's head value).

## core/lib/blocks/default.nix — block types

```
simple      = name: { inherit name; type = name; };
dynamic     = name: { inherit name; type = name; cli = true; actions = args: {}; };
autodiscover= { name = "__autodiscover"; type = "__autodiscover"; ... };
```
Used in flake.nix as `with ren.blocks; [ (simple "devshells") (simple "profiles") ... ]`.

## core/lib/utils/import-signature.nix — what a block receives

```
createImportSignature = cfg: system: cell: cells: additionalInputs: {
  inputs = cfg.transformInputs system (
    (deSystemize system (cfg.inputs // additionalInputs))
    // { self = <sourceInfo // {rev}>; cells = deSystemize system cells; });
  inherit cell system;
};
```
- `self` is ONLY `inputs.self.sourceInfo` (+ `rev`). No custom flake outputs.
- `deSystemize` (cutoff=3) recursively lifts `fragment.${system}` up one level —
  this is why `inputs.nixpkgs.lib`/`.hello` work but stdenv builders don't.
- `additionalInputs` = the cell's OWN flake outputs (see loader below).

## core/lib/core/loader.nix — cell/block loading

- `loadCellBlock` (l.18-122): if `cellP.flake` exists, `callFlake` it with
  `root.parent = transformInputs system inputs` and merge `.outputs` as
  `additionalInputs` (l.26-33). Empty/absent lock ⇒ empty outputs ⇒ silent
  fallthrough to root inputs.
- `createCellLoader` builds the `cell` arg by loading each sibling block
  lazily (l.142-157) with an `addErrorContext` guard against sibling infinite
  recursion. Use `cell.<block>` for siblings, never `inputs.cells.<self>`.
- `dynamic`/`cli` blocks get `actions` harvested into `__ren.actions` (l.68-104).

## core/lib/compat — get / select / filter

```
get = t: p: (select t p).<firstAttr>      # get.nix
```
`ren.get self [["cell" "block"]]` → the target set. `select`/`filter` support
`*` wildcards (compat commit abe19f9f).

## utils/lib/default.nix

```
mkSystem     = import ./mkSystem.nix {lib,...};
mkHome       = import ./mkHome.nix {lib,...};
mkDisk       = import ./mkDisk.nix {lib,...};
collectDisks = disks: foldr recursiveUpdate {}
                 (map (d: removeAttrs d.userConfig ["ren"]) (attrValues disks));
importModules= { dir, args ? {}, currentFile ? "default.nix", usePathAsKeys ? false }: ...
findModules  = { dir, currentFile ? "default.nix", relative ? false }: ...
```
`importModules` calls `import "${dir}/${file}" args` UNCONDITIONALLY (l.79) —
hence the plain-module shape problem.

## utils/lib/ren-module.nix — the ONLY ren.* options

```
options.ren = {
  system      : str  (defaults to config.ren.pkgs.system if pkgs set)
  home-manager: input  (check: has sourceInfo)
  disko       : input
  nixos-wsl   : input
  nix-darwin  : input
  pkgs        : packages (check: has .path — must be INSTANTIATED nixpkgs)
};
```
Note: NO `bee` option — see the mkHome bug.

## utils/lib/mkSystem.nix

```
mkSystem = userConfig:
  evalModules { modules = [./ren-module.nix userConfig {_module.check=true; freeformType=unspecified;}]; }
  -> if ren.nix-darwin defined: nix-darwin.lib.darwinSystem {...}
     else: import (ren.pkgs.path + "/nixos/lib/eval-config.nix") { system=null; modules = [ren-module userConfig] ++ [extraNixosConfig] ++ nixosModules; }
```
- `extraNixosConfig` sets `nixpkgs = {inherit (ren) system pkgs;}` and CONDITIONALLY
  imports home-manager / nixos-wsl / disko nixosModules if that `ren.<input>` is
  defined (l.23-47).
- Returns the eval-config result `// { userConfig; innerConfig; }`. The system is
  at `.config.system.build.toplevel`; `.config.deployment` exists only if colmena
  modules were imported.

## utils/lib/mkDisk.nix

```
mkDisk = userConfig:
  diskConfig = evalModules { modules = [./ren-module.nix userConfig {freeformType = diskoLib.toplevel;}]; };
  -> { userConfig; innerConfig = removeAttrs diskConfig.config ["ren"]; config; options;
       scripts = config._scripts {inherit (ren) pkgs;}; }
```
Freeform type is `diskoLib.toplevel` ⇒ declare `disk.<name>` at top level.

## utils/lib/mkHome.nix — BUGGY (line 25)

```
homeConfig = hmLib.evalModules {
  specialArgs = { modulesPath = toString (evaled.config.bee.home + /modules); };  # BUG: bee.home
  modules = [./ren-module.nix userConfig] ++ hmModules;
};
```
`config.bee.home` does not exist (ren-module has no `bee`). Fix: `home-manager`
(the input at `config.ren.home-manager`, resolved at l.14). Until fixed, mkHome
cannot be used.

## direnv (v0.3.0 direnvrc) — functions available in .envrc

- `use ren //<cell>/<block>/<target>` (alias `use rensa`): resolves
  `.#${currentSystem}.${cell}.${block}.${target}` (or a direct `.#attr` if the
  arg contains `#`); caches via `nix print-dev-env` into `.ren/direnv/profile-*.rc`;
  gcroots inputs; sets `PRJ_*`. Reads `.#__ren.cellsFrom` to locate cells.
- `read_state <key>` / `write_state <key> <value>`: read/write `$REN_STATE/<key>`
  (i.e. `.ren/<key>`). The intended switchable-shell mechanism.
- Env vars: `REN_ROOT` (git root), `REN_STATE` (`$REN_ROOT/.ren`),
  `REN_DO_WATCH`, `REN_DO_GCROOTS`, `REN_DO_ARCHIVE`, `REN_FLAKE_ATTR` (`__ren`).
- The profile rc ends with `eval "${shellHook:-}"`, so a shell FUNCTION defined
  by `source`-ing a file inside a devShell `shellHook` IS available in the
  interactive shell (but NOT across a `direnv exec` boundary — direnv only
  marshals env vars, not functions).
