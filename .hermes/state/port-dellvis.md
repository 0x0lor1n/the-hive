# port-dellvis

Source: sevastopol (this repo, cells/workstation) + ~/nixos-config/hosts/dellvis
(the machine's current NixOS: btrfs on nvme0n1p3, services.intune + mdatp).
Target: dellvis as a second host in cells/workstation, same `workstation` base,
its own `hardware` list. Sevastopol was the rehearsal; this is the real disk.

phase: 1 config -- NOT STARTED (phase 0 complete 2026-09-03)
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
- Secure Boot: disabled, PK/KEK/db populated (factory keys). User must clear
  keys in BIOS Setup (-> Setup Mode) before phase 3 so lanzaboote enrolls its
  own. No Windows on the disk, so nothing to preserve. Not blocking phase 1-2.

## verified
0 (laptop, partial): lscpu/lspci/ip/nmcli/systemctl/nixos-generate-config pasted by user @ 2026-09-03 -> notes "dellvis facts"
0 (laptop, rest): lsblk/sgdisk/blkid/tpm2_getcap/bootctl/efivars/efibootmgr/dmidecode pasted by user @ 2026-09-03 -> notes "dellvis disk/firmware". Phase 0 DONE.
0 (desk part): `cat ~/nixos-config/hosts/dellvis/{disko,fs,net,default}.nix` -> facts recorded in notes @ 2026-09-03
0: osgiliath-unchanged -> nxca0xf2 (match); sevastopol-unchanged -> hwdrgcb on clean tree, 9kamqrvb with the uncommitted gtk.nix WIP (Kanagawa gtk theme + phinger cursors -- a workstation change, not dellvis) @ 2026-09-03

## notes
- Phase 0 command list, to run on the laptop and paste back:
  `lsblk -f`; `sudo sgdisk -p /dev/nvme0n1`; `ls /sys/class/tpm`;
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
- ~/nixos-config/hosts/dellvis/disko.nix (device=nvme0n1p3, ESP 1G) does NOT
  match the live disk -- stale, ignore it. Old default.nix also imports
  hardware/{mesa,intel,ergohaven,ni-audio-6}.nix and amnezia.nix. Last commit
  to hosts/dellvis: ca43fab 2026-04-20.
- dellvis disk/firmware (2026-09-03): Dell Latitude 5580, BIOS 1.14.2 (AMI
  5.11, UEFI 2.60). Disk Crucial CT1000P3SSD8 931.5G, one plain GPT:
  p1 ESP 5G vfat A936-4157 (/boot, 54% used), p2 btrfs 926.5G (/). No p3, no
  Windows, no recovery partition -> whole-disk `disk.main` is correct.
  systemd-boot 259.3; Boot0000 is a stale entry for a partition GUID that no
  longer exists (previous disk), Boot0001/0002 point at p1 -- all gone after
  wipe anyway. TPM2 present: Nuvoton NPCT (NTC), spec rev 1.16, fw from 2015
  -- old but TPM 2.0; PCR7 sealing should work, verify in phase 3. dmidecode
  type 22 empty -> no battery installed. i7-7600U + HD 620 + 930MX (nouveau).
- User decisions 2026-09-03: all data already rescued, wipe the whole nvme
  freely. /porsche = external HDD, drop it entirely. mdatp NOT wanted
  (currently active but "severely outdated"; intune-daemon inactive) -- no
  nix-mdatp input, himmelblau + compliance CSE as on sevastopol.
- dellvis facts (2026-09-03): i7-7600U 4c, 31G RAM, Micron 2550 NVMe
  (DRAM-less). Intel HD 620 (i915) + **NVIDIA GM108M GeForce 930MX on
  nouveau** -- hybrid GPU, not in the old config at all. Plan: p.gpu-intel
  as primary, blacklist nouveau/nvidia and power the dGPU off (no reason to
  carry the nvidia stack for a 930MX); revisit only if an external display
  turns out to hang off it. Wifi Intel 8265 (iwlwifi, wlp2s0), ethernet
  enp0s31f6 (e1000e, no carrier), bt hci0. Network: NetworkManager active,
  iwd inactive -> stay on NM. initrd modules: xhci_pci nvme rtsx_pci_sdmmc;
  kvm-intel. /sys/class/power_supply has only AC -- no BAT0: battery absent
  or dead; skip battery tuning until it shows up. No ed25519 host key on the
  old install (confirms: generate on the ZBook, ship via --extra-files).
- User 2026-09-03 on old-host peripherals: NI Audio 6 and amnezia -- drop.
  ergohaven + mesa bits -- dellvis-only, not workstation-wide. Caveat: the
  machine sat untouched ~1 year, so treat the old config as a hint, not a
  spec; port ergohaven only if the keyboard is actually still in use (ask
  at phase 4, not before).
- The ZBook (HP, Ubuntu + nix pm) is last on purpose: it is the work machine,
  and dellvis is where the hardware surprises get paid for.
