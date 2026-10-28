# /srv/workspace: project clones shared by both accounts, setgid + default hive
# ACL.
{
  lib,
  config,
  ...
}: let
  admin = lib.head config.hive.roleHolders.admin;
in {
  # `hive` group and its members: srv-the-hive.nix (local user) and
  # himmelblau local_groups (Entra user).
  systemd.tmpfiles.rules = [
    "d /srv/workspace          2770 ${admin} hive -"
    "d /srv/workspace/work     2770 ${admin} hive -"
    "d /srv/workspace/projects 2770 ${admin} hive -"
    "a+ /srv/workspace - - - - d:group:hive:rwx,group:hive:rwx"
  ];

  # Project .envrc files load without `direnv allow`. System-level for the
  # same reason as in srv-the-hive.nix: DIRENV_CONFIG=/etc/direnv, the HM toml
  # is never read.
  programs.direnv.settings.whitelist.prefix = ["/srv/workspace"];
}
