# agenix + agenix-rekey for workstation hosts. Only secrets with a runtime
# consumer live here; login hashes stay in globals so console login survives
# an agenix outage.
#
# Master identity: jarvis-nopin-rage.pub (TPM-sealed, no PIN, so
# `agenix generate/rekey` stay non-interactive). The same identity decrypts
# secrets/globals.nix.age. `generated/` holds values encrypted to it,
# `rekeyed/<host>/` the same values re-encrypted to host.sshHostPubkey.
{
  inputs,
  cell,
}: {
  pkgs,
  lib,
  config,
  host,
  ...
}: let
  flakeRoot = inputs.self.outPath;
in {
  imports = [
    inputs.agenix.nixosModules.default
    inputs.agenix-rekey.nixosModules.default
  ];

  # With no pubkey the host decrypts nothing and zfs-key-sync stays inert
  # (hardware-zfs-tpm.nix), so a missing pubkey must fail at eval, not at boot.
  assertions = [
    {
      assertion = host.sshHostPubkey != null;
      message = "secrets: globals.hosts.${host.hostName}.sshHostPubkey is null; capture it with `ssh-keyscan -t ed25519` and `agenix rekey`.";
    }
  ];

  # The persisted path, not /etc/ssh: agenixInstall runs at activation before
  # impermanence bind-mounts /etc/ssh, so at boot the default identity is
  # absent ("no readable identities found") and zfs-key-sync sees no secret.
  # /persist is mounted in the initrd. Measured on boot 4 of sevastopol.
  age.identityPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];

  age.rekey = {
    masterIdentities = [
      {
        identity = "${flakeRoot}/secrets/jarvis-nopin-rage.pub";
        # Required for TPM identities: age-plugin-tpm cannot derive the
        # recipient from the identity file without touching the TPM.
        pubkey = "age1tag1q2vgn00whx3eukfv6n97udenlcl2nqx39ykq40z5gccc3exugtdq6kedkgm";
      }
    ];
    agePlugins = [pkgs.age-plugin-tpm];
    hostPubkey = host.sshHostPubkey;
    # Rekeyed bundles are committed; rekeying at build time would need a
    # sandbox escape.
    storageMode = "local";
    # Both per host: one passphrase per pool.
    generatedSecretsDir = "${flakeRoot}/secrets/generated/${host.hostName}";
    localStorageDir = "${flakeRoot}/secrets/rekeyed/${host.hostName}";
  };

  # Consumed by zfs-key-sync.service: the pool is rotated to this value and
  # the TPM credential re-sealed from it. Rotate with
  # `agenix generate --force zfs-rpool-passphrase` (rekey never changes the
  # value). Entropy on every host, playground included: the VM's pool is
  # unlocked by the TPM, nobody types this.
  age.secrets.zfs-rpool-passphrase.generator.script = {pkgs, ...}: ''
    # No trailing newline: `zfs change-key` and mkzfscreds must see the same
    # bytes, or the sealed credential unseals to a key ZFS rejects and it
    # looks like a TPM fault.
    ${pkgs.coreutils}/bin/printf '%s' \
      "$(${pkgs.xkcdpass}/bin/xkcdpass --numwords=6 --delimiter=-)"
  '';

  zfsUnlock.passphraseFile = config.age.secrets.zfs-rpool-passphrase.path;

  # The local user's SSH keypair (layer-users-local reads the .pub). Custom
  # generator: agenix's built-in ssh-ed25519 does not write a .pub. The private
  # key is the secret; the .pub is committed next to the .age in generated/.
  age.secrets.user-ssh-key.generator.script = {
    pkgs,
    lib,
    file,
    ...
  }: ''
    tmp=$(${pkgs.coreutils}/bin/mktemp -d)
    trap "${pkgs.coreutils}/bin/rm -rf '$tmp'" EXIT
    ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" \
      -C "${host.hostName} user (agenix-generated)" -f "$tmp/key" >/dev/null
    ${pkgs.coreutils}/bin/cp "$tmp/key.pub" \
      ${lib.escapeShellArg (lib.removeSuffix ".age" file + ".pub")}
    ${pkgs.coreutils}/bin/cat "$tmp/key"
  '';
}
