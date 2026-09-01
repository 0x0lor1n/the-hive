# Reset @root to @root-blank in the initrd, before /sysroot mounts.
#
# btrfs has no atomic `zfs rollback -r`; this is delete-then-snapshot with a
# window. The unit is idempotent against a crash inside it: conditional delete,
# unconditional snapshot. Boot-time so the state is known regardless of how the
# previous run ended. No dated archive of the outgoing root -- on a 15 GB disk
# that is a slow out-of-space failure.
{
  inputs,
  cell,
}: {pkgs, ...}: let
  # disko labels `disk-<disk>-<part>`; virtio disks have no serial, so
  # by-partlabel is what udev actually populates.
  device = "/dev/disk/by-partlabel/disk-main-root";
  btrfs = "${pkgs.btrfs-progs}/bin/btrfs";
in {
  boot.initrd.systemd.services.impermanence-root = {
    description = "Reset @root to @root-blank";
    wantedBy = ["initrd.target"];
    after = ["dev-disk-by\\x2dpartlabel-disk\\x2dmain\\x2droot.device"];
    requires = ["dev-disk-by\\x2dpartlabel-disk\\x2dmain\\x2droot.device"];
    before = ["sysroot.mount"];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";

    script = ''
      set -eu

      mkdir -p /btrfs_tmp
      mount -t btrfs -o subvolid=5 ${device} /btrfs_tmp

      if [ -e /btrfs_tmp/@root ]; then
        # `subvolume delete` fails on a subvolume that still nests one.
        ${btrfs} subvolume list -o /btrfs_tmp/@root | cut -f9 -d' ' \
          | while read -r sub; do
              ${btrfs} subvolume delete "/btrfs_tmp/$sub"
            done
        ${btrfs} subvolume delete /btrfs_tmp/@root
      fi

      ${btrfs} subvolume snapshot /btrfs_tmp/@root-blank /btrfs_tmp/@root

      umount /btrfs_tmp
    '';
  };

  boot.initrd.systemd.initrdBin = [pkgs.btrfs-progs];
}
