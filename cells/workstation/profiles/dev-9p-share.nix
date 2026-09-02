# The host's repo, exported into a QEMU guest over virtio-9p.
#
# Split out of platform-virtio.nix in iter 11. It is a PLAYGROUND fact, not
# a virtio fact: it exists so `nixos-rebuild switch --flake /mnt/share#...`
# works inside the dev VMs without a manual mount each boot, and it pairs
# with the host's `-virtfs local,mount_tag=share,...` in the justfile.
#
# osgiliath is a virtio guest with no such share, which is precisely why
# this could not stay in platform-virtio.nix.
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
