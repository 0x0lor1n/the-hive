# port-test-vm

Source: ~/workspace/playground/test-vm (divnix/hive, 5.8k lines). Target: a
new cells/workstation in this repo, isolated from cells/server.

phase: 0 not started
phases: 1 storage+boot (zfs native enc, tpm unlock, pcr15, lanzaboote,
           impermanence) | 2 secrets (agenix + rekey) | 3 auth (himmelblau,
           layer-users-local) | 4 desktop (dwl, home-manager as NixOS module)

## ported
(none)

## invariants
osgiliath-unchanged: `nix eval --raw .#colmenaHive.toplevel.osgiliath.drvPath` == /nix/store/nxca0xf2iphm3qgg118vcavj5h85dxps-nixos-system-osgiliath-26.11pre-git.drv   last: /nix/store/nxca0xf2iphm3qgg118vcavj5h85dxps-nixos-system-osgiliath-26.11pre-git.drv @ 2026-09-02
server-isolation: `nix eval --json .#x86_64-linux.server.nixosConfigurations.osgiliath --apply 'x: builtins.attrNames x' 2>/dev/null; jq -r '.nodes.root.inputs|keys[]' cells/server/flake.lock` must not gain lanzaboote/himmelblau/home-manager/cachyos

## blocked_on
(none)

## verified
(none)

## notes
- Scope: port ONLY the vm-zfs host (native zfs enc + pcr15). Do not port luksTpm / hardware-luks-tpm.nix.
- Runner (test-vm justfile; reproduce in cells/workstation): `just image` -> `just secureboot-reset` -> `just vm-run-secureboot` (lanzaboote 3-boot enrollment, OVMFFull varstore starts in Setup Mode) -> inside VM as root: `mkzfscreds --devices rpool --print-pcr15`, then `just seal-zfs-cred` (seal onto ESP). swtpm state in ./swtpm-state/; delete to re-enroll after a new image.
- Target: test VM only; later the basis for the dellvis laptop.
- utils.mkHome is broken upstream (bee.home); test-vm uses HM as a NixOS module via home-manager.users.<name>, so mkHome is not needed.
- globals-options was trimmed for the server; isVm/hasTpm/gpu/entra.*/user.* come back for workstations. Encrypted half already sets user.*/entra.*.
- test-vm secrets are agenix + agenix-rekey by host key; server uses colmena deployment.keys. Different mechanism, phase 2.
- test-vm profiles are {inputs, cell}: module -- port mechanically like the server ones.
