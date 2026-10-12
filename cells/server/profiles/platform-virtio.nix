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

  # BIOS boot. `device` stays unset: disko already populates
  # boot.loader.grub.devices from the EF02 partition, and nixpkgs folds
  # `device` into the same list -> "duplicated devices in mirroredBoots".
  boot.loader.grub = {
    enable = true;
    efiSupport = false;
    # /boot is 512 MB ext4; ~70 MB per generation.
    configurationLimit = 5;
  };

  # 1 vCPU / 1.9 GB / no swap / 15 GB disk. zram, not a swapfile: disk is the
  # binding constraint and nothing builds here (buildOnTarget = false).
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
