# Physical x86 machine -- the counterpart to platform-virtio.nix. Generic
# "it is real hardware" facts only; the GPU and the laptop shape are their own
# profiles (gpu-intel.nix, laptop.nix), per devices/default.nix.
#
# First host: penrose (Dell Latitude 5580, i7-7600U). The initrd module list
# is what nixos-generate-config emitted there; it is the common set for any
# NVMe laptop with a Realtek card reader, not penrose-specific.
{
  inputs,
  cell,
}: {
  lib,
  config,
  ...
}: {
  # The disk (nvme) and the keyboard (xhci) must be visible before stage 2,
  # same reasoning as virtio_blk in platform-virtio.nix.
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "nvme"
    "usb_storage"
    "sd_mod"
    "rtsx_pci_sdmmc"
  ];
  boot.kernelModules = ["kvm-intel"];

  # Firmware owns its NVRAM here: lanzaboote/systemd-boot may write boot
  # entries. Plain `true` overrides the mkDefault false in
  # hardware-secureboot.nix (image builds must not touch the build host).
  boot.loader.efi.canTouchEfiVariables = true;
  # Replaced by lanzaboote when hardware-secureboot is in the host's list.
  boot.loader.systemd-boot.enable = lib.mkDefault true;

  # Ported from ~/nixos-config/config/hardware/intel.nix: microcode rides on
  # the redistributable-firmware switch, the wifi/bt blobs come with it.
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Real console: the last console= wins, so tty1 stays primary (no serial).
  boot.kernelParams = ["console=tty1"];
}
