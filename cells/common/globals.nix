# Repo-wide parameters: schema (globals-options.nix) + public values (here) +
# the encrypted half, merged with lib.evalModules. A block, so it is evaluated
# once and read as `inputs.cells.common.globals`.
{
  inputs,
  cell,
  ...
}: let
  lib = inputs.nixpkgs.lib;

  # extra-builtins.nix asserts isPath; outPath carries store context.
  flakeRoot = /. + builtins.unsafeDiscardStringContext inputs.self.outPath;

  identities = [(flakeRoot + "/secrets/jarvis-nopin-rage.pub")];

  encrypted = assert lib.assertMsg (builtins ? extraBuiltins) ''
    globals: `builtins.extraBuiltins` is missing. Run from the repo devshell,
    which sets NIX_CONFIG's plugin-files and extra-builtins-file.
  '';
    builtins.extraBuiltins.rageImportEncrypted identities (flakeRoot + "/secrets/globals.nix.age");
in
  (lib.evalModules {
    modules = [
      ./globals-options.nix
      encrypted
      {
        globals = {
          hosts.osgiliath.diskDevice = "/dev/vda";
          persistence = {
            statePath = "/persist/state";
            dataPath = "/persist/data";
          };
          acme.email = null;
        };
      }
    ];
  })
  .config
  .globals
