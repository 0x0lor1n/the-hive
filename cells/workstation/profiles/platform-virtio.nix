# QEMU/virtio guest platform — the VM counterpart to
# platform-baremetal.nix. Was profiles/hardware-vm-guest.nix.
#
# Generic virtio facts ONLY. The playground's 9p repo share moved to
# dev-9p-share.nix in iter 11, because osgiliath is a virtio guest (a KVM
# VPS) with no such share — a new machine is a new COMBINATION of device
# files, per devices/default.nix.
{
  inputs,
  cell,
}: {lib, ...}: {
  services.qemuGuest.enable = true;

  # Without these in the initrd the kernel cannot see /dev/vda before
  # stage 2 and the root filesystem mount hangs forever — services.qemuGuest
  # does not add them itself. (Bare metal's equivalent is disk-nvme.nix.)
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
  ];

  # Linux uses the LAST console= as primary; with -nographic (no tty1 output)
  # ttyS0 must be last so the serial console is the live one. This is also
  # what puts osgiliath's boot output on the provider's serial console —
  # the only way to watch a failed boot on a VPS.
  boot.kernelParams = [
    "console=tty1"
    "console=ttyS0,115200"
  ];

  # Replaced by Lanzaboote in hardware-secureboot.nix, kept for the
  # non-SecureBoot `just vm-run` path. mkDefault so a BIOS-booting guest
  # (osgiliath, which uses GRUB) can turn it off with a plain definition.
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  # False on purpose: no NVRAM writes on the host building the image;
  # QEMU+OVMF's firmware fallback path handles boot without it.
  boot.loader.efi.canTouchEfiVariables = false;
}
