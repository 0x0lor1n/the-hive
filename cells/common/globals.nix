# Repo-wide parameters: the public schema, the public values, and the
# age-encrypted half, merged with lib.evalModules.
#
# Ported from test-vm's cells/nixos/globals.nix. Two changes for rensa:
#
#  1. It is a BLOCK, not a file imported by its consumers. Cells read it as
#     `inputs.cells.common.globals`, so it is evaluated once rather than
#     re-imported by every consumer.
#  2. `self` comes from `inputs.self`, which rensa reduces to sourceInfo
#     (import-signature.nix:20-23). `outPath` survives, which is all this
#     needs -- verified by spike A.
{
  inputs,
  cell,
  ...
}: let
  lib = inputs.nixpkgs.lib;

  # /. + <string> re-coerces the flake root to a genuine PATH:
  # extra-builtins.nix asserts builtins.isPath, and unsafeDiscardStringContext
  # is required because outPath carries store-path context.
  flakeRoot = /. + builtins.unsafeDiscardStringContext inputs.self.outPath;

  identities = [(flakeRoot + "/secrets/jarvis-nopin-rage.pub")];

  encrypted = assert lib.assertMsg (builtins ? extraBuiltins) ''

    globals: the `extraBuiltins` namespace is missing.

    Run from inside test-vm's devshell, which sets NIX_CONFIG's plugin-files
    and extra-builtins-file. See the rensa spike README.
  '';
    builtins.extraBuiltins.rageImportEncrypted identities (flakeRoot + "/secrets/globals.nix.age");

  user = {
    uid = 1000;
    shell = "zsh";
  };

  hosts.osgiliath = {
    hostName = "osgiliath";
    isVm = true;
    isPlayground = false;
    gpu = "none";
    hasTpm = false;
    isLaptop = false;
    diskDevice = "/dev/vda";
    headless = true;
  };

  persistence = {
    statePath = "/persist/state";
    dataPath = "/persist/data";
  };

  acme.email = null;

  merged =
    (lib.evalModules {
      modules = [
        ./globals-options.nix
        encrypted
        {globals = {inherit user hosts persistence acme;};}
      ];
    })
    .config
    .globals;
in
  merged
  // {
    hosts =
      builtins.mapAttrs (
        _: h:
          h
          // {
            userName =
              if h.userName != null
              then h.userName
              else merged.user.name;
            homeDir =
              if h.userName != null
              then "/home/${h.userName}"
              else merged.user.homeDir;
          }
      )
      merged.hosts;
  }
