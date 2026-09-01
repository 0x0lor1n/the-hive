# BIOS boot: 1 MiB EF02 for GRUB stage 1.5, no ESP, /boot on its own ext4
# because impermanence rolls the btrfs root back on every boot.
{
  inputs,
  cell,
  system,
  ...
}: let
  globals = inputs.cells.common.globals;
in
  inputs.utilsLib.mkDisk {
    ren = {
      inherit system;
      inherit (inputs) pkgs disko;
    };

    # mkDisk's freeform type is diskoLib.toplevel, i.e. the CONTENT of
    # disko.devices -- so `disk.main`, not `disko.devices.disk.main`.
    disk.main = {
      device = globals.hosts.osgiliath.diskDevice;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02";
            priority = 1;
          };

          bootfs = {
            size = "512M";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/boot";
            };
          };

          root = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = ["-f"];
              # Siblings, not nested under @root: the rollback deletes @root.
              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = ["compress=zstd" "noatime"];
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = ["compress=zstd" "noatime"];
                };
                "@state" = {
                  mountpoint = "/state";
                  mountOptions = ["compress=zstd" "noatime"];
                };
                "@persist" = {
                  mountpoint = "/persist";
                  mountOptions = ["compress=zstd" "noatime"];
                };
              };
              postCreateHook = ''
                MNT=$(mktemp -d)
                mount -t btrfs -o subvol=/ "$device" "$MNT"
                btrfs subvolume snapshot -r "$MNT/@root" "$MNT/@root-blank"
                umount "$MNT"
                rmdir "$MNT"
              '';
            };
          };
        };
      };
    };
  }
