# /srv/agents: agent state shared by both accounts (the local user and the
# Entra user), outside either home. Homes are per-account and the local one
# is rolled back; /srv is the shared plane, like /srv/the-hive and
# /srv/workspace.
#
#   /srv/agents/hermes/skills     one skill tree for both Hermes instances
#   /srv/agents/hermes/memories   MEMORY.md / USER.md, shared long-term memory
#
# What is NOT shared: ~/.hermes/sessions (per-account history), config.yaml,
# auth.json, plugins (agent-proxy.nix seeds those per user). Each user's
# ~/.hermes/{skills,memories} is a symlink into here, made by the
# hermes-seed-proxy user unit (agent-proxy.nix) on login.
#
# Same mechanism as srv-workspace.nix: setgid dirs so new files land in the
# hive group, plus a default POSIX ACL so group write survives any umask.
# Hermes writes MEMORY.md through atomic rename with preserve_mode=True and
# creates skill files 0644 -> the ACL is what makes the other account able
# to write them back.
#
# The dataset (rpool/safe/srv/agents, disks/<host>.nix) survives the @blank
# rollback. On an already installed host, once by hand:
#   sudo zfs create -o mountpoint=legacy rpool/safe/srv/agents
#   (rebuild -> mount + rules below are live)
{host, ...}: {
  systemd.tmpfiles.rules = [
    "d /srv/agents                 2770 ${host.userName} hive -"
    "d /srv/agents/hermes          2770 ${host.userName} hive -"
    "d /srv/agents/hermes/skills   2770 ${host.userName} hive -"
    "d /srv/agents/hermes/memories 2770 ${host.userName} hive -"
    "A+ /srv/agents - - - - d:group:hive:rwx,group:hive:rwx"
  ];
}
