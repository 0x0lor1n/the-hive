# Intel iGPU (i915) as the only display device. Counterpart to gpu-virtio.nix:
# nothing here about cursors or output modes -- a real panel has a real EDID.
#
# penrose is a hybrid (HD 620 + GeForce 930MX on nouveau, phase 0 recon). The
# dGPU is not worth its power budget for dwl: keep it off the bus. Revisit
# only if an external display turns out to be wired to it.
{
  inputs,
  cell,
}: {pkgs, ...}: {
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver # VAAPI (Broadwell+), what firefox/mpv ask for
    intel-compute-runtime # OpenCL, cheap to carry
  ];

  boot.blacklistedKernelModules = ["nouveau" "nvidia" "nvidia_drm" "nvidia_modeset"];
  # Without a driver bound, the dGPU sits in D0 forever; runtime PM lets the
  # PCI core put it to D3cold once nothing claims it.
  boot.kernelParams = ["nouveau.modeset=0"];
  services.udev.extraRules = ''
    # NVIDIA VGA/3D controller with no driver: allow runtime suspend.
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto"
  '';
}
