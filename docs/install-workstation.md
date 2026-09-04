# Installing a workstation host (as done for penrose)

Fresh install of a `cells/workstation` host onto bare metal via nixos-anywhere.
Written after penrose (Dell Latitude 5580); adjust names for the next box.

## Identities

Three age master identities, `secrets/*.pub` holds the recipients:

| identity | where the key lives | scope |
|---|---|---|
| `jarvis-nix-rage` | ZBook TPM, PIN | ZBook-only secrets |
| `dellvis-nix-rage` | penrose TPM, PIN | penrose-only secrets |
| `jarvis-nopin-rage` | ZBook TPM, no PIN (**temporary**) | secrets shared between VM/hosts, and host bootstrap |

KeePass holds a plain `AGE-SECRET-KEY-1...` as recovery recipient
(`extraEncryptionPubkeys` in `cells/workstation/profiles/secrets.nix`).
Everything flows through `agenix-rekey`; per-host rekeyed files land in
`secrets/rekeyed/<host>/` and `secrets/generated/<host>/`.

## 1. Host config

- `cells/workstation/hosts/<host>.nix` — hostname, disk device, profiles.
- `cells/workstation/disks/<host>.nix` — disko: ESP + ZFS rpool (native encryption,
  passphrase via `/tmp/rpool.key` at install), impermanence layout.
- `cells/workstation/profiles/hardware-*.nix` — split per hardware, not per host.
- Register in `nixosConfigurations` and run `agenix generate && agenix rekey`
  from the workstation devshell (`nix develop .#workstation`). Commit the
  generated secrets.

## 2. Bootstrap files

Host SSH key must exist **before** install, otherwise rekeyed secrets don't decrypt:

```sh
mkdir -p /dev/shm/x/persist/etc/ssh
rage -d -i secrets/jarvis-nopin-rage.pub secrets/hosts/<host>/ssh_host_ed25519_key.age \
  > /dev/shm/x/persist/etc/ssh/ssh_host_ed25519_key
cp secrets/hosts/<host>/ssh_host_ed25519_key.pub /dev/shm/x/persist/etc/ssh/
chmod 600 /dev/shm/x/persist/etc/ssh/ssh_host_ed25519_key
rage -d -i secrets/jarvis-nopin-rage.pub secrets/generated/<host>/zfs-rpool-passphrase.age \
  > /dev/shm/rpool.key
```

(`rage -d -i <identity>` — the `.pub` here is the TPM identity file, not a public key.)

## 3. Target

Boot the target from a NixOS live ISO (Ventoy works). Wi‑Fi via `wpa_supplicant`
or `nmcli`; find the IP with `ip -4 a`. Put your pubkey into
`/root/.ssh/authorized_keys` (`chmod 700 /root/.ssh; chmod 600 authorized_keys`,
owner root — otherwise `bad ownership or modes`).

Secure Boot in the BIOS: **off** for the install; enrollment is done after first boot (§6).

## 4. Build + flash

Build locally (needs `extraBuiltins` → run inside the devshell). Keep an
`--out-link`, otherwise the next GC eats the closure.

```sh
nix build --out-link /tmp/<host>-toplevel .#nixosConfigurations.<host>.config.system.build.toplevel
nix build --out-link /tmp/<host>-disko    .#nixosConfigurations.<host>.config.system.build.diskoScript

env -u NIX_CONFIG nix run github:nix-community/nixos-anywhere -- \
  --store-paths "$(readlink -f /tmp/<host>-disko)" "$(readlink -f /tmp/<host>-toplevel)" \
  --disk-encryption-keys /tmp/rpool.key /dev/shm/rpool.key \
  --extra-files /dev/shm/x \
  root@<ip>
```

`env -u NIX_CONFIG` — nixos-anywhere brings its own `nix`, which can't load
our `nix-plugins` (`undefined symbol ... allocBindings`). With `--store-paths`
it doesn't evaluate anything, so the plugin isn't needed.

Order on the wire: disko → copy closure (~8.6 GiB, Wi‑Fi = slow) → extra-files →
nixos-install → reboot.

## 5. After first boot

- Boot 1: rpool asks for the passphrase on console. `zfs-key-sync.service` rotates
  the pool key to the agenix passphrase and seals a credential into
  `/boot/zfs-unlock/rpool.cred`. Every boot after that unlocks silently.
- Secure Boot — see next section. No `sbctl` in PATH is needed, the config does it.
- Create the host TPM identity (`age-plugin-tpm --generate` with PIN), add it to
  `masterIdentities`, rekey, and drop `jarvis-nopin-rage` from the recipients.
- Log in as the fleet user from `secrets/globals.nix.age` (not `jarvis` — that's the
  zBook playground user). From the builder:
  `ssh -o IdentitiesOnly=yes -i ~/.ssh/id_ed25519 <user>@<ip>` — without
  `IdentitiesOnly` the agent burns through `MaxAuthTries` before it gets to the
  right key. Put it in `~/.ssh/config` as `Host penrose`.
