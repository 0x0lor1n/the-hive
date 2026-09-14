# /srv/workspace: project clones shared by both accounts, outside either
# home (homes are per-account and the local one is rolled back; /srv is
# the shared plane, like /srv/the-hive).
#
#   /srv/workspace/work       client / employer repos
#   /srv/workspace/projects   personal
#
# Same mechanism as srv-the-hive.nix, but writable for the whole hive group
# from the root down: setgid dir so new files land in the group, plus a
# DEFAULT POSIX ACL so group write survives any umask git clones under.
# ACLs live in the fs, not in git; tmpfiles re-applies them at every boot.
#
# The dataset (rpool/safe/srv/workspace, disks/<host>.nix) survives the
# @blank rollback. On an already installed host, once by hand:
#   sudo zfs create -o mountpoint=legacy rpool/safe/srv/workspace
#   (rebuild -> mount + rules below are live)
{host, ...}: {
  # `hive` group and its members: srv-the-hive.nix (local user) and
  # himmelblau local_groups (Entra user).
  systemd.tmpfiles.rules = [
    "d /srv/workspace          2770 ${host.userName} hive -"
    "d /srv/workspace/work     2770 ${host.userName} hive -"
    "d /srv/workspace/projects 2770 ${host.userName} hive -"
    "A+ /srv/workspace - - - - d:group:hive:rwx,group:hive:rwx"
  ];
}
