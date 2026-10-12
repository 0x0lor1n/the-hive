# Each cell's profiles/default.nix: one profile per .nix file in `dir`.
# A profile is `{inputs, cell}: <module>` or a plain module, told apart by
# functionArgs: utils.importModules applies args unconditionally and breaks
# plain modules ("called without required argument 'pkgs'").
# `__`-prefixed files are helpers imported by profiles, not modules.
{
  inputs,
  cell,
  dir,
}: let
  lib = inputs.nixpkgs.lib;

  files = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n && n != "default.nix" && !lib.hasPrefix "__" n) (builtins.readDir dir);

  load = name: let
    fn = import (dir + "/${name}");
    wants =
      if builtins.isFunction fn
      then builtins.functionArgs fn
      else {};
  in
    if (wants ? inputs) || (wants ? cell)
    then fn {inherit inputs cell;}
    else fn;
in
  lib.mapAttrs' (name: _: lib.nameValuePair (lib.removeSuffix ".nix" name) (load name)) files
