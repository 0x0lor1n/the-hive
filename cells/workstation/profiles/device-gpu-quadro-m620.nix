# Quadro M620 (Maxwell) on the proprietary driver, for CUDA. 580 is the last
# branch with Maxwell; no runtime D3 before Turing, so the GPU idles in D0
# (~7.5 W over nouveau's D3cold, accepted). Muxless: the i915 stays scanout.
{
  inputs,
  cell,
}: {
  config,
  lib,
  pkgs,
  ...
}: {
  services.xserver.videoDrivers = ["nvidia"];
  # The module loads these only with xserver.enable; udev autoloads just
  # `nvidia`, and EGL offload under Wayland needs nvidia_drm.
  boot.kernelModules = ["nvidia" "nvidia_modeset" "nvidia_drm"];
  hardware.nvidia = {
    # Follows boot.kernelPackages, so specialisation.safe gets its own build.
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    open = false; # open modules are Turing+
    nvidiaSettings = false; # X11 GUI, nothing to drive here
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true; # nvidia-offload
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };
  # btop dlopens libnvidia-ml only with the driver runpath patched in.
  security.wrappers.btop.source = lib.mkForce "${pkgs.btop.override {cudaSupport = true;}}/bin/btop";

  # D3cold with no driver bound (nouveau, or none): coreboot's _PR3 on PEG
  # does the rest. pcieport allows it on the root port.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto"
  '';
}
