# Workstation impermanence layout minus /srv; the key is unsealed behind PCR 15.
{
  inputs,
  cell,
  system,
  ...
}: let
  globals = inputs.cells.common.globals;
  host = globals.hosts.minas-tirith;
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
in
  inputs.utilsLib.mkDisk {
    ren = {
      inherit system;
      inherit (inputs) pkgs disko;
    };

    disk.main = {
      # by-id, encrypted half: nvmeX swaps when a second disk is present.
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

    zpool.rpool = {
      type = "zpool";
      rootFsOptions = {
        acltype = "posixacl";
        atime = "off";
        compression = "zstd";
        xattr = "sa";
        mountpoint = "none";
        # Install-time key via --disk-encryption-keys; zfs-key-sync rotates it
        # to the agenix passphrase on boot 1 (as penrose).
        encryption = "on";
        keyformat = "passphrase";
        keylocation = "file:///tmp/rpool.key";
      };
      options = {
        ashift = "12";
        autotrim = "on";
      };
      postCreateHook = ''
        zfs set keylocation=prompt rpool
      '';

      datasets = {
        # Headroom: logs can never fill the pool to zero.
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
        # IDS output: no snapshots, no backup, capped so a broken rotation
        # cannot eat the pool. Quotas are start values (`zfs set quota=`).
        logs = container;
        "logs/suricata" =
          legacy "/var/log/suricata"
          // {
            options = {
              mountpoint = "legacy";
              recordsize = "1M"; # eve.json / pcap: large sequential writes
              quota = "300G";
            };
          };
        "logs/kismet" =
          legacy "/var/lib/kismet"
          // {
            options = {
              mountpoint = "legacy";
              quota = "50G"; # sqlite .kismet files: default recordsize
            };
          };
      };
    };
  }
