# port-test-vm

Source: ~/workspace/playground/test-vm (divnix/hive, 5.8k lines). Target: a
new cells/workstation in this repo, isolated from cells/server.

phase: 1 storage+boot -- DONE 2026-09-02 (3-boot dance + silent TPM unlock verified in VM). next: 2 secrets
phases: 1 storage+boot (zfs native enc, tpm unlock, pcr15, lanzaboote,
           impermanence) | 2 secrets (agenix + rekey) | 3 auth (himmelblau,
           layer-users-local) | 4 desktop (dwl, home-manager as NixOS module)

## ported
cells/workstation/flake.nix (+lock): utils, disko(65fb947), lanzaboote d232658 (master; v1.0.0 sets boot.bootspec.enable which nixpkgs 34ab990 rejects), mkcreds 112d95f, nixpkgs pinned = root
cells/workstation/profiles: storage-zfs, storage-zfs-rollback, hardware-zfs-unlock, hardware-zfs-tpm (+__mkzfscreds, __zfs-fingerprint), hardware-secureboot, platform-virtio, gpu-virtio, dev-9p-share   <- test-vm profiles/ + devices/, mechanically
cells/workstation/disks/vm-zfs.nix     <- diskoConfigurations.nix vm-zfs target via utilsLib.mkDisk
cells/workstation/nixosConfigurations.nix  mkHost vm-zfs = foundation(common) + zfs + vmGuest + zfsNative; disko.imageBuilder.pkgs vmTools kernelImage=bzImage workaround (new nixpkgs vmTools vs disko aggregateModules)
cells/workstation/devshells.nix        ws-image / ws-secureboot-reset / ws-vm-run (justfile image / secureboot-reset / vm-run-secureboot-tpm), state in .ren/vm/
cells/common: globals-options + isVm/hasTpm/userName/homeDir/hashedPassword per host, user.uid; globals.nix hosts.vm-zfs (public throwaway hashes), userName/homeDir resolution
flake.nix: nixosConfigurations = server // workstation; devShells += workstation. colmenaHive unchanged (server only).

## invariants
osgiliath-unchanged: `nix eval --raw .#colmenaHive.toplevel.osgiliath.drvPath` == /nix/store/nxca0xf2iphm3qgg118vcavj5h85dxps-nixos-system-osgiliath-26.11pre-git.drv   last: /nix/store/nxca0xf2iphm3qgg118vcavj5h85dxps-nixos-system-osgiliath-26.11pre-git.drv @ 2026-09-02 (after phase-1 edits)
server-isolation: `nix eval --json .#x86_64-linux.server.nixosConfigurations.osgiliath --apply 'x: builtins.attrNames x' 2>/dev/null; jq -r '.nodes.root.inputs|keys[]' cells/server/flake.lock` must not gain lanzaboote/himmelblau/home-manager/cachyos   last: `disko utils` @ 2026-09-02

## blocked_on
(none)

## verified
1-eval: `nix eval --raw .#nixosConfigurations.vm-zfs.config.system.build.toplevel.drvPath` -> /nix/store/0pziad3hpwhw81fqbp8wgiq3kiz5ab8y-nixos-system-vm-zfs-26.11pre-git.drv; zfsUnlock.devices = {rpool={pcrBank=sha256}}; kernel 6.18.48 (stock)
1-build: `nix build .#nixosConfigurations.vm-zfs.config.system.build.toplevel` -> /nix/store/vh817lvmhz346j77srp7fxs8y936vr88-nixos-system-vm-zfs-26.11pre-git; `...diskoImages` -> /nix/store/8sic0flskqmk9q8r38q6nvl0x0vzb8gy-vm-zfs-disko-images (main.raw 20G); `ws-image` -> .ren/vm/vm-zfs.raw
1-boot (ws-vm-run, serial console):
  boot1: bootctl `Secure Boot: disabled (setup)`, TPM2 yes; passphrase prompt -> qwerty123; /boot/loader/keys/auto/{PK,KEK,db}.auth written; generate-sb-keys + prepare-sb-auto-enroll finished; systemctl --failed empty
  boot2: `Secure Boot: enabled (user)`, lanzastub 1.1.0; passphrase prompt; `mkzfscreds --devices rpool --print-pcr15` = 3ba11bda...7070 (fp 710afecb...7e61); sealed to /boot/zfs-unlock/rpool.cred (537 B)
  boot3: NO prompt. journal: `zfs-unlock: PCR extend for rpool (fingerprint: 710afecb...)` -> `TPM unlock for rpool` -> `Unlocked rpool` -> `Anti-replay PCR 15 extension`; PCR15 after = d8534895...92f9; keystatus available; / = rpool/local/root, /persist = rpool/safe/persist; /var/lib/sbctl/keys/db persisted; snapshot rpool/local/root@blank; --failed empty

## notes
- Phase 1 deviation: zfs-key-sync.service is gated on new option zfsUnlock.passphraseFile (null in phase 1 -> service absent; pool keeps disko key qwerty123, operator seals by hand). Phase 2 sets it to config.age.secrets.zfs-rpool-passphrase.path.
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
