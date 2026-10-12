# A host on a public IP: SSH exposure, store housekeeping, deploy key.
# Bootloader and swap are platform facts (platform-*.nix).
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

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nix.optimise.automatic = true;
}
