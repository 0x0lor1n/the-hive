# One file per profile; a .nix file here is picked up by name.
#
# Two shapes are accepted, detected via functionArgs:
#   { inputs, cell }: <nixos module>   -- needs cell args
#   <nixos module>                      -- plain
# utils.importModules applies its args unconditionally, which breaks the plain
# shape ("called without required argument 'pkgs'"), hence this loader.
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
