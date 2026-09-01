# osgiliath's disk, in rensa's idiom: one file per disk in a `disks` block,
# merged into disko.devices by utils.collectDisks.
#
# BIOS boot, not UEFI -- confirmed on the target. So a 1 MiB EF02 partition for
# GRUB's stage 1.5, no ESP, and /boot on its own ext4 partition because
# impermanence rolls the btrfs root back on every boot.
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

    # NOT `disko.devices.disk.main`. mkDisk's second evalModules sets
    # `freeformType = diskoLib.toplevel`, which is the type of the CONTENT of
    # disko.devices -- so a disk is declared at the top level here, and
    # `collectDisks` produces the value for `disko.devices` in the host.
    disk.main = {
      # Real device, not a REPLACE-ME sentinel: virtio disks have no by-id
      # entry, the machine is meant to be wiped, and `nixos-anywhere
      # --store-paths` has no --disk override. NEVER /dev/sda -- that is the
      # provider's 368 KB iso9660 config drive.
      device = globals.hosts.osgiliath.diskDevice;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          # priority 1 forces it first; without it GRUB has nowhere to embed.
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
              # Siblings, NOT nested under @root: storage-btrfs-rollback
              # deletes @root wholesale.
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
              # Taken at CREATE time so it captures a genuinely empty root.
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
