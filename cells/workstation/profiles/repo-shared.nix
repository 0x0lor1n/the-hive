# The fleet checkout at /etc/nixos, shared between the local break-glass user
# and whoever logs in through Entra (himmelblau mints those accounts at first
# login, so they cannot be listed here). Anyone in group `hive` may pull and
# rebuild; `nixos-rebuild switch --sudo` needs no --flake because the CLI
# defaults to /etc/nixos/flake.nix.
#
# Group-writable checkout mechanics:
#   setgid + default ACL  -> new files inherit group `hive` and g+rw whatever
#                            the writer's umask says (rpool mounts with posixacl)
#   core.sharedRepository -> git keeps .git/objects group-writable too
#   safe.directory        -> git refuses "dubious ownership" otherwise, since the
#                            tree is owned by one user and read by another (and root)
{
  inputs,
  cell,
  ...
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  host = config.rensa.host;
  repo = "/etc/nixos";
in {
  users.groups.hive = {};
  users.users.${host.userName}.extraGroups = ["hive"];

  # Entra users pick the group up alongside wheel/video/... at login.
  services.himmelblau.settings.local_groups = ["hive"];

  # Ephemeral root: the checkout itself has to survive the rollback.
  environment.persistence."/persist".directories = [
    {
      directory = repo;
      user = "root";
      group = "hive";
      mode = "2775";
    }
  ];

  # Default ACL so files created by any member stay group-writable, whatever
  # their umask. Idempotent; runs after impermanence has bind-mounted the dir.
  systemd.tmpfiles.rules = [
    "d ${repo} 2775 root hive -"
    "A+ ${repo} - - - - default:group:hive:rwx,default:user::rwx,default:other::r-x,default:mask::rwx"
  ];

  programs.git = {
    enable = true;
    config = {
      safe.directory = [repo];
      # inherited by clones only at init; set explicitly in docs for the first clone
      core.sharedRepository = "group";
    };
  };
}
