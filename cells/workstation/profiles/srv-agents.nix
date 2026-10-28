# /srv/agents: Hermes skills and memories shared by both accounts (links: agent-proxy.nix).
{
  lib,
  config,
  ...
}: let
  admin = lib.head config.hive.roleHolders.admin;
in {
  systemd.tmpfiles.rules = [
    "d /srv/agents                 2770 ${admin} hive -"
    "d /srv/agents/hermes          2770 ${admin} hive -"
    "d /srv/agents/hermes/skills   2770 ${admin} hive -"
    "d /srv/agents/hermes/memories 2770 ${admin} hive -"
    # Hermes writes MEMORY.md by mode-keeping rename and skills as 0644; the ACL adds group write.
    "a+ /srv/agents - - - - d:group:hive:rwx,group:hive:rwx"
  ];
}
