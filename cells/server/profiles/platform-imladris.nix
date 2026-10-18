# MSI B250M PRO-VD: OS NVMe behind an ASM2824 switch, IronWolfs on the PCH
# AHCI, NIC r8169. Onboard xHCI (8086:a2af) is dead and hangs probing, so
# pci_stub claims it before xhci_hcd can.
{
  inputs,
  cell,
}: {
  lib,
  config,
  ...
}: {
  boot.initrd.availableKernelModules = [
    "nvme"
    "ahci"
    "sd_mod"
  ];
  boot.initrd.kernelModules = ["pci_stub"];
  boot.extraModprobeConfig = "options pci_stub ids=8086:a2af";
  boot.kernelModules = ["kvm-intel"];

  # storage-zfs-rollback is an initrd systemd unit.
  boot.initrd.systemd.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  # Installed from a legacy-booted kexec (no EFI runtime): land in the
  # fallback \EFI\BOOT\BOOTX64.EFI instead of an NVRAM entry.
  boot.loader.efi.canTouchEfiVariables = false;

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  boot.kernelParams = ["console=tty1"];
}
