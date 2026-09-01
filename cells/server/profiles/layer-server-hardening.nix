# A host on a public IP: SSH exposure, bootloader, swap, store housekeeping,
# deploy key.
{
  inputs,
  cell,
}: {host, ...}: {
  # Key-only over SSH; the password below is the console (VNC) recovery path,
  # which matters because impermanence wipes / on every boot.
  services.openssh.settings = {
    PermitRootLogin = "prohibit-password";
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
  };

  users.users.root.openssh.authorizedKeys.keyFiles = [
    (inputs.self.outPath + "/secrets/deploy.pub")
  ];

  # An internet-facing host must not inherit the fleet root password.
  assertions = [
    {
      assertion = host.rootHashedPassword != null;
      message = ''
        layer-server-hardening: host '${host.hostName}' has no rootHashedPassword.
        Set hosts.${host.hostName}.rootHashedPassword in secrets/globals.nix.age
        (mkpasswd --method=yescrypt).
      '';
    }
  ];

  # BIOS boot. `device` deliberately unset: disko already populates
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

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nix.optimise.automatic = true;
}