- Sanity check: `bootctl status | grep 'Secure Boot'` → `enabled (user)`,
  `zfs get keystatus rpool` → `available`, `systemctl --failed` → empty.
- Check `hermes/state/post-dellvis-tooling.md` for what's still not ported.

## 6. Secure Boot (Lanzaboote, bare metal)

`hardware-secureboot.nix`: `autoGenerateKeys` + `autoEnrollKeys`. Three boots:

1. **Boot 1** (SB off): `generate-sb-keys` creates `/var/lib/sbctl/keys`, `lzbt`
   writes `PK/KEK/db.auth` to `/boot/loader/keys/auto/`. Firmware is *not* in
   Setup Mode yet — check `cat /sys/firmware/efi/efivars/SetupMode-* | xxd`
   (last byte `00`).
2. Reboot → BIOS (Dell: Secure Boot → Expert Key Management) → **Enable Custom
   Mode** → **Delete All Keys**. Leave Secure Boot itself *disabled*. Empty PK =
   Setup Mode.
3. **Boot 2**: systemd-boot prints `Enrolling secure boot keys from directory` and
   writes them into NVRAM. `bootctl status` → `Secure Boot: disabled (user)`.
4. Reboot → BIOS → Secure Boot **Enabled**. **Boot 3** should come up; `bootctl
   status` → `enabled (user)`.

`includeMicrosoftKeys = true` keeps MS certs in db so signed option ROMs still load.

ZFS auto-unlock survives all of this: `__mkzfscreds.nix` seals against **PCR 15
only** (pool fingerprint), not PCR 7 (SB state), so toggling SB or updating
firmware does not invalidate `rpool.cred`. Anti-replay/gate is in
`hardware-zfs-unlock.nix`, not in SB.

If boot 3 fails with `Security Violation`: BIOS → SB off, boot, `sbctl verify`
to find the unsigned component.

## Traps

- `nix-collect-garbage --delete-older-than` still deletes any unrooted path,
  regardless of age. Use `--out-link`.
- Root filesystem at 100% on the builder host = everything dies quietly. Check `df` first.
- `Could not create NMClient object` on the live ISO — NetworkManager not running,
  use `wpa_supplicant` directly.
- The Intune compliance script matches by ZFS/LUKS state, not by disk name — don't
  "fix" it to look for `nvme0n1p3`.

## 7. Intune (himmelblau)
Login with Entra creds on the greeter; the device enrolls on first login. Compliance
runs the ZFS-encryption script in `cells/workstation/profiles/auth-entra.nix`
(root on encrypted dataset -> compliant). Portal shows the device within ~5 min.
Note: the same config on the sevastopol VM reports "Not evaluated" -- the platform
check rejects the VM, it is not a config bug.

## 8. Day-to-day quirks (expected, not bugs)
- **greeter goes straight to PIN** for a user with an enrolled Hello PIN.
  Upstream himmelblau asks Password first and ignores the answer; we carry a
  patch (`cells/workstation/profiles/auth-entra.nix`, `patchedHimmelblauSrc`)
  that checks the cached Hello key in `pam authenticate init` and skips the
  password prompt. Re-check the patch on every himmelblau bump. Disabling
  `enable_hello` would mean password + MFA every login.
- **rpool passphrase after a rebuild + reboot.** The ZFS key is TPM-sealed to
  PCR15 of the *booted* generation; `nixos-rebuild switch` produces a new
  generation, so the first boot into it falls back to the passphrase
  (KeePass). zfs-key-sync reseals after login; the next boot auto-unlocks.
  Check: `journalctl -b -u zfs-key-sync`.

## 9. Open questions
- **Should the Entra user be able to rebuild at all?** Current answer: no.
  `the-hive` lives in `/persist/home/crookedmirror/the-hive`; the Entra (PAM)
  user has no access to the checkout, the TPM PIN identity or the deploy key.
  Rebuilds are done as `crookedmirror` (local admin / break-glass), the Entra
  session is a plain workstation session. Revisit only if daily work under the
  Entra account needs the repo — then a shared checkout in `/etc/nix/the-hive`
  (root:users, `git config --system safe.directory`) is the candidate, not
  giving the Entra user sudo.
- Split secrets into "install-time, TPM+PIN" vs "rebuild-time, no PIN" so
  `nixos-rebuild` never prompts in a tty popup. Not before penrose is stable.
- **Slack does not survive a reboot even with `~/.config/Slack` persisted**
  (auth-entra.nix). Something else is written outside that dir. Diagnose under
  the Entra user after a fresh login:
  `find ~ -path '*/.nix-profile' -prune -o -newer ~/.config/Slack/Preferences -type f -print | grep -viE '/\.config/Slack/|/\.cache/'`
  Suspects: `~/.local/share/keyrings` (a secret-service got activated via the
  portal → Electron uses it for the token) or `~/.config/Slack` being created
  by Slack *before* the impermanence bind lands on first login. Fix once known.
