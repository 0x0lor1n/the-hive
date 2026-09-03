# port-dellvis

Source: sevastopol (this repo, cells/workstation) + ~/nixos-config/hosts/dellvis
(the machine's current NixOS: btrfs on nvme0n1p3, services.intune + mdatp).
Target: dellvis as a second host in cells/workstation, same `workstation` base,
its own `hardware` list. Sevastopol was the rehearsal; this is the real disk.

phase: 0 recon -- IN PROGRESS: desk facts from ~/nixos-config done (2026-09-03), laptop facts pending
phases: 0 recon (facts off the running machine, nothing written) |
          1 config (globals + disk + hardware profiles, builds on the ZBook) |
          2 install (nixos-anywhere from the ZBook, wipes the disk) |
          3 first boot (passphrase -> mkzfscreds -> TPM unlock, safe entry) |
          4 daily driver (wifi/bt/battery, editor+agents, then ZBook)

## ported
(nothing yet)

## invariants
osgiliath-unchanged: `nix eval --raw .#colmenaHive.toplevel.osgiliath.drvPath` == /nix/store/nxca0xf2iphm3qgg118vcavj5h85dxps-nixos-system-osgiliath-26.11pre-git.drv   last: /nix/store/nxca0xf2iphm3qgg118vcavj5h85dxps-nixos-system-osgiliath-26.11pre-git.drv @ 2026-09-03
sevastopol-unchanged: `nix eval --raw .#nixosConfigurations.sevastopol.config.system.build.toplevel.drvPath` == /nix/store/hwdrgcbw0v920fykvya0305lndqz8i25-nixos-system-sevastopol-26.11pre-git.drv   last: /nix/store/hwdrgcbw0v920fykvya0305lndqz8i25-nixos-system-sevastopol-26.11pre-git.drv @ 2026-09-03 (clean tree, d81e4be..467844c; the earlier 8h7zdb5 baseline was taken on a dirty tree and matches no commit)
dellvis-builds: `nix build --no-link .#nixosConfigurations.dellvis.config.system.build.toplevel` -> exit 0   last: -

## blocked_on
- phase 0 needs physical access to the laptop (user: no access from work).
  Checked 2026-09-03 from the ZBook (192.168.10.0/24): `dellvis` does not
  resolve, no ssh path. Waiting on the pasted output of the phase 0 list.
- What is on nvme0n1p1/p2? The old disko names only p3, and fs.nix mounts an
  NTFS /porsche by uuid C88E64058E63EB00 -- so the disk holds a Windows or a
  data partition that our whole-disk `disk.main` would eat. Decides whether
  the pool takes the disk or one partition.
- Is anything on /porsche and the btrfs root worth keeping? Both are wiped.
- mdatp (Defender): does the tenant's compliance policy require it, or is
  himmelblau + the custom-compliance CSE enough (as on sevastopol)? Decides
  whether the nix-mdatp input enters the workstation cell.
- NetworkManager or iwd?
- Peripheral configs in the old host (ergohaven keyboard, NI Audio 6 pipewire
  rates, amnezia VPN, mesa): workstation-wide or dellvis-only?

## verified
0 (desk part): `cat ~/nixos-config/hosts/dellvis/{disko,fs,net,default}.nix` -> facts recorded in notes @ 2026-09-03
0: osgiliath-unchanged -> nxca0xf2 (match); sevastopol-unchanged -> hwdrgcb on clean tree, 9kamqrvb with the uncommitted gtk.nix WIP (Kanagawa gtk theme + phinger cursors -- a workstation change, not dellvis) @ 2026-09-03

## notes
- Phase 0 command list, to run on the laptop and paste back:
  `lsblk -f`; `sudo sgdisk -p /dev/nvme0n1`; `ls /sys/class/tpm`;
  `sudo sgdisk -p /dev/nvme0n1p3` (old disko put a GPT *inside* p3, see below);
  `sudo tpm2_getcap properties-fixed | head -30`; `bootctl status`;
  `lspci -k | grep -A3 -iE 'vga|network'`; `sudo dmidecode -s system-product-name`;
  `nixos-generate-config --show-hardware-config`; `du -sh /porsche/* 2>/dev/null | tail`.
- The layered split already exists and is the whole point: `workstation` (UX)
  is shared, `hardware` is per host. Nothing under layer-*/auth-*/storage-*
  should need an isVm branch for dellvis; if it does, that is a bug in the
  split, not a dellvis special case.
- VM-only things that must NOT reach dellvis: p.platform-virtio (virtio initrd
  modules, console=ttyS0), p.gpu-virtio (WLR_NO_HARDWARE_CURSORS,
  WLR_OUTPUT_DEFAULT_MODE=1440x2400 -- real EDID must win), p.dev-9p-share
  (/mnt/share). New: p.platform-baremetal, p.gpu-intel, p.laptop.
- `host.isVm = false` already flips the right switches in shared profiles:
  storage-zfs drops forceImportRoot/zfs_force and turns on monthly autoScrub.
- Host key chicken-and-egg: secrets.nix asserts globals.hosts.<h>.sshHostPubkey
  is non-null, and agenix-rekey keys by hostname. Generate the ed25519 host key
  on the ZBook before installing and hand it to nixos-anywhere via
  --extra-files (into /persist/etc/ssh), then `agenix generate && git add
  secrets && agenix rekey`. Do not wait for a first boot to keyscan it.
- Secure Boot: clear the factory keys in BIOS setup (Setup Mode) before phase
  3 so lanzaboote can enroll its own. If p1/p2 turn out to be Windows and it
  must keep booting, auto-enrollment has to preserve the Microsoft keys --
  verify before wiping, this is not reversible from Linux.
- ZFS passphrase at install time comes from a file in the installer's /tmp
  (disko reads keylocation=prompt), never from the store. sevastopol's
  disks file says as much and has never been run on real hardware.
- Kernel: layer-kernel is CachyOS 7.2.2 + zfs_cachyos with a stock
  specialisation.safe. Kaby Lake is fine, but the safe entry exists exactly
  for a first boot on unknown hardware -- boot it once deliberately.
- ~/nixos-config/hosts/dellvis for reference only: btrfs (no encryption),
  services.intune.enable + services.mdatp.enable, security.tpm2.pkcs11,
  docker rootless, flatpak, hardware/intel.nix = microcode + linux-firmware,
  net.nix = useDHCP. Nothing there is worth porting mechanically except the
  intel microcode/firmware pair and the /porsche question.
- Old disko.nix: `disk.my-disk.device = "/dev/nvme0n1p3"; type = "disk"` with
  GPT -> ESP 1G (vfat, /boot, uuid A936-4157) + btrfs root (uuid
  88136b8e-d669-4712-865a-e5fde573f7ef). Nested partition table in p3; the
  outer p1/p2 were never touched by disko. Old default.nix also imports
  hardware/{mesa,intel,ergohaven,ni-audio-6}.nix and amnezia.nix; /porsche
  mount is duplicated (fs.nix live, default.nix commented). Last commit to
  hosts/dellvis: ca43fab 2026-04-20.
- The ZBook (HP, Ubuntu + nix pm) is last on purpose: it is the work machine,
  and dellvis is where the hardware surprises get paid for.
