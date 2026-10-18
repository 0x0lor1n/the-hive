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
      };
    };

    zpool.tank = {
      type = "zpool";
      mode = "raidz";
      rootFsOptions = poolFsOptions;
      options.ashift = "12";
      datasets.data = legacy "/tank";
    };
  }
