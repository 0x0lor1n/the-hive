# Native ZFS encryption behind a pre-unseal PCR 15 gate. Ported from test-vm's
# diskoConfigurations.nix (sevastopol target only; the LUKS variant was dropped).
#
# ESP + one partition for `rpool`. The pool root carries the encryption, the
# datasets are the impermanence layout: local/root is rolled back to @blank on
# every boot (storage-zfs-rollback.nix), local/nix, local/state and
# safe/persist survive.
{
  inputs,
  cell,
  system,
  ...
}: let
  globals = inputs.cells.common.globals;
  host = globals.hosts.sevastopol;
  inherit (inputs) pkgs;
in
  inputs.utilsLib.mkDisk {
    ren = {
      inherit system;
      inherit (inputs) pkgs disko;
    };

    # mkDisk's freeform type is diskoLib.toplevel, i.e. the CONTENT of
    # disko.devices -- so `disk.main`, not `disko.devices.disk.main`.
    disk.main = {
      device = host.diskDevice;
      type = "disk";
      # Only consumed by the disko image builder (`ws-image`).
      imageSize = "20G";
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

        # Throwaway key in the nix store so disko can create the pool without a
        # TTY; the operator re-seals/rotates after the first boot (see
        # hardware-zfs-tpm.nix). Never used on real hardware: dellvis will get
        # its own disk file with a real passphrase flow.
        encryption = "on";
        keyformat = "passphrase";
        keylocation = "file://${pkgs.writeText "zfs-initial-key" "qwerty123"}";
      };
      options = {
        ashift = "12";
        autotrim = "on";
      };
      # The store path above does not exist in the booted initrd; switch to the
      # prompt (or the TPM credential) once the pool exists.
      postCreateHook = ''
        zfs set keylocation=prompt rpool
      '';

      datasets = {
        reserved = {
          type = "zfs_fs";
          options = {
            canmount = "off";
            mountpoint = "none";
            refreservation = "1G";
          };
        };
        local = {
          type = "zfs_fs";
          options = {
            canmount = "off";
            mountpoint = "none";
          };
        };
        "local/root" = {
          type = "zfs_fs";
          mountpoint = "/";
          options.mountpoint = "legacy";
          # Runs after the dataset mounts, so mkdir lands inside it: pre-creates
          # the local user's home in the @blank snapshot. gid 100 is the `users`
          # group set in common/layer-users-root.nix.
          postMountHook = ''
            mkdir -p "''${rootMountPoint:-/mnt}${host.homeDir}"
            chown ${toString globals.user.uid}:100 "''${rootMountPoint:-/mnt}${host.homeDir}"
            chmod 0700 "''${rootMountPoint:-/mnt}${host.homeDir}"
            zfs snapshot rpool/local/root@blank
          '';
        };
        "local/nix" = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options.mountpoint = "legacy";
        };
        "local/state" = {
          type = "zfs_fs";
          mountpoint = "/state";
          options.mountpoint = "legacy";
        };
        safe = {
          type = "zfs_fs";
          options = {
            canmount = "off";
            mountpoint = "none";
          };
        };
        "safe/persist" = {
          type = "zfs_fs";
          mountpoint = "/persist";
          options.mountpoint = "legacy";
        };
      };
    };
  }
