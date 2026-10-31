# penrose-only. The machine is on or off, never asleep (coreboot advertises
# only S0/S5). elster keeps the default sleep: its Intune compliance wants it.
{
  inputs,
  cell,
}: {config, ...}: {
  # Quadro M620 (Maxwell) on the proprietary driver, for CUDA. 580 is the last
  # branch with Maxwell; no runtime D3 before Turing, so the GPU idles in D0
  # (~7.5 W over nouveau's D3cold, accepted). Muxless: the i915 stays scanout.
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

  # Boot default only; the powermenu still flips it (cpu-governor.nix).
  powerManagement.cpuFreqGovernor = "performance";

  services.logind.settings.Login = {
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
  };

  # No Intune here, so no idle lock either; swayidle only blanks the screen.
  session.idleLock = false;

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };
}
