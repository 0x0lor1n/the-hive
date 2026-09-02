# port-test-vm

Source: ~/workspace/playground/test-vm (divnix/hive, 5.8k lines). Target: a
new cells/workstation in this repo, isolated from cells/server.

phase: 2 secrets -- DONE 2026-09-02 (agenix rotate + reseal + silent boot on the agenix key verified in VM). next: 3 auth
phases: 1 storage+boot (zfs native enc, tpm unlock, pcr15, lanzaboote,
           impermanence) | 2 secrets (agenix + rekey) | 3 auth (himmelblau,
           layer-users-local) | 4 desktop (dwl, home-manager as NixOS module)

## ported
cells/workstation/flake.nix (+lock): utils, disko(65fb947), lanzaboote d232658 (master; v1.0.0 sets boot.bootspec.enable which nixpkgs 34ab990 rejects), mkcreds 112d95f, nixpkgs pinned = root
cells/workstation/profiles: storage-zfs, storage-zfs-rollback, hardware-zfs-unlock, hardware-zfs-tpm (+__mkzfscreds, __zfs-fingerprint), hardware-secureboot, platform-virtio, gpu-virtio, dev-9p-share   <- test-vm profiles/ + devices/, mechanically
cells/workstation/disks/vm-zfs.nix     <- diskoConfigurations.nix vm-zfs target via utilsLib.mkDisk
cells/workstation/nixosConfigurations.nix  mkHost vm-zfs = foundation(common) + zfs + vmGuest + zfsNative; disko.imageBuilder.pkgs vmTools kernelImage=bzImage workaround (new nixpkgs vmTools vs disko aggregateModules)
cells/workstation/devshells.nix        ws-image / ws-switch / ws-secureboot-reset / ws-vm-run (justfile image / switch / secureboot-reset / vm-run-secureboot-tpm) + agenix CLI, state in .ren/vm/
cells/workstation/profiles/secrets.nix  <- test-vm profiles/secrets.nix, ONLY zfs-rpool-passphrase (logins stay in globals); hostPubkey from globals.hosts.<h>.sshHostPubkey (new option), master = jarvis-nopin-rage.pub only, age.identityPaths=/persist/etc/ssh/ssh_host_ed25519_key
cells/workstation/agenixRekey.nix      agenix-rekey.configure over cell.nixosConfigurations; root flake exposes `agenix-rekey` via new cell block (simple "agenixRekey")
secrets/generated/vm-zfs/zfs-rpool-passphrase.age + secrets/rekeyed/vm-zfs/7322449f...age
cells/common: globals-options + isVm/hasTpm/userName/homeDir/hashedPassword per host, user.uid; globals.nix hosts.vm-zfs (public throwaway hashes), userName/homeDir resolution
flake.nix: nixosConfigurations = server // workstation; devShells += workstation. colmenaHive unchanged (server only).

## invariants
osgiliath-unchanged: `nix eval --raw .#colmenaHive.toplevel.osgiliath.drvPath` == /nix/store/nxca0xf2iphm3qgg118vcavj5h85dxps-nixos-system-osgiliath-26.11pre-git.drv   last: /nix/store/nxca0xf2iphm3qgg118vcavj5h85dxps-nixos-system-osgiliath-26.11pre-git.drv @ 2026-09-02 (after phase-2 edits)
server-isolation: `nix eval --json .#x86_64-linux.server.nixosConfigurations.osgiliath --apply 'x: builtins.attrNames x' 2>/dev/null; jq -r '.nodes.root.inputs|keys[]' cells/server/flake.lock` must not gain lanzaboote/himmelblau/home-manager/cachyos   last: `disko utils`, osgiliath `config ? age` = false @ 2026-09-02 (phase 2)

## blocked_on
(none)

## verified
1-eval: `nix eval --raw .#nixosConfigurations.vm-zfs.config.system.build.toplevel.drvPath` -> /nix/store/0pziad3hpwhw81fqbp8wgiq3kiz5ab8y-nixos-system-vm-zfs-26.11pre-git.drv; zfsUnlock.devices = {rpool={pcrBank=sha256}}; kernel 6.18.48 (stock)
1-build: `nix build .#nixosConfigurations.vm-zfs.config.system.build.toplevel` -> /nix/store/vh817lvmhz346j77srp7fxs8y936vr88-nixos-system-vm-zfs-26.11pre-git; `...diskoImages` -> /nix/store/8sic0flskqmk9q8r38q6nvl0x0vzb8gy-vm-zfs-disko-images (main.raw 20G); `ws-image` -> .ren/vm/vm-zfs.raw
1-boot (ws-vm-run, serial console):
  boot1: bootctl `Secure Boot: disabled (setup)`, TPM2 yes; passphrase prompt -> qwerty123; /boot/loader/keys/auto/{PK,KEK,db}.auth written; generate-sb-keys + prepare-sb-auto-enroll finished; systemctl --failed empty
  boot2: `Secure Boot: enabled (user)`, lanzastub 1.1.0; passphrase prompt; `mkzfscreds --devices rpool --print-pcr15` = 3ba11bda...7070 (fp 710afecb...7e61); sealed to /boot/zfs-unlock/rpool.cred (537 B)
  boot3: NO prompt. journal: `zfs-unlock: PCR extend for rpool (fingerprint: 710afecb...)` -> `TPM unlock for rpool` -> `Unlocked rpool` -> `Anti-replay PCR 15 extension`; PCR15 after = d8534895...92f9; keystatus available; / = rpool/local/root, /persist = rpool/safe/persist; /var/lib/sbctl/keys/db persisted; snapshot rpool/local/root@blank; --failed empty
