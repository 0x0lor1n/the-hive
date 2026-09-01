# Btrfs support: kernel support and periodic scrub.
#
# The btrfs counterpart to storage-zfs.nix, and deliberately much smaller.
# There is no hostId (that is a ZFS multihost-protection concept), no
# devNodes override (btrfs finds its own members by UUID), and no
# forceImportRoot (btrfs has no import step).
{
  inputs,
  cell,
}: {...}: {
  boot.supportedFilesystems = ["btrfs"];

  # A pool that is never scrubbed silently rots — same reasoning as
  # storage-zfs.nix's autoScrub, and unconditional here because the only
  # btrfs host is real (a VPS), not a disposable image.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = ["/"];
  };
}
