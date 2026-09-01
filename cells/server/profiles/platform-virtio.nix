# QEMU/virtio guest.
{
  inputs,
  cell,
}: {...}: {
  services.qemuGuest.enable = true;

  # services.qemuGuest does not add these; without them /dev/vda is invisible
  # before stage 2 and the root mount hangs.
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
  ];

  # The LAST console= is primary; ttyS0 last puts boot output on the provider's
  # serial console, the only way to watch a failed boot on a VPS.
  boot.kernelParams = [
    "console=tty1"
    "console=ttyS0,115200"
  ];
}
