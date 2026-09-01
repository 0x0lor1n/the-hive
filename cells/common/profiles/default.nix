# Composable NixOS modules. One file per profile; add a .nix file and it is
# picked up. rensa's equivalent of hive's `findLoad`.
#
# Two profile shapes exist in the ported code and BOTH must work:
#
#   { inputs, cell }: { config, ... }: { ... }   -- needs cell args
#   { lib, pkgs, ... }: { ... }                  -- a plain NixOS module
#
# hive's loader accepted either. `utils.importModules` applies its `args`
# unconditionally, which calls the second shape with `{inputs, cell}` and fails
# with "called without required argument 'pkgs'". So the shape is detected via
# builtins.functionArgs instead: apply cell args only if the outer function
# actually asks for them.
{
  inputs,
  cell,
  ...
}: let
  lib = inputs.nixpkgs.lib;

  files = lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n && n != "default.nix") (builtins.readDir ./.);

  load = name: let
    fn = import (./. + "/${name}");
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
