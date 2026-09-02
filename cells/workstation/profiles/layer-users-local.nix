# The local (non-Entra) unix user: account, sudo policy, and the carve-outs
# that survive the @blank rollback of its home.
#
# Workstation-only: osgiliath is root-key-only and stops at
# common/layer-users-root.
{
  inputs,
  cell,
}: {
  globals,
  host,
  ...
}: {
  users.users.${host.userName} = {
    isNormalUser = true;
    uid = globals.user.uid;
    extraGroups = ["wheel"];

    # Fleet default from the ENCRYPTED half of globals, per-host public
    # override for the playground VMs (AGENTS.md documents the passphrase).
    # Real hardware gets the encrypted value, which must satisfy the tenant's
    # Intune Linux password policy (>=8 chars, digit + lowercase + symbol) or
    # enrolment reports the device non-compliant.
    hashedPassword =
      if host.hashedPassword != null
      then host.hashedPassword
      else globals.user.hashedPassword;
    home = host.homeDir;

    # Per host, matching secrets.nix's generatedSecretsDir, so a playground
    # key can never be authorised on real hardware.
    openssh.authorizedKeys.keyFiles = [
      (inputs.self.outPath + "/secrets/generated/${host.hostName}/user-ssh-key.pub")
    ];
  };

  security.sudo.wheelNeedsPassword = true;

  # The home lives on the rolled-back root; anything not listed here is gone
  # at next reboot. Paths are relative to the home, stored under
  # /persist/<homeDir>/<...>. Declared here, not in storage-impermanence: it
  # names the account this file creates.
  environment.persistence."/persist".users.${host.userName} = {
    directories = [
      # sshd refuses keys at anything looser than 0700.
      {
        directory = ".ssh";
        mode = "0700";
      }
    ];
    files = [".bash_history"];
  };
}
