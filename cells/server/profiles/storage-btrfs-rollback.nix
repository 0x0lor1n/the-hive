# Initrd service that resets the @root subvolume to a pristine @root-blank
# before /sysroot mounts — this is what makes root ephemeral on btrfs.
#
# The btrfs counterpart to storage-zfs-rollback.nix, and NOT a mechanical
# translation of it. `zfs rollback -r` is one atomic operation; btrfs has no
# equivalent, so this is delete-then-snapshot, which has a window. The unit
# is therefore written to be idempotent against a crash inside that window:
# the delete is conditional, the snapshot is unconditional, so a machine
# that dies mid-rollback recovers on the next boot rather than coming up
# with no root subvolume at all.
#
# Boot-time (not shutdown-time) so the system reaches a known state
# regardless of how the previous run ended; environment.persistence layers
# the carve-outs (/persist, /state) back in afterward.
#
# Deliberately does NOT archive the outgoing root the way the widely-copied
# "erase your darlings" snippet does. That snippet keeps dated copies of
# every previous root, which on a 15 GB disk is a slow-motion out-of-space
# failure. Anything worth keeping belongs in /persist by name.
{
  inputs,
  cell,
}: {pkgs, ...}: let
  # disko labels partitions `disk-<diskName>-<partName>`; ours is disk
  # `main`, partition `root`. Same by-partlabel convention storage-zfs.nix
  # relies on, and it is what udev actually populates for virtio disks
  # (which carry no serial, so by-id does not exist -- confirmed on the
  # target, iter 11 §2.2).
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
      # subvolid=5 is the btrfs top level, so @root and @root-blank are both
      # visible as plain directories here regardless of what is mounted where.
      mount -t btrfs -o subvolid=5 ${device} /btrfs_tmp

      if [ -e /btrfs_tmp/@root ]; then
        # Nested subvolumes must go first -- `btrfs subvolume delete` fails
        # on a subvolume that still contains one. Nothing in this host's
        # layout nests (@nix/@state/@persist are siblings), but a runtime
        # tool could have made one, and discovering that at boot with no
        # console is not the moment to find out.
        ${btrfs} subvolume list -o /btrfs_tmp/@root | cut -f9 -d' ' \
          | while read -r sub; do
              ${btrfs} subvolume delete "/btrfs_tmp/$sub"
            done
        ${btrfs} subvolume delete /btrfs_tmp/@root
      fi

      # Unconditional: this is what makes the unit safe to re-run after a
      # crash between the delete above and this line.
      ${btrfs} subvolume snapshot /btrfs_tmp/@root-blank /btrfs_tmp/@root

      umount /btrfs_tmp
    '';
  };

  # systemd-initrd ships a minimal store closure; btrfs-progs is not in it
  # by default, and `mount`/`umount` come from util-linux which systemd's
  # initrd already provides.
  boot.initrd.systemd.initrdBin = [pkgs.btrfs-progs];
}
