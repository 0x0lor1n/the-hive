# The host's repo, exported into a QEMU guest over virtio-9p.
#
# A playground fact, not a virtio fact: it exists so `nixos-rebuild switch
# --flake /mnt/share#...` works inside the dev VMs without a manual mount each
# boot, and it pairs with the host's `-virtfs local,mount_tag=share,...`.
# osgiliath is a virtio guest with no such share, hence the separate profile.
{
  inputs,
  cell,
}: {...}: {
  fileSystems."/mnt/share" = {
    device = "share";
    fsType = "9p";
    options = [
      "trans=virtio"
      "version=9p2000.L"
      "nofail" # don't block boot if running without the 9p share
    ];
  };

  boot.initrd.availableKernelModules = [
    "9p"
    "9pnet_virtio"
  ];
}
