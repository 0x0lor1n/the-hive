# ZFS support profile: enables ZFS, sets a stable per-host hostId.
{
  lib,
  config,
  host,
  ...
}: {
  boot.supportedFilesystems = ["zfs"];

  # ZFS requires a stable 8-hex hostId. Derived from the host's own hostName,
  # so the disko-created pool's hostid matches at import time and no two hosts
  # share one -- that collision is exactly what ZFS multihost protection exists
  # to detect. Consequence: renaming a host orphans its pool (forceImportRoot).
  networking.hostId = lib.substring 0 8 (builtins.hashString "sha256" config.networking.hostName);

  # Default /dev/disk/by-id doesn't populate for virtio disks (no hardware
  # serial); the disko-created pool's vdev label uses by-partlabel, which
  # udev does populate. GPT partlabels exist on bare metal too, so this is
  # correct for both.
  boot.zfs.devNodes = "/dev/disk/by-partlabel";

  # VM-ONLY, and deliberately not applied to real hardware.
  #
  # The disko image builder VM writes an /etc/hostid that does not match
  # networking.hostId, so without forcing, the pool refuses to import in
  # initrd. forceImportRoot only affects the userspace zfs-import script;
  # the initrd's zfs-import-rpool checks kernelParams for zfs_force, so
  # both are needed together.
  #
  # But forcing import is exactly "ignore the hostId mismatch", i.e. it
  # switches off the protection the per-host hostId above provides. On a
  # laptop that could mean importing a pool another system still has open.
  # A bare-metal pool is created by disko running on the target itself, so
  # the hostid matches from the start and no forcing is needed.
  boot.zfs.forceImportRoot = host.isVm;
  boot.kernelParams = lib.optionals host.isVm ["zfs_force=1"];

  # No autoScrub on the VMs (ephemeral, scrubs are noise). Real hardware
  # gets it -- a laptop pool that is never scrubbed silently rots.
  services.zfs.autoScrub = lib.mkIf (!host.isVm) {
    enable = true;
    interval = "monthly";
  };
}
