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
in let
  merged =
    (lib.evalModules {
      modules = [
        ./globals-options.nix
        encrypted
        {
          globals = {
            hosts.osgiliath.diskDevice = "/dev/vda";

            # Playground workstation VM (cells/workstation). Public throwaway
            # identity: the hashes are for `vmuser`/root on a disposable image and
            # exist so the VM boots without the encrypted half being needed.
            hosts.sevastopol = {
              diskDevice = "/dev/vda";
              isVm = true;
              hasTpm = true; # swtpm
              userName = "vmuser";
              hashedPassword = "$y$j9T$z/Vdo8yMPLoQ9PEXJDj7//$6BuWjVnrKNXrYiXOSmWReG3Iji0JZXUjAqiIUtb7hj/";
              rootHashedPassword = "$y$j9T$46atH3AmHBsnheSr3VdkW/$qaal/LB3V26HiltSiVTtd6DP3DZVJEmo24AO8EN2311";
              # Persisted in the image (/persist/etc/ssh); a new `ws-image` changes it.
              sshHostPubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJEkHLFGCFphGyc0GGyxCENyE/762o1ZPOVa1Ar15ee5 root@sevastopol";
            };

            persistence = {
              statePath = "/persist/state";
              dataPath = "/persist/data";
            };
            acme.email = null;
          };
        }
      ];
    }).config.globals;
in
  # Resolve the per-host user: a host either names its own (playground) or
  # inherits the encrypted fleet user. After this, host.userName/homeDir are
  # always strings.
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
              if h.homeDir != null
              then h.homeDir
              else if h.userName != null
              then "/home/${h.userName}"
              else merged.user.homeDir;
          }
      )
      merged.hosts;
  }
