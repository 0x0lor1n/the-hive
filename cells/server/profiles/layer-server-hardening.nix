# Everything that makes a host safe and maintainable on a public IP:
# SSH exposure, bootloader, swap, store housekeeping, and the deploy key.
#
# Server-only (suites.server). base.nix's sshd settings are deliberately
# permissive for the playground -- `just ssh-vm-agent` depends on password
# auth, see AGENTS.md -> "Coding-agent SSH access to the VM" -- so this
# profile overrides them rather than weakening base.nix for every host.
{
  inputs,
  cell,
}: {
  lib,
  host,
  ...
}: {
  # ---------------------------------------------------------------------
  # SSH exposure
  # ---------------------------------------------------------------------
  #
  # mkForce on every line: base.nix sets these as PLAIN definitions, so a
  # plain value here is a conflict rather than an override -- the same trap
  # hardware-secureboot.nix:56-63 documents for canTouchEfiVariables.
  services.openssh.settings = {
    # "prohibit-password", not "yes": root gets in by key only. The console
    # (the provider's VNC) still accepts the password below, which is the
    # recovery path if the deploy key is ever lost -- and it matters more
    # here than elsewhere, because impermanence wipes / on every boot.
    PermitRootLogin = lib.mkForce "prohibit-password";
    PasswordAuthentication = lib.mkForce false;
    KbdInteractiveAuthentication = lib.mkForce false;
  };

  # The colmena deploy key. PUBLIC half, committed plaintext; the private
  # half lives in secrets/deploy/osgiliath-deploy.age, encrypted to the
  # PIN-protected workstation identity so no unattended process can deploy.
  #
  # inputs.self.outPath (not ./.) so this resolves to the flake root
  # regardless of how deep this file sits -- same idiom as
  # layer-users-local.nix.
  users.users.root.openssh.authorizedKeys.keyFiles = [
    (inputs.self.outPath + "/secrets/deploy/osgiliath-deploy.pub")
  ];

  # Root's password itself is resolved by layer-users-root.nix, which reads
  # host.rootHashedPassword with a fallback to the fleet default. What is
  # server-specific is that the FALLBACK MUST NOT HAPPEN here.
  #
  # An internet-facing host silently inheriting the fleet password would be
  # the same defect as `isPlayground = host.isVm` (iter 11 §0.3): a shared,
  # and for the playground hosts published, credential reachable from the
  # internet. An assertion makes it loud at eval time.
  #
  # This is the console (VNC) recovery path -- root SSH is key-only -- so it
  # cannot simply be left unset either.
  assertions = [
    {
      assertion = host.rootHashedPassword != null;
      message = ''
        layer-server-hardening: host '${host.hostName}' has no rootHashedPassword.

        A server reachable from the internet must not fall back to the fleet
        default in layer-users-root.nix, which real hardware shares and the
        playground VMs publish in git.

        Set hosts.${host.hostName}.rootHashedPassword in secrets/globals.nix.age:
          mkpasswd --method=yescrypt
      '';
    }
  ];

  # ---------------------------------------------------------------------
  # Bootloader — GRUB, because the target boots BIOS (iter 11 §2.2)
  # ---------------------------------------------------------------------
  #
  # This is the repo's first non-UEFI host. Everything else uses
  # systemd-boot or lanzaboote.
  boot.loader.grub = {
    enable = true;
    efiSupport = false;

    # `device` is deliberately NOT set here.
    #
    # disko's module.nix already populates
    # `boot.loader.grub.devices = [ "/dev/vda" ]` because the disk carries an
    # EF02 partition, and nixpkgs' grub.nix folds `device` into that SAME
    # list. Setting both yields [ "/dev/vda" "/dev/vda" ] and evaluation
    # fails with "You cannot have duplicated devices in mirroredBoots" --
    # measured, not theorised (definitionsWithLocations named both files).
    #
    # Letting disko own it is also correct on the merits: it knows which
    # disk it partitioned, so the bootloader target cannot disagree with the
    # layout. That matters because this profile is shared by any future
    # server, whose disko config will name a different disk.

    # /boot is a 512 MB ext4 partition. Five generations at roughly 70 MB
    # of kernel+initrd each is ~350 MB; unbounded, /boot fills and the next
    # activation fails.
    configurationLimit = 5;
  };
  # platform-virtio.nix enables systemd-boot as a mkDefault for the
  # playground VMs' non-SecureBoot path; a BIOS host must not have both.
  boot.loader.systemd-boot.enable = false;

  # ---------------------------------------------------------------------
  # Resources — 1 vCPU, 1.9 GB RAM, no swap, 15 GB disk
  # ---------------------------------------------------------------------
  #
  # The box ships with no swap at all. zram rather than a swapfile: disk is
  # the binding constraint here, and nothing builds locally (colmena's
  # buildOnTarget = false), so this is for peak working-set relief, not for
  # compilation headroom.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # A 15 GB disk with an unbounded Nix store fills silently and then
  # nothing can be deployed to fix it.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nix.optimise.automatic = true;
}
