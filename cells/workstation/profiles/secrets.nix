# agenix + agenix-rekey for workstation hosts. Only secrets with a runtime
# consumer live here; login hashes stay in globals so console login survives
# an agenix outage.
#
# Master identities: jarvis-nopin-rage.pub (TPM-sealed, no PIN, so
# `agenix generate/rekey` stay non-interactive; also decrypts
# secrets/globals.nix.age at eval time) and dellvis-nix-rage.pub (TPM on
# dellvis, PIN-gated). Every secret is additionally encrypted to the
# recovery key held offline in KeePass (extraEncryptionPubkeys) so losing
# both TPMs does not lose the secrets. `generated/` holds values encrypted
# to those recipients, `rekeyed/<host>/` the same values re-encrypted to
# host.sshHostPubkey.
{
  inputs,
  cell,
}: {
  pkgs,
  lib,
  config,
  host,
  globals,
  ...
}: let
  flakeRoot = inputs.self.outPath;

  # OUTBOUND ssh identities, transplanted verbatim from jarvis (the pubkeys
  # are registered on GitHub/Azure/client hosts, so no generator). Split per
  # account (state: port-jarvis-home, key table): the local user gets the
  # personal + freelance keys, the Entra user the employer ones. Each key
  # ships with its .pub: the private halves are passphrase-protected, and
  # without the .pub next to it ssh must decrypt the key just to learn which
  # agent identity to offer, i.e. it prompts even when the agent has it.
  # IdentityFile in the per-role user secrets points at these paths.
  # Source: secrets/ssh/<name>.age (master identities + recovery), rekeyed
  # per host like everything else.
  #
  # Entra owner: users.users has no entry, so `owner` is the numeric uid
  # (chown accepts it, nothing resolves the name at activation) and group
  # falls back to root; mode keeps it to the owner.
  entraUid = globals.entra.user.uid;
  mkIdentity = owner: name: {
    "${name}" = {
      rekeyFile = "${flakeRoot}/secrets/ssh/${name}.age";
      inherit owner;
      mode = "0600";
    };
    "${name}.pub" = {
      rekeyFile = "${flakeRoot}/secrets/ssh/${name}.pub.age";
      inherit owner;
      mode = "0644";
    };
  };
  # Real hosts only: the VM rehearsal has its own host key and no business
  # holding these, so no rekeyed bundle exists for it (eval would assert).
  sshIdentities = lib.optionals (!host.isVm) (
    map (mkIdentity host.userName) [
      "ssh-github"
      "ssh-qvalon"
      "ssh-git-mdaudit"
    ]
    ++ lib.optionals (entraUid != null) (map (mkIdentity (toString entraUid)) [
      "ssh-azure-owt"
      "ssh-github-owt"
      "ssh-id-engie"
      "ssh-id-engie-prod"
    ])
  );
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
      {
        identity = "${flakeRoot}/secrets/dellvis-nix-rage.pub";
        pubkey = "age1tag1q2ggf943ppzwpqwcf39m0r3ztj3vzg6yap2e3tewda7m7k6k0cxdv9dramt";
      }
    ];
    # Offline recovery identity (plain age key, stored in KeePass). Never
    # used for decryption from this repo.
    extraEncryptionPubkeys = [
      "age12tng070ds3cr6xfhlyqqqc5mnavgxuen865uynr8vja2krt8cy2qz0p80l"
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
  age.secrets = lib.mkMerge ([
      {
        zfs-rpool-passphrase.generator.script = {pkgs, ...}: ''
          # No trailing newline: `zfs change-key` and mkzfscreds must see the same
          # bytes, or the sealed credential unseals to a key ZFS rejects and it
          # looks like a TPM fault.
          ${pkgs.coreutils}/bin/printf '%s' \
            "$(${pkgs.xkcdpass}/bin/xkcdpass --numwords=6 --delimiter=-)"
        '';

        # The local user's SSH keypair (layer-users-local reads the .pub). Custom
        # generator: agenix's built-in ssh-ed25519 does not write a .pub. The private
        # key is the secret; the .pub is committed next to the .age in generated/.
        user-ssh-key.generator.script = {
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
    ]
    ++ sshIdentities);

  zfsUnlock.passphraseFile = config.age.secrets.zfs-rpool-passphrase.path;
}
