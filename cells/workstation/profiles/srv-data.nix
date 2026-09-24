# /srv/data: personal files that are not code, shared by both accounts like
# the rest of /srv. the-hive and workspace stay for repos.
#
#   /srv/data/music       own dataset, recordsize=1M
#   /srv/data/documents   own dataset
#   /srv/data/torrents    plain dir, qBittorrent downloads
#   /srv/data/*           anything else: plain dirs until it needs its own
#                         dataset (snapshot/backup policy)
#
# Same mechanism as srv-workspace.nix: setgid dirs + default hive ACL.
#
# The datasets (rpool/safe/srv/data{,/music,/documents}, disks/<host>.nix)
# survive the @blank rollback. On an already installed host, once by hand:
#   sudo zfs create -o mountpoint=legacy rpool/safe/srv/data
#   sudo zfs create -o mountpoint=legacy -o recordsize=1M rpool/safe/srv/data/music
#   sudo zfs create -o mountpoint=legacy rpool/safe/srv/data/documents
#   (rebuild -> mounts + rules below are live)
{host, ...}: {
  systemd.tmpfiles.rules = [
    "d /srv/data           2770 ${host.userName} hive -"
    "d /srv/data/music     2770 ${host.userName} hive -"
    "d /srv/data/documents 2770 ${host.userName} hive -"
    # qBittorrent save path (home/desktop/torrent.nix).
    "d /srv/data/torrents  2770 ${host.userName} hive -"
    "A+ /srv/data - - - - d:group:hive:rwx,group:hive:rwx"
  ];
}
