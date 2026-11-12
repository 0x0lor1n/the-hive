# /srv/the-hive: the single checkout of this repo, writable by both accounts via the hive group.
{
  lib,
  config,
  ...
}: let
  admin = lib.head config.hive.roleHolders.admin;
in {
  # The Entra account gets the group from himmelblau's local_groups (auth-entra.nix).
  users.groups.hive = {};
  users.users = lib.genAttrs config.hive.localUsers (_: {extraGroups = ["hive"];});

  # NixOS sets DIRENV_CONFIG=/etc/direnv, so a home-manager whitelist is never read.
  programs.direnv.settings.whitelist.prefix = ["/srv/the-hive"];

  systemd.tmpfiles.rules = [
    # `z`, not `d`: a dir created before the clone makes `git clone` refuse it.
    # 0770, not 0750: with an ACL the group bits are the mask, so 0750 caps group:hive at r-x.
    "z /srv/the-hive 0770 ${admin} hive -"
    # Default ACL instead of setgid/umask/core.sharedRepository: inherited under any umask.
    # Lowercase `a+` is non-recursive; a recursive walk cost 10+ min per boot on /srv/workspace.
    "a+ /srv/the-hive - - - - d:group:hive:rwx,group:hive:rwx"
  ];
}