2-eval: toplevel drv /nix/store/6snfbx3v78h5vadp6bbxs4jrfq9w6l29-nixos-system-vm-zfs-26.11pre-git.drv; zfsUnlock.passphraseFile=/run/agenix/zfs-rpool-passphrase; agenix-rekey.x86_64-linux = [edit-view generate rekey update-masterkeys]
2-secrets: `agenix generate` -> secrets/generated/vm-zfs/zfs-rpool-passphrase.age (git add before rekey or "rekeyFile doesn't exist"); `agenix rekey` -> rekeyed/vm-zfs/7322449f...; host pubkey captured via ssh-keyscan = ...IJEkHLFGCFphGyc0GGyxCENyE/762o1ZPOVa1Ar15ee5
2-activate (ws-switch + activate.sh in VM, gen mb1xv9pg...): agenix decrypted (48 B); zfs-key-sync: `rotating rpool to the agenix passphrase` -> `sealing credential for PCR 15 of the next boot` (expected PCR15 44d0cf49...5b23) -> `done`; /boot/zfs-unlock/rpool.cred 589 B; --failed empty
2-boot4 (FAIL, fixed): TPM unlock OK but `[agenix] identityPaths entry /etc/ssh/ssh_host_ed25519_key not present` -> agenixInstall failed, zfs-key-sync `no readable secret`. Cause: activation runs before impermanence binds /etc/ssh. Fix: age.identityPaths=[/persist/etc/ssh/ssh_host_ed25519_key].
2-boot5 (gen jsgwkdap...): `zfs-unlock: Unlocked rpool` (no prompt), agenix gen 1 decrypted at boot, `zfs load-key -n -L file:///run/agenix/zfs-rpool-passphrase rpool` = 1/1 verified, zfs-key-sync `already in sync`, --failed empty

## notes
- zfs-key-sync.service is gated on zfsUnlock.passphraseFile (null -> service absent); profiles/secrets.nix sets it. Pool passphrase qwerty123 is now ROTATED on the current image; agenix view / /run/agenix in the VM is the only copy.
- Not ported from test-vm secrets.nix: root-password/user-password/luks-passphrase/user-ssh-key (no runtime consumer here; logins come from globals; user-ssh-key -> phase 3 with layer-users-local), isPlayground dev-values, dellvis master identity.
- New host bootstrap: boot on disko key, `ssh-keyscan -t ed25519`, set globals.hosts.<h>.sshHostPubkey, `agenix generate && git add secrets && agenix rekey`, ws-switch. secrets.nix asserts the pubkey is non-null.
- ssh root@vm is prohibit-password; activation goes over serial console (ws-vm-run) until vmuser exists (phase 3).
- layer-kernel (CachyOS) NOT ported in phase 1: stock kernel + zfs. Needs nix-cachyos-kernel input + overlay in the workstation cell; do it in phase 1b or 4.
- VM logins (public, from test-vm AGENTS.md): root/onion, vmuser/Qwerty123! (no vmuser yet in phase 1); pool passphrase qwerty123. ssh -p 2222.
- sbctl not on the VM PATH (common/base.nix has no sbctl; test-vm base had it). Add to a workstation profile when needed.
- gpu-virtio sets WLR_* env + mesa; harmless without a desktop, kept so phase 4 does not re-port it.
- Scope: port ONLY the vm-zfs host (native zfs enc + pcr15). Do not port luksTpm / hardware-luks-tpm.nix.
- Runner (test-vm justfile; reproduce in cells/workstation): `just image` -> `just secureboot-reset` -> `just vm-run-secureboot` (lanzaboote 3-boot enrollment, OVMFFull varstore starts in Setup Mode) -> inside VM as root: `mkzfscreds --devices rpool --print-pcr15`, then `just seal-zfs-cred` (seal onto ESP). swtpm state in ./swtpm-state/; delete to re-enroll after a new image.
- Target: test VM only; later the basis for the dellvis laptop.
- utils.mkHome is broken upstream (bee.home); test-vm uses HM as a NixOS module via home-manager.users.<name>, so mkHome is not needed.
- globals-options was trimmed for the server; isVm/hasTpm/gpu/entra.*/user.* come back for workstations. Encrypted half already sets user.*/entra.*.
- test-vm secrets are agenix + agenix-rekey by host key; server uses colmena deployment.keys. Different mechanism, phase 2.
- test-vm profiles are {inputs, cell}: module -- port mechanically like the server ones.
