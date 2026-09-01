# Two-root impermanence: /state (runtime state, not backed up) and /persist
# (identity, backed up). Filesystem-agnostic -- both are mountpoints, whether
# ZFS datasets or btrfs subvolumes. Per-service state is declared by the
# profile that owns the service, not here.
{
  inputs,
  cell,
}: {...}: {
  imports = [inputs.impermanence.nixosModules.impermanence];

  # Asserted by impermanence; neither disko nor a hand-written mount sets it.
  fileSystems."/state".neededForBoot = true;
  fileSystems."/persist".neededForBoot = true;

  environment.persistence."/state" = {
    hideMounts = true;
    files = ["/etc/machine-id"];
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/spool"
    ];
  };

  # SSH host keys are the agenix recipient and what every client pins.
  environment.persistence."/persist" = {
    hideMounts = true;
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };
}
