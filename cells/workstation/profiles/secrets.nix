# agenix + agenix-rekey for workstation hosts. Only secrets with a runtime
# consumer live here; login hashes stay in globals so console login survives
# an agenix outage.
#
# Master identities: penrose-nix-rage.pub and elster-nix-rage.pub (each a
# TPM-sealed, PIN-gated age-plugin-tpm identity on its own host). Every secret
# is additionally encrypted to the recovery key held offline in KeePass
# (extraEncryptionPubkeys) so losing both TPMs does not lose the secrets.
# `agenix rekey/generate` on host X must be told to use X's identity only
# (AGENIX_REKEY_PRIMARY_IDENTITY[_ONLY], set by the devshell): rage stops at
# the first TPM identity it cannot open instead of trying the next one.
# `generated/` holds values encrypted to those recipients, `rekeyed/<host>/`
# the same values re-encrypted to host.sshHostPubkey.
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

  # Outbound ssh identities; the pubkeys are registered on GitHub/Azure/client
  # hosts, so there is no generator. Handed out by role (accounts.nix): dev
  # gets the personal keys, employer and freelance their organisation's.
  # Each key ships with its .pub: for a passphrase-protected key, without the
  # .pub next to it ssh must decrypt the key just to learn which agent
  # identity to offer, i.e. it prompts even when the agent has it.
  # IdentityFile in the per-role user secrets points at these paths.
  #
  # Owner is account.owner: the name for a local account, the numeric uid for
  # an Entra one (users.users has no entry; chown accepts the number, nothing
  # resolves the name at activation, group falls back to root).
  holders = config.hive.roleHolders;
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
  # A role held by two accounts: one copy, owned by the first holder and read
  # by the rest through the shared group. One pubkey to register, one key to
  # revoke.
  shared = attrs:
    attrs
    // {
      group = "hive";
      mode = "0640";
    };
  mkRoleIdentity = role: name: let
    hs = holders.${role};
    id = mkIdentity (lib.head hs) name;
  in
    lib.optionalAttrs (hs != [])
    (
      if lib.length hs > 1
      then id // {"${name}" = shared id.${name};}
      else id
    );
  # Real hosts only: the VM rehearsal has its own host key and no business
  # holding these, so no rekeyed bundle exists for it (eval would assert).
  sshIdentities = lib.optionals (!host.isVm) (
    [
      # Personal GitHub key: this flake, the-hive tooling, public repos.
      # Passphrase-protected: typed once per session into the agent.
      (mkRoleIdentity "dev" "ssh-github")
      # Rented GPU boxes for training runs. Passphrase-less, unlike the others:
      # the pod is destroyed after the run and a prompt would block a job
      # nobody is watching.
      (mkRoleIdentity "dev" "ssh-runpod")
    ]
    # Letter = organisation (o employer, t its client, w freelance); which one
    # is behind a letter lives only in the encrypted user secrets.
    ++ map (mkRoleIdentity "employer") ["ssh-ogh" "ssh-oaz" "ssh-tgl" "ssh-tprod"]
    ++ map (mkRoleIdentity "freelance") ["ssh-wgl" "ssh-w"]
  );
  # gitleaks rule naming the user, for public repos' pre-commit. Encrypted
  # because the regex is the list of names it hunts for. dev commits to those
  # repos; home/dev links it into ~/.config, which does not survive a relogin.
  gitleaksPersonal = lib.optionalAttrs (!host.isVm && holders.dev != []) {
    gitleaks-personal = shared {
      rekeyFile = "${flakeRoot}/secrets/gitleaks/personal.toml.age";
      owner = lib.head holders.dev;
    };
  };
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
  # /persist is mounted in the initrd.
  age.identityPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];

  age.rekey = {
    masterIdentities = [
      {
        identity = "${flakeRoot}/secrets/penrose-nix-rage.pub";
        # Required for TPM identities: age-plugin-tpm cannot derive the
        # recipient from the identity file without touching the TPM.
        pubkey = "age1tag1q2ggf943ppzwpqwcf39m0r3ztj3vzg6yap2e3tewda7m7k6k0cxdv9dramt";
      }
      {
        identity = "${flakeRoot}/secrets/elster-nix-rage.pub";
        pubkey = "age1tag1qthur0dg6lhanph2gpgcnzuv07epumxxnw9ka3c7ltz2sr6nqhe9ktwgr2k";
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

        # The workstation's homelab key (layer-users-local reads the .pub). Custom
        # generator: agenix's built-in ssh-ed25519 does not write a .pub. The private
        # key is the secret; the .pub is committed next to the .age in generated/.
        # Owned by admin: the fleet's servers authorise it for their admin user
        # (server/layer-users-admin). Read through hive by dev too: the
        # system-wide `Host minas-tirith`/`imladris` entries (layer-users-local,
        # ygg-client) point at this path, and one key per workstation is still
        # one key to revoke.
        user-ssh-key.owner = lib.head config.hive.roleHolders.admin;
        user-ssh-key.group = "hive";
        user-ssh-key.mode = "0640";
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
    ++ sshIdentities
    ++ [gitleaksPersonal]);

  zfsUnlock.passphraseFile = config.age.secrets.zfs-rpool-passphrase.path;
}
