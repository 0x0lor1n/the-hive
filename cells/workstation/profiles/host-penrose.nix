# penrose-only. The machine is on or off, never asleep (coreboot advertises
# only S0/S5). elster keeps the default sleep: its Intune compliance wants it.
{
  inputs,
  cell,
}: {
  config,
  lib,
  pkgs,
  ...
}: {
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
  # btop dlopens libnvidia-ml only with the driver runpath patched in.
  security.wrappers.btop.source = lib.mkForce "${pkgs.btop.override {cudaSupport = true;}}/bin/btop";

  # The firmware leaves TB3 at SL1; the dock is authorised by dock-wd19tb.nix.
  # Authorisation only gates the tunnel; an authorised device still DMAs
  # anywhere without VT-d. The coreboot DMAR has no opt-in flag, so it stays
  # off by default.
  boot.kernelParams = ["intel_iommu=on"];

  # Boot default only; the powermenu still flips it (cpu-governor.nix).
  powerManagement.cpuFreqGovernor = "performance";

  services.logind.settings.Login = {
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
  };

  # No Intune here, so no idle lock either; swayidle only blanks the screen.
  session.idleLock = false;

  # Own PK/KEK/db only. Nothing here runs an option ROM: libgfxinit drives the
  # iGPU, the M620 has no ROM chip, the I219 has no oprom.
  boot.lanzaboote.autoEnrollKeys = {
    includeMicrosoftKeys = false;
    allowBrickingMyMachine = true;
  };
  # sbctl create-keys takes the cert CN from keys.*.description.
  environment.etc."sbctl/sbctl.conf".source = let
    dir = config.boot.lanzaboote.pkiBundle;
    key = name: description: {
      privkey = "${dir}/keys/${name}/${name}.key";
      pubkey = "${dir}/keys/${name}/${name}.pem";
      type = "file";
      inherit description;
    };
  in
    lib.mkForce ((pkgs.formats.yaml {}).generate "sbctl.conf" {
      keydir = "${dir}/keys";
      guid = "${dir}/GUID";
      keys = {
        pk = key "PK" "penrose.the-hive Platform Key";
        kek = key "KEK" "penrose.the-hive Key Exchange Key";
        db = key "db" "penrose.the-hive Signature Database Key";
      };
    });

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };
}
