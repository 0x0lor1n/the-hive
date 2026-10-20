# minas-tirith's rpool without encryption, plus `tank` raidz1 over the three
# IronWolf Pro. All by-ids live in the encrypted half.
{
  inputs,
  cell,
  system,
  ...
}: let
  globals = inputs.cells.common.globals;
  host = globals.hosts.imladris;
  legacy = mountpoint: {
    type = "zfs_fs";
    inherit mountpoint;
    options.mountpoint = "legacy";
  };
  container = {
    type = "zfs_fs";
    options = {
      canmount = "off";
      mountpoint = "none";
    };
  };
  poolFsOptions = {
    acltype = "posixacl";
    atime = "off";
    compression = "zstd";
    xattr = "sa";
    mountpoint = "none";
  };
  hdd = device: {
    inherit device;
    type = "disk";
    content = {
      type = "gpt";
      partitions.zfs = {
        size = "100%";
        content = {
          type = "zfs";
          pool = "tank";
        };
      };
    };
  };
in
  inputs.utilsLib.mkDisk {
    ren = {
      inherit system;
      inherit (inputs) pkgs disko;
    };

    disk =
      {
        main = {
          device = host.diskDevice;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                size = "1G";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = ["umask=0077"];
                };
              };
              rpool = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "rpool";
                };
              };
            };
          };
        };
      }
      // builtins.listToAttrs (inputs.nixpkgs.lib.imap1 (i: d: {
          name = "hdd${toString i}";
          value = hdd d;
        })
        host.dataDisks);

    zpool.rpool = {
      type = "zpool";
      rootFsOptions = poolFsOptions;
      options = {
        ashift = "12";
        autotrim = "on";
      };
      datasets = {
        reserved =
          container
          // {
            options = container.options // {refreservation = "10G";};
          };
        local = container;
        "local/root" =
          legacy "/"
          // {
            postMountHook = ''
              zfs snapshot rpool/local/root@blank
            '';
          };
        "local/nix" = legacy "/nix";
        "local/state" = legacy "/state";
        safe = container;
        "safe/persist" = legacy "/persist";
        # Per-service state, one dataset each so it can move pools on its own
        # (zfs send). Disko only creates these on install; on the live host
        # `zfs create -o mountpoint=legacy <name>` once before deploying.
        "safe/torrserver" = legacy "/var/lib/torrserver";
      };
    };

    zpool.tank = {
      type = "zpool";
      mode = "raidz";
      rootFsOptions = poolFsOptions;
      options.ashift = "12";
      # Disko only creates these on install; on the live host
      # `zfs create -o mountpoint=legacy [-o ...] <name>` once before deploying.
      datasets = {
        data = legacy "/tank";
        # Photos/video from camera and phone; Immich external library.
        photos =
          legacy "/tank/photos"
          // {
            options = {
              mountpoint = "legacy";
              recordsize = "1M";
            };
          };
        # Cold data that must survive: sanoid snapshots, first into warm backup.
        archive = container;
        "archive/projects" = legacy "/tank/archive/projects";
        "archive/games" = legacy "/tank/archive/games";
        "archive/backups" = legacy "/tank/archive/backups";
        "archive/archive" = legacy "/tank/archive/archive";
        # Replaceable media; Jellyfin/Navidrome. Short snapshot retention,
        # not sent to the warm backup.
        media = container;
        "media/anime" =
          legacy "/tank/media/anime"
          // {
            options = {
              mountpoint = "legacy";
              recordsize = "1M";
            };
          };
        "media/films" =
          legacy "/tank/media/films"
          // {
            options = {
              mountpoint = "legacy";
              recordsize = "1M";
            };
          };
        "media/series" =
          legacy "/tank/media/series"
          // {
            options = {
              mountpoint = "legacy";
              recordsize = "1M";
            };
          };
        "media/cartoons" =
          legacy "/tank/media/cartoons"
          // {
            options = {
              mountpoint = "legacy";
              recordsize = "1M";
            };
          };
        "media/tutorials" =
          legacy "/tank/media/tutorials"
          // {
            options = {
              mountpoint = "legacy";
              recordsize = "1M";
            };
          };
        "media/music" = legacy "/tank/media/music";
      };
    };
  }
