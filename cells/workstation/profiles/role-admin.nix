# admin: the account that rebuilds this host. wheel (sudo with password,
# polkit admin, nix trusted-users through wheel) and the eval-time secrets
# cache. The account itself -- users.users, its persisted home, ssh client
# config -- is layer-users-local.nix; accounts.nix asserts admin is that one.
{
  lib,
  config,
  ...
}: let
  admin = lib.head config.hive.roleHolders.admin;
in {
  users.users.${admin}.extraGroups = ["wheel"];

  security.sudo.wheelNeedsPassword = true;

  # Eval-time plaintext of secrets/globals.nix.age (nix/rageImportEncrypted.sh).
  # Keyed by ciphertext hash, so a changed secret misses the cache and needs one
  # TPM PIN (prompted by eval itself);
  # an unchanged one never touches the TPM again. Persisted so a reboot does
  # not force the PIN either. Accepted risk: 0700 to admin, the only account
  # that can rebuild anyway (trusted-users, checkout, PIN identity), and the
  # pool itself is encrypted.
  environment.persistence."/persist".directories = [
    {
      directory = "/var/tmp/nix-import-encrypted";
      user = admin;
      group = "users";
      mode = "0700";
    }
  ];
}
