# /srv/data: non-code files shared by both accounts, setgid + default hive ACL.
{
  lib,
  config,
  ...
}: let
  admin = lib.head config.hive.roleHolders.admin;
in {
  systemd.tmpfiles.rules = [
    "d /srv/data           2770 ${admin} hive -"
    "d /srv/data/music     2770 ${admin} hive -"
    "d /srv/data/documents 2770 ${admin} hive -"
    # qBittorrent save path (home/desktop/torrent.nix).
    "d /srv/data/torrents  2770 ${admin} hive -"
    "a+ /srv/data - - - - d:group:hive:rwx,group:hive:rwx"
  ];
}
