# Secrets

Two channels, chosen by who consumes the value:

- **eval-time** -- plain Nix values the configuration is built from (IPs, login
  hashes, git identities). Decrypted on the machine that evaluates, never
  reach a host as files.
- **runtime** -- files a service reads on the host (ssh keys, VPN configs, the
  ZFS passphrase). agenix-rekey on the TPM hosts, colmena `deployment.keys` on
  osgiliath; imladris has no runtime secrets yet.

Anything with a runtime consumer stays out of the eval channel: the plaintext
would land in `/nix/store`.

## Identities

| identity | where | used for |
|---|---|---|
| `secrets/penrose-nix-rage.pub`, `secrets/elster-nix-rage.pub` | age-plugin-tpm, sealed in each workstation's TPM, PIN-gated | everything below; the file is a handle, the key never leaves the TPM |
| recovery key | plain age key, offline in KeePass | extra recipient on every file, never used from the repo |
| host ssh key (`/persist/etc/ssh/ssh_host_ed25519_key`) | each ZFS host | decrypts that host's rekeyed agenix bundle at activation |

The `.pub` files and `age1tag1…` recipients are public. A TPM identity only
works on its own machine: rage aborts on the first TPM identity it cannot
open ("unable to acquire SRK") instead of trying the next, so every tool picks
`secrets/$(uname -n)-nix-rage.pub` first.

## Eval-time

| file | content | read by |
|---|---|---|
| `secrets/globals.nix.age` | encrypted half of `globals`: IPs, user names, password hashes, disk ids | `cells/common/globals.nix` |
| `secrets/<host>-site.nix.age` | per-host site params (minas-tirith: WAN/LAN, leases, yggdrasil keys) | `cells/server/nixosConfigurations.nix` (`site = true`) |
| `secrets/user-{local,entra}.nix.age` | per-account git identities, ssh matchBlocks, vpn credentials | `cells/workstation/home/secrets.nix` |

All are encrypted to both workstation TPM identities plus the recovery key.
Files are named by role, never by account: the user names themselves are in
`globals.nix.age`.

Mechanism: the deploy shell's `NIX_CONFIG` loads nix-plugins and
`nix/extra-builtins.nix`, which exposes `builtins.extraBuiltins.rageImportEncrypted`.
It runs `nix/rageImportEncrypted.sh`: rage-decrypt with the identities in the
order above, cache the plaintext in `/var/tmp/nix-import-encrypted/$UID/`
keyed by ciphertext hash, `import` it. The cache is persisted, so the TPM PIN
is asked once per change of an `.age` file, not per eval.

On a cache miss with a tty, eval prompts for the PIN itself. Without one
(agents, `sudo` without a terminal) it fails with a hint; prime the cache
first:

```bash
unlock-secrets      # globals.nix.age + user-*.nix.age, this host's TPM PIN
```

`sudo` drops `NIX_CONFIG`; use `--preserve-env=NIX_CONFIG` or `nixos-rebuild
--sudo`. Only the local user can decrypt: the Entra account has no TPM access.

## Runtime: agenix-rekey (workstations, minas-tirith)

Profiles: `cells/workstation/profiles/secrets.nix`,
`cells/server/profiles/secrets-agenix-zfs.nix`. Master identities are the two
workstation TPMs, the recovery key is an `extraEncryptionPubkeys` entry.

| path | what |
|---|---|
| `secrets/ssh/`, `secrets/vpn/`, `secrets/gitleaks/` | hand-made sources (`rekeyFile`), to the masters |
| `secrets/generated/<host>/` | generator output (`zfs-rpool-passphrase`, `user-ssh-key`), to the masters |
| `secrets/rekeyed/<host>/` | the same values re-encrypted to `globals.hosts.<host>.sshHostPubkey`; committed (`storageMode = "local"`) |

```bash
agenix edit secrets/vpn/w.ovpn.age
agenix generate            # missing generated secrets
agenix rekey               # refresh rekeyed/<host>/ after any change
```

The devshell sets `AGENIX_REKEY_PRIMARY_IDENTITY[_ONLY]` to this host's
recipient (`nix/agenix-primary.sh`), so `agenix` never touches the other TPM.
`cells/repo/agenixRekey.nix` lists the nodes the CLI covers; a host missing
there gets no `rekeyed/` bundle.

Both directories are keyed by hostname: renaming a host means regenerating.
`zfs-rpool-passphrase` rotates only with `agenix generate --force`; rekey
never changes a value.

agenix decrypts with the persisted host key path, not `/etc/ssh`: activation
runs before impermanence bind-mounts `/etc/ssh`.

## Runtime: colmena keys (osgiliath)

osgiliath is btrfs, no agenix. `secrets/hisilome/*.age` are pushed by colmena
`deployment.keys` (`cells/server/profiles/deploy-osgiliath.nix`): the
deploying workstation decrypts with its own TPM identity and uploads to
`/run/keys` before activation. The PIN prompt is drawn under colmena's
progress bar, so "Uploading key" looks hung: `colmena apply --verbose`.

## Deploy key and host keys

- `secrets/deploy.age` -- the fleet's ssh deploy key, to the TPM identities
  only. `deploy-key` loads it into the agent for 15 minutes; no unattended
  process can deploy.
- `secrets/hosts/<host>/` -- ssh host keys (and minas-tirith's initrd key),
  shipped by `nixos-anywhere --extra-files` at install. The `.pub` goes into
  `globals.hosts.<host>.sshHostPubkey`, which is the agenix recipient.

## Scanning

`gitleaks protect --staged` on pre-commit (lefthook, `cells/repo/devshells.nix`).
The PII rule set is itself a secret: a regex hunting a name leaks the name,
so it lives in `secrets/gitleaks/personal.toml.age` and reaches `~/.config`
via agenix.
