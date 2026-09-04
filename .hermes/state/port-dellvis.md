# port-dellvis (host is named `penrose` in the repo; dellvis = the old install)

Source: sevastopol (this repo, cells/workstation) + ~/nixos-config/hosts/dellvis
(the machine's current NixOS: btrfs on nvme0n1p3, services.intune + mdatp).
Target: penrose as a second host in cells/workstation, same `workstation` base,
its own `hardware` list. Sevastopol was the rehearsal; this is the real disk.
Naming (user, 2026-09-03): osgiliath = LotR, sevastopol = Alien, penrose = the
Ergo Proxy/Signalis-adjacent pick; hostname == globals key == secrets dirs.

phase: 4 daily driver -- IN PROGRESS (phases 2+3 done before 2026-09-04: the
machine is penrose on rpool/local/root, Secure Boot enabled (user), himmelblaud
active; they were never recorded here -- the file lagged reality, see notes)
phases: 0 recon (facts off the running machine, nothing written) |
          1 config (globals + disk + hardware profiles, builds on the ZBook) |
          2 install (nixos-anywhere from the ZBook, wipes the disk) |
          3 first boot (passphrase -> mkzfscreds -> TPM unlock, safe entry) |
          4 daily driver (wifi/bt/battery, editor+agents, then ZBook)

## ported
- globals.hosts.penrose (diskDevice /dev/nvme0n1, hasTpm, sshHostPubkey) -- cells/common/globals.nix
- disks/penrose.nix: sevastopol layout, keylocation=file:///tmp/rpool.key (nixos-anywhere --disk-encryption-keys), no imageSize
- profiles: platform-baremetal (initrd nvme/xhci/rtsx, kvm-intel, efivars=true, microcode+firmware), gpu-intel (media-driver, nouveau/nvidia blacklisted, dGPU runtime PM), laptop (NetworkManager + nm group, bluetooth off-at-boot, lid ignored, NM/bt persisted)
- input-vial: workstation-wide (in `workstation` list, so sevastopol got it too); udev rule verbatim from old ergohaven.nix
- nixosConfigurations.penrose = mkHost {base=workstation; hardware=intelLaptop; encryption=zfsNative}
- host key: secrets/hosts/penrose/ssh_host_ed25519_key.{age,pub}; .age is rage-encrypted to nopin + dellvis-nix (TPM) + KeePass recovery. Decrypt on the ZBook only for --extra-files.
- agenix generate + rekey done: secrets/generated/penrose/{user-ssh-key,zfs-rpool-passphrase}, secrets/rekeyed/penrose/
- auth-entra: nvme0n1p3 compat symlink now matches ENV{ID_PART_ENTRY_NAME}=="disk-main-rpool" instead of KERNEL=="vda2" (was VM-only; on penrose rpool is nvme0n1p2)
- persist (2026-09-04): local user .hermes/.claude 0700 (layer-users-local); Entra user .config/{Slack,teams-for-linux,o365-profiles}, .hermes, .claude (auth-entra, absolute paths + uid); CLAUDE_CONFIG_DIR=$HOME/.claude in sessionVariables (layer-session) so ~/.claude.json lands inside the persisted dir. o365 + sso from patchedHimmelblau in systemPackages (o365 = teams-for-linux wrapper + 8 .desktop; sso = linux-entra-sso native-messaging host, the himmelblau module already wires the chromium/firefox json)

## invariants
osgiliath-unchanged: `nix eval --raw .#colmenaHive.toplevel.osgiliath.drvPath` == /nix/store/2ija2h1wbprlgn2s03sdvy1b3kfa25kd-nixos-system-osgiliath-26.11pre-git.drv   last: 2ija2h1 @ 2026-09-04 (match after libhimmelblau bump; rebaselined earlier today: nxca0xf2 -> 2ija2h1 from 3aba742/21114be nix 2.31 overlay, not workstation work)
sevastopol-unchanged: `nix eval --raw .#nixosConfigurations.sevastopol.config.system.build.toplevel.drvPath` == /nix/store/044c1dy1s26rzjj4plclyysadd51bbkn-nixos-system-sevastopol-26.11pre-git.drv   last: 044c1dy @ 2026-09-04 (rebaselined after libhimmelblau 0.8.39 bump in shared auth-entra; before that cbb68j6 after the persist edit)
penrose-builds: `nix build --no-link .#nixosConfigurations.penrose.config.system.build.toplevel` -> exit 0   last: exit 0 @ 2026-09-04 -> /nix/store/xbcj1r5glcfrdgyg152y4ahsz3ns2hbz-nixos-system-penrose-26.11pre-git (22m, 1104 built; himmelblaud drv closure has rust_libhimmelblau-0.8.39.drv only)

## next (phase 4, on penrose itself)
1. `unlock-secrets`, then `sudo nixos-rebuild switch --flake .#penrose` to pick
   up the two fixes still only in the working tree: the home-manager-entra
   ExecStartPre wait (layer-compositor) and /etc/teams-for-linux/config.json
   (auth-entra). Then delete the hand-written
   ~/.config/o365-profiles/Teams/config.json and confirm o365 apps still SSO
   from the system file alone.
2. Reboot once and confirm the first login now activates HM (fonts + Slack
   present without manual `systemctl --user start home-manager-entra`), and
   `findmnt | grep -E 'hermes|claude|Slack|teams'` for both users.
3. Decide on `patchedHimmelblau.packages.sso` (commented out in the working
   tree; verified-persist claims linux-entra-sso in sw/bin, current system has
   none -- /etc/chromium/native-messaging-hosts/linux_entra_sso.json is wired
   by the module either way, so this only adds the binary to PATH).
4. wifi/bt on real hardware; battery only if BAT0 ever appears. Then the ZBook.
5. Commit: libhimmelblau 0.8.39, persist dirs, HM race fix, teams config, this
   state file -- one commit once the switch above is verified.

## blocked_on
- Secure Boot: RESOLVED -- `bootctl status` on penrose says "Secure Boot: enabled (user)" @ 2026-09-04.
- Every eval/build needs `unlock-secrets` by the user after a reboot (globals.nix.age cache, PIN identity); the agent cannot run it.
- `nixos-rebuild switch` needs the user's sudo password.

## verified
o365-intune-sso: teams-for-linux 2.17.1 ignores the o365 wrapper's `--ssoInTuneEnabled=true` (flag removed upstream; new keys are auth.intune.{enabled,user}). Hand-written `{"auth":{"intune":{"enabled":true,"user":"<upn>"}}}` in ~/.config/o365-profiles/Teams/config.json -> Teams stopped showing the "install Intune" wall, user-confirmed @ 2026-09-04. NOT yet: the declarative /etc/teams-for-linux/config.json (auth-entra.nix) built or switched.
intune-fix: after `nixos-rebuild switch` to xbcj1r5 (himmelblaud restarted 16:51:39, libhimmelblau 0.8.39) the `missing field PolicyId` error is GONE: `aad-tool compliance-check` at 16:59:25 -> `apply_intune_policy [158ms]` in himmelblaud-tasks, no Invalid JSON, no `policy failure`, no `non-compliant` warning (success itself is a debug! line, invisible at debug=false). Only the pre-existing benign `Unrecognized compliance option 'linux_customcompliance_discoveryscript'` (compliance_ext.rs warns; custom_compliance_ext.rs handles it) @ 2026-09-04.
persist: penrose toplevel xl3b7qms; `grep CLAUDE_CONFIG_DIR $out/etc/pam/environment` -> DEFAULT="@{HOME}/.claude"; `grep -rho '/persist/home/.*' $out/etc/systemd/system/*.mount` lists .hermes/.claude for both users + Slack/teams-for-linux/o365-profiles for Entra; sw/bin has o365, o365-multi, o365-url-handler, linux-entra-sso; 8 o365-*.desktop in sw/share/applications @ 2026-09-04. NOT yet: rebuild + reboot on penrose, `findmnt | grep -E 'hermes|claude|Slack'` after login.
1: penrose toplevel builds; eval check: initrd has nvme/xhci_pci/rtsx_pci_sdmmc, efivars=true, lanzaboote on/systemd-boot off, forceImportRoot=false, autoScrub=true, NM on, nouveau blacklisted, WLR_OUTPUT_DEFAULT_MODE absent, user crookedmirror in wheel+networkmanager, Vial-0.7.5 + hidraw rule present @ 2026-09-03
1: sevastopol drvPath moved hwdrgcb -> yncp0rcm -- EXPECTED: input-vial added to the shared `workstation` list, auth-entra udev rule generalised, agenix rekey renamed rekeyed/sevastopol files (hash includes hostPubkey+rekeyFile, both unchanged -- values identical, filenames differ because rekey is not deterministic in name). New baseline below.
0 (laptop, partial): lscpu/lspci/ip/nmcli/systemctl/nixos-generate-config pasted by user @ 2026-09-03 -> notes "dellvis facts"
0 (laptop, rest): lsblk/sgdisk/blkid/tpm2_getcap/bootctl/efivars/efibootmgr/dmidecode pasted by user @ 2026-09-03 -> notes "dellvis disk/firmware". Phase 0 DONE.
0 (desk part): `cat ~/nixos-config/hosts/dellvis/{disko,fs,net,default}.nix` -> facts recorded in notes @ 2026-09-03
0: osgiliath-unchanged -> nxca0xf2 (match); sevastopol-unchanged -> hwdrgcb on clean tree, 9kamqrvb with the uncommitted gtk.nix WIP (Kanagawa gtk theme + phinger cursors -- a workstation change, not dellvis) @ 2026-09-03

## notes
- o365 apps and Intune SSO (2026-09-04): the wrapper passes the flat
  `--ssoInTuneEnabled=true`, removed in teams-for-linux 2.17. Electron ignores
  unknown switches silently, so SSO stayed off and every o365 app showed the
  "install Intune" wall while the broker was running and the device compliant.
  Config lookup order in appConfiguration.js: /etc/teams-for-linux/config.json
  first, then `app.getPath("userData")`/config.json -- and userData is the
  wrapper's `--user-data-dir`, i.e. ~/.config/o365-profiles/<App>, NOT
  ~/.config/teams-for-linux (that dir only holds Electron state). A file
  dropped in ~/.config/teams-for-linux is never read; that cost an iteration.
  Also from the same source: multi-account is forced off when Intune is on
  (ADR-020, concurrent-enrollment behaviour of the D-Bus broker).
- The broker (himmelblau_broker, user unit, D-Bus activated on
  com.microsoft.identity.broker1) must be running for any of this; it is
  started on demand, so a fresh session has none until something asks.
- Intune non-compliance 2026-09-04 (not a config regression): from 10:18 UTC
  every ApplyPolicy failed with `Invalid JSON: missing field PolicyId` from
  LinuxDeviceCheckinService/status -- Microsoft switched that response to
  camelCase. libhimmelblau 0.8.39 (released the same day) adds serde aliases;
  Cargo.toml 0.8.34..0.8.39 differs only in the version line, so the Cargo.nix
  two-line swap in auth-entra.nix still works. Recipe for next time: fetch
  static.crates.io/crates/libhimmelblau/libhimmelblau-<v>.crate, diff
  Cargo.toml, `nix hash file --type sha256 --base32` for the new sha.
- Persist gotchas (2026-09-04): Slack (Electron) writes ~/.config/Slack, not
  ~/.config/slack. himmelblau's o365 = wrapper around pkgs.teams-for-linux
  (--ssoInTuneEnabled), state in ~/.config/teams-for-linux plus
  ~/.config/o365-profiles/<slug> for --profile launches (word/excel/...).
  Claude Code's ~/.claude.json lives beside ~/.claude unless CLAUDE_CONFIG_DIR
  is set -- set it rather than persisting a lone file (first-shell symlink race).
  hermes: everything under ~/.hermes (config.yaml, sessions, skills, plugins).
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
  ergohaven + vial -- WORKSTATION-WIDE (user's daily split keyboard, used on
  every machine): vial package + its udev rules (old host declared them in
  code -- grep the old dellvis config for `vial`/`udev`/`ergohaven` and port
  verbatim into a shared workstation module, not per-host). mesa bits --
  dellvis-only. The machine sat untouched ~1 year, so everything else in the
  old config is a hint, not a spec.
- The ZBook (HP, Ubuntu + nix pm) is last on purpose: it is the work machine,
  and dellvis is where the hardware surprises get paid for.
