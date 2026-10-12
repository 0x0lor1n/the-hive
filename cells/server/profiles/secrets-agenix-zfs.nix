# Masters: both workstation TPMs + KeePass recovery. The router's own TPM
# identity is a reserve, not a master.
{
  inputs,
  cell,
}: {
  pkgs,
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

  assertions = [
    {
      assertion = host.sshHostPubkey != null;
      message = "secrets-agenix-zfs: globals.hosts.${host.hostName}.sshHostPubkey is null.";
    }
  ];

  # agenix runs before impermanence binds /etc/ssh.
  age.identityPaths = ["/persist/etc/ssh/ssh_host_ed25519_key"];

  age.rekey = {
    masterIdentities = [
      {
        identity = "${flakeRoot}/secrets/penrose-nix-rage.pub";
        pubkey = "age1tag1q2ggf943ppzwpqwcf39m0r3ztj3vzg6yap2e3tewda7m7k6k0cxdv9dramt";
      }
      {
        identity = "${flakeRoot}/secrets/elster-nix-rage.pub";
        pubkey = "age1tag1qthur0dg6lhanph2gpgcnzuv07epumxxnw9ka3c7ltz2sr6nqhe9ktwgr2k";
      }
    ];
    extraEncryptionPubkeys = [
      "age12tng070ds3cr6xfhlyqqqc5mnavgxuen865uynr8vja2krt8cy2qz0p80l"
    ];
    agePlugins = [pkgs.age-plugin-tpm];
    hostPubkey = host.sshHostPubkey;
    storageMode = "local";
    generatedSecretsDir = "${flakeRoot}/secrets/generated/${host.hostName}";
    localStorageDir = "${flakeRoot}/secrets/rekeyed/${host.hostName}";
  };

  # Same generator as the workstations: no trailing newline (zfs-key-sync).
  age.secrets.zfs-rpool-passphrase.generator.script = {pkgs, ...}: ''
    ${pkgs.coreutils}/bin/printf '%s' \
      "$(${pkgs.xkcdpass}/bin/xkcdpass --numwords=6 --delimiter=-)"
  '';

  zfsUnlock.passphraseFile = config.age.secrets.zfs-rpool-passphrase.path;
}
