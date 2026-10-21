# CWWK N305 router board: 2x 82599ES SFP+ (ixgbe), 2x I226-V (igc), NVMe on
# PCIe x1. Port names are the board's, not its labels (HARDWARE-NOTES).
{
  inputs,
  cell,
}: {
  lib,
  config,
  ...
}: {
  router.ports = {
    wan = "enp1s0f0"; # SFP+ #1, WAS-110 ONU stick
    lan = [
      "enp2s0" # ETH2, Asus AP (elster, Pixel, ... behind it)
      "enp3s0" # ETH1, Vontar X5 direct (fdb 2026-10: 00:ea:25:…, adb :5555)
      "enp1s0f1" # SFP+ #2, DAC to imladris enp7s0
    ];
  };

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = ["kvm-intel"];
  # The WAS-110 is not on Intel's SFP whitelist.
  boot.extraModprobeConfig = "options ixgbe allow_unsupported_sfp=1";

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  boot.kernelParams = ["console=tty1"];

  specialisation.performance.configuration = {
    powerManagement.cpuFreqGovernor = "performance";
  };
}
